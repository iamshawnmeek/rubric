#!/usr/bin/env python3
"""game_loop — the guardrails that let a Claude Code session run unattended, safely.

WHAT THIS IS
    A dungeon-crawl loop for your AI: game_loop doesn't play for the agent, it keeps the run alive and
    stops it from wiping. Two forces work together:

      * an AUTONOMY engine (bin/watchdog + the `stopgate` Stop hook) that keeps the session moving
        so it does not stop the moment there is no human to press "continue";
      * GUARDRAILS (`claim`, the write guard, the arm->consume primitive) that make running
        unattended safe rather than reckless.

THE ONE DESIGN RULE (everything follows from it)
    Enforcement lives in TOOLS and ARTIFACTS, never in instructions to the model. The test for any
    guard here is: *if the agent ignored every instruction, would this still hold?* If no, it is not
    enforcement — it is a promise, and a promise is exactly what long sessions and context
    compaction break.

    That is why the keystone check is always the same shape: **name a real file that exists.** An LLM
    defeats any check on the mere PRESENCE of a string by writing a plausible string — that is its
    native skill. "Point at a file on disk" is the one check prose cannot satisfy.

LINEAGE
    Extracted from two projects that already ran unattended for real: an on-device firmware loop where
    the expensive gated action was a human button-press, and a trading loop where it was a real-money
    order. Same arm->gate->consume primitive, same VERIFIED/RULED-OUT/OPEN ledger vocabulary, two
    unrelated domains. game_loop is that pattern with the domain specifics removed. See docs/.

State is PER SESSION: each Claude Code session gets .game_loop/sessions/<session_id>/state.json
(atomic writes), so two sessions sharing one checkout cannot see — or trip over — each other's
mandate, checkpoint, arm, or authorizations. A mandate one session binds must never gate another:
that cross-talk sent an unrelated session off to "resume" work it was never asked to do. Outside any
session (a human terminal, an older harness) state falls back to the repo-global .game_loop/state.json.
Every event appends to the shared .game_loop/log.jsonl, stamped with the session that wrote it.
Configuration lives in .game_loop/config.json. Nothing here needs any dependency beyond Python 3 stdlib.
"""
import ast
import argparse
import collections
import datetime
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # for the local flair/notify modules
try:
    import flair  # decoration only; game_loop works identically without it
except Exception:  # noqa: BLE001 — a missing/broken flair file must never break a real command
    flair = None


class _LazyModule:
    """Imported on first USE, never at startup.

    `notify` reaches urllib.request -> http.client -> ssl, and profiling one `game_loop claim` put
    25ms of a 168ms run inside that import chain — paid by EVERY invocation of this binary, to reach
    a module only three commands ever touch. The suite alone starts it 721 times per run.

    Truthiness is the load trigger, so `if notify:` still answers "is paging available?" exactly as
    it did when the import was eager, and a missing or broken file still degrades to falsey instead
    of raising — the property the original try/except existed to provide, kept rather than traded.
    """

    def __init__(self, name):
        self._name = name
        self._mod = False               # False = never tried; None = tried and not available

    def _load(self):
        if self._mod is False:
            try:
                self._mod = __import__(self._name)
            except Exception:  # noqa: BLE001 — a missing/broken file must never break a real command
                self._mod = None
        return self._mod

    def __bool__(self):
        return self._load() is not None

    def __getattr__(self, attr):
        mod = self._load()
        if mod is None:
            raise AttributeError(attr)
        return getattr(mod, attr)


notify = _LazyModule("notify")          # paging only; game_loop works identically without it

CODE_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # the .game_loop/ this CODE is in

# --- WHERE THE HOME IS, AND WHY IT IS NOT WHERE THE CODE IS -------------------------------------
#
# game_loop guards the session that is EDITING game_loop. The hooks run `.game_loop/bin/*` out of the
# checkout being worked on, so a half-finished edit to a gate is live in the same breath it is
# written: a merge left conflict markers in this file and every verb died with a SyntaxError; a shell
# parse error in the write guard once blocked every tool call including its own fix.
#
# The answer is to run the CODE from a pinned checkout — a gitignored directory holding a known-good
# commit — while the HOME stays in the repo. GAME_LOOP_HOME names that home. Two reasons the split
# falls exactly there, neither of them cosmetic:
#
#   1. verify.yaml must be the REPO's or dogfooding is silently off. bin/verify resolves the tree it
#      checks from its own __file__; a pinned copy resolves it to the PINNED directory, so editing
#      the repo's own gates owes nothing, `verify --check` prints "nothing owes a check", and the
#      commit gate passes. A green that gated nothing is the failure shape of #25 and #30.
#   2. State in the pinned directory is DESTROYED on every upgrade, because upgrading IS a
#      re-checkout. Pins, the ruled-out list, hardened learnings, the log — the accumulated identity
#      that most needs to outlive a version bump — is exactly what a naive pin would wipe.
#
# UNSET is the common path and behaves byte-identically to before: home is the code's own directory.
HOME_ENV = "GAME_LOOP_HOME"
PINNED_MARK = "PINNED"   # written into a pinned checkout by `game_loop self --pin`; see resolve_home
PINNED_DIRNAME = ".game_loop_self"   # where `self --pin` puts it, inside the repo, gitignored


def refuse_home(msg):
    """A home that cannot be trusted is refused, never guessed. Stderr + exit 2, before any work."""
    sys.stderr.write(msg + "\n")
    raise SystemExit(2)


def resolve_home(code_root, prog):
    """The .game_loop/ that owns identity and state, given the one the CODE lives in.

    Unset  → the code's own directory (today's behavior, unchanged).
    Set    → it must exist and carry config.json, or this REFUSES. A silent fallback to __file__ is
             the whole trap: it would point every check at the pinned copy and report success.
    Set to the empty string → also refused. That is deliberately NOT the GAME_LOOP_SESSION
             convention, where empty names a real target (the repo-global state file). Empty names
             no directory, and the reading that would make it harmless — "treat it as unset" — is
             the silent fallback again.

    A PINNED marker in the code directory flips the default the other way: pinned code run with NO
    home is refused too. That combination is undetectable from the inside otherwise (it looks exactly
    like an ordinary install of the pinned tree) and it is the one wiring that recreates the trap.
    """
    raw = os.environ.get(HOME_ENV)
    if raw is None:
        if os.path.exists(os.path.join(code_root, PINNED_MARK)):
            refuse_home(
                f"{prog} REFUSED — this is a PINNED code checkout and no {HOME_ENV} names its "
                f"project.\n    code : {code_root}\n\n"
                "A pinned checkout carries CODE only. Its verify.yaml is a copy of some older "
                "commit's,\nand any state written beside it is destroyed by the next re-pin. Name "
                "the project's home:\n"
                f"    {HOME_ENV}=<project>/.game_loop {code_root}/bin/{prog} ...\n"
                "  → `game_loop self` prints the hook wiring that sets it.")
        return code_root
    home = os.path.abspath(os.path.expanduser(raw.strip())) if raw.strip() else ""
    if home and os.path.isfile(os.path.join(home, "config.json")):
        return home
    refuse_home(
        f"{prog} REFUSED — {HOME_ENV} does not name a game_loop home.\n"
        f"    {HOME_ENV} : {raw!r}\n"
        f"    looked for : {os.path.join(home, 'config.json') if home else '(empty value)'}\n\n"
        "It must name the .game_loop/ holding the PROJECT's own identity — config.json, "
        "verify.yaml,\nINVARIANTS.md, state, log.jsonl, pins, the ruled-out list. Falling back to "
        "this code's own\ndirectory would check the PINNED copy instead of the project and report "
        "success while gating\nnothing, so this refuses. Point it at a real .game_loop/, or unset it "
        "entirely.")


ROOT = resolve_home(CODE_ROOT, "game_loop")   # .game_loop/ — identity and state
REPO_ROOT = os.path.dirname(ROOT)
SESSIONS_DIR = os.path.join(ROOT, "sessions")
LEGACY_STATE_F = os.path.join(ROOT, "state.json")   # no-session fallback (human terminal, old harness)
STATE_F = LEGACY_STATE_F                            # re-pointed by set_session()
LOG_F = os.path.join(ROOT, "log.jsonl")
CONFIG_F = os.path.join(ROOT, "config.json")
INV_F = os.path.join(ROOT, "INVARIANTS.md")
# THE FALLBACK, NOT THE ANSWER — read limits_file() below, which is account-scoped. This one is
# per-CHECKOUT and is used only when git cannot tell us where the main checkout is. It carried the
# comment "account-scoped" until an orchestrator grepped it, read the property it asserts, and
# nearly filed a false report that the worktree fix had never landed. A name that reads as the
# authority is a defect even when the code beneath it is correct.
_LIMITS_LOCAL = os.path.join(ROOT, "limits.json")   # degraded: this tree only, never the shared one
_LIMITS_PATH = None


def limits_file():
    """Where the account-scoped snapshot lives — the MAIN checkout's copy, not this worktree's.

    THE RESOURCE IS ACCOUNT-WIDE AND THE FILE WAS PER-CHECKOUT, which #47 already settled for the
    write guard and never reached here: a linked worktree IS this project. Every worktree resolved
    ROOT to its own tree, and the snapshot is gitignored so it does not cross — so N worktrees meant
    N snapshots of one account's windows, N probes fetching the same number, and N leases each
    believing it was the only one. The lease was reported as protection and did not reach the
    topology it was offered for.

    Found by an orchestrator reading this source against its own dispatch, in about four minutes,
    after I told it the lease covered its fan-out. My sentence was unfalsifiable in this repo and
    checkable in theirs — the two-owner rule, the day it was broadcast.

    ONLY THE SNAPSHOT MOVES. Session state, the edited-file set, claims and authorizations stay
    per-tree: sharing those would collapse the isolation a worktree exists for, which is the fix the
    orchestrator explicitly refused to make on its side and was right to refuse.

    Cached because it shells out to git and every statusline refresh reads it. Falls back to this
    tree whenever the main checkout cannot be determined — a snapshot in the wrong place is a
    degraded reading, while failing here would take the statusline down with it.
    """
    global _LIMITS_PATH
    if _LIMITS_PATH is None:
        main = None
        try:
            main = main_checkout()
        except Exception:  # noqa: BLE001 — no git, odd worktree, anything: degrade, never raise
            main = None
        if main:
            shared = os.path.join(main, ".game_loop", "limits.json")
            if os.path.isdir(os.path.dirname(shared)):
                _LIMITS_PATH = shared
        if _LIMITS_PATH is None:
            _LIMITS_PATH = _LIMITS_LOCAL
    return _LIMITS_PATH
VERSION_F = os.path.join(ROOT, "VERSION")     # the game_loop commit sha install.sh copied in
UPDATE_CACHE_F = os.path.join(ROOT, ".update_cache.json")  # cached latest-sha lookup (gitignored)

SESSION = None  # sanitized id of the session this invocation belongs to, or None


def sanitize_session(sid):
    """A session id becomes a directory name — keep it to safe characters, bounded length."""
    if not isinstance(sid, str) or not sid.strip():
        return None
    return re.sub(r"[^A-Za-z0-9._-]", "-", sid.strip())[:64]


def env_session():
    """The session id visible to a CLI invocation (agent-run Bash exports it).

    GAME_LOOP_SESSION set-but-empty is a deliberate opt-out: it targets the repo-global legacy
    state even inside a Claude session (how a leftover pre-per-session mandate gets cleared).
    """
    if "GAME_LOOP_SESSION" in os.environ:
        return os.environ["GAME_LOOP_SESSION"]
    return os.environ.get("CLAUDE_CODE_SESSION_ID")


def set_session(sid):
    """Scope all state to one session. No id → the repo-global legacy file, unchanged behavior."""
    global SESSION, STATE_F
    SESSION = sanitize_session(sid)
    STATE_F = os.path.join(SESSIONS_DIR, SESSION, "state.json") if SESSION else LEGACY_STATE_F

DEFAULT_CONFIG = {
    "project_name": os.path.basename(REPO_ROOT) or "project",
    "read_roots": [],          # extra dirs where `claim --read` may resolve a path
    "allow_write_roots": [],   # extra dirs the write guard permits (beyond the repo + scratchpad)
    "deploy_verbs": [],        # extra irreversible verbs the guard blocks anywhere
    "generated_globs": [],     # extra generated/vendored paths the commit blast-radius warning skips
    "trans_nudge_every": 12,   # phase transitions between retro nudges
    # Evidence work (claims, hardens, fix proofs) between retro nudges. The transitions counter above
    # cannot fire on its own: it counts an OPTIONAL verb, and in this repo's whole history `trans`
    # ran once against twelve hardens and zero retros. This one counts work that logs itself.
    "work_nudge_every": 8,
    "retro_overdue_factor": 2,   # the nudge becomes a GATE at factor x threshold; 0 disables
    "watchdog": {"idle_sec": 30, "settle_sec": 5, "ring_cap": 3},
    # Usage-limit survival (statusline tap + limitgate + watchdog park). threshold_pct is where the
    # handoff gate closes; exhausted_pct is where the watchdog treats the session as rate-limited
    # and parks until the window resets; handoff_file resolves relative to .game_loop/.
    # Three NESTED sub-dicts are read by their own helpers rather than listed here, because
    # limits_cfg() is a shallow merge and a partial override would silently drop the keys it did not
    # name: "probe" (probe_cfg), "context" (context_cfg — the context-size trigger on the same gate,
    # which also carries the FAN-OUT BRAKE: block_spawn / spawn_threshold_tokens / spawn_verbs,
    # refusing `showrunner spawn` out of an over-large session in a way no handoff satisfies)
    # and "successor" (successor_cfg — how the next session is started). The first two default
    # OFF/inert; "successor" defaults to "auto", which is inert until somebody RUNS the verb and
    # then reads the terminal rather than a config key. Its one non-mode key,
    # "skip_permissions", defaults FALSE: true appends --dangerously-skip-permissions to the
    # successor's command line. It is NOT read from here -- config.json is tracked and seeds fresh
    # installs, so a bypass written here would travel to every clone. skip_permissions_grant()
    # reads config.local.json only, and `successor` says out loud when it finds one set here.
    "limits": {"threshold_pct": 98, "exhausted_pct": 99, "handoff_file": "HANDOFF.md"},
    # Update check: on `status`, compare the installed game_loop commit (.game_loop/VERSION, written by
    # install.sh) against the latest on the source repo's main, and note when a re-install is due. Best
    # effort, cached, network-silent-on-failure. Set update_check:false to disable.
    "update_check": True,
    "update_repo": "SupposedlySam/game_loop",
    "update_api_base": "https://api.github.com",   # override for tests
}

# THE user-owned file set — the one place it is written down (issue #30).
#
# Everything under .game_loop/ is one of three things: the tool (bin/, VERSION — always refreshed by
# install.sh), runtime state (gitignored, per-tree), or one of THESE — the project's own files, seeded
# once and never overwritten. Three readers need this set and none of them may keep its own copy:
# install.sh (what to seed, or adopt from another tree), `status` (what has drifted between two trees
# of one project), and an orchestrator provisioning worktrees, which otherwise hardcodes a list that
# goes stale the moment game_loop adds a file. It is published as `game_loop owned --porcelain`.
#
#   seed_from — where a FRESH install copies it from, relative to the game_loop payload root.
#               verify.yaml comes from templates/ because it ships EMPTY: game_loop's own rules would
#               (wrongly) fire on a new project's first commit.
#   rule      — does it define what the project ENFORCES? Two trees carrying different rule files are
#               two different projects. LEDGER.md is owned but is NOT a rule: findings are notes about
#               one tree's work and are expected to diverge, so drift there is not a finding.
OWNED_FILES = [
    {"path": "config.json",   "seed_from": ".game_loop/config.json",   "rule": True},
    {"path": "INVARIANTS.md", "seed_from": ".game_loop/INVARIANTS.md", "rule": True},
    {"path": "verify.yaml",   "seed_from": "templates/verify.yaml",    "rule": True},
    {"path": "LEDGER.md",     "seed_from": ".game_loop/LEDGER.md",     "rule": False},
]

# TWO sets, named, because there are two different questions and one flat list makes a caller GUESS
# which it is answering — which is how the answers silently diverge. "Does this tree carry the same
# harness?" is about all four. "Do these two trees enforce the same RULES?" is about the gate-carrying
# three, and only that one should stop a spawn: LEDGER.md is accumulated findings, reference and not
# a gate, so two trees are EXPECTED to write different ones and a block on that would be noise.
RULE_FILES = [o["path"] for o in OWNED_FILES if o["rule"]]
NOTES_FILES = [o["path"] for o in OWNED_FILES if not o["rule"]]

# The irreversible verbs the write guard blocks with no path needed. A copy for reporting only —
# bin/guard-writes-impl.sh owns the enforcing list, and a test asserts the two still agree, because
# a status line that understates a rail's reach is worse than no status line.
DEPLOY_VERB_DEFAULTS = ["npm publish", "yarn publish", "pnpm publish", "twine upload",
                        "gh release create", "docker push"]

DEFAULT_STATE = {
    "version": "1.0",
    "claim_count": 0,
    "hardened_count": 0,
    "trans_since_stepback": 0,
    "phase": {},
    "stop_blocks": 0,
    "mandate": {},
    "stop_ok": False,
    "stop_ok_notes": None,
    "stop_ok_setter": None,
    "watchdog_rings": 0,
    "t3_armed": None,
    "authorized": [],
    "attributed": [],  # merges declared by REF and recomputed here — one commit each (see #29)
    "watchdog_rings_total": 0,
    "stop_gate_blocks_total": 0,
    # Per-ATTACHMENT, keyed by the trigger's name: how many turn-ends in a row it has blocked, and
    # what it last did. Keyed by name rather than counted in one number because the bound is a
    # statement about ONE attachment — two of them each blocking once is not the same event as one
    # blocking twice, and a shared counter would stand the innocent one down.
    "stop_triggers": {},
    "flair_fired": [],
    "pins": [],        # load-bearing environment facts, carried so `status` re-shows them post-compaction
    "pin_seq": 0,      # monotonic id source — a released pin's id is never handed out again
    "effectors": [],   # things that ACT, proved to have acted (before/after pair) — see cmd_effector
    "instruments": [], # metrics admitted as evidence: declared harm + null/positive controls + readings
    "fixes": [],       # fixes proved by exercising what they PRODUCE — see cmd_fix (a repro is not one)
}


def now():
    return datetime.datetime.now().isoformat(timespec="seconds")


CONFIG_LOCAL_F = os.path.join(ROOT, "config.local.json")

# MACHINE-WIDE CONFIG — the layer UNDER both repo files, and not an invention here. The write guard
# has read ~/.game_loop/config.json for as long as it has had allow_write_roots, and its own comment
# names the failure that follows when only SOME readers honour a layer: "it works where you test it
# and not where it matters", which this project shipped once, when a waiting probe lived in a file
# the watchdog could not see. The python side read two files while the shell guard read three. That
# is the same shape waiting its turn, so this closes it rather than adding another half.
#
# WHY IT EARNS A LAYER. "Cap the context in every project" and "successors do not stop to ask" are
# facts about a MACHINE, not about any one checkout. With nowhere to say that, the choice had to be
# re-made per repo — in a tracked file that hands it to every clone, or in a gitignored one nobody
# remembers to create. Both failure directions are worse than a home for it.
#
# ENV-OVERRIDABLE BECAUSE A TEST MUST BE ABLE TO PIN IT. The suite builds throwaway projects, and a
# reader that reached the developer's real home would make every run depend on a file outside the
# tree under test — the same reason SAGGAR_PRESENCE_DIR is overridable, and the same race.
CONFIG_GLOBAL_F = os.path.abspath(os.path.expanduser(
    os.environ.get("GAME_LOOP_GLOBAL_CONFIG")
    or os.path.join("~", ".game_loop", "config.json")))

# The layers, BASE FIRST — later wins. One list, so "which files are config" has a single answer
# instead of one per caller; every reader below walks this rather than naming files itself.
CONFIG_LAYERS = (CONFIG_GLOBAL_F, CONFIG_F, CONFIG_LOCAL_F)

# Keys that UNION across layers instead of being replaced by the last file to name them. This
# mirrors bin/guard-writes-impl.sh's own set and must keep mirroring it: these are TRUST LISTS, and
# a machine-wide grant the guard honours while `claim --read` does not is a divergence that reads as
# a bug in whichever half you happened to test. Everything else keeps later-wins, so a project can
# still override a machine-wide scalar.
CONFIG_UNION_KEYS = frozenset({"read_roots", "allow_write_roots", "deploy_verbs",
                               "generated_globs", "mcp_read_only_tools", "mcp_standing_writes",
                               "mcp_trusted_servers"})


_CONFIG_UNREADABLE = set()


def _config_merge(base, over):
    """`over` laid onto `base` — dict into dict at EVERY depth, union for the trust lists, replace
    for everything else.

    DEEP, and it was shallow until the machine-wide layer arrived. Shallow was defensible while
    there were two files one person edited by hand: "watchdog" meant THIS watchdog block and not
    half of one, and whoever wrote the override had just read the thing they were replacing. It
    stops being defensible the moment a layer exists that a DIFFERENT decision wrote — set
    `limits.context.enabled` in your home, then let any project name `limits` for an unrelated
    reason, and the cap is silently gone. That is a run widening itself back to the default nobody
    re-chose, and nothing reports it.

    A partial override quietly losing the keys it did not restate is precisely the hazard
    `successor` used to print four lines of warning about. Merging is the fix those lines were
    standing in for, which is why they are gone: the warning described a shape that can no longer
    occur, and a warning that cannot fire is not coverage.

    LISTS REPLACE unless the key is a trust list. A machine-wide `deploy_verbs` and a project's own
    both name things that must be BLOCKED, so dropping either half is the unsafe direction and they
    add up; an ordinary list is a value somebody chose whole, and appending to it would produce a
    setting neither layer asked for.
    """
    out = dict(base)
    for k, v in over.items():
        cur = out.get(k)
        if k in CONFIG_UNION_KEYS and isinstance(v, list) and isinstance(cur, list):
            out[k] = cur + [x for x in v if x not in cur]
        elif isinstance(v, dict) and isinstance(cur, dict):
            out[k] = _config_merge(cur, v)
        else:
            out[k] = v
    return out


def config():
    """The three layers merged over the defaults: ~/.game_loop/config.json (machine-wide), then
    .game_loop/config.json (tracked), then .game_loop/config.local.json (GITIGNORED).

    config.json is a tracked, user-owned file AND the seed a fresh install copies from. So a value
    that is true of one machine -- a path, a tracked issue queue, a command that only exists here --
    does not merely clutter this repo's config: it becomes the DEFAULT for everybody who installs
    from it. This project has already had to remove one leak of exactly that kind from its docs.
    The machine-wide file is where such a value belongs: per-machine by construction, inheritable by
    no clone, and outside the repo — which means both write rails already refuse it.

    The precedent is already here and this closes the gap in it: notify.json and triggers.json are
    gitignored because they are site wiring. Config had no such home, so anything site-specific had
    to go in the tracked file or nowhere.

    A DEEP merge — _config_merge says why it stopped being shallow. `status` names when an override
    is live, because a config you cannot see is a divergence nobody can explain.
    """
    cfg = dict(DEFAULT_CONFIG)
    for f_ in CONFIG_LAYERS:
        try:
            with open(f_) as f:
                d = json.load(f)
            if isinstance(d, dict):
                cfg = _config_merge(cfg, d)
        except OSError:
            continue            # absent is a FACT: this project set no config here
        except ValueError:
            # PRESENT AND UNPARSEABLE IS NOT THAT FACT, and storing it as one is permissive. A git
            # conflict in this tracked file (two branches that both edited it — ordinary) made every
            # configured key read as unset, which for a DENYLIST rail means allow: `deploy_verbs`
            # stopped blocking and nothing said so. Found by running a consumer's own test against
            # this repo — break the file the way git would, then ask your query and your destructive
            # verb. A failed read is not a fact.
            _CONFIG_UNREADABLE.add(f_)
            continue
    return cfg


def config_unreadable():
    """Config files that EXIST and do not parse — never the ones that are simply absent."""
    config()                    # populate; cheap and already cached by callers' usage patterns
    return sorted(_CONFIG_UNREADABLE)


def config_layer_keys(path):
    """The top-level keys one config layer sets, for reporting. Never a decision."""
    try:
        with open(path) as f:
            d = json.load(f)
        return sorted(d) if isinstance(d, dict) else []
    except (OSError, ValueError):
        return []


def config_local_keys():
    """The keys config.local.json is overriding, for reporting. Never a decision."""
    return config_layer_keys(CONFIG_LOCAL_F)


def config_global_keys():
    """The keys ~/.game_loop/config.json is setting for EVERY project on this machine.

    Reported separately from the local ones rather than folded in with them, because the two answer
    different questions. A local override is a fact about this checkout, which is where the reader
    already is. A machine-wide one reaches repos they are not looking at, so the surprising case is
    the one where they open an unrelated project and find a cap or a bypass they set months ago in a
    file no repo contains — and the only moment that can be said is here.
    """
    return config_layer_keys(CONFIG_GLOBAL_F)


# Set by load() when state.json EXISTED and would not parse. Not stored in the state dict, because
# that dict gets written back and this is a fact about one process, not about the session.
STATE_UNREADABLE = None


def load():
    """Load state, seeding defaults on first run so a fresh checkout just works.

    ABSENT AND UNREADABLE ARE DIFFERENT, and this used to return the same pristine defaults for
    both. A corrupt state.json therefore read as A BRAND NEW SESSION: the mandate vanished, the
    stop gate went inert, the retro counters reset — and status said "MANDATE: none", which is
    exactly what it says for a session that never had one. Then the next save() wrote the defaults
    over the corrupt file and the mandate text was gone for good.

    That is the shape a neighbouring project reported to me the same day: unreadable rendered as
    absent, AND THEN OVERWRITTEN. Their case was a swap record; this is the file that decides
    whether an unattended run is still under orders.

    Still never raises — everything here calls load(), and a state file nobody can parse must not
    take the tool down. It sets the bytes aside first, so the answer to "what was my mandate" is
    recoverable rather than a thing to reconstruct from memory.
    """
    global STATE_UNREADABLE
    try:
        with open(STATE_F) as f:
            raw = f.read()
    except OSError:
        return dict(DEFAULT_STATE)          # absent: a genuinely fresh session, and that is fine
    try:
        s = dict(DEFAULT_STATE)
        s.update(json.loads(raw))
        return s
    except ValueError:
        kept = STATE_F + ".unreadable"
        try:
            if not os.path.exists(kept):    # never clobber an earlier copy with a later mangling
                with open(kept, "w") as f:
                    f.write(raw)
            STATE_UNREADABLE = kept
        except OSError:
            STATE_UNREADABLE = "(could not be set aside either)"
        return dict(DEFAULT_STATE)


def save(s):
    # atomic: temp file in the same dir + os.replace() (POSIX-atomic). A crash mid-write must never
    # truncate state.json and brick `game_loop status` — the compaction-recovery path.
    os.makedirs(os.path.dirname(STATE_F), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(STATE_F), prefix=".state.", suffix=".tmp")
    with os.fdopen(fd, "w") as f:
        json.dump(s, f, indent=2)
        f.write("\n")
    os.replace(tmp, STATE_F)


def logline(rec):
    # The log is SHARED across sessions (one chronological story per checkout); the sid field says
    # which session wrote each line, so attribution survives the sharing.
    stamp = {"t": now()}
    if SESSION:
        stamp["sid"] = SESSION[:8]
    with open(LOG_F, "a") as f:
        f.write(json.dumps({**stamp, **rec}) + "\n")


REFUSED_EXIT = 3   # a GATE said no. 2 stays what argparse and unhandled errors produce (#91)


def die(msg, code=REFUSED_EXIT):
    """A refusal: exit 3, and the FULL reason on BOTH stdout and stderr.

    Both halves are a consumer's report. Three refuted claims in one evening went unrecorded
    because a refusal read as success: it exited 2 exactly like a typo does, and its reason was on
    the one stream a quiet hook discards. They wrote a 36-line wrapper to recover the distinction,
    which is every consumer paying for something this can decide once.

    THIS DOCSTRING USED TO DESCRIBE A DESIGN THIS FUNCTION NO LONGER HAS -- "reason on STDOUT, one
    line on stderr", and a paragraph arguing NOT to duplicate. The code below duplicates in full,
    and the comment inside it explains why that argument lost. The prose above the code and the
    comment inside it disagreed, in the one function that defines what a refusal IS, and a reader
    who trusted the docstring would have believed stderr carries a pointer rather than the reason.
    Corrected rather than deleted: the argument it made is real, and losing it would invite someone
    to re-make it.

    The cost is duplication on a terminal. That is smaller than either failure it sits between --
    stderr-only is swallowed by `2>/dev/null`, and stdout-only breaks every consumer already
    reading stderr.
    """
    text = "GAMELOOP ✗ " + msg
    # BOTH STREAMS, which is what the reporter asked for and I first talked myself out of on
    # aesthetics. `2>/dev/null` is what anyone writes to keep a hook quiet, so a reason that lives
    # only on stderr is a reason a quiet hook discards — and a refusal nobody sees reads as success.
    # Only on stdout would have broken every consumer already reading stderr. Duplication on a
    # terminal is the price, and it is smaller than either failure.
    print(text)
    print(text, file=sys.stderr)
    sys.exit(code)


def out(*lines):
    print("\n".join(lines))


def flair_lines(s, event=None):
    """Return fun assist + milestone lines (and persist any newly-fired milestones). Never raises."""
    if flair is None:
        return []
    lines = []
    try:
        if event:
            line = flair.assist(event)
            if line:
                lines.append(line)
        msgs, new = flair.milestones(s)
        if new:
            s.setdefault("flair_fired", []).extend(new)
            save(s)
        lines += msgs
    except Exception:  # noqa: BLE001 — decoration must never break a command
        return lines
    return lines


def flair_out(s, event=None):
    """Print flair to stdout after a normal command."""
    for line in flair_lines(s, event):
        out(line)


_INV_FALLBACK = ("INV: enforcement-in-tools-not-instructions · READ-a-real-file-before-claiming · "
                 "no-gate-without-an-observed-failure · a-guard-must-never-block-its-own-fix · "
                 "ENCODE-don't-remember · the-outside-view-outranks-my-attachment")


def inv_oneline():
    """One-line INV summary for status — sourced from the PROJECT's INVARIANTS.md, not hardcoded.

    Parses the `## INVn — <title>` headings a migrator actually edits, so status reflects their north
    star the same way stepback does. Falls back to game_loop's built-in creed if the file is missing or
    has no recognizable headings — status must never break just because INVARIANTS.md was reshaped.
    """
    try:
        with open(INV_F) as f:
            titles = re.findall(r"^##\s+INV\d+\s*[—–:.-]*\s*(.+?)\s*$", f.read(), re.MULTILINE)
    except OSError:
        titles = []
    if titles:
        return "INV: " + " · ".join(titles)
    # AND SAY WHICH CREED THIS IS. The fallback used to print as a bare `INV: ...` — identical in
    # shape to the project's own, so "these are YOUR invariants" and "I could not read yours, here
    # is game_loop's" were one observable. The fallback is also STALE by construction: it is a
    # hardcoded six-item list maintained separately from anybody's INVARIANTS.md, so a project
    # whose headings get reshaped silently starts being shown a shorter, different creed as if it
    # were theirs — and the reshaping is the likeliest way to get here.
    #
    # Still never breaks status, which is why the fallback exists. It just stops lying about whose
    # north star it is quoting.
    return (_INV_FALLBACK + "\n"
            "  ⚠ THAT IS game_loop's OWN CREED, NOT THIS PROJECT'S — no `## INVn — <title>` "
            "headings were readable in\n"
            f"    {INV_F}. Restore that heading shape and status quotes your invariants again.")


# Cost ladder, cheapest -> most expensive. T3 is the only hard-gated rung: it is the human's
# attention, the one genuinely scarce resource in an unattended run.
TIER_NAMES = {
    "T0": "read source (this repo / deps / our own docs)",
    "T1": "research subagents (free, no human)",
    "T2": "build & verify (analyze / test / actually run it)",
    "T3": "the human's attention (a question / decision / a claim that changes their plan)",
}


# ── display ────────────────────────────────────────────────────────────────────────────────────────

def _vw(l):
    return len(l) + l.count("▸") + l.count("→")


def _box(lines):
    w = max((_vw(l) for l in lines), default=0)
    top = "╭─" + "─" * (w + 1) + "╮"
    bot = "╰─" + "─" * (w + 1) + "╯"
    body = ["│ " + l + " " * (w - _vw(l)) + " │" for l in lines]
    return "\n".join([top] + body + [bot])


def phase_head_note(ph, head=None, ahead=None):
    """The phase line was written at a COMMIT; say so once the tree has moved past it.

    THE DATE IS NOT THE SCOPE, and `phase_written_note` beside this says why in its own words:
    "the decision was written to the record WITH the thing that scopes it, and the reader ignored
    the scope. There the scope was a HEAD; here it is a date." It was right about the shape and
    the date is only half of it.

    OBSERVED, SAME DAY, TWICE IN ONE SESSION. A phase written at 00:22 was three commits stale by
    00:47 — so `phase_written_note` was correctly silent (same day, nothing to correct about the
    prose) while the phase itself claimed an open gap that had been closed two commits earlier.
    The watchdog then quoted that line back as current state to argue the session was idle. A
    banner is read as a description of the tree, and nothing compared it to the tree.

    PURE, and the git calls live at the call site, because `phase_written_note` is a TWIN carried
    separately in bin/watchdog and the lesson recorded there is that a copy which is hard to drive
    is a copy that silently diverges. Both of these take their facts as arguments so both can be
    driven against the same table.

    THREE ANSWERS, AND "COULD NOT TELL" ONLY SPEAKS WHEN THERE IS SOMETHING TO COMPARE:
      * no recorded head — a phase stamped before this existed. Silent: accusing a record that
        never claimed a commit would be a false report, and every consumer upgrading has one.
      * a recorded head and git could not answer — ONE line saying so. It is rare by construction
        (it needs a stamped phase AND a git that will not respond) and it is exactly the case
        where silence would read as agreement.
      * moved — name both commits and the distance.
    """
    if not isinstance(ph, dict):
        return ""
    was = str(ph.get("head") or "").strip()
    if not was:
        return ""
    if not head:
        return ("  phase stamped at %s; COULD NOT READ HEAD to compare — this is not agreement, "
                "nothing was compared" % was[:8])
    if head.startswith(was) or was.startswith(head):
        return ""
    if ahead is None:
        return ("  ⚠ phase was written at %s and HEAD is %s — the distance could not be counted, "
                "but they are not the same commit" % (was[:8], head[:8]))
    return ("  ⚠ phase was written at %s · HEAD is now %s, %d commit(s) later — anything it says "
            "about the tree describes THAT commit" % (was[:8], head[:8], ahead))


def phase_head_facts(ph):
    """(current HEAD short sha or None, commits HEAD is past the phase's head or None).

    The impure half, kept apart so the note above can be driven from a table. Never raises — `_git`
    degrades to None on a missing binary, no repo, or a locked index, and both halves of this read
    as "could not tell" rather than as zero.
    """
    head = _git("rev-parse", "--short", "HEAD")
    was = str((ph or {}).get("head") or "").strip() if isinstance(ph, dict) else ""
    if not (head and was):
        return head, None
    n = _git("rev-list", "--count", "%s..HEAD" % was)
    try:
        return head, int(n)
    except (TypeError, ValueError):
        return head, None


def phase_written_note(ph, when=None):
    """How old the phase line is, but ONLY once it is old enough to lie — "" on the same day.

    THE TWIN of the function of the same name in bin/watchdog, and it has to stay one, for the
    reason _config_merge's twin states there: the watchdog is standalone and imports nothing
    from here, so a fix applied to one copy and not the other works where you test it and not
    where it matters. `status` is the higher-traffic caller — CLAUDE.md tells every session to
    run it first — and the watchdog is where the staleness was actually read.

    `trans` has always stamped `phase["since"]`, and nothing has ever read it back. So a phase
    written on one day keeps being re-printed on the next, and every relative date inside it —
    "today", "this morning", "earlier" — silently re-points at whatever day the reader is having.
    OBSERVED TWICE in one run: a banner saying "FOUR fixes today" about the previous day, and then
    a banner saying "#125 ARRIVED TODAY" that went on saying it across a date rollover. Both were
    repaired by hand, which is rung 0 and lasts until the next rollover.

    This is behaviour 56's shape exactly, one file over: the decision was written to the record
    WITH the thing that scopes it, and the reader ignored the scope. There the scope was a HEAD;
    here it is a date.

    SAME-DAY IS SILENT, deliberately. A note on every banner is a note nobody reads by the third
    one, and on the day it was written the prose is simply true — there is nothing to correct.
    Negative ages (a clock that moved backwards, a phase stamped in the future) are treated as
    same-day rather than reported: this is a readability aid, and an aid that starts making
    accusations about the clock has become a different feature.

    WHAT IT DOES NOT DO: it does not read the prose. A phase with no relative dates in it gets the
    note too, and a phase written twenty minutes before midnight gets it eight hours later. Both
    are over-reports of a fact that is true — this text is from an earlier day — and the honest
    alternative, guessing which words are time-relative, fails in the direction that matters by
    staying quiet about a stale "today" it did not recognise.
    """
    since = (ph or {}).get("since")
    if not since:
        return ""
    try:
        wrote = datetime.datetime.fromisoformat(since)
    except (TypeError, ValueError):
        return ""
    days = ((when or datetime.datetime.now()).date() - wrote.date()).days
    if days < 1:
        return ""
    return (f"written {wrote.date().isoformat()} · {days} day{'s' if days != 1 else ''} ago — "
            f'any "today" in it means THAT day')


def render_banner(s, frm=None):
    ph = s.get("phase", {})
    name = config().get("project_name", "project").upper()
    if not ph.get("tier"):
        # Fresh state — no phase transition has run yet. A row of "?"s reads as broken to a first-time
        # integrator, so say plainly that the run just hasn't started rather than that something failed.
        return _box([
            f"{name} ▸ T0",
            "no phase yet — run `game_loop trans` to set one",
            f"not started · claims {s.get('claim_count', 0)} · hardened {s.get('hardened_count', 0)}",
        ])
    tier = ph.get("tier")
    arrow = f"{frm} → {tier}" if (frm and frm != tier) else tier
    doing = ph.get("doing", "")
    head = f"{ph.get('milestone', '?')} · {doing}".rstrip(" ·") if doing else ph.get("milestone", "?")
    return _box([
        f"{name} ▸ {arrow}",
        head,
        f"{TIER_NAMES.get(tier, tier).split(' (')[0]} · claims {s.get('claim_count', 0)} · "
        f"hardened {s.get('hardened_count', 0)}",
    ] + ([note] if (note := phase_written_note(ph)) else [])
      + ([hn] if (hn := phase_head_note(ph, *phase_head_facts(ph))) else []))


def retro_overdue(s):
    """PAST the nudge by a wide margin — the point where advice has demonstrably not worked.

    Reported by a human watching several machines: agents ignore the nudge, never re-check it, and
    when asked will happily say the retro is past due. That is the nudge working exactly as designed
    and the design being wrong — `status` prints a sentence, and a sentence is a thing to remember.
    INV1 has one test: if the agent ignored every instruction, would this still hold? It did not.

    A WIDE MARGIN on purpose. The nudge stays a nudge for a whole threshold's worth of work, so an
    agent mid-chapter is never yanked out of it; the gate closes only once the count says the nudge
    has been passed over for as long again. Config-tunable, and a project that wants no gate sets
    the factor to 0.
    """
    cfg = config()
    factor = cfg.get("retro_overdue_factor", 2)
    if not factor:
        return None
    t, w = s.get("trans_since_stepback", 0), s.get("work_since_stepback", 0)
    t_every = cfg.get("trans_nudge_every", 12) * factor
    w_every = cfg.get("work_nudge_every", 8) * factor
    if w >= w_every:
        return (f"{w} pieces of evidence work since the last retro (the gate closes at {w_every})")
    if t >= t_every:
        return (f"{t} transitions since the last retro (the gate closes at {t_every})")
    return None


def retro_nudge(s):
    """Due-for-a-retro, measured on work that ACTUALLY HAPPENS.

    This nudge was unreachable for the whole life of the project, and the arithmetic says why: it
    counted `trans` only, `trans` had run ONCE in the log's entire history, and the threshold was 12.
    Nothing was broken — the counter simply never moved, so the check could not fire, and its
    silence read exactly like "no retro is due". Meanwhile `harden` had run twelve times and
    `stepback` zero, which is the retro not happening at all.

    A trigger fed by an OPTIONAL bookkeeping verb is enforcement resting on the thing it is meant to
    enforce (INV1). So the second counter is fed by work that leaves a log line whether or not
    anyone remembers this feature exists: claims sourced, learnings hardened, fixes proved.
    Either counter can fire it — `trans` stays honoured for anyone who does drive phases.
    """
    cfg = config()
    t, w = s.get("trans_since_stepback", 0), s.get("work_since_stepback", 0)
    t_every, w_every = cfg.get("trans_nudge_every", 12), cfg.get("work_nudge_every", 8)
    if t >= t_every:
        return (f"⚠ {t} transitions since the last retro — `game_loop stepback --notes ..` is due "
                "(reflect, harden the chapter's learnings, reset the count).")
    if w >= w_every:
        return (f"⚠ {w} pieces of evidence work (claims, hardens, fix proofs) since the last retro — "
                "`game_loop stepback --notes ..` is due. This counter exists because the "
                "transitions one counted a verb nobody runs, and so never fired.")
    return None


# ── triggers ──────────────────────────────────────────────────────────────────────────────────
#
# A place for a project to attach ITS OWN action to a moment in the loop. game_loop cannot ship the
# actions themselves: the one that prompted this is broadcasting a generalised learning to a channel
# other agents read, and most installs have no such channel, no other agents, and no wish to talk to
# anyone at all. A rule that cannot apply to everyone must not be wired in for everyone — so the
# harness owns the MOMENT, and the project owns what happens there.
#
# Config lives in triggers.json, which is GITIGNORED, exactly like notify.json and for the same
# reason: it is site wiring, not product. config.json is tracked and would ship one machine's paths
# and room names to every cloner.
#
# Three rules, each a scar:
#   * NEVER BLOCKS. A trigger that fails must not stop a learning from being hardened — the work
#     outranks the announcement, and a broadcast that can veto the thing it reports on is a guard
#     blocking its own fix (INV5).
#   * NEVER SILENT. Failure, timeout and a command that cannot be found all SAY so. A missing
#     trigger is the usage-limit tap over again: three gates fed by one file nobody noticed was
#     never written (INV8).
#   * ALWAYS ACCOUNTED. Every configured trigger carries its last outcome in state, so `status`
#     can name one that has never fired. "Configured" and "working" are different claims.
TRIGGERS_F = os.path.join(ROOT, "triggers.json")

# The moments the loop publishes. Adding one is a deliberate act: a moment nobody attaches to is
# dead weight, and a moment that fires on a hot path turns a helpful hook into a tax.
TRIGGER_EVENTS = {
    "harden": "a learning was just encoded into an artifact — the moment to GENERALISE and share it",
    "stepback": "a retro just began — the moment to LEARN from what others have shared",
    # `confidence --mark` is the exact instant "ready for consumers" stops being an intention and
    # becomes a fact about a sha. Anything downstream that distributes this project -- a package
    # manager, a mirror, an announcement -- wants to happen HERE and nowhere else. Left to memory it
    # does not happen: the first stable mark was published by a downstream maintainer who happened
    # to be watching, not by the person who marked it.
    "confidence": "a commit was just marked — the moment to publish it wherever consumers take it",
    # THE ONE MOMENT THAT IS NOT A VERB SOMEBODY TYPED (#63). `sessionstart` already runs at the
    # right instant and can TELL a session things; what it could not do is ACT once on the session's
    # behalf, and the only way to get that was a SECOND SessionStart hook beside game_loop's — a
    # second registrant in one settings file, which makes "registered vs has-fired vs firing-now"
    # harder to diagnose in exchange for no new capability.
    #
    # TWO THINGS DIFFER FROM THE OTHER THREE, and both are the reader's problem if left unsaid
    # (INV6). It runs on the session's CRITICAL PATH, so the budget is per attachment: N of them
    # cost up to N timeouts before the session sees a word, and nothing here caps the sum. And it
    # fires at EVERY start and EVERY compaction, so "once per project" is the attachment's own job
    # — the payload carries `source` (startup / resume / compact) so it can tell those apart.
    "session_start": "a session just started or was compacted — the moment to ACT once on its "
                     "behalf, before it reads anything",
    # THE ONE MOMENT THAT PARTICIPATES IN A DECISION (#64). The other four are ANNOUNCEMENTS: the
    # verb has already happened, the attachment reports on it, and nothing it does can change the
    # outcome — "a trigger never blocks the work" is printed under every failure. Here the exit code
    # MEANS something: non-zero blocks turn-end and stderr goes back to the model, which is
    # cmd_stopgate's own contract handed to a command this repo did not write.
    #
    # It exists because "reply when a human addresses you" lived in prose, and prose is followed
    # sometimes: an agent asked a direct question through a chat bridge did the work and ended its
    # turn without answering. A rule the agent must remember is followed only sometimes; a rule a
    # hook consumes holds every time (INV1). The alternative was a SECOND Stop hook registered
    # beside game_loop's — two registrants deciding one turn-end, either able to end it, neither
    # able to see that the other said no.
    #
    # THREE THINGS DIFFER FROM THE OTHER FOUR, and every one of them is the reader's problem if left
    # unsaid (INV6). Its exit code is a verdict rather than a status. It runs on EVERY turn-end, so
    # its timeout is a tax on every turn and the default is small. And its condition is EXTERNAL —
    # the only block in this gate that may be satisfiable by nobody present — so it is bounded by
    # consecutive count (STOP_TRIGGER_BLOCK_LIMIT) rather than trusted to clear itself.
    "stop": "the turn is about to end — the moment to REFUSE that, if something this project can "
            "check says the turn is not actually finished",
}


def load_triggers():
    try:
        with open(TRIGGERS_F) as f:
            d = json.load(f)
    except (OSError, ValueError):
        return {}
    return d if isinstance(d, dict) else {}


def triggers_for(event):
    e = load_triggers().get(event)
    return [t for t in e if isinstance(t, dict) and t.get("command")] if isinstance(e, list) else []


def _run_trigger(s, t, event, payload, default_timeout=20.0):
    """Run ONE attachment, record it, and report what happened. Raises nothing, ever.

    Returns (name, ran, code, body, err). `ran` is the distinction the `stop` moment lives on and
    the other four do not need: True means the command REACHED A VERDICT — it exited, whatever the
    code — and False means nothing was decided, because it timed out or could not be run at all.
    Everywhere else those two collapse into "failed", correctly: an announcement that failed and an
    announcement that never ran cost the same, which is nothing. Where the exit code BLOCKS a turn
    they must never be one state — "it said no" is a refusal to honour, "it could not tell me" is a
    guard that has to fail open (INV5), and a gate that cannot tell them apart picks one at random.
    """
    name = str(t.get("name") or "(unnamed)")
    try:
        timeout = max(1.0, float(t.get("timeout_sec") or default_timeout))
    except (TypeError, ValueError):
        timeout = default_timeout
    # AN EXPLICIT VALUE WINS SILENTLY, and on the one moment where the budget is a tax somebody pays
    # every turn that is worth saying out loud. A consumer wired stop with timeout_sec: 30 against a
    # default of 10 — overriding a number chosen because this moment runs at EVERY turn-end — and
    # nothing told them they had. NOT CAPPED: a project that means 30 gets 30, and overruling a
    # consumer about their own tree is not mine to do. The defect was the silence, not the number.
    # Same family as the budget-margin reading: a value that wins without announcing it.
    over_default = None
    if event == "stop" and timeout > default_timeout:
        over_default = (timeout, default_timeout)
    # GAME_LOOP_SESSION rides along for the same reason the waiting probe gets it (#60): a
    # checkout can hold many concurrent sessions, and a trigger that cannot tell which one it is
    # speaking for cannot scope anything it reads or writes. Empty means UNKNOWN -- the legacy
    # repo-global paths -- never a session whose name is the empty string.
    env = dict(os.environ, GAME_LOOP_EVENT=event, GAME_LOOP_ROOT=ROOT, GAME_LOOP_REPO=REPO_ROOT,
               GAME_LOOP_SESSION=SESSION or "",
               GAME_LOOP_SESSION_DIR=(os.path.join(ROOT, "sessions", SESSION) if SESSION
                                      else ""))
    ran, code = True, None
    _t0 = time.time()
    near_cap = None
    try:
        r = subprocess.run(["bash", "-c", t["command"]], input=json.dumps(payload),
                           capture_output=True, text=True, timeout=timeout, env=env)
        code, body, err = r.returncode, (r.stdout or "").strip(), (r.stderr or "").strip()
        # THE MARGIN, REPORTED WHILE IT STILL EXISTS. A budget is a cap that starts out true and
        # becomes a lie as the work under it grows; nothing speaks at the moment it stops being
        # right. Measured here because this is the only place the number exists, and reported as a
        # READING rather than a failure — the run succeeded, and a warning that failed it would
        # teach people to raise the budget to silence the warning rather than to fit the work.
        _spent = time.time() - _t0
        if timeout > 0 and _spent >= timeout * 0.75:
            near_cap = (_spent, timeout)
        if code != 0 and not err:
            err = f"exited {code} with nothing on stderr"
    except subprocess.TimeoutExpired:
        ran, body, err = False, "", f"timed out after {timeout:.0f}s"
    except Exception as exc:  # noqa: BLE001 — see below; the promise above has to be true
        # NOT JUST OSError, which is what this caught while the docstring promised "raises nothing,
        # ever". A `command` that is a number rather than a string raises TypeError from inside
        # subprocess, and one badly-typed line of site config would then propagate out of a function
        # two entry points call without expecting it to. Config is somebody's typing, so anything it
        # can do to us is an ANSWER — unrunnable — never a crash.
        ran, body, err = False, "", f"could not run: {exc}"
    ok = ran and code == 0
    if over_default:
        _t, _d = over_default
        _note = (f"⚠ timeout_sec {_t:.0f}s overrides the {_d:.0f}s default for `stop`, which runs at "
                 f"EVERY turn-end — so this budget is paid on every turn, not once. Explicit values "
                 f"are honoured uncapped; omitting the key follows the default if it is ever retuned.")
        body = (body + "\n" + _note) if body else _note
    if near_cap:
        # Appended to the trigger's OWN reported text, so it travels with the thing it is about
        # rather than into a log nobody re-reads.
        _sp, _cap = near_cap
        _margin = (f"⚠ took {_sp:.0f}s of a {_cap:.0f}s budget — {_cap - _sp:.0f}s of headroom left. "
                   f"This budget will start failing silently as the work under it grows; that is how "
                   f"the publish trigger died today, three seconds over.")
        body = (body + "\n" + _margin) if body else _margin
    rec = s.setdefault("triggers", {}).setdefault(name, {})
    rec.update({"event": event, "at": now(), "ok": ok, "detail": (err or body)[:200]})
    logline({"kind": "trigger", "name": name, "event": event, "ok": ok,
             "detail": (err or "")[:200]})
    return name, ran, code, body, err


def fire_triggers(s, event, payload):
    """Run this project's attachments for `event`. Returns lines to print; raises nothing, ever.

    The payload goes in as JSON on stdin — the same shape Claude Code hands its own hooks, so anyone
    who has written one of those already knows this contract. stdout comes BACK to the agent on
    purpose: a trigger that reads a channel is useless if what it read is thrown away.

    THE `stop` MOMENT DOES NOT COME THROUGH HERE. This function's whole shape is announcement — it
    collects outcomes, prints them, and lets the verb stand no matter what any of them said. A
    moment whose exit code is a VERDICT needs the opposite shape, so it runs the same attachments
    through the same runner and decides for itself: see stop_trigger_block.
    """
    todo = triggers_for(event)
    if not todo:
        return []
    # A LOST UPDATE, OBSERVED. This used to run every trigger and then save(s), which writes back
    # the WHOLE state dict the verb loaded when it started. Triggers can be slow: lamp's publish
    # gate took ~8 minutes on 2026-09-23. Any state written during that window was silently erased,
    # and it was. A `trans` at 18:36:51 vanished when `confidence --mark` (loaded 18:34:57) saved at
    # the end of its publish trigger, and the phase line reverted to one the watchdog then quoted
    # back as current. The watchdog's own ring counters live in the same file.
    #
    # So: persist the verb's own changes BEFORE the slow part, run the triggers, then RELOAD and
    # merge in only what this function owns (its trigger records). The caller's `s` is refreshed IN
    # PLACE, because cmd_fix and cmd_stepback call save(s) again afterwards and would otherwise
    # write the stale copy one line later. If the reload cannot read the state, this falls back to
    # the old behaviour rather than swapping defaults in over real state.
    save(s)
    fired = []
    for t in todo:
        name, ran, code, body, err = _run_trigger(s, t, event, payload)
        fired.append((name, ran and code == 0, body, err))
    mine = {n: (s.get("triggers") or {}).get(n) for n, _ok, _b, _e in fired}
    global STATE_UNREADABLE
    _was_unreadable = STATE_UNREADABLE
    STATE_UNREADABLE = None
    fresh = load()
    if STATE_UNREADABLE is None and os.path.exists(STATE_F):
        fresh.setdefault("triggers", {}).update({n: r for n, r in mine.items() if r is not None})
        s.clear()
        s.update(fresh)
    STATE_UNREADABLE = STATE_UNREADABLE or _was_unreadable
    save(s)
    lines = [f"— triggers · {event} ——————————————————————————"]
    for name, ok, body, err in fired:
        if ok:
            lines.append(f"  ✓ {name}")
            lines.extend("     " + l for l in (body.splitlines() or ["(no output)"]))
        else:
            # Loud, and it says the verb still stands — otherwise the next reader assumes it didn't.
            lines.append(f"  ✗ {name} FAILED — {err or 'no detail'}")
            if body:
                lines.extend("     " + l for l in body.splitlines())
            lines.append(f"     (the {event} itself stands; a trigger never blocks the work)")
    return lines


def _minutes_since(ts):
    """Whole minutes since an ISO stamp, or None when it cannot be read.

    None is a THIRD answer and is rendered as one. A stamp this cannot parse is not zero minutes
    old, and printing "0 min ago" for it would make the freshest possible reading out of the one
    case where nothing is known.
    """
    try:
        then = datetime.datetime.fromisoformat(str(ts).replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return None
    if then.tzinfo is not None:
        then = then.replace(tzinfo=None)
    return max(0, int((datetime.datetime.now() - then).total_seconds() // 60))


def wake_landed_lines(s):
    """What is known about wakes that ACTUALLY ARRIVED (#95, the observable half of proposal 4).

    A wake that lands leaves a trace, because the run happens. A wake that was REQUESTED and never
    delivered leaves NOTHING here — the report behind this issue caught a six-hour hole only
    because the chat transport's doctor watches from OUTSIDE the session. Nothing running inside a
    stalled run can see the request that never reached it.

    So this says the one direction it can, and names the other rather than implying it covered
    both. "No wake recorded" is never "no wake arrived": it is recorded only when a woken run says
    so, and a run that never woke could not have.
    """
    w = s.get("wake_landed") or {}
    if not w.get("at"):
        return ["  NO WAKE IS RECORDED AS HAVING LANDED here. That is not evidence none did — it is",
                "  recorded only by a woken run saying so:  game_loop note --woke"]
    mins = _minutes_since(w.get("at"))
    age = "age unreadable" if mins is None else f"{mins} min ago"
    L = [f"  last wake LANDED: {w.get('at')} ({age}); {w.get('count', 1)} this session."]
    # A CADENCE GONE SILENT IS OBSERVABLE, and saying only "a missed wake is invisible" was
    # overclaiming. ONE wake that never arrived leaves nothing here — true. But a path DECLARED to
    # fire every N minutes, with nothing landed in many multiples of N, is a dead path, and this
    # run can say so with no help from outside. That gap is the whole of the report behind #95: a
    # live poller, a healthy heartbeat, and six hours since anything was delivered.
    every = int((s.get("mandate") or {}).get("wake_every") or 0)
    if every and mins is not None and mins > 3 * every:
        L += [f"  ⚠ OVERDUE — that path is declared every {every} min and nothing has landed in "
              f"{mins}.",
              f"    About {mins // every} expected wakes did not arrive. One missing wake proves",
              "    nothing; a cadence this far gone is a path that has stopped delivering."]
    elif every:
        L.append(f"  declared every {every} min, and the last is within that — the cadence holds.")
    else:
        L += ["  No cadence is declared, so a path that has STOPPED cannot be told from one nobody",
              "  has needed yet:  mandate --wake-every <minutes>"]
    L += ["  A single wake requested and never delivered is still invisible from in here — only a",
          "  CADENCE gone quiet is detectable, and only once one is declared."]
    return L


def grant_age_note(a, now_iso=None):
    """" · granted N days ago" for a grant old enough that its age is the interesting fact, else "".

    SILENT UNDER A DAY, because on the day it was granted the age says nothing anybody does not
    already know, and a note that prints on every grant is a note that stops being read — the same
    failure the bare live/spent count already demonstrated on a real reader.
    """
    at = str((a or {}).get("at") or "")[:19]
    if len(at) < 19:
        return ""
    try:
        then = datetime.datetime.fromisoformat(at)
        cur = datetime.datetime.fromisoformat(str(now_iso or now())[:19])
    except ValueError:
        return ""
    days = (cur - then).days
    if days < 1:
        return ""
    exp = (a or {}).get("expires_at")
    return " · granted %d day%s ago%s" % (days, "" if days == 1 else "s",
                                          "" if exp else ", NO EXPIRY")


def authorizations_report(s):
    """The `authorize` grants this session holds, and what is LEFT of each.

    A grant is a consumable the human paid for, and nothing showed its balance. `authorize` prints
    the count at grant time and then the number only ever moves silently — so a session cannot see
    what it holds, cannot see it being spent, and cannot see that it is already gone.

    That is not hypothetical. Twice now a probe of the write guard has consumed a standing grant:
    feeding a guard a payload is not a read, it decides and DEDUCTS exactly as a real call would.
    The second time cost two of the human's uses on a question that a throwaway GAME_LOOP_HOME
    would have answered for nothing. Reporting the balance is what turns "spent without noticing"
    into a number that was on screen beforehand.

    SPENT GRANTS ARE COUNTED, NOT LISTED. A used-up grant is not clutter to hide — it is the record
    that a hatch was opened, and a session that sees only live ones cannot tell "never authorized"
    from "authorized and exhausted", which are different answers to "may I do this".
    """
    auth = [a for a in (s.get("authorized") or []) if isinstance(a, dict)]
    if not auth:
        return []
    _n = now()
    live = [a for a in auth if grant_live(a, _n)]
    # AN EXPIRED GRANT IS NOT A SPENT ONE EITHER, and it is not revoked: nobody withdrew it and
    # nobody used it, the clock closed it. Three ways to stop being live, three counts.
    expired = [a for a in auth if grant_expired(a, _n) and int(a.get("uses_left") or 0) > 0]
    # A REVOKED GRANT IS NOT A SPENT ONE. Folding them together would say a hatch was opened and
    # used when it was withdrawn unused — the same conflation the `--revoke` refusal exists to
    # prevent, one surface over. The extra clause appears only once something has been revoked, so
    # no consumer's status line moves until they use the verb.
    dead = [a for a in auth if int(a.get("uses_left") or 0) <= 0]
    revoked = [a for a in dead if a.get("revoked_at")]
    spent = len(dead) - len(revoked)
    L = ["", "authorize grants: %d live, %d spent%s%s"
         % (len(live), spent, (", %d revoked" % len(revoked)) if revoked else "",
            (", %d lapsed" % len(expired)) if expired else "")]
    for a in live[:6]:
        # THE AGE, BESIDE THE BALANCE. wcs read past "5 live, 6 spent" on every run of a long
        # session and then reported that status did not surface grants at all — so the count alone
        # is demonstrably not enough to make a stale grant look stale. An age is the one number
        # that says which of these was a decision made for the work in front of you.
        L.append("  %3d left · %s%s" % (int(a.get("uses_left") or 0), a.get("path"),
                                        grant_age_note(a, _n)))
    if len(live) > 6:
        L.append(f"  ... and {len(live) - 6} more live")
    L.append("  A GRANT IS A CONSUMABLE, and running a guard SPENDS one — a probe decides and")
    L.append("  deducts exactly as a real call does. To ask what a guard would say, read its source")
    L.append("  or point GAME_LOOP_HOME at a throwaway tree.")
    return L


def wake_path_report(s):
    """Say when a mandate is armed and NOBODY HAS SAID how an external signal reaches this run (#95).

    Every gate here fires from INSIDE the session — the Stop gate, the watchdog, the limit gate —
    which is precisely what stops working when a run goes quiet. A consumer's run sat inert for six
    hours with all three reporting healthy while its chat transport's own doctor said no wake had
    landed. I hit the same thing the same week, for 303 minutes.

    A DECLARATION, NOT A PROBE, and the difference is stated where it is printed: game_loop cannot
    see a host's cron and does not pretend to. What it can do is refuse to let "nobody has said"
    look like "there is one".
    """
    m = s.get("mandate") or {}
    if not m.get("active") or m.get("parked"):
        return []
    if m.get("wake_path"):
        return ["", f"wake path (declared): {m['wake_path']}",
                "  A DECLARATION, not a probe — nothing here has verified a signal actually lands."
                ] + wake_landed_lines(s)
    return ["", "⚠ MANDATE ARMED, AND NO EXTERNAL WAKE PATH IS RECORDED.",
            "  Every gate here fires from INSIDE this session — which is the thing that stops",
            "  working when the run goes quiet. If nothing outside can reach you, an inert run and",
            "  a healthy one look identical from in here, and they did for six hours in the report",
            "  that prompted this.",
            "    game_loop mandate --set \"..\" --wake-path \"<how a signal reaches this session>\"",
            "  A cron that pokes the session, a Stop-hook waker, a human who checks. Recording it is",
            "  a declaration and is worth less than a probe; not recording it is worth nothing."]


def guards_report():
    """Registered project guards, each ACTIVE / INERT / UNKNOWN — never silently healthy (#90).

    A guard can be structurally disabled by the state it reads: `grep -qi '^lead' .game_loop/seat
    || exit 0` is inert the moment that file says anything else, and an exit 0 from a satisfied
    guard is byte-identical to an exit 0 from a disabled one. Sixteen hours of a run in that state
    looked exactly like sixteen hours of compliance.

    ABSENT PROBE => UNKNOWN, NEVER ACTIVE. A guard nobody can interrogate must not render as
    healthy; promoting "could not ask" to "fine" is the failure this exists to refuse, rebuilt.
    """
    guards = config().get("guards") or []
    if not isinstance(guards, list) or not guards:
        return []
    lines = ["GUARDS — this project's own PreToolUse gates, and whether they can fire at all:"]
    n_inert = n_unknown = 0
    for g in guards:
        if not isinstance(g, dict):
            continue
        name = str(g.get("name") or g.get("script") or "(unnamed)")
        script = g.get("script")
        if script and not os.path.exists(os.path.join(REPO_ROOT, str(script))):
            n_inert += 1
            lines.append(f"  ✗ {name} — INERT: its script is not in this tree ({script})")
            continue
        probe = g.get("probe")
        if not probe:
            n_unknown += 1
            lines.append(f"  ? {name} — UNKNOWN: no probe declared, so whether it can fire at all "
                         "was never asked.")
            lines.append("      A guard nobody can interrogate is not a guard reported healthy. "
                         "Give it a `probe`:")
            lines.append('      config.json -> guards: [{"name": .., "script": .., "probe": '
                         '"<command; exit 0 = it would evaluate>"}]')
            continue
        try:
            r = subprocess.run(["bash", "-c", str(probe)], cwd=REPO_ROOT, capture_output=True,
                               text=True, timeout=10)
        except (OSError, subprocess.TimeoutExpired) as exc:
            n_unknown += 1
            lines.append(f"  ? {name} — UNKNOWN: its probe did not answer "
                         f"({type(exc).__name__}). NOT the same as active.")
            continue
        if r.returncode == 0:
            lines.append(f"  ✓ {name} — ACTIVE: its probe says it would evaluate.")
        else:
            n_inert += 1
            detail = ((r.stdout or "") + (r.stderr or "")).strip().split("\n")[0][:100]
            lines.append(f"  ✗ {name} — INERT: the state it reads disables it"
                         + (f" — {detail}" if detail else f" (probe exit {r.returncode})"))
            lines.append("      It is registered and it runs and it returns 0, which is what a "
                         "SATISFIED guard returns.")
    if n_inert or n_unknown:
        lines.append(f"  → {n_inert} INERT · {n_unknown} UNKNOWN. An enabling condition the agent "
                     "can WRITE is an off")
        lines.append("    switch, and it gets flipped at the moment the agent is most stuck. "
                     "Derive it instead.")
    return lines


def triggers_report():
    """Silent when a project has attached nothing — most installs want no part of this.

    Once something IS attached, silence becomes the failure mode worth naming: a trigger that has
    never fired looks identical, from outside, to one that fires perfectly every time.
    """
    cfg = load_triggers()
    entries = [(ev, t) for ev in cfg for t in triggers_for(ev)]
    if not entries:
        return []
    s = load()
    seen = s.get("triggers") or {}
    lines = ["TRIGGERS — this project's own attachments to the loop:"]
    for ev, t in entries:
        name = str(t.get("name") or "(unnamed)")
        rec = seen.get(name)
        if ev not in TRIGGER_EVENTS:
            # NOT THE SAME AS "hasn't happened yet", and game_loop is the only party that can tell
            # them apart. A neighbouring project can assert that its own docs agree with each other
            # about which moment to recommend — agreement is all it can check — but whether that
            # moment EXISTS is a fact about this tool, falsifiable only here. Wired to a name
            # game_loop does not have, a trigger never fires, and "never fired" reads as patience.
            lines.append(f"  ✗ [{ev}] {name} — THERE IS NO SUCH MOMENT. This will never fire, no "
                         "matter how long you wait.")
            lines.append("      game_loop's moments are: " + " · ".join(sorted(TRIGGER_EVENTS)))
            continue
        if ev == "session_start" and not config().get("session_start", True):
            # A FOURTH state, and only this moment can be in it. The moment exists, the wiring is
            # right, and `session_start: false` has switched the whole entry point off — so the
            # attachment waits forever while "CONFIGURED BUT NEVER FIRED" reads as patience. The
            # opt-out is written by somebody who wants no injected status block; nobody typing it
            # is thinking about an attachment added months earlier, which is exactly why the harness
            # has to be the one that remembers.
            lines.append(f"  ✗ [{ev}] {name} — SWITCHED OFF by config.json session_start:false, so "
                         "this moment never comes round. Not waiting — disabled.")
            continue
        if not rec:
            lines.append(f"  ⚠ [{ev}] {name} — CONFIGURED BUT NEVER FIRED in this tree. Either the "
                         f"moment has not come round yet, or it is not wired to anything.")
        else:
            mark = "✓" if rec.get("ok") else "✗"
            lines.append(f"  {mark} [{ev}] {name} — last {rec.get('at')}"
                         + ("" if rec.get("ok") else f" · FAILING: {rec.get('detail') or '?'}"))
        # THE STOP MOMENT'S EXTRA STATE, because "FAILING" is the wrong word for it and would be
        # read as harmless. Everywhere else a failing attachment costs an announcement; here it is
        # holding the turn shut, or it has stopped being able to, and those are different enough
        # that a session asking "why did this not stop" must not have to reconstruct them from the
        # log. Three verdicts, three lines, and the third one is the one nobody would guess.
        st = ((s.get("stop_triggers") or {}).get(name) or {}) if ev == "stop" else {}
        if st.get("verdict") == "stood_down":
            lines.append(f"      STOOD DOWN — it blocked {st.get('consecutive')} consecutive "
                         f"turn-ends, past its bound of {STOP_TRIGGER_BLOCK_LIMIT}, and is now "
                         "OVERRIDDEN: turn-end no longer waits on it. It is still running, and one "
                         "pass resets the count and puts it back in charge.")
        elif st.get("verdict") == "failed_open_error":
            lines.append(f"      FAILED OPEN — it could not answer ({st.get('detail') or '?'}), so "
                         "the last turn-end went UNCHECKED. Not a pass: nothing was decided.")
        elif st.get("consecutive"):
            lines.append(f"      BLOCKING turn-end — {st.get('consecutive')} consecutive of "
                         f"{STOP_TRIGGER_BLOCK_LIMIT} before it stands down.")
    # A DEAD CONDITION, which is the same failure as a dead moment one level in (#87). The block
    # above catches a trigger wired to a moment that does not exist; this catches one wired to the
    # right moment and matching a RECORD KIND nothing here ever writes. Reported by an author who
    # made that mistake twice in two triggers — nothing corrected the first — and then wrote a test
    # suite from the same wrong mental model, so the suite passed while both guards were dead.
    for fname, kind in trigger_dead_kinds():
        lines.append(f"  ✗ {fname} matches kind {kind!r}, WHICH NOTHING HERE EVER WRITES.")
        lines.append("      It cannot fire, and exit 0 is also what a satisfied guard does — so "
                     "broken and quiet")
        lines.append("      are the same observable from outside. → game_loop kinds")
    unused = [e for e in TRIGGER_EVENTS if not triggers_for(e)]
    if unused:
        lines.append("  → moments with nothing attached: " + ", ".join(sorted(unused)))
    return lines


# ── source resolution ───────────────────────────────────────────────────────────────────────────

def resolve_read(p):
    """Resolve a path as-is, or under any configured read root.

    The keystone invariant is that the file EXISTS and was read — not that it is contained in the repo.
    An absolute path to any real, non-empty file resolves (that is the point: you cite the sibling repo
    you actually read). read_roots only add extra bases for RELATIVE paths — a convenience, not a fence.

    read_roots are READ roots (dependency source, reference repos). Being resolvable here confers no
    write permission — writes are blocked separately and mechanically by the write guard, because a
    rule that lives only here is a rule that lives only in prose.
    """
    for cand in [p] + [os.path.join(r, p) for r in config().get("read_roots", [])]:
        cand = os.path.expanduser(cand)
        if os.path.isfile(cand) and os.path.getsize(cand) > 0:
            return os.path.realpath(cand)
    return None


# ── usage limits ─────────────────────────────────────────────────────────────────────────────────
#
# Claude Code exposes subscription rate limits ONLY through the statusline stdin payload:
# rate_limits.five_hour / .seven_day, each {used_percentage: 0..100, resets_at: unix epoch}.
# No hook event, headless flag, or local file carries them (verified 2026-07; see LEDGER.md), so the
# tap is a statusline command (`game_loop statusline`) that snapshots the payload to limits.json.
# From that snapshot: `limitgate` (PreToolUse) demands a handoff file once a window crosses
# threshold_pct, and the watchdog parks an exhausted run and rings it awake when the window resets.
#
# WHAT THIS MISSES, stated plainly: the per-model weekly limit is not in the payload — only the 5h
# and 7d windows are visible. And the snapshot only refreshes while statusline events fire (API
# responses / a refreshInterval), so a session that never rendered a statusline has no snapshot and
# every gate here fails OPEN. Absence of limits.json is absence of signal, not evidence of headroom.

WINDOW_LABELS = {"five_hour": "5h", "seven_day": "7d"}


def limits_cfg():
    """config.json -> limits, merged over defaults (config() is a shallow update by design)."""
    merged = dict(DEFAULT_CONFIG["limits"])
    lc = config().get("limits")
    if isinstance(lc, dict):
        merged.update(lc)
    return merged


def context_cfg():
    """The context-size trigger's settings, OFF unless a human turned it on.

    A SECOND TRIGGER ON MACHINERY THAT ALREADY EXISTS. The usage trigger asks "is the account nearly
    out"; this one asks "is this session's context now so large that every remaining call overpays
    for it". They want the same thing at the end — the run's state written down before it moves —
    so they share one gate rather than growing a second one beside it.

    Why context is worth a trigger at all, measured rather than assumed: over one week on this
    account, 80.7% of the spend was cache reads — the same context re-sent on every call, 5.87
    billion tokens across 25,546 calls against 15.7M output tokens. Cost is the integral of context
    size over calls, so a session that never resets pays for its whole history on every turn.

    Default-OFF, like probe_cfg() and for the same reason: it interrupts a run somebody is watching,
    which should be a decision they made rather than one they inherited.

    IT CARRIES A SECOND VERB (`block_spawn`), because the first one did not hold. Demanding a handoff
    and then OPENING is the whole failure this repo watched happen: the gate closed, the agent wrote
    the handoff, the gate opened, and the orchestrator went straight back to spawning Crawlers out of
    a session that was already the expensive part. A handoff answers "is this written down"; it
    cannot answer "should this session be starting new work", and nothing was asking the second
    question. `block_spawn` asks it, and no handoff satisfies it — only a smaller session does.

    It reads its own sub-dict with its own defaults instead of joining DEFAULT_CONFIG["limits"],
    because limits_cfg() is a SHALLOW merge — a user who set only `threshold_tokens` there would
    silently lose every key they did not name.
    """
    lc = (config().get("limits") or {})
    c = lc.get("context") if isinstance(lc.get("context"), dict) else {}
    try:
        thr = int(c.get("threshold_tokens", 300000) or 300000)
    except (TypeError, ValueError):
        thr = 300000                    # a threshold nobody can parse is not a threshold
    # THE SPAWN CAP IS A SECOND, HIGHER BAR ON THE SAME READING. The handoff demand and the
    # spawn refusal want different points on one curve: "write down where you are" is cheap and
    # should come early, while "you may not start new work" is disruptive and should come late. One
    # threshold cannot be both, so `spawn_threshold_tokens` defaults to threshold_tokens and is
    # raised by anyone who wants the handoff nudge long before the brake.
    try:
        sthr = int(c.get("spawn_threshold_tokens", thr) or thr)
    except (TypeError, ValueError):
        sthr = thr
    # DENYLIST, and it defaults NON-EMPTY unlike deploy_verbs — because the cost of the two misses
    # runs opposite ways. A deploy verb nobody listed fires once and is irreversible, so that rail
    # must not guess; a fan-out verb nobody listed merely keeps spending, and the one verb every
    # install of this harness ships beside is `showrunner spawn`. Listing it is not a guess.
    verbs = c.get("spawn_verbs")
    if not isinstance(verbs, list) or not verbs:
        verbs = ["showrunner spawn"]
    return {"enabled": bool(c.get("enabled", False)), "threshold_tokens": thr,
            "block_spawn": bool(c.get("block_spawn", True)),
            "spawn_threshold_tokens": sthr,
            "spawn_verbs": [str(v) for v in verbs if str(v).strip()]}


def handoff_path():
    """PER SESSION, like all written state: two sessions sharing a checkout each hand off into their
    own sessions/<id>/ dir, so one run's dying words can never overwrite another's. No session id
    (a human terminal) falls back to the repo-global .game_loop/HANDOFF.md, as ever."""
    name = limits_cfg().get("handoff_file", "HANDOFF.md")
    if SESSION:
        return os.path.join(SESSIONS_DIR, SESSION, name)
    return os.path.join(ROOT, name)


def watchdog_pidfile():
    """Mirrors bin/watchdog's PID_PATH exactly — per session, and for its reason: a shared pidfile
    would let one session's hook kill another session's armed watchdog. Two files, one convention;
    if either moves, both move."""
    if SESSION:
        return os.path.join(SESSIONS_DIR, SESSION, ".watchdog.pid")
    return os.path.join(ROOT, ".watchdog.pid")


PROC_GONE = "\x00gone"     # mirrors bin/watchdog: ps ran and there is no such process


def watchdog_pid_identity(pid):
    """The start time ps reports for a pid, or None if it could not be read. Mirrors bin/watchdog's
    _proc_start() — see the note on watchdog_pidfile(): two files, one convention."""
    try:
        r = subprocess.run(["ps", "-o", "lstart=", "-p", str(pid)],
                           capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return None                      # could not look. NOT evidence about the process.
    out = (r.stdout or "").strip()
    if out:
        return out
    # ps RAN and reported nothing: that pid is gone, which is an ANSWER. Distinct from the None
    # above, which is silence about a machine rather than about a process. See bin/watchdog's
    # PROC_GONE — two files, one convention.
    return PROC_GONE if r.returncode != 0 else None


def _writer_mark():
    """Who wrote a permission into this state file, as far as anything here CAN know (#94).

    checkpoint and arm both write a PERMISSION -- a turn-end the Stop gate will spend, and a T3 the
    human will answer -- and an in-process subagent inherits CLAUDE_CODE_SESSION_ID, so both land in
    the PARENT's state file. #88 guards `mandate --set` against exactly this and keys on the WORDS,
    because the two callers are indistinguishable by identity: same session id, and the pid differs
    on every CLI invocation including legitimate ones.

    So this does not claim to identify anybody. It records what is mechanically true at the moment
    of writing, and the CWD is the part that can actually differ: a subagent dispatched into its own
    worktree writes from a different tree, and that crossing is nameable. A same-tree in-process
    subagent is NOT distinguishable here and this must not be read as though it were -- what catches
    that case is the same thing #88 relies on, the words being ones you do not recognise.
    """
    return {"pid": os.getpid(), "cwd": os.getcwd(), "at": now()}


def disarm_watchdog():
    """SIGTERM the watchdog armed for THIS session and drop its pidfile. Returns (pid, note).

    This is LATENCY, not enforcement. A Stop hook arms a fresh watchdog at every turn-end, so a kill
    is undone by the next turn — what actually stands the engine down is `handed_off` in state, which
    bin/watchdog reads. This exists so the one process already sleeping stops within seconds instead
    of waking once more to discover the flag.

    Only ever this session's own pid, read from this session's own pidfile. It never goes looking for
    watchdog processes by name: a scan cannot tell this project's from another's, and killing another
    project's autonomy engine is a far worse bug than the one being fixed.

    AND ONLY A PID IT CAN PROVE IS THAT WATCHDOG. Nothing deletes a pidfile when a watchdog exits, so
    the pid in it is usually dead already; if the OS has recycled it, the number alone cannot tell
    this session's watchdog from a stranger, and what follows the read is a SIGTERM. The file records
    the process's start time beside the pid, and a mismatch — or a file too old to carry one — means
    NOT SIGNALLED, said in the returned note rather than passed off as a kill. game_loop#102.
    """
    f = watchdog_pidfile()
    try:
        with open(f) as fh:
            parts = fh.read().strip().split(None, 1)
        pid = int(parts[0])
        recorded = (parts[1].strip() or None) if len(parts) > 1 else None
    except (OSError, ValueError, IndexError):
        return None, "none was armed"
    if recorded is None:
        note = (f"pid {pid} was recorded without an identity (a pidfile older than that format), so "
                "it could NOT be shown to be this session's watchdog — left alone rather than "
                "signalled, because a recycled pid belongs to somebody else. The handed_off flag "
                "still stands it down on its next wake.")
    else:
        live = watchdog_pid_identity(pid)
        if live is None:
            # NOT "it exited" — that would be a claim about the process from a failure to look.
            note = (f"could not check pid {pid} at all (ps did not run), so it was NOT signalled. "
                    "The handed_off flag still stands the watchdog down on its next wake.")
        elif live == PROC_GONE:
            note = f"pid {pid} had already exited"
        elif live != recorded:
            note = (f"pid {pid} is NOT the watchdog that wrote this file — it exited and the OS gave "
                    "its number to another process, which was therefore not signalled. The "
                    "handed_off flag still stands the watchdog down.")
        else:
            note = f"stopped pid {pid}"
            try:
                os.kill(pid, 15)
            except ProcessLookupError:
                note = f"pid {pid} exited between the check and the signal"
            except OSError as e:
                note = (f"could not signal pid {pid} ({e.__class__.__name__}) — the state flag still "
                        "stands it down")
    try:
        os.remove(f)
    except OSError:
        pass
    return pid, note


def successor_seen(to):
    """Has the session `successor` named ever actually existed? Its own state file is the artifact —
    nothing but a real SessionStart writes one. Same test bin/watchdog uses to decide whether a
    handover is real, and it must stay the same test: a status line that reads 'handed over' where
    the watchdog reads 'nobody came' is the disagreement nobody would check."""
    return bool(to) and os.path.isfile(os.path.join(SESSIONS_DIR, str(to), "state.json"))


def load_limits():
    try:
        with open(limits_file()) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def save_limits(snap):
    # The temp file must sit beside the DATA file — os.replace cannot cross filesystems, and after
    # the snapshot moved to the main checkout, ROOT is no longer where it lands.
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(limits_file()), prefix=".limits.", suffix=".tmp")
    with os.fdopen(fd, "w") as f:
        json.dump(snap, f, indent=2)
        f.write("\n")
    os.replace(tmp, limits_file())


class limits_lock:
    """Serialize limits.json read-modify-write across SESSIONS.

    The snapshot is deliberately account-scoped (both sessions burn the same subscription windows),
    which makes updating it the one place two statuslines write the same file: without a lock,
    concurrent read-modify-writes can resurrect a consumed `notified` flag and page the human twice,
    or lose a `crossed_at`. flock on a sidecar lockfile (never the data file — os.replace swaps the
    data file's inode out from under a held lock). Fails OPEN where flock is unavailable: a missed
    lock risks a duplicate page, which is cheaper than a statusline that can hang or crash.
    """

    def __enter__(self):
        self._fh = None
        try:
            import fcntl
            # BESIDE THE DATA FILE, not in this tree. Once the snapshot moved to the main
            # checkout, a per-tree lock would let two worktrees serialise against different files
            # and race on the one that matters — a shared file with private locks is worse than
            # the private files it replaced.
            self._fh = open(os.path.join(os.path.dirname(limits_file()), ".limits.lock"), "w")
            fcntl.flock(self._fh, fcntl.LOCK_EX)
        except Exception:  # noqa: BLE001
            if self._fh:
                self._fh.close()
                self._fh = None
        return self

    def __exit__(self, *exc):
        if self._fh:
            try:
                import fcntl
                fcntl.flock(self._fh, fcntl.LOCK_UN)
            except Exception:  # noqa: BLE001
                pass
            self._fh.close()
        return False


def binding_windows(snap, pct, now_epoch):
    """Windows at/over pct whose reset is still ahead: [(name, window), ...].

    A resets_at in the past means the window rolled over since the snapshot — whatever it said no
    longer binds. That, not snapshot age, is the correct staleness test: used_percentage is monotonic
    within a window and only ever falls by resetting.
    """
    out = []
    for name, w in ((snap or {}).get("windows") or {}).items():
        try:
            if float(w.get("used_percentage", 0)) >= pct and float(w.get("resets_at", 0)) > now_epoch:
                out.append((name, w))
        except (TypeError, ValueError):
            continue
    return out


def record_context_reading(s, tokens, now_epoch):
    """Cache this turn's context size in session state, carrying the crossing forward.

    WHY CACHED AT TURN-END RATHER THAN READ AT THE GATE. The reading comes off the transcript, and
    `transcript_path` is a key this repo has READ on the Stop payload (cmd_stopgate does it every
    turn) and has NEVER checked for on the PreToolUse one. A gate that parsed the transcript itself
    would rest on a key nobody has observed, and would re-read a file on every single tool call to
    learn a number that changes once a turn.

    crossed_at is stamped the first turn the reading is at/over threshold and CLEARED the first turn
    it drops back under — the same carry-forward absorb_rate_limits does for a usage window, and for
    the same reason. Without it every turn-end would move the bar: a handoff written one turn ago
    would read as older than the newest reading, and the gate could never be satisfied at all.
    Dropping back under is this trigger's analogue of a window resetting — a compaction, or a fresh
    successor session — and it ends the crossing rather than leaving a stamp nothing can clear.
    """
    if not tokens:
        return                          # no reading is not a small reading (INV5)
    cc = context_cfg()
    prev = s.get("context_reading") or {}
    rec = {"tokens": int(tokens), "observed_at": int(now_epoch),
           "threshold_tokens": cc["threshold_tokens"], "crossed_at": prev.get("crossed_at")}
    if rec["tokens"] >= cc["threshold_tokens"]:
        if not rec["crossed_at"]:
            rec["crossed_at"] = int(now_epoch)
            logline({"kind": "context_threshold", "tokens": rec["tokens"],
                     "threshold_tokens": cc["threshold_tokens"], "enabled": cc["enabled"]})
    else:
        rec["crossed_at"] = None
    s["context_reading"] = rec
    return rec


def binding_context(s):
    """This session's context reading if it binds the gate, else None.

    Fail-OPEN wherever the signal is missing (INV5): the trigger switched off, no reading recorded
    yet, a reading that will not parse — none of those is evidence that the context is large, and a
    gate that blocks on absent evidence blocks its own fix. It closes only on a POSITIVE signal: a
    recorded reading at or over the configured cap.

    The threshold is re-read from config here rather than trusted from the stored record, so raising
    the cap opens the gate on the next tool call instead of on the next turn-end.
    """
    cc = context_cfg()
    if not cc["enabled"]:
        return None
    rec = s.get("context_reading") or {}
    try:
        tokens = int(rec.get("tokens") or 0)
    except (TypeError, ValueError):
        return None
    if tokens < cc["threshold_tokens"]:
        return None
    return dict(rec, tokens=tokens, threshold_tokens=cc["threshold_tokens"])


def _spawn_verb_hit(cmd, verbs):
    """The configured fan-out verb this command line runs, or None.

    Same whole-word-both-sides match `deploy_verbs` settled on in #51, and reused rather than
    reinvented for the reason that bug taught: a substring match refuses ordinary English, the
    refusal names a verb nobody typed, and the natural response is to rephrase and never learn the
    guard was wrong. The boundary class includes quotes so a verb nested in an interpreter argument
    still counts, and `\\s+` between words so `showrunner   spawn` is the same verb.

    WHAT IT STILL MATCHES, said plainly (INV6): the verb as a whole word in PROSE — a commit message
    quoting `showrunner spawn` trips it. That trade is deliberate and identical to the deploy rail's:
    narrowing to command position would miss a real spawn nested in an interpreter argument.
    """
    for v in verbs:
        words = [w for w in str(v).split() if w]
        if not words:
            continue
        # THE LEADING CLASS CARRIES `/` AND THE DEPLOY RAIL'S DOES NOT, which is not an oversight in
        # either place. `npm publish` is typed as a bare command; the verbs THIS rail blocks are
        # harness entrypoints invoked by path — `./.showrunner/bin/showrunner spawn` is the form
        # every install of this repo actually uses, and without `/` in the class the brake matched
        # nothing at all while looking completely correct. The trailing class keeps no `/`: a verb
        # followed by a slash is a longer word, not this verb.
        pat = (r"(^|[\s;&|'\"/])" + r"\s+".join(re.escape(w) for w in words)
               + r"($|[\s;&|'\"])")
        if re.search(pat, cmd or ""):
            return v
    return None


def binding_spawn_block(s, payload):
    """This session's reading if it forbids STARTING NEW WORK on this call, else None.

    Returns a dict carrying the reading, the cap and the verb that tripped it, or None.

    WHY THE BRAKE IS HERE AND NOT IN SHOWRUNNER, which is the first place anyone looks. Read
    2026-08-24: showrunner has no usage or session-size awareness anywhere. Its whole tree contains
    one occurrence of `limits.json` (lib/showrunner/harness.py:86, an ignore-list entry naming a file
    NOT copied into a worktree), and cmd_spawn (lib/showrunner/cli.py:1416) refuses for exactly one
    reason, a harness gap — account usage and context size are consulted on no path. So "showrunner
    kept going after game_loop said the limit was hit" was never two tools disagreeing: nothing was
    ever asking showrunner to stop. It stays unmodified and unaware, and the brake rides the gate
    that already has the reading.

    WHY THIS IS NOT JUST ANOTHER BRANCH OF binding_context. That one answers "is a handoff owed",
    and its answer is CANCELLED by writing a handoff. This one must not be: the failure it exists to
    stop is a session that wrote the handoff and then kept fanning out. So it is computed
    independently, checked BEFORE the handoff exemption in _limitgate_verdict, and reads its own
    threshold — which may sit above the handoff cap, in which case binding_context is None on the
    very calls this must refuse. Sharing the predicate would have re-introduced the bug.

    Fail-OPEN wherever the signal is missing (INV5): the trigger off, block_spawn off, no reading
    recorded yet, a reading that will not parse, a tool that is not Bash, a command naming no
    configured verb. None of those is evidence that this session is large, and a gate that blocks on
    absent evidence blocks its own fix.
    """
    cc = context_cfg()
    if not cc["enabled"] or not cc["block_spawn"]:
        return None
    if (payload.get("tool_name") or "") != "Bash":
        return None                     # the rail is the Bash verb; see the coverage note in status
    rec = s.get("context_reading") or {}
    try:
        tokens = int(rec.get("tokens") or 0)
    except (TypeError, ValueError):
        return None
    if tokens < cc["spawn_threshold_tokens"]:
        return None
    hit = _spawn_verb_hit((payload.get("tool_input") or {}).get("command") or "",
                          cc["spawn_verbs"])
    if not hit:
        return None
    return {"tokens": tokens, "cap": cc["spawn_threshold_tokens"], "verb": hit,
            "observed_at": rec.get("observed_at")}


def _fmt_reset(epoch):
    try:
        dt = datetime.datetime.fromtimestamp(float(epoch))
    except (TypeError, ValueError, OverflowError):
        return "?"
    fmt = "%H:%M" if 0 <= float(epoch) - time.time() < 86400 else "%a %H:%M"
    return dt.strftime(fmt)


def limits_summary(snap):
    """One line for status/statusline: '5h 23% ↺14:32 · 7d 41% ↺Mon 09:00', or None."""
    parts = []
    for name in ("five_hour", "seven_day"):
        w = ((snap or {}).get("windows") or {}).get(name)
        if not w:
            continue
        try:
            parts.append(f"{WINDOW_LABELS[name]} {float(w['used_percentage']):.0f}% "
                         f"↺{_fmt_reset(w.get('resets_at'))}")
        except (TypeError, ValueError, KeyError):
            continue
    return " · ".join(parts) or None


def probe_reading(doc):
    """Split a probe's stdout into (rate_limits, context_window). Never raises on shape.

    TWO SHAPES ON PURPOSE. The probe used to print the rate_limits object bare; it now prints an
    envelope carrying context_window beside it. Both are accepted because a PIN can pair an older
    shipped probe script with newer game_loop code — the pinned copy and the repo copy are separate
    trees, and assuming they move together is the kind of assumption this file exists to refuse.

    The discriminator is the envelope's own key. A real rate_limits object carries window names
    (five_hour, seven_day) and can never contain a key called "rate_limits", so the test cannot
    misread a legacy reading as an envelope.
    """
    if not isinstance(doc, dict):
        return {}, None
    if "rate_limits" in doc:
        rl = doc.get("rate_limits")
        cw = doc.get("context_window")
        return (rl if isinstance(rl, dict) else {},
                cw if isinstance(cw, dict) else None)
    return doc, None                 # legacy: the bare rate_limits object, from an older probe


def record_context_window(cw):
    """Write the raw context_window a probe render carried, or record that it carried none.

    NOT INTERPRETED. This does not compute a token floor, compare against the claim, or decide
    anything — it records what the host said so a later exercise reads a real reading instead of my
    expectation of one. Absent is written as an explicit null rather than an empty file, because a
    missing file cannot say whether the probe ran.
    """
    try:
        p = os.path.join(ROOT, "probe", "context-window.json")
        os.makedirs(os.path.dirname(p), exist_ok=True)
        tmp = p + ".tmp"
        with open(tmp, "w") as f:
            # THE OBSERVATION CARRIES ITS OWN ATTRIBUTION (2026-08-24). Three claims here were
            # being CONFIRMED LIVE every day against a version nobody had written down, and
            # closing that meant reconstructing which build was running from the binary's mtime.
            # "Observed today" and "observed under this version" are different claims; a reading
            # that cannot name its subject makes the second one a guess somebody has to redo.
            # Unknown is recorded as an explicit null WITH its reason, never omitted.
            _hv, _hw = running_host_version()
            json.dump({"context_window": cw, "observed_at": int(time.time()),
                       "host_version": _hv, "host_version_how": _hw,
                       "note": "raw, uninterpreted: what the probe's fresh-session render carried"},
                      f, indent=2)
            f.write("\n")
        os.replace(tmp, p)
    except (OSError, ValueError, TypeError):
        pass                         # a recording that fails must never cost the reading


def absorb_rate_limits(rate_limits, lc, now_epoch):
    """Fold a rate_limits reading into the account-scoped snapshot; return the windows.

    EXTRACTED SO THE TAP AND THE PROBE CANNOT DRIFT. Both produce the same snapshot from the same
    field, and both must carry crossing history forward, page exactly once per window instance, and
    take the MAX against a previous reading of the same instance. Two copies of that would be two
    chances to get paging wrong, and the second copy would be the one nobody re-read — which is the
    shape this repo keeps paying for. The tap calls it on every statusline refresh; `limitprobe`
    calls it with a reading fetched from a spawned session, on hosts that render no statusline.
    """
    with limits_lock():
        prev = ((load_limits() or {}).get("windows") or {})
        windows = {}
        for name in ("five_hour", "seven_day"):
            w = ((rate_limits or {}).get(name) or {})
            try:
                used = float(w["used_percentage"])
                resets = float(w["resets_at"])
            except (TypeError, ValueError, KeyError):
                continue
            rec = {"used_percentage": used, "resets_at": resets, "crossed_at": None, "notified": False}
            p = prev.get(name) or {}
            if p.get("resets_at") == resets:  # same window instance — carry crossing history forward
                rec["crossed_at"], rec["notified"] = p.get("crossed_at"), p.get("notified", False)
                rec["used_percentage"] = max(used, float(p.get("used_percentage") or 0))
            if rec["used_percentage"] >= float(lc["threshold_pct"]) and resets > now_epoch:
                if not rec["crossed_at"]:
                    rec["crossed_at"] = now_epoch
                    logline({"kind": "limit_threshold", "window": name, "used_percentage": used,
                             "resets_at": resets, "threshold_pct": lc["threshold_pct"]})
                if not rec["notified"]:
                    # One page per window instance, sent whether or not it lands — retrying a failed
                    # page on every statusline tick would spam the log without reaching anyone new.
                    rec["notified"] = True
                    if notify:
                        notify.send("limit_handoff",
                                    f"⏳ the {WINDOW_LABELS[name]} usage window is at {used:.0f}% "
                                    f"(resets {_fmt_reset(resets)}). The limitgate now requires each "
                                    f"session to write its handoff before other work continues.")
            windows[name] = rec
        try:
            save_limits({"captured_at": now_epoch, "session": SESSION, "windows": windows})
        except OSError:
            pass
    return windows

def cmd_statusline(s, a, payload):
    """The statusline tap: snapshot rate_limits to limits.json, render one row, page on crossing.

    Runs on every statusline refresh, so it must be fast and must NEVER exit non-zero — a broken
    statusline row is cosmetic, but this tap is what feeds the limitgate and the watchdog's park, so
    it degrades to printing less rather than failing. crossed_at/notified survive refreshes for the
    SAME window instance (same resets_at) and reset when the window rolls over.
    """
    lc = limits_cfg()
    now_epoch = time.time()
    # The whole read-modify-write sits under the cross-session lock: two sessions' statuslines
    # refresh the same account-scoped snapshot, and crossed_at/notified must be consumed exactly
    # once between them. (The page itself is sent under the lock too — brief, bounded by the send
    # timeout, and it is what makes "paged ONCE" true account-wide rather than per-session.)
    windows = absorb_rate_limits(payload.get("rate_limits"), lc, now_epoch)
    model = ((payload.get("model") or {}).get("display_name")) or ""
    try:
        ctx = f"ctx {float((payload.get('context_window') or {}).get('used_percentage')):.0f}%"
    except (TypeError, ValueError):
        ctx = None
    lim = limits_summary({"windows": windows}) or "limits n/a (API key or no response yet)"
    over = binding_windows({"windows": windows}, float(lc["threshold_pct"]), now_epoch)
    row = " · ".join(x for x in ["🎮 " + model if model else "🎮", ctx, lim] if x)
    if over:
        row += "  ⚠ LIMIT — HANDOFF DUE"
    # The context trigger gets a row of its own: it fires on a reading the statusline's own
    # `ctx N%` cannot produce (that is a percentage of the window, this is the cap in tokens), and
    # a gate whose first appearance is a refused tool call is a gate nobody saw coming.
    if binding_context(s):
        row += "  ⚠ CONTEXT OVER CAP — HAND OFF"
    # The spawn cap gets its own marker for the same reason the row above exists, and it is a
    # SEPARATE marker because it can bind when that one does not: the caps are independent, and a
    # session sitting between them is refused fan-out while owing no handoff at all.
    cc = context_cfg()
    if cc["enabled"] and cc["block_spawn"]:
        try:
            _tok = int((s.get("context_reading") or {}).get("tokens") or 0)
        except (TypeError, ValueError):
            _tok = 0
        if _tok >= cc["spawn_threshold_tokens"]:
            row += "  ⛔ NO NEW SPAWNS"
    print(row)


def _spawn_block_reason(s, sb):
    """The refusal a blocked fan-out verb prints. Its job is to be ACTED ON, not merely understood —
    so it names the successor command, and says outright that writing a handoff will not help, since
    that is precisely what the agent will otherwise try next."""
    hp = handoff_path()
    m = s.get("mandate") or {}
    return (
        f"NO NEW WORK — this session is too big to be starting Crawlers.\n\n"
        f"  refused    : {sb['verb']}\n"
        f"  context    : {sb['tokens'] / 1000:.0f}K tokens on the last turn, over the "
        f"{sb['cap'] / 1000:.0f}K spawn cap\n\n"
        "Every call this session makes re-sends that whole context, and orchestrating a fan-out is\n"
        "all calls: a brief per Crawler, a reconcile per wave, an integration at the end. Spawning\n"
        "from here does not spend the fan-out's tokens, it spends THIS context once per Crawler, and\n"
        "the bill lands on the week rather than on the turn you can see.\n\n"
        "WRITING A HANDOFF WILL NOT OPEN THIS. The usage gate above it works that way and this one\n"
        "deliberately does not — a handoff says where you got to, it does not make the next call\n"
        "cheaper. The only thing that clears this is a SMALLER SESSION:\n\n"
        f"  1. write the handoff, if you have not:  {hp}\n"
        "  2. start the successor:                 ./.game_loop/bin/game_loop successor\n"
        "  3. spawn from THERE — a fresh session orchestrates the same fan-out at a fraction of the\n"
        "     per-call cost, and it inherits the campaign through showrunner, not through context.\n\n"
        f"  mandate in flight: {m.get('text') or '(none bound)'}\n\n"
        "Work already claimed here is NOT affected — running Crawlers finish and close normally, and\n"
        "you may still reconcile, check and integrate. Only STARTING more is refused.\n\n"
        "If this cap is simply set too low for the campaign, that is the human's call to make in\n"
        ".game_loop/config.local.json -> limits.context.spawn_threshold_tokens (or block_spawn:false\n"
        "to remove the brake). Do not route around it by invoking the verb another way.")


def _limitgate_verdict(s, payload, now_epoch):
    """Decide whether this tool call may proceed — at/over a usage window, or over the context cap.

    Returns (allow: bool, reason: str|None). Pure decision so tests can drive every branch.

    TWO TRIGGERS, ONE GATE. A nearly-exhausted usage window and a session whose context has grown
    past the cap want the same thing — the run's state written down before it moves — so the second
    trigger was added to this machinery rather than beside it. Everything below the trigger is
    shared: the same handoff check, the same auto-handoff exclusion, the same allow-list, the same
    fail-open. A second gate would have been a second chance to get those six things wrong.

    Fail-OPEN everywhere the signal is missing: no snapshot, unparseable snapshot, windows that
    already reset, no context reading recorded yet, the context trigger switched off — none of those
    is evidence of a binding limit, and a gate that blocks on absent evidence blocks its own fix
    (INV5). The gate closes only on a POSITIVE signal: a window at/over threshold_pct whose reset is
    still ahead, or a context reading at/over threshold_tokens — with no handoff written since it
    crossed.

    While closed, exactly the handoff work stays allowed: Write/Edit to the handoff file, and any
    game_loop invocation (checkpoint/arm/mandate/notify are how a dying run reports, and `successor`
    is how an over-cap one leaves). Yes, a Bash command merely MENTIONING the handoff file passes —
    this gate nudges the handoff into existence, it is not a security boundary; the write guard still
    owns what may be mutated.
    """
    # ── FIRST, and above the handoff exemption on purpose ────────────────────────────────────────
    #
    # Everything below this block can be satisfied by writing a file. This cannot, and that is the
    # entire reason it sits here rather than three lines further down. The observed failure: the
    # context trigger closed the gate, the agent wrote a handoff, the gate opened, and the very next
    # thing the session did was spawn more Crawlers out of the context that had just been declared
    # too expensive to keep using. A handoff records where a run got to; it does not make the run
    # cheaper, and it must not buy the right to start new work.
    #
    # It is also ahead of the `if not over and not ctx` early return, because the spawn cap may sit
    # ABOVE the handoff cap — in which case ctx is None on exactly the calls this must refuse.
    sb = binding_spawn_block(s, payload)
    if sb:
        return False, _spawn_block_reason(s, sb)
    snap = load_limits()
    lc = limits_cfg()
    over = binding_windows(snap, float(lc["threshold_pct"]), now_epoch) if snap else []
    ctx = binding_context(s)
    if not over and not ctx:
        return True, None
    hp = handoff_path()
    # The earliest crossing among everything currently binding: a handoff must postdate the crossing
    # it is answering, and when both triggers bind it is the older one that sets the bar.
    stamps = [(w.get("crossed_at") or (snap or {}).get("captured_at") or now_epoch) for _, w in over]
    if ctx:
        stamps.append(ctx.get("crossed_at") or ctx.get("observed_at") or now_epoch)
    try:
        crossed = min(float(x) for x in stamps)
    except (TypeError, ValueError):
        crossed = now_epoch
    try:
        if os.path.getsize(hp) > 0 and os.path.getmtime(hp) >= float(crossed):
            with open(hp) as f:
                head = f.read(200)
            # THE AUTO HANDOFF DOES NOT SATISFY THIS GATE (#45). It is refreshed at every turn-end,
            # so accepting it would make this check pass forever without the agent doing anything —
            # a gate quietly turned vacuous by a safety net added to help it. The generated file is
            # the FLOOR (a limit death costs at most one turn); the agent's own account of where it
            # got to is still owed, and only `checkpoint --notes` or a hand-written file provides it.
            if AUTO_HANDOFF_MARK not in head:
                return True, None
    except OSError:
        pass
    tool = payload.get("tool_name") or ""
    ti = payload.get("tool_input") or {}
    if tool in ("Write", "Edit", "NotebookEdit"):
        fp = ti.get("file_path") or ti.get("notebook_path") or ""
        if fp and os.path.realpath(os.path.expanduser(fp)) == os.path.realpath(hp):
            return True, None
    if tool == "Bash":
        cmd = ti.get("command") or ""
        if ".game_loop/bin/" in cmd or "game_loop " in cmd or os.path.basename(hp) in cmd:
            return True, None
    detail = "\n".join(
        [f"  {WINDOW_LABELS.get(n, n)} window: {float(w.get('used_percentage', 0)):.0f}% used, "
         f"resets {_fmt_reset(w.get('resets_at'))}" for n, w in over]
        + ([f"  context: {ctx['tokens'] / 1000:.0f}K tokens on the last call, over the "
            f"{ctx['threshold_tokens'] / 1000:.0f}K cap"] if ctx else []))
    if over and ctx:
        head = ("LIMIT GATE CLOSED — a usage window is nearly exhausted AND this session's context "
                "is over the cap.\nNo handoff exists yet.")
        why = ("Either one alone ends this run: the window dying kills it MID-ACTION, and the "
               "context is\nre-sent whole on every remaining call. Everything you know right now — "
               "where you are, what\nis verified, what you planned next — is only in this session. "
               "Write it down first.")
    elif ctx:
        head = ("LIMIT GATE CLOSED — this session's context is over the cap and no handoff exists "
                "yet.")
        why = ("Every call from here re-sends this whole context, so the same work costs more the "
               "longer this\nsession runs — cache reads, not output, are where a week's usage "
               "actually goes. The fix is a\nSUCCESSOR: hand the state over and let a fresh session "
               "carry on cheaply. Nothing is lost that\nyou write down, and everything is lost that "
               "you do not.")
    else:
        head = "LIMIT GATE CLOSED — a usage window is nearly exhausted and no handoff exists yet."
        why = ("When this window runs dry the session dies MID-ACTION and everything you know right "
               "now —\nwhere you are, what is verified, what you planned next — dies with it. Write "
               "it down first.")
    if ctx:
        tail = ("Then START THE SUCCESSOR — writing the handoff opens this gate, but it does not "
                "shrink the\ncontext, and carrying on here keeps paying for it:\n"
                "  ./.game_loop/bin/game_loop successor\n\n"
                "It mints the session id, points the next session at the handoff above, and prints "
                "(or opens)\nthe command that starts it. Your context does not come back down any "
                "other way.")
    else:
        tail = ("Once the handoff is written, this gate opens and you may keep working until the "
                "window\nactually resets — the watchdog will park an exhausted run and ring it "
                "awake after the\nreset, pointing at your handoff.")
    ph = s.get("phase") or {}
    m = s.get("mandate") or {}
    return False, (
        head + "\n\n"
        + detail + "\n\n"
        + why + "\n\n"
        f"Write the handoff NOW (the Write tool to exactly this path is allowed):\n  {hp}\n\n"
        "Include, concretely:\n"
        f"  * the mandate: {m.get('text') or '(none bound)'}\n"
        f"  * where you are: {ph.get('milestone') or '?'} · {ph.get('doing') or '?'}\n"
        "  * what is DONE and VERIFIED (with the file paths that prove it)\n"
        "  * what you were IN THE MIDDLE OF, and the exact next actions you had planned\n"
        "  * how to resume (commands, branch, open questions)\n\n"
        + tail)


# ── the unbound mandate, said at the moment it matters ──────────────────────────────────────────
#
# THE BUG REPORT IS THE HUMAN'S OWN SENTENCE: "I have to tell them manually, none of them know."
# Agents across this machine start long unattended runs with no mandate bound. The Stop gate is then
# inert by construction, `doorbell` correctly answers that there is nothing to wake the run FOR, and
# a wake that lands mid-run drops the agent into a prompt with a hole where the goal goes.
#
# THE INFORMATION WAS NEVER MISSING, which is the whole diagnosis and it is showrunner's, reported
# after they built the workaround in their own layer and saw the debt: `game_loop status` prints
# `MANDATE: none (Stop gate inert)`, `doorbell` explains the remedy in full to anyone who runs it,
# and their own SessionStart banner repeats the mandate line. THREE SURFACES, ALL CORRECT, ALL
# IGNORED. So this is a DELIVERY defect, and more documentation is the one fix guaranteed not to
# work — session-start text is read once, before the agent knows whether the work ahead is long, and
# by the time it is long the banner is thousands of tokens upstream. The human succeeds where all
# three documents fail for one reason: he speaks AT THE MOMENT, and the moment is the start of the
# long thing rather than the start of the session.
#
# WHY IT LIVES HERE RATHER THAN IN showrunner, whose version works today: the mandate and the
# doorbell are this tool's, so their gate re-derives a conclusion this one is better placed to
# state; and it reaches only repos that install showrunner, while balooga, llm_chat, wcs and every
# other consumer has the identical gap. Nine installs, one covered. They offered to delete theirs
# and were asked to keep it until this one has fired somewhere real, because a notice that has never
# fired and a notice that CANNOT fire look identical from the inside.
#
# IT RIDES THE HOOK THAT IS ALREADY REGISTERED. `game_loop limitgate` is a PreToolUse hook on
# Write|Edit|NotebookEdit|Bash in every install. A new hook would need nine settings.json files
# updated by hand before the fix reached anybody, which is the same delivery failure one layer out.


def mandate_binding(s):
    """Whether a goal is bound here: "armed", "unarmed" or "unknown" — never a bare boolean.

    "COULD NOT TELL" MUST NEVER READ AS ARMED. showrunner's constraint, and it is the load-bearing
    half of their report: a check that folds unknown into armed goes quiet exactly when it has lost
    the ability to speak, and from the inside that is indistinguishable from a run properly under
    orders. Their `armed()` returns four answers for this reason.

    This repo already made the same distinction one level down and paid for it there. `load()` used
    to return pristine defaults for a state.json that EXISTED and would not parse, so a corrupt file
    read as a brand new session: the mandate vanished and status printed "MANDATE: none" — the exact
    sentence it prints for a session that never had one. Same rule, one layer up.

    A PARKED mandate counts as armed. The human called that break, so somebody is by definition
    there to notice; nudging them to bind a goal they have already bound and paused is the nag that
    turns a true signal into scenery.
    """
    if STATE_UNREADABLE:
        return "unknown"
    m = s.get("mandate")
    if m is None:
        return "unarmed"                 # a genuinely fresh session, and that is fine
    if not isinstance(m, dict):
        return "unknown"                 # something is there and it is not what this reads
    if m.get("active") and str(m.get("text") or "").strip():
        return "armed"
    if m.get("active"):
        return "unknown"                 # active with no text: bound to what?
    return "unarmed"


# NOT A GUESS THIS TOOL INVENTED. Two of these three are the lists the deploy rail and the fan-out
# brake already read, so a consumer who has tuned those gets this for free and has ONE place to
# argue with rather than a second copy drifting from the first. The third is a built-in list of
# suite and build runners, overridable at config.long_work_verbs, because "what starts a long run"
# is genuinely per-project and a hard-coded list is how six repos end up with six forks of it.
#
# HONEST ABOUT WHAT IT IS (INV6): a command-shape guess, exactly like showrunner's. game_loop knows
# a mandate is unbound and knows when the last checkpoint landed, but the moment work BECOMES long
# is not something it observes either — it sees tool calls through the same hooks. The improvement
# over their version is not accuracy, it is that this is one guess in one place.
LONG_WORK_VERBS = [
    "pytest", "npm test", "npm run build", "yarn build", "flutter test", "flutter build",
    "cargo test", "cargo build", "go test", "make", "gradle", "./gradlew", "tox", "nox",
    "bazel build", "bazel test", "docker build", "terraform apply", "claude -p",
]


def long_work_verbs():
    """The configured long-work verbs, or the built-in list. A consumer's list REPLACES."""
    v = config().get("long_work_verbs")
    if isinstance(v, list) and v:
        return [str(x) for x in v if str(x).strip()]
    return list(LONG_WORK_VERBS)


_QUOTED = re.compile(r"""'[^']*'|"[^"]*\"""", re.S)
_CMD_SPLIT = re.compile(r"\|\||&&|[;|\n]")
_LEADING_ENV = re.compile(r"^(?:[A-Za-z_][A-Za-z_0-9]*=\S*\s+)+")


def _blank_quoted(cmd):
    """Quoted CONTENTS replaced by spaces, quotes and length kept.

    REPORTED TWICE IN ONE DAY, in two repos, in two alphabets. wcs hit it writing a knowledge-base
    entry whose BODY quoted `git worktree add` as the example of the thing not to do, and the advice
    fired on their prose about the advice; their own matcher had the identical bug with `Kansas`
    matching "Kansas City" and pinning a Missouri buyer to Kansas. showrunner fixed the same class
    in their own guard and this is their fix, not a reinvention of it.

    A word boundary is not a semantic boundary. `dart run tool/kb.dart --body "... git worktree add
    ..."` is not a git invocation and nothing in the text says otherwise except the substring.
    """
    return _QUOTED.sub(lambda mm: mm.group(0)[0] + " " * (len(mm.group(0)) - 2) + mm.group(0)[-1],
                       cmd)


def _verb_at_command_position(cmd, verbs):
    """The verb this command line RUNS — at a command boundary, outside quotes — or None.

    STRICTER THAN `_spawn_verb_hit`, DELIBERATELY, AND NOT A CORRECTION OF IT. That matcher's
    boundary class includes quotes on purpose, so a verb nested in an interpreter argument still
    trips the DENY rails; for an irreversible deploy, over-refusing is the cheap direction and its
    docstring says so.

    THIS RAIL'S ARITHMETIC IS THE OPPOSITE, and for a reason particular to it: the notice speaks
    ONCE PER SESSION. So a false positive does not cost one spurious line — it SPENDS THE ONLY
    NOTICE, and the real unattended run an hour later gets silence. The expensive direction here is
    the false positive, which is the same conclusion showrunner reached for a channel whose only
    value is being worth reading, by a different route.

    THE COST, asserted rather than left to be discovered: `bash -c "pytest"` is now a miss. That
    trade is taken knowingly. Every ordinary invocation still hits — bare, after `&&`, after `;`,
    after a pipe, behind a path, behind leading environment assignments.
    """
    text = _blank_quoted(cmd)
    for seg in _CMD_SPLIT.split(text):
        seg = _LEADING_ENV.sub("", seg.strip())
        if not seg:
            continue
        for v in verbs:
            words = [w for w in str(v).split() if w]
            if not words:
                continue
            # `(?:\S*/)?` on the FIRST word only: `./.showrunner/bin/showrunner spawn` is the form
            # every install of that harness actually uses, and a rule anchored to a bare word would
            # match nothing at all while looking completely correct — the #51 lesson, kept.
            pat = (r"^(?:\S*/)?" + r"\s+".join(re.escape(w) for w in words) + r"(?:$|[\s;&|])")
            if re.search(pat, seg):
                return v
    return None


def long_work_hit(payload):
    """What about this call says a long run is starting, or None. Bash only.

    Backgrounding is checked separately from the verb list because it is the one shape that carries
    no verb at all: `&` at the end says "this outlives the turn" whatever is in front of it. `&&` is
    not backgrounding and the distinction is one character, so it is matched rather than searched —
    and it is checked against the QUOTE-BLANKED text, or `echo "a & b"` reads as backgrounding.
    """
    if (payload or {}).get("tool_name") != "Bash":
        return None
    cmd = str(((payload or {}).get("tool_input") or {}).get("command") or "")
    if not cmd.strip():
        return None
    if re.search(r"(?<!&)&\s*$", _blank_quoted(cmd).strip()):
        return "a backgrounded command"
    c = config()
    for label, verbs in (("a fan-out verb", spawn_cfg_verbs()),
                         ("a deploy verb", [str(x) for x in (c.get("deploy_verbs") or [])]),
                         ("a long-running command", long_work_verbs())):
        v = _verb_at_command_position(cmd, verbs)
        if v:
            return "%s (%s)" % (label, v)
    return None


def spawn_cfg_verbs():
    """The fan-out brake's verb list, read WITHOUT its enabled flag.

    The brake is off by default and this notice is not the brake: `showrunner spawn` starts a long
    unattended run whether or not anybody configured a token threshold to refuse it at. Reading the
    flag here would make the notice silent in exactly the installs that never configured limits,
    which is most of them.
    """
    try:
        return list((context_cfg() or {}).get("spawn_verbs") or [])
    except Exception:
        return ["showrunner spawn"]


def unbound_mandate_notice(s, payload):
    """The text to put in front of the agent, or "" — pure, and silent in four distinct cases.

    SILENCE MUST BE CHEAP AND THE NOTICE MUST BE RARE. showrunner's other constraint, and they named
    the failure mode this feature is most likely to die of: a nag on every long command is how a
    true signal becomes scenery. Silent when a mandate is bound, silent when this call starts
    nothing long, silent when it has already spoken once in this session, and silent on every tool
    that is not Bash. It never refuses — the agent may have a perfectly good reason, and a gate that
    blocks work it cannot judge is a gate that gets routed around.
    """
    if s.get("mandate_notice_said"):
        return ""
    state = mandate_binding(s)
    if state == "armed":
        return ""
    hit = long_work_hit(payload)
    if not hit:
        return ""
    if state == "unknown":
        where = STATE_UNREADABLE or "(the mandate record is present but not in the shape this reads)"
        return (
            "COULD NOT TELL WHETHER A GOAL IS BOUND, and you are starting %s.\n\n"
            "  state: UNREADABLE — set aside at %s\n\n"
            "This is NOT 'no mandate' and it is NOT 'you are fine'. The record that says what this\n"
            "run is for cannot be read, so the Stop gate's inertness here means nothing either way.\n"
            "Check `game_loop status` before this goes unattended; if the mandate is genuinely gone,\n"
            "the set-aside file above is where its text still is." % (hit, where))
    # WHO THE SENTENCE IS ADDRESSED TO — balooga-owner's finding, relayed by showrunner, and the
    # only result in that whole exchange that survived every refutation because it is not a rule
    # about text. Across 35 measured mandates the finish condition is in the AGENT's half and
    # never the human's: showrunner's 29 have no human half at all — the human said "work the
    # issues" and what reached mandate_set was the agent's own summary of what it decided that
    # meant. So a notice worded as though the goal were something the human should have supplied
    # misattributes the gap every time, and the agent's natural response is to go ask for a better
    # brief instead of writing down the boundary it had already chosen. The placeholder said
    # "<what this run is for>", which reads as "what you were told", and that was the defect.
    return (
        "NO MANDATE IS BOUND, and you are starting %s.\n\n"
        "Nothing is wrong yet. But the Stop gate is INERT while no goal is bound — so if this run\n"
        "goes quiet, ends early, or gets woken mid-way, there is nothing recorded for it to be\n"
        "woken FOR, and no gate will notice the stop. That is the shape behind a human having to\n"
        "restart runs by hand, which is the report this notice exists for.\n\n"
        "  game_loop mandate --set \"<the goal, and what finishing looks like>\" --wake-every <sec>\n\n"
        "THIS IS YOURS TO WRITE, not something to go and ask for. Measured across 35 mandates in\n"
        "five repos: the finish condition is in the AGENT's words every time it is there at all.\n"
        "You already decided what this run is for when you started it — write that down.\n\n"
        "If this is short, attended, or not the kind of work a mandate covers, ignore this — it\n"
        "does not refuse anything and it will not ask again this session." % hit)


def cmd_limitgate(s, a, payload):
    """PreToolUse entrypoint for the limit gate. Same output protocol as guard-writes.sh: a deny is
    JSON on stdout with permissionDecision=deny, always exit 0."""
    allow, reason = _limitgate_verdict(s, payload, time.time())
    if allow:
        # THE NOTICE RIDES THE ALLOW PATH ONLY. A call that is being refused already has the
        # agent's attention and a reason on screen; adding a second, unrelated paragraph to it is
        # how the one that matters gets skimmed.
        notice = unbound_mandate_notice(s, payload)
        if notice:
            # THE ONCE-PER-SESSION FLAG IS WRITTEN HERE, IN THE I/O LAYER, and not inside
            # unbound_mandate_notice, which is documented pure. Same split `_stop_verdict` has and
            # for the same reason it was moved there: a verdict function that writes state cannot
            # be called twice by a test to check its answer is stable.
            _binding, _hit = mandate_binding(s), long_work_hit(payload)
            s["mandate_notice_said"] = now()
            save(s)
            logline({"kind": "mandate_notice", "binding": _binding, "trigger": _hit})
            print(json.dumps({"hookSpecificOutput": {
                "hookEventName": "PreToolUse", "additionalContext": notice}}))
        sys.exit(0)
    # WHICH trigger, in the log — three of them now. A block count that cannot separate "the
    # account ran dry" from "the cap is set too low" from "a fan-out was refused" cannot tell an
    # operator which knob to turn, and the spawn refusal is the one most likely to be mis-set.
    sb = binding_spawn_block(s, payload)
    logline({"kind": "limit_gate_block", "tool": payload.get("tool_name"),
             "context_bound": bool(binding_context(s)),
             "spawn_blocked": bool(sb), "spawn_verb": (sb or {}).get("verb")})
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse", "permissionDecision": "deny",
        "permissionDecisionReason": reason}}))
    sys.exit(0)


# CODE_ROOT, not ROOT: the probe is executable code, so under a pin it must come from the
# pinned copy alongside every other script rather than from the project it is guarding.
PROBE_SCRIPT = os.path.join(CODE_ROOT, "bin", "limit-probe.sh")
# Longer than a probe takes (~75s measured) and far shorter than any sane interval: a stale claim
# must expire on its own, or one session dying mid-probe would silence the others indefinitely.
PROBE_LEASE_SEC = 300


def probe_cfg():
    """The probe's settings, OFF unless a human turned it on.

    Default-off because it spends real tokens (~24k input per run, measured at 2.1.223) and because
    a feature that costs money should be a decision somebody made, not one they inherited. Nothing
    about the rest of the limit family changes when it is off.
    """
    lc = (config().get("limits") or {})
    p = lc.get("probe") if isinstance(lc.get("probe"), dict) else {}
    return {"enabled": bool(p.get("enabled", False)),
            "min_interval_sec": int(p.get("min_interval_sec", 900) or 900),
            "max_interval_sec": int(p.get("max_interval_sec", 3600) or 3600)}


def next_probe_after(snap, now_epoch, pc=None):
    """Seconds until the next probe is worth spending tokens on — the 'when to check next' half.

    SCALED TO WHAT IS AT STAKE, because a fixed interval is wrong at both ends: far from the limit
    it burns tokens to learn nothing, and near the limit it learns too late. Closest window by
    percentage decides, and a window about to RESET is not urgent no matter how full it is — the
    thing being timed is the moment work would stop, and a window that resets in two minutes stops
    nothing.

    Returns the max interval when there is no snapshot to reason from: the first probe is the one
    with the least information, so it should not also be the most frequent.
    """
    pc = pc or probe_cfg()
    lo, hi = pc["min_interval_sec"], max(pc["min_interval_sec"], pc["max_interval_sec"])
    worst = 0.0
    for w in ((snap or {}).get("windows") or {}).values():
        try:
            used, resets = float(w["used_percentage"]), float(w["resets_at"])
        except (TypeError, ValueError, KeyError):
            continue
        if resets <= now_epoch:
            continue                      # already reset — it constrains nothing
        worst = max(worst, used)
    if not worst:
        return hi
    # Linear from hi at 0% to lo at 90%+, then hold at lo. Not a tuned curve and not presented as
    # one: it is a ramp chosen so the spend rises as the risk does, and the numbers it interpolates
    # between are the human's own config rather than anything invented here.
    frac = min(1.0, worst / 90.0)
    return int(hi - (hi - lo) * frac)


def cmd_limitprobe(s, a):
    """Fetch a usage reading by spawning a session, on a host that cannot render a statusline.

    THE COST IS REAL AND SO IS THE ALTERNATIVE. ~24k input tokens per run against an unattended run
    that hits its limit at 1am, dies mid-action, and is still dead at 7am because nothing could see
    the wall coming. The whole limit family — the handoff gate, the park, the wake-on-reset — is
    built and tested and was only ever missing the snapshot. This supplies it.
    """
    pc = probe_cfg()
    if getattr(a, "interval_only", False):
        # The watchdog asks the SAME function that reports "next probe in ~N min", so the two can
        # never disagree about when the next spend is due. Prints seconds and nothing else.
        out(str(next_probe_after(load_limits(), time.time(), pc)))
        return
    if not (pc["enabled"] or a.force):
        die("the limit probe is off. It spends ~24k input tokens per run, so it is a decision "
            "somebody makes rather than inherits:\n"
            '  .game_loop/config.json -> "limits": {"probe": {"enabled": true}}\n'
            "Or run this once by hand with --force.")
    if not os.path.exists(PROBE_SCRIPT):
        die(f"the probe script is missing: {PROBE_SCRIPT}")

    # ONE PROBE SERVES THE CHECKOUT. The snapshot is account-scoped, so the number is the same for
    # every session sharing it — but each session runs its own watchdog, and each would
    # independently find the snapshot stale and spend ~24k tokens fetching an answer another session
    # was already fetching. Reported from a checkout running EIGHTEEN concurrent sessions, where
    # that is 430k tokens to read one number.
    #
    # A LEASE RATHER THAN A HELD LOCK. The probe takes ~75s and the limits lock is also what the
    # statusline tap takes on every refresh, so holding it across the spawn would stall every
    # statusline in the checkout for over a minute. Instead: claim under the lock, release, spawn.
    # A claim older than the lease is ignored, so a session that dies mid-probe cannot wedge the
    # others — it costs one duplicate probe, once, which is the cheap direction to fail.
    now_probe = time.time()
    if not a.force:
        with limits_lock():
            snap = load_limits() or {}
            claimed = float(snap.get("probe_started_at") or 0)
            if now_probe - claimed < PROBE_LEASE_SEC:
                out(f"another session started a probe {int(now_probe - claimed)}s ago — skipping.",
                    "  The snapshot is account-scoped, so its answer is this session's answer too.")
                logline({"kind": "limit_probe", "outcome": "deferred_to_peer"})
                return
            snap["probe_started_at"] = now_probe
            try:
                save_limits(snap)
            except OSError:
                pass                    # unclaimable is not fatal; worst case is a duplicate probe
    r = subprocess.run(["bash", PROBE_SCRIPT], capture_output=True, text=True, timeout=180)
    if r.returncode == 2:
        # COULD NOT LOOK. Never folded into "no limits data": a caller that treats them the same
        # reports a broken probe as an account with no windows, forever.
        logline({"kind": "limit_probe", "outcome": "could_not_tell",
                 "detail": (r.stderr or "").strip()[:200]})
        die("the probe could not tell: " + ((r.stderr or "").strip()[:300] or "no reason given"))
    if r.returncode == 1:
        logline({"kind": "limit_probe", "outcome": "no_rate_limits"})
        out("the host rendered a statusline and carried NO rate_limits.",
            "  That is an answer, not a failure: the field is subscriber-only. Nothing here can",
            "  protect a run whose limits it cannot see, and it will keep saying so.")
        return
    try:
        rl = json.loads(r.stdout or "{}")
    except ValueError:
        logline({"kind": "limit_probe", "outcome": "unparseable"})
        die("the probe answered with something that is not JSON — treating as could-not-tell.")
    rl, cw = probe_reading(rl)
    record_context_window(cw)
    now_epoch = time.time()
    windows = absorb_rate_limits(rl, limits_cfg(), now_epoch)
    logline({"kind": "limit_probe", "outcome": "ok",
             "windows": {k: v.get("used_percentage") for k, v in (windows or {}).items()},
             # RECORDED, NOT JUDGED: whether a fresh render carries a usable count is a question the
             # first real reading answers, not one this line should pretend to have settled.
             "context_window_keys": sorted(cw) if isinstance(cw, dict) else None})
    nxt = next_probe_after({"windows": windows}, now_epoch, pc)
    out("✓ usage read by spawning a session — the snapshot is live on this host now.",
        "  " + (limits_summary({"windows": windows}) or "no windows in the reading"),
        f"  next probe worth spending on in ~{nxt // 60} min (scaled to the fullest window;",
        "  a window about to reset is not urgent however full it is).")


def cmd_notify(s, a):
    """Page the configured channel by hand: a test ping, or a message the run's human should see."""
    if not notify:
        die("notify module missing (.game_loop/bin/notify.py) — reinstall game_loop.")
    if not a.test and not a.text:
        die("notify needs --text \"<message>\" (or --test to verify the channel works).")
    if not notify.configured():
        out("notify: NOT configured — no page sent.",
            "  Create .game_loop/notify.json (gitignored). Minimal bot-token form:",
            '    {"slack": {"bot_token": "xoxb-...", "channel": "C..."}}',
            "  or send-only: {\"slack\": {\"webhook_url\": \"https://hooks.slack.com/...\"}}",
            "  Full schema + scopes: .game_loop/bin/notify.py docstring.")
        return
    text = a.text or ("test page from game_loop. If you are reading this, the channel ACCEPTED and "
                      "DELIVERED it — which is the half sending cannot prove on its own.")
    res = notify.send("manual", text)
    if res is None:
        out("✗ page FAILED — see the last notify_error line in .game_loop/log.jsonl.")
        return
    logline({"kind": "notify_manual", "text": text})
    out("✓ the channel ACCEPTED the page." + ("" if res is True else f" (thread ts {res})"))
    if a.test:
        # ACCEPTED IS NOT DELIVERED, and this verb used to say "the notify channel works" — in the
        # page's own text, in front of a human (#95). Sending establishes that the API took it.
        # Whether a human sees it, and whether any WAKE lands, are two further claims this cannot
        # make. A run went inert for six hours behind exactly that conflation, with every internal
        # gate reporting healthy.
        out("  WHAT THAT DOES NOT ESTABLISH: that a human saw it, or that a WAKE can reach this",
            "  session while it is idle. Those are the failure this verb gets trusted to rule out,",
            "  and an accepted send rules out neither. Ask your transport's own doctor whether a",
            "  wake has LANDED — accepted, delivered and woke-me are three different facts.")
    if a.test:
        # Sending proves chat:write; it does NOT prove the bot can READ replies back. Probe that too,
        # so a wrong history scope (the classic: channels:history on a PRIVATE channel) is named here
        # instead of silently swallowing every reply at poll time.
        if not notify.can_read_replies():
            out("• send-only (webhook or no bot token+channel) — arm questions page one-way; a Slack "
                "reply can't resume the run. Use bot_token+channel to enable phone-answer resume.")
        else:
            ok, detail = notify.read_probe()
            if ok:
                out("✓ reply reads work — the watchdog can carry a Slack answer back into the run.")
            else:
                tip = {
                    "missing_scope": "add the history scope for THIS channel's type and REINSTALL the "
                    "Slack app: groups:history (private), channels:history (public), im:history (DM), "
                    "mpim:history (group DM). A C-prefixed id can still be a PRIVATE channel.",
                    "not_in_channel": "invite the bot into the channel (/invite @your-bot).",
                    "channel_not_found": "check the channel id in .game_loop/notify.json.",
                }.get(detail, "")
                out(f"⚠ reply READS FAILED: {detail} — arm will page, but the human's reply won't come "
                    "back.", *(["  " + tip] if tip else []))


# ── unpushed work ────────────────────────────────────────────────────────────────────────────────
#
# Agents commit constantly and push rarely. Committed-but-unpushed work is invisible to everyone
# except the agent that wrote it — and the agent reports it as DONE, because locally it is. That cost
# a real session: 14 commits sat on main for hours while the Crawler told the human a collaborator's
# deploy was missing a schema change, framed as a fact about the collaborator's build. He could not
# pull what had never been pushed. Every symptom pointed outward; none pointed at the branch.
#
# So the handback — checkpoint and mandate --clear, the exact moments the human forms a picture of
# what exists — says how far ahead of its upstream HEAD is. A WARNING, never a block: there are good
# reasons to hold commits back, and a gate that blocks them would be wrong on purpose.
#
# WHAT THIS MISSES, stated plainly: it compares HEAD to ITS upstream and nothing else. Uncommitted
# work, stashes, and commits sitting on other local branches are all invisible to it. A branch with
# no upstream is silent by design — nobody was ever promised that branch. And "pushed" is not
# "merged": a pushed branch nobody has merged is still absent from anyone else's build. Silence here
# means only that this one branch's upstream is current.

GIT_TIMEOUT = 3   # a courtesy check at turn-end must never stall the handback


def _git(*args):
    """git stdout (stripped), or None on any failure. Never raises: no git, no repo, no upstream, a
    hung index lock — every one of them degrades to silence, because this is a courtesy line."""
    try:
        r = subprocess.run(["git", *args], cwd=REPO_ROOT, capture_output=True, text=True,
                           timeout=GIT_TIMEOUT)
    except Exception:  # noqa: BLE001 — missing binary, timeout, decode error: all mean "stay quiet"
        return None
    return r.stdout.strip() if r.returncode == 0 else None


def ahead_of_upstream():
    """(commits ahead, branch, upstream) — or (0, None, None) when there is nothing honest to say.

    Nothing to say covers: no git, not a repo, an unborn or detached HEAD, and the important one —
    a branch with NO upstream. An untracked branch was never promised to anyone, so warning about it
    would be noise, and a guard that cries wolf is a guard that gets tuned out.
    """
    branch = _git("rev-parse", "--abbrev-ref", "HEAD")
    if not branch or branch == "HEAD":
        return 0, None, None
    upstream = _git("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}")
    if not upstream:
        return 0, None, None
    try:
        n = int(_git("rev-list", "--count", "@{upstream}..HEAD") or 0)
    except ValueError:
        return 0, None, None
    return (n, branch, upstream) if n > 0 else (0, None, None)


# Handback notes that make unpushed work someone else's problem: work called finished, a deploy, a
# handoff, another person. Deliberately generous — over-firing costs one louder paragraph, while
# under-firing costs the afternoon this whole check exists to prevent.
_HANDBACK_ESCALATORS = re.compile(
    r"\b(done|finish\w*|complete\w*|ship(?:ped|ping)?|land(?:ed|ing)|merg\w*|deploy\w*|releas\w*|"
    r"hand(?:ed|ing)?[- ]?(?:off|over|back)|handoff|handover|"
    r"teammate|collaborator|colleague|reviewer|review|team|CI|pull request|PR)\b", re.I)


def unpushed_warning(notes=None):
    """The handback line for work that exists only on this machine, or None. Logs when it fires, so
    how often commits sit local is a fact in log.jsonl rather than a hunch (INV4 wants the entry
    before anyone argues this should become a block)."""
    n, branch, upstream = ahead_of_upstream()
    if not n:
        return None
    loud = bool(notes and _HANDBACK_ESCALATORS.search(notes))
    logline({"kind": "unpushed", "ahead": n, "branch": branch, "upstream": upstream, "loud": loud})
    plural = "s" if n != 1 else ""
    lines = [f"⚠ UNPUSHED — {n} commit{plural} on {branch} exist{'' if n != 1 else 's'} only on this "
             f"machine (ahead of {upstream})."]
    if loud:
        lines.append("  ‼ Your notes read like a handback of finished work. Nobody — a teammate, CI, "
                     "a review,\n    a deploy — can pull what was never pushed, and every symptom "
                     "will point somewhere else.")
    lines.append("  Not a block; holding commits back is sometimes right. But if you are not doing "
                 "that on\n  purpose: `git push`. If you are, say so in the handback, in as many "
                 "words.")
    return "\n".join(lines)


# ── verbs ────────────────────────────────────────────────────────────────────────────────────────

# How a claim LANDED, and the headline each outcome prints. `resolved` is the default, so nothing
# about an ordinary claim changes. The other two exist because a harness that records only forward
# motion is training the agent to quietly move on when it turns out to be wrong.
CLAIM_OUTCOMES = {
    "resolved": "✓ CLAIM sourced.",
    "refuted": "✗ CLAIM REFUTED — a ruled-out path, on the record.",
    "inconclusive": "~ CLAIM INCONCLUSIVE — recorded; it did not settle.",
}


# ── scope claims ────────────────────────────────────────────────────────────────────────────────
#
# "only X", "X is restricted", "X does not support Y" is a claim about a SET, and it is routinely
# drawn from a sample of one. The observed failure (#22): one table's DELETE returned 500, the run
# concluded that THAT table was restricted, told the human so, and designed an archive-instead-of-
# delete scheme around the restriction. Hours later every DELETE on every table returned 500 — the
# delete path was down everywhere. The observation was correct and the SCOPE was invented, and one
# request against any other table at the moment of the first failure would have shown it.
#
# So a scope claim costs a second probe on a DIFFERENT member of the category. That is the keystone
# prose cannot satisfy here: not a file this time, but a second data point the first cannot fake.

# Wording that READS category-shaped. A heuristic, and only ever a NUDGE — it never refuses a claim.
# INV1 is explicit that enforcement must not depend on reading English (rephrase, and any word list
# loses), and INV5 forbids a guard that blocks its own fix, which a false positive here would be.
# It earns its place anyway because the run filing the claim is exactly the one that cannot see it
# is a set claim — so the flag has to be put in front of it while the second probe is still cheap.
_CATEGORY_TELLS = (
    r"\bonly\b", r"\ball\b", r"\bevery\b", r"\bany\b", r"\bnever\b", r"\balways\b",
    r"\bunsupported\b", r"\bcannot\b", r"\bcan't\b",
    r"\b(?:does|do|did|is|are)\s*n[o']?t\s+(?:support|allow|permit|accept)\w*\b",
    r"\b(?:is|are|was|were)\s+(?:restricted|protected|forbidden|blocked|disallowed|read-only)\b",
    r"\bnot\s+(?:allowed|permitted|supported)\b",
)


def category_tell(text):
    """The wording that makes an assertion read like a claim about a SET, or None.

    A heuristic on prose, deliberately kept out of the enforcement path: it decides what gets said,
    never what gets refused. What it misses is unbounded — any rephrasing walks straight past it.
    """
    low = (text or "").lower()
    for pat in _CATEGORY_TELLS:
        if (m := re.search(pat, low)):
            return m.group(0).strip()
    return None


# Wording that makes an assertion read like it came off an AGGREGATE rather than off an observation.
# Same standing as _CATEGORY_TELLS and for the same reason: a heuristic on prose decides what gets
# SAID, never what gets refused (INV1). Any rephrasing walks straight past it, and it only ever fires
# on a claim that is already citing a metric.
_AGGREGATE_TELLS = [
    r"\b\d+(\.\d+)?\s*%", r"\bper ?cent\w*\b", r"\btotals?\b", r"\bsummed\b", r"\bin total\b",
    r"\baverage[ds]?\b", r"\bmean\b", r"\bcombined\b", r"\baggregate\w*\b", r"\bper event\b",
    r"\bacross \d+\b", r"\bover \d+ (runs|trials|events|samples|iterations)\b",
]


def aggregate_tell(text):
    """The wording that makes an assertion read like it was derived from a sum/mean/percentage, or None.

    Advisory only, exactly like category_tell — and it misses an unbounded amount, starting with the
    incident's own sentence, which named two bare totals and no arithmetic at all.
    """
    low = (text or "").lower()
    for pat in _AGGREGATE_TELLS:
        if (m := re.search(pat, low)):
            return m.group(0).strip()
    return None


def cmd_claim(s, a):
    """Record an assertion about external reality, with the source that backs it — and how it landed.

    THE gate. Every "X does Y" about a dependency, a harness, or another repo goes through here. It
    refuses prose and demands a real file. This is the keystone check the module docstring describes:
    a path, not a paragraph.

    OUTCOMES. Being WRONG is the result most worth keeping: the reason a dead path is not re-walked
    in a later session is that the log says *this looked right, here is the control that killed it*.
    So an outcome is explicit — resolved (default) / refuted / inconclusive — and a refutation must
    name the control that killed it (`--evidence`), which is this same keystone turned on being
    wrong. A retraction costs exactly one real path, the same as any other claim: retracting already
    LOOKED like failure while costing what progress costs, and that asymmetry is what taught the
    quiet move-on. `game_loop status` reads the standing RULED-OUT list back out of the shared log.

    SCOPE. A claim about a CATEGORY is not a claim about the instance you observed — "only X", "X is
    restricted", "X does not support Y" are claims about a SET, and a set is exactly what one
    observation cannot establish. `--scope "<the category>"` with two `--probe` values on DIFFERENT
    members is the admission gate for those, and both probes are recorded. The flag is the
    enforcement; `category_tell()` is only a nudge when a set-shaped assertion is filed as an
    instance, because enforcement that depends on reading English is not enforcement (INV1).
    EVIDENCE THAT IS A NUMBER. `--read` is unchanged and remains THE keystone for a claim backed by
    a document. `--metric` adds a second kind of evidence for the claims a path cannot source —
    "the number shows Y" — because "name a real file" is not merely insufficient there, it is
    satisfiable while being completely wrong: every instrument incident was run by an agent who
    could have cited a real file the whole time. Its keystone is a controlled instrument plus a
    two-endpoint reading (see admit_metric).

    AN AGGREGATE IS NOT AN OBSERVATION. `--aggregate sum|mean|pct` says the effect was derived by
    collapsing a set of events into one number, and a collapsed number owes the set it came from
    (see admit_distribution). `aggregate_tell()` is only a nudge when an aggregate-shaped sentence
    is filed without it, for the same reason category_tell never refuses.
    """
    outcome = (a.outcome or "resolved").lower()
    if outcome not in CLAIM_OUTCOMES:
        die("--outcome must be one of: " + " · ".join(CLAIM_OUTCOMES) + "\n"
            "  resolved     — it held up\n"
            "  refuted      — it did NOT: name the control that killed it with --evidence\n"
            "  inconclusive — the experiment ran and did not settle it")
    if outcome == "refuted" and not a.evidence:
        die("a refuted claim needs --evidence <path[,path]>: the control, log, or output that\n"
            "DISPROVED it. A retraction without its evidence is a deletion — the next session just\n"
            "re-walks the dead path. Name the file that killed it; that is the whole value here.")
    # A finding that depends on a verb having ACTED is admitted only if that verb has been proved to
    # act (`effector --prove`). This is the #19 gate at the point of assertion: the four incidents
    # were all confident, detailed, WRONG findings written from a screen an effector never touched.
    proof = None
    if a.effector:
        proof = effector_proof(s, a.effector)
        if proof is None:
            proved = ", ".join(e.get("name", "?") for e in (s.get("effectors") or [])) or "(none)"
            die(f"this claim leans on the effector {a.effector!r} having acted, and nothing in this "
                "session proves it did.\n"
                f"  proved here: {proved}\n"
                "An effector that fails quietly does not produce zero findings — it produces FALSE "
                "ones, indistinguishable in tone and detail from real ones. Prove it against a state "
                "whose response you already know, then claim:\n"
                '  game_loop effector --prove ' + a.effector + ' --known-state ".." '
                "--before <capture> --observed <capture>")
    aggregate = (a.aggregate or "").lower() or None
    if aggregate and aggregate not in AGGREGATE_KINDS:
        die("--aggregate must be one of: " + " · ".join(AGGREGATE_KINDS) + "\n"
            "  sum  — the effect is a total over events\n"
            "  mean — the effect is an average over events\n"
            "  pct  — the effect is a percentage, which is a total wearing a ratio\n"
            "All three collapse a distribution into one number, and all three hide the same thing.")
    if aggregate and not a.metric:
        die("--aggregate describes a READING, so it needs the instrument that reading belongs to:\n"
            '  game_loop claim --assert ".." --metric <name> --aggregate ' + aggregate + "\n"
            "An aggregate with no measurement behind it is a number nobody can decompose.")
    exclude = parse_event_index(a.exclude) if a.exclude is not None else None
    if exclude is not None and not a.metric:
        die("--exclude drops one event from a reading's distribution, so it needs --metric <name>.")
    # A metric is admitted through its own gate (controls + a two-endpoint reading), so it stands in
    # for --read the way a refutation's evidence does — the keystone changes shape, never softens.
    metric = (admit_metric(s, a.metric, a.recheck, aggregate, exclude, a.because)
              if a.metric else None)
    # For a refutation the evidence IS a source you read, so it stands in for --read. Retracting must
    # cost no more than claiming, or the cheapest move stays "say nothing and move on". An effector
    # proof stands in the same way: its before/after pair are real files, already resolved.
    read_arg = (a.read or (a.evidence if outcome == "refuted" else None)
                or (proof["before"] + "," + proof["observed"] if proof else None))
    if not a.assert_ or not (read_arg or metric):
        die("claim needs --assert \"<what you're about to tell the human>\" and --read <path[,path]>.\n"
            "The read path is the keystone: name the file you ACTUALLY read, not a memory of it.\n"
            "A claim you cannot source is a guess wearing a citation.\n"
            "When the evidence is a MEASUREMENT rather than a document, cite the instrument instead:\n"
            '  game_loop claim --assert ".." --metric <name>   (see `game_loop instrument`)')
    paths = [p.strip() for p in (read_arg or "").split(",") if p.strip()]
    resolved = {p: resolve_read(p) for p in paths}
    bad = [p for p, r in resolved.items() if r is None]
    if bad:
        die("these --read paths don't resolve to a real, non-empty file "
            "(absolute, or relative to the repo / a read_root): "
            + ", ".join(bad) + "\nName a source you actually read (T0), then claim.")
    ev_paths = [p.strip() for p in (a.evidence or "").split(",") if p.strip()]
    ev_resolved = {p: resolve_read(p) for p in ev_paths}
    ev_bad = [p for p, r in ev_resolved.items() if r is None]
    if ev_bad:
        die("these --evidence paths don't resolve to a real, non-empty file: " + ", ".join(ev_bad) +
            "\nThe disproving evidence is the point of a retraction — name the real control, log, or "
            "output that killed the claim, not a description of one.")
    # A scope claim costs a second probe on a DIFFERENT member. One data point can only ever say
    # "this call failed"; the sentence that gets acted on is "this CLASS of call fails".
    probes = [p.strip() for p in (a.probe or []) if p.strip()]
    if probes and not a.scope:
        die("--probe needs the category it is probing: --scope \"<the set you are claiming about>\".\n"
            "Two members with no set named is not a boundary, it is two observations.")
    if a.scope:
        if len(probes) < 2:
            die(f"a claim about \"{a.scope}\" needs two --probe values, on DIFFERENT members.\n"
                "\"only X\" / \"X is restricted\" / \"X does not support Y\" is a claim about a SET,\n"
                "and it is the first hypothesis that fits one failure — seductive because it explains\n"
                "the evidence completely while being invented. Probe a second member: one more\n"
                "request is what turns the guess into a boundary.")
        members = {" ".join(p.split()).lower() for p in probes}
        if len(members) < 2:
            die(f"both --probe values name the same member ({probes[0]}) — a second probe identical\n"
                f"to the first proves nothing. Probe a DIFFERENT member of \"{a.scope}\": the one that\n"
                "says whether you found a boundary or the whole path is down.")
    rec = {"kind": "claim", "assert": a.assert_, "read": list(resolved.values()),
           "outcome": outcome, "evidence": list(ev_resolved.values()),
           "confidence": a.confidence, "effector": a.effector,
           "scope": a.scope, "probes": probes}
    if metric:
        inst, reading, mv, dist = metric
        rec.update({"metric": inst["name"], "measures": inst.get("measures"),
                    "reading": {k: reading[k] for k in ("before", "after", "delta")}})
        if dist:
            # The share the tool computed, the excluded event and the stated reason all go to the
            # shared log. In the incident the artifact had already been identified and dismissed
            # earlier in the SAME session and was rediscovered anyway; the record is what breaks that.
            rec["distribution"] = dist
            if "excluded" in dist:
                reading["excluded"] = dict(dist["excluded"], at=now())
        if mv and a.recheck:
            # The re-check is recorded ON the instrument and counted against the readings it was
            # made at, so a LATER movement demands a fresh one instead of resting on this answer.
            rec["recheck"] = a.recheck
            inst["recheck"] = {"text": a.recheck, "at": now(), "pct": round(mv["pct"], 1)}
            inst["recheck_n"] = len(inst.get("readings") or [])
    logline(rec)
    s["claim_count"] = s.get("claim_count", 0) + 1
    s["work_since_stepback"] = s.get("work_since_stepback", 0) + 1   # feeds the retro nudge
    save(s)
    msg = [CLAIM_OUTCOMES[outcome],
           f"  assert    : {a.assert_}",
           f"  outcome   : {outcome}"]
    if paths:
        msg.append(f"  read (T0) : {', '.join(paths)}")
    if metric:
        inst, reading, mv, dist = metric
        msg.append(f"  metric    : {inst['name']} — {_num(reading['before'])} → "
                   f"{_num(reading['after'])} (Δ {_num(reading['delta'])}, computed by the tool)")
        msg.append(f"  stands for: {inst.get('measures')}")
        if aggregate:
            msg.append(f"  derived by: {AGGREGATE_KINDS[aggregate]} over "
                       f"{dist['events'] if dist else 0} events")
        if dist and dist["top_event"] is not None:
            msg.append(f"  shape     : {dist['events']} events totalling "
                       f"{_num(dist['total'])} · event {dist['top_event']} carries "
                       f"{dist['share_pct']:.1f}%   ← computed by the tool")
        elif dist:
            msg.append(f"  shape     : {dist['events']} events, every one of them zero")
        if dist and "excluded" in dist:
            ex, rest = dist["excluded"], dist["without"]
            msg += [f"  excluded  : event {ex['event']} ({_num(ex['value'])}) — {ex['reason']}",
                    f"  without it: {_num(rest['total'])} across {rest['n']} events — "
                    f"{rest['per_event']:.1f} per event, {rest['nonzero']} non-zero",
                    "→ the exclusion and its reason are on the record, so the next run inherits the "
                    "artifact instead of rediscovering it."]
        if a.recheck:
            msg.append(f"  re-checked: {a.recheck}")
    if ev_paths:
        msg.append(f"  killed by : {', '.join(ev_paths)}")
    if proof:
        msg.append(f"  effector  : {proof['name']} — proved {proof['at']} against: "
                   f"{proof['known_state']}")
    if a.confidence:
        msg.append(f"  confidence: {a.confidence}")
    if a.scope:
        msg += [f"  scope     : {a.scope}",
                f"  probes    : {' · '.join(probes)}",
                "→ recorded as a boundary rather than a guess.",
                "  WHAT THIS CANNOT CHECK: that either probe was actually run, or that the second",
                "  member sits on the other side of the category. It holds you to two members, not",
                "  to the right two."]
    elif (tell := category_tell(a.assert_)):
        # Filed as an instance, but it READS like a claim about a set. Loud, never blocking.
        msg += [f"⚠ that assertion reads category-shaped (\"{tell}\") but was filed as an instance.",
                "  A scope hypothesis is the first thing that fits one failure, and one observation",
                "  is exactly what cannot establish it. If it is a claim about a SET, probe a second",
                "  member and re-file it:",
                "    game_loop claim --assert \"..\" --read <path> --scope \"<the category>\" "
                "--probe <a> --probe <b>",
                "  The tell that you need this: you start building a WORKAROUND. A workaround is",
                "  downstream of a scope claim, and the last moment the claim is cheap to check.",
                "  (Wording only — it cannot tell a set claim from an innocent \"only\", so it never",
                "   refuses, and any rephrasing walks past it. An instance claim owes nothing here.)"]
    # Cited a metric, the sentence reads like it came off a total, and no distribution is attached.
    # Loud, never blocking — the wording check cannot tell an aggregate from an innocent "total", and
    # a guard that refused on a false positive here would block its own fix (INV5).
    if metric and not metric[3] and (tell := aggregate_tell(a.assert_)):
        msg += [f"⚠ that assertion reads aggregate-shaped (\"{tell}\") and the reading behind it has "
                "no shape.",
                "  A SUM IS NOT A DISTRIBUTION. One event of thirty once carried 96% of a total that",
                "  was written up as a total elimination — and the totals revealed nothing; only the",
                "  per-event values did. Record them against the reading and re-file it:",
                f"    game_loop measure --instrument {metric[0]['name']} --before <n> --after <n> "
                "--events \"<v,v,v,..>\"",
                f"    game_loop claim --assert \"..\" --metric {metric[0]['name']} --aggregate sum",
                "  (Wording only — it cannot tell a derived number from an observed one, so it never",
                "   refuses, and the incident's own sentence named two bare totals and would have",
                "   walked straight past it. A single-quantity reading owes nothing here.)"]
    if outcome == "refuted":
        msg.append("→ it now stands in the RULED-OUT list on `game_loop status`, so the next run "
                   "inherits it instead of re-walking it.")
    if metric:
        msg.append("  " + "\n  ".join(INSTRUMENT_MISSES))
        if metric[3]:
            msg.append("  " + "\n  ".join(DISTRIBUTION_MISSES))
    out(*msg)
    flair_out(s, "claim")


# ── what a mandate SAID about its own finish line: facts, not a verdict ──────────────────────────
#
# THE SEQUENCING IS wcs's AND SO IS THE SHAPE, and it is the second time in one exchange their
# measurement killed a design of mine that I was about to build.
#
# WHAT I WAS GOING TO BUILD: `mandate --set` nudges when the text carries no finish line, and
# records `has_finish_line: false` so a later clear-side gate could be answerable. Both halves were
# wrong, and they ran it against 42 real mandate_set records before I wrote a line of it:
#
#   IT FIRES ON 88%.  37 of 42 have no explicit marker. A nudge that speaks on seven of every eight
#   mandates is not rare, it is the banner an agent learns to scroll past — the exact failure
#   showrunner named as the one this class of feature dies of, and the one #4 already died of once.
#
#   THE FALSE NEGATIVES ARE THE BEST-SPECIFIED MANDATES IN THE LOG. Ten of theirs ENUMERATE their
#   work — "(1) skip-trace API seam ... (2) ... (3) ..." — and carry no marker. Those have a finish
#   line; it is the list. Nudging them teaches agents that enumerating the work is not good enough
#   and that a magic phrase is, which is backwards.
#
#   AND THE FALSE POSITIVE READS GREEN, which is the direction that matters. Their live mandate
#   matched on `until` — inside item (2), "re-run the neutral reviewer until READY". A condition on
#   ONE ITEM, not a finish line for the mandate. Mention versus use, in the third place this
#   exchange has found it, and recorded as `has_finish_line: true` it would be quietly wrong for
#   exactly the mandates nobody re-checks.
#
# SO: RECORD THE FACTS, NOT THE CONCLUSION. Three things that cannot be wrong because they are not
# judgements, plus the EVIDENCE for each — which is the half that answers wcs's false positive. A
# bare `true` gives a later reader nothing to judge; `until` with the words either side of it lets
# them see it sits inside item (2) and decide in a second. Storing the conclusion destroys the
# information that would show the conclusion was wrong.
#
# AND NO NUDGE SHIPS YET, deliberately. Their 42 records and this repo's 7 are different
# populations from the same tool and the same author — their shortest mandate is 198 characters and
# this repo's log contains the literal string "ship it". A threshold tuned on either misfires on
# the other, so the number is per-repo and there is no cross-repo measurement to set it from. The
# facts are what make that measurement possible later; guessing the threshold now is what makes it
# impossible to check.

_FINISH_MARKERS = ("done when", "definition of done", "finished when", "complete when",
                   "acceptance criteria", "success criteria", "exit criteria")
_ENUM_ITEM_PAT = re.compile(r"(?:^|\s)(?:\(\d+\)|\d+[.)]|[-*•])\s+\S", re.M)


def _typographic_at(text, i, marker):
    """Was this marker TYPED AS A CONVENTION — upper case and followed by a colon?

    wcs's rule, and it is the one that separates the two populations they measured: "prefer markers
    that are TYPOGRAPHIC (caps, colon, line-initial) over markers that are lexical. A word can be
    used in a sentence; a convention has to be typed on purpose."

    They measured the difference rather than arguing it. Over 42 records their proposed marker set
    hit 5 times at 40% precision, and every miss was a LEXICAL match — `until` three times, once
    cautioning against trusting a source, once forbidding a re-run, once as a condition on item (2)
    of four. Both true positives were `DONE WHEN:` — capitalised, colon, at a clause boundary.

    So the flag rather than a shorter list: dropping the lexical forms would throw away the record
    that they appeared, and this field is supposed to let a later reader judge rather than inherit
    somebody's threshold. A marker with typographic False is not a false positive, it is a match
    whose precision is known to be poor.
    """
    seg = text[i:i + len(marker)]
    after = text[i + len(marker):i + len(marker) + 2]
    return seg.isupper() and after.lstrip()[:1] == ":"


def finish_line_facts(text, window=36):
    """What a mandate's text SAYS about its own finish line, as facts with their evidence.

    Returns markers_checked / labelled_markers / enumerated_items / text_len.

    EVERY FIELD IS AN OBSERVATION, NOT A CLASSIFICATION. Nothing here says whether the mandate HAS
    a finish line, because that judgement was measured and found wrong in both directions — and
    because a reader in a month can ask questions of these that a boolean has already thrown away,
    including the one that caught it: was the marker inside an enumerated item?

    THE FIELD IS `labelled_markers` AND THE LIST IS RECORDED BESIDE IT, and that is showrunner's
    finding rather than tidiness. They ran this over 29 of their own records and got 0 hits, and
    were about to report "showrunner never writes a finish condition" — then read the records
    instead of the count. Sixteen of the twenty-nine state a terminal state INLINE and label none
    of it: "work issue #75 through to pushed and closed", "spawn a real Crawler ... and integrate
    or reap the result". So `0 of 29` was a fact about the MARKER LIST, not about the mandates —
    the instrument, not the measurement.

    An empty list here therefore licenses exactly one sentence: no marker from `markers_checked`
    was found. It does NOT say the mandate has no finish line, and the field is named for the
    labelling rather than the finish so that a later gate cannot quietly read it as the second
    thing. Carrying the list makes the record self-describing — the instrument travels with the
    reading, which is the only thing that would have caught showrunner's near-miss from outside.

    The context window is the point of each entry, not a nicety. `done when` alone is unjudgeable;
    `done when` with the words either side of it is judgeable at a glance, which is the cheapest
    guard against the mention-versus-use failure that produced all of this.
    """
    t = str(text or "")
    low = t.lower()
    markers = []
    for mk in _FINISH_MARKERS:
        start = 0
        while True:
            i = low.find(mk, start)
            if i < 0:
                break
            markers.append({"marker": mk, "at": i,
                            "typographic": _typographic_at(t, i, mk),
                            "context": " ".join(t[max(0, i - window):i + len(mk) + window].split())})
            start = i + len(mk)
    # HOW MUCH OF THIS IS A QUOTED INSTRUCTION — balooga-owner's correction, and it invalidated a
    # cross-repo comparison that five of us had already started making. Five of their six mandates
    # embed TWO documents: a verbatim quote of the human, then the agent's plan. Raw median 722,
    # agent's half alone 479. Nobody had asked whether the field was one document or two, so the
    # length rows were silently comparing different objects. showrunner checked their own at the
    # same instruction and found 0.7% quoted, all of it error strings — one-part, like-for-like.
    #
    # A LOWER BOUND AND IT SAYS SO: this counts characters inside '' and "" spans, so a human
    # instruction pasted with no quotation marks at all measures zero. That is why the number is
    # reported rather than a two-part/one-part verdict — the fact is countable, the conclusion is
    # not, which is the same rule as every other field here.
    _blanked = _blank_quoted(t)
    return {"markers_checked": list(_FINISH_MARKERS),
            "labelled_markers": markers,
            "enumerated_items": len(_ENUM_ITEM_PAT.findall(t)),
            "quoted_chars": sum(1 for a, b in zip(t, _blanked) if a != b),
            "text_len": len(t)}


def cmd_mandate(s, a):
    """Bind, park, resume, or release an autonomy mandate. While bound, the Stop gate is live.

    Self-binding on purpose. A human says "work autonomously"; that instruction is prose, and prose
    is what the agent demonstrably ignores. Recording it in state turns it into something a hook can
    read at the exact moment the session tries to stop early.

    A mandate has exactly TWO ends, and the difference between them is the whole point:
      * --clear  CLOSURE. The work is done. The gate goes inert because there is nothing left.
      * --park   A HUMAN CALLED A BREAK. Not done, not given up on — interrupted by the one authority
                 this engine exists to defer to. The mandate stays OPEN, so `status` keeps showing it
                 as outstanding work with the human's own words and the next step intact.
    Nothing else ends a mandate, which is what keeps the gate sharp for everything else: before this,
    an interrupted run had two options, violate the gate or fabricate a closure that reads forever
    after as though the work had been finished.

    WHAT A PARK CANNOT DO, structurally: it is not a way out of the gate. It buys exactly ONE
    turn-end (`_stop_verdict` consumes it, like a checkpoint or an arm), it does not launder a
    question — the ask/announce checks run first — and it does not clear anything, so the next
    turn-end faces a live gate again and the parked work follows the run until it is really closed.

    WHAT IT CANNOT ENFORCE, said plainly (INV6, and the same honesty `authorize` owes): nothing on
    this side of the keyboard can verify the human really called the break — the agent is the one
    typing. What it does is make the break LOUD (`mandate_park` in the log, attributed to the human,
    with their verbatim words), NARROW (one turn-end), and PERMANENT (never quietly reads as a
    closure). That is strictly more than `--clear` could ever prove, and `--clear` is the exit an
    interrupted run was already taking.

    On the name: `park` is also the watchdog's word for waiting out an exhausted usage window
    (`limit_park`). Same meaning — the run pauses and is expected to come back — different noun
    parked and different waker: the clock ends a limit park, the human ends this one. Every
    identifier here is namespaced to the mandate (`mandate.parked`, `mandate_park`,
    `mandate_resume`) and shares nothing with `limit_parked_until` / `watchdog_limit_park`.
    """
    m = s.setdefault("mandate", {})
    if a.park:
        if not m.get("active"):
            die("nothing to park — no mandate is bound, so the Stop gate is already inert.")
        if not a.reason:
            die("mandate --park needs --reason \"<the human's words, verbatim>\".\n"
                "This exit exists for THEIR break, not your judgement — so it records who called it\n"
                "and in whose words. Quote them; don't paraphrase, and don't park your own decision.")
        nxt = a.next or (s.get("phase") or {}).get("doing")
        m["parked"] = {"by": "human", "reason": a.reason, "next": nxt, "at": now(), "spent": False}
        s["stop_blocks"] = 0
        save(s)
        logline({"kind": "mandate_park", "text": m.get("text"), "by": "human",
                 "reason": a.reason, "next": nxt})
        out("⏸ MANDATE PARKED — a human called this break. The work stays OPEN, not closed.",
            f"  mandate    : {m.get('text')}",
            f"  their words: {a.reason}",
            f"  next step  : {nxt or '(none recorded — say what you were about to do)'}",
            "→ this buys ONE turn-end. It is not a closure: `game_loop status` keeps showing this as",
            "  outstanding, and the next turn-end meets a live gate again.",
            "→ when they're back:  game_loop mandate --resume",
            "   if it turns out to be finished: game_loop mandate --clear --notes \"..\"")
        return
    if a.resume:
        p = m.get("parked")
        if not p:
            die("nothing to resume — this mandate is not parked. (A mandate that was never bound is "
                "bound with `mandate --set \"..\"`.)")
        m.pop("parked")
        m["active"] = True
        s["stop_blocks"] = 0
        # Same re-arm as --set: the break may have outlasted the ring budget, and a resumed run must
        # not inherit an exhausted watchdog and silently never be woken.
        s["watchdog_rings"] = 0
        s["watchdog_last_ring_size"] = 0
        s["watchdog_exhausted_paged"] = False
        # Same reason one step further: a session that handed over and is now being driven again is
        # driving again. Leaving the flag would keep its watchdog stood down for the rest of its life.
        s.pop("handed_off", None)
        save(s)
        logline({"kind": "mandate_resume", "text": m.get("text"), "parked_at": p.get("at"),
                 "reason": p.get("reason")})
        out("▶ MANDATE RESUMED — the break is over and the Stop gate is LIVE again.",
            f"  mandate    : {m.get('text')}",
            f"  parked at  : {p.get('at')} — {p.get('reason')}",
            f"  next step  : {p.get('next') or '(none was recorded)'}",
            "→ pick that next step up; the work was never closed.")
        return
    if a.clear:
        if not m.get("active"):
            out("no mandate was bound; nothing to clear.")
            return
        was_parked = bool(m.pop("parked", None))
        m["active"] = False
        m["cleared_at"] = now()
        s["stop_blocks"] = 0
        s["stops_since_clear"] = 0     # each clear gets its own window; see cmd_stopgate
        save(s)
        logline({"kind": "mandate_clear", "text": m.get("text"), "notes": a.notes,
                 "was_parked": was_parked})
        if notify:
            notify.send("mandate_clear",
                        f"🏁 mandate complete — {m.get('text')}\nnotes: {a.notes or '(none)'}")
        out("✓ MANDATE released — the Stop gate is inert again.",
            f"  was  : {m.get('text')}",
            f"  notes: {a.notes or '(none)'}")
        # The work is being declared done — say whether anyone but this machine can see it, and
        # whether a fix it reports was ever exercised. This is the loudest "shipped" there is.
        if (w := unpushed_warning(a.notes)):
            out(w)
        if (w := fix_warning(s, a.notes)):
            out(w)
        flair_out(s, "mandate_clear")
        return
    if not a.set:
        # RECORDING A WAKE PATH MUST NOT COST THE MANDATE'S OWN HISTORY (#95). --wake-path was
        # reachable only through --set, and --set stamps `since` with now() — so the only way to
        # answer status's "MANDATE ARMED, AND NO EXTERNAL WAKE PATH IS RECORDED" warning on an
        # already-bound mandate was to RE-BIND it, silently replacing the record of when the human
        # actually said the words. That warning appears later than the binding by construction, so
        # the broken case was the normal one, not an edge. Measured here: the field was unusable for
        # its own purpose, and the honest move was to skip it and write the finding down elsewhere.
        # AN EMPTY --wake-path IS FALSY, so it fell past this block and out to the generic "mandate
        # needs --set" usage text — the right refusal reached by the wrong road, telling the caller
        # nothing about the flag they actually typed. Same shape as `--fault ""` and the misspelt
        # `expect`: a verdict that is correct while its reason sends you somewhere else.
        if getattr(a, "wake_path", None) == "":
            die("--wake-path was given but is EMPTY.\n\n"
                "The field answers 'how does a signal reach this session while it is idle', and an\n"
                "empty answer is worse than none: `status` would stop warning while nothing had\n"
                "actually been arranged, which is the silence this field exists to break.\n\n"
                "    mandate --wake-path \"a cron every 10 minutes\"\n"
                "    mandate --wake-path \"a human who checks\"   <- the common case, and honest")
        if getattr(a, "wake_path", None):
            if not m.get("active"):
                die("no mandate is bound here, so there is nothing to record a wake path for.\n"
                    "A wake path answers 'how does a signal reach this session while it is idle' —\n"
                    "which is only a question while something is waiting on it.")
            # A REPLACEMENT IS NOT A RECORDING, and until now they printed the same line (#95).
            # OBSERVED, in this repo's own log: a session declared a careful 751-character wake
            # path — the honest one, "a human who checks", spelling out that nothing here wakes an
            # inert run — and a later probe of this very flag overwrote it with "x". Both writes
            # printed the same success line, nothing named what was lost, and `status` went on
            # reporting a declared wake path, because ANY non-empty string satisfies that check.
            # The warning this field exists to raise had been silenced by a placeholder — which is
            # worse than the empty value two branches up, and that one is refused outright.
            #
            # LOUD, NOT REFUSED. Updating a wake path is legitimate and common — the run that
            # arranges a cron after starting without one is the good case — so refusing would be
            # wrong. What was missing is that the old answer left without being named.
            _prev = m.get("wake_path")
            _replaced = []
            if _prev and _prev != a.wake_path:
                _lines = _prev.splitlines() or [""]
                _replaced = ["⚠ THIS REPLACED AN EXISTING DECLARATION, which said:",
                             "    " + _lines[0][:150]]
                if len(_lines) > 1:
                    _replaced.append("    (+%d more line(s), %d chars in total)"
                                     % (len(_lines) - 1, len(_prev)))
                _replaced += [
                    "  Named here so a clobber is visible rather than inferred. A probe of this",
                    "  flag writes to the REAL record, which is how the observed one happened; the",
                    "  previous value is in .game_loop/log.jsonl under kind=mandate_wake_path.", ""]
            m["wake_path"] = a.wake_path
            if getattr(a, "wake_every", None):
                m["wake_every"] = int(a.wake_every)
            save(s)
            logline({"kind": "mandate_wake_path", "wake_path": a.wake_path, "text": m.get("text"),
                     "replaced": _prev})
            if _replaced:
                out(*_replaced)
            out("✓ wake path recorded — DECLARED, never probed.",
                f"  mandate : {m.get('text')}",
                f"  wake    : {a.wake_path}",
                "",
                "This records a CLAIM that something outside can reach this session. Nothing here",
                "tested it, and a declared path that has stopped delivering reads exactly like one",
                "that works — which is the failure this field exists to make visible, not to fix.")
            return
        die("mandate needs --set \"<the mandate, in the human's words>\", or one of\n"
            "  --park --reason \"<their words>\"   a human called a break (stays OPEN)\n"
            "  --resume                          they're back\n"
            "  --clear [--notes ..]              the work is actually done")
    # A LIVE MANDATE IS NOT SILENTLY REPLACEABLE (#88). A dispatched subagent inherits
    # CLAUDE_CODE_SESSION_ID, so its `--set` lands in the PARENT's state file and overwrites the
    # parent's mandate — after which the Stop gate and the watchdog enforce the WORKER's goal
    # against the LEAD, for several turns, with every gate working correctly.
    #
    # Keyed on the WORDS rather than on identity, deliberately. The two callers are
    # indistinguishable by construction — same session id, and pid differs on every CLI invocation
    # including legitimate ones — so an identity check could not separate the cases it exists for.
    # "A live mandate is being replaced with different words" needs no identity, catches their case,
    # and also catches two sibling sessions colliding in one state file, which an id check misses.
    if m.get("active") and (m.get("text") or "").strip() and (m.get("text") or "").strip() != \
            (a.set or "").strip():
        die("REFUSED — a mandate is already bound here, and this would replace it.\n\n"
            f"  BOUND  : {m.get('text')}\n"
            f"      set : {m.get('since')}"
            + (f"   by pid {m['setter'].get('pid')}" if isinstance(m.get("setter"), dict) else "")
            + f"\n  YOURS  : {a.set}\n\n"
            "IF YOU ARE A DISPATCHED SUBAGENT, this is not your state file. An in-process subagent\n"
            "inherits CLAUDE_CODE_SESSION_ID, so your mandate would land in your PARENT's session\n"
            "and the watchdog would spend the next several turns telling THEM to do YOUR task.\n"
            "Give yourself your own state:\n\n"
            "    GAME_LOOP_SESSION=<something unique to you> game_loop mandate --set \"..\"\n\n"
            "IF YOU MEAN TO REPLACE IT, say so in one line first — that verb already exists:\n\n"
            "    game_loop mandate --clear --notes \"superseded by: ..\"\n\n"
            "Re-setting the SAME words is allowed, so a retry or a re-bind after compaction costs\n"
            "nothing. What is refused is losing a live mandate without a decision.")
    if getattr(a, "wake_path", None):
        m["wake_path"] = a.wake_path
        if getattr(a, "wake_every", None):
            m["wake_every"] = int(a.wake_every)
    m.pop("parked", None)   # a re-bind supersedes any break; the new words are the mandate now
    # AN IDENTICAL RE-BIND KEEPS THE ORIGINAL `since`. The refusal above explicitly allows
    # re-setting the SAME words "so a retry or a re-bind after compaction costs nothing" — but it
    # did cost something, silently: `since` moved to now(), so a mandate bound six hours ago read as
    # bound just now, and every staleness judgement downstream of it was reset by a no-op re-bind.
    # New words are a new mandate and correctly restamp.
    _same_words = bool(m.get("active")) and (m.get("text") or "").strip() == (a.set or "").strip()
    m.update({"active": True, "text": a.set,
              "since": (m.get("since") or now()) if _same_words else now(),
              # Recorded even though it decides nothing here: their second suggestion is that a
              # COLLISION be visible, and it is worth having for a mandate that was allowed through.
              "setter": {"pid": os.getpid(), "ppid": os.getppid(),
                         "claude_session": os.environ.get("CLAUDE_CODE_SESSION_ID", ""),
                         "gl_session": os.environ.get("GAME_LOOP_SESSION", "")}})
    s["stop_blocks"] = 0
    # A new mandate re-arms the watchdog, so it does not inherit an exhausted ring budget from an
    # earlier session and silently never enforce.
    s["watchdog_rings"] = 0
    s["watchdog_last_ring_size"] = 0
    s["watchdog_exhausted_paged"] = False
    # ...and it cancels any handover recorded here. Handing a mandate over stands this session's
    # watchdog down; taking a NEW mandate is this session saying it is working again, and a fresh
    # mandate with a permanently disarmed engine is the exact stall `handed_off` exists to avoid.
    s.pop("handed_off", None)
    save(s)
    # THE FACTS ABOUT THE FINISH LINE RIDE THE SET RECORD, because the clear side cannot be made
    # answerable for a promise the set side never wrote down — which is what every clear-side gate
    # proposed in this exchange foundered on, mine included.
    # THE INSTRUCTION THAT PROMPTED IT, IF THE AGENT WILL QUOTE ONE — showrunner's second
    # instrument, offered explicitly as "not a request" and taken because it is cheap now and
    # expensive to reconstruct later. Their measurement: 29 mandates, 0 with the triggering
    # instruction recorded beside them. balooga-owner's handover hypothesis was testable on
    # balooga's data and not on showrunner's for exactly one reason — balooga's mandate text
    # EMBEDS the human quote and showrunner's does not. With this field the whole class of
    # question is answerable from the log instead of from an agent's memory of its own sessions.
    #
    # NAMED `because_quote` AND NOT `reason`, and the distinction is the load-bearing part.
    # showrunner's own argument for why `authorize --reason` is a better source than mandate_set
    # is that it is REQUIRED VERBATIM, so it cannot drift into paraphrase the way a summary does.
    # This field has no such protection: it is optional, and the agent is the one typing — the
    # same honesty `authorize` already owes, where nothing can verify the human really said it.
    # So it is recorded as a QUOTE the agent supplied, flagged unverified, and no consumer of the
    # log may read it as established. A field that looked like the human's words and was not would
    # be worse than the gap it fills.
    _mrec = dict({"kind": "mandate_set", "text": a.set}, **finish_line_facts(a.set))
    if getattr(a, "because", None):
        _mrec["because_quote"] = a.because
        _mrec["because_verified"] = False
    logline(_mrec)
    out("✓ MANDATE bound. The Stop gate (protecting the human's attention) is now LIVE.",
        f"  {a.set}",
        "→ ending your turn now requires one of:",
        "    game_loop checkpoint --notes \"..\"                report progress and hand back (no question)",
        "    game_loop arm --question .. --read .. --predict .. ask something you genuinely can't derive",
        "    game_loop mandate --clear --notes \"..\"           the work is actually done",
        "    game_loop mandate --park --reason \"<their words>\"  ONLY when a human calls a break",
        "Otherwise the Stop hook sends you back to work. That is the point.")
    flair_out(s, "mandate_set")


def ritual_checkpoints():
    """Checkpoints since the last piece of EVIDENCE WORK, from the shared log (#75).

    NOT a gate, deliberately. `checkpoint` is cheap so a stop is always DELIBERATE, and pricing it
    would push the next agent toward `--park`, which claims a human called a break when none did —
    a worse failure than the one being fixed. What changes is the RECORD: repetition becomes
    visible, which is what makes "this mandate is being ritualised" arguable with evidence instead
    of something a human has to notice and say twice.
    """
    WORK = {"claim", "harden", "fix_prove", "effector_prove", "mutate_prove", "trans", "stepback",
            "measure", "instrument", "confidence", "authorize"}
    n, oldest = 0, None
    try:
        with open(LOG_F) as f:
            recs = [l for l in f if '"kind"' in l]
    except OSError:
        return 0
    for line in reversed(recs):
        try:
            r = json.loads(line)
        except ValueError:
            continue
        k = r.get("kind")
        if k == "checkpoint":
            n += 1
            oldest = r.get("t") or oldest
        elif k in WORK:
            break
    # A COMMIT IS THE HALF THE AGENT DOES NOT AUTHOR, and without it this counter measures narration
    # rather than work. Every name in WORK is a verb the agent CHOOSES to call: a session that stalls
    # also fails to call them, which is the case we want — but a session doing real work without
    # narrating it gets told it is ritualising, and the remedy it will reach for is to call a verb
    # rather than to do something. Found by a consumer who built this same counter, made the same
    # choice, and measured its consequence before I had.
    if n >= 2 and oldest:
        try:
            r = subprocess.run(["git", "log", "--all", f"--since={oldest}", "--format=%h"],
                               cwd=REPO_ROOT, capture_output=True, text=True, timeout=10)
            if r.returncode == 0 and r.stdout.strip():
                return 0            # real work landed; the checkpoints were reporting it
        except (OSError, subprocess.SubprocessError):
            pass                    # no git, no answer: fall through to the verb-only count
    return n


# THE CAVEATS ARE FIXED STRINGS AND MUST STAY THAT WAY (#76). Counts and names interpolate; the
# sentence explaining what a number does NOT mean must not. An assembled caveat can render empty
# under exactly the conditions that make it matter most, and a caveat that renders empty is worse
# than no caveat at all — it reads as a clean result.
_UP_MOVEMENT_CAVEAT = (
    "MOVEMENT IS NOT AN ANSWER. This compares counts and states; it has not read a word of any\n"
    "  of them. A label change, a drive-by '+1' and the reply you have been blocked on are the\n"
    "  same event here.")
_UP_QUIET_CAVEAT = (
    "A QUIET RUN IS WEAK EVIDENCE, not a clean bill. GitHub's search index lags publication:\n"
    "  two issues filed from one machine were observed absent from --involves results for over\n"
    "  an hour after they existed. So 'no movement' means the index showed none, which is a\n"
    "  fact about the index.")
_UP_PARTIAL_CAVEAT = (
    "A PARTIAL RESULT IS NOT A RESULT. What moved in the repo(s) that could not be checked is\n"
    "  UNKNOWN, not absent. Their stored baseline was deliberately NOT advanced, so the next\n"
    "  successful run reports what moved in the meantime instead of swallowing it.")
_UP_OUTAGE_CAVEAT = (
    "This is NOT 'no movement'. Nothing was compared, the stored baseline is UNCHANGED, and the\n"
    "  next run will report anything that moved in the meantime rather than skipping it.")

UPSTREAM_F = os.path.join(ROOT, "upstream.json")


def is_repo_slug(r):
    """`owner/name`, and nothing that is merely path-shaped (#129).

    The old filter was `"/" in r`, which EVERY absolute path satisfies — so a config holding
    `~/dev/game_loop` sailed through and reached `gh search --repo`, which answered with GitHub's
    generic "the listed users and repositories cannot be searched either because the resources do
    not exist or you do not have permission to view them". Four watched repos, every checkpoint,
    and that sentence sends a reader to `gh auth status`, token scopes, repo visibility and the
    search rate limit before it sends them to the value they typed.
    """
    if not isinstance(r, str):
        return False
    r = r.strip()
    return (r.count("/") == 1 and not r.startswith(("~", "/", "."))
            and " " not in r and all(part for part in r.split("/")))


def upstream_repos():
    """Repos to watch. EMPTY BY DEFAULT, so this is inert until somebody opts in.

    A value that is not a slug is DROPPED AND NAMED rather than silently passed to `gh` — see
    `upstream_config_warning`, which is what makes the drop visible at the top of `status`.
    """
    v = config().get("upstream_repos", [])
    return [r.strip() for r in v if is_repo_slug(r)] if isinstance(v, list) else []


def upstream_rejected_repos():
    """The entries `upstream_repos()` refused, so a caller can say WHICH value was wrong."""
    v = config().get("upstream_repos", [])
    if not isinstance(v, list):
        return []
    return [r for r in v if isinstance(r, str) and r.strip() and not is_repo_slug(r)]


def upstream_config_warning():
    """A loud, one-line complaint naming the offending value — or "" when the config is clean.

    LOUD AND AT THE TOP, because the failure it replaces was a recurring runtime mystery: the check
    reported four repos unreachable every checkpoint and the cause was one character class in a
    filter. Naming the value turns a session of auth debugging into one read.
    """
    bad = upstream_rejected_repos()
    if not bad:
        return ""
    return "\n".join(
        ["⚠ upstream_repos HAS %d ENTRY(IES) THAT ARE NOT `owner/name` AND ARE BEING IGNORED:" % len(bad)]
        + ["    %s" % b for b in bad]
        + ["  `gh search --repo` takes a SLUG, not a path. A filesystem path reaches GitHub and comes",
           "  back as \"the listed users and repositories cannot be searched ... or you do not have",
           "  permission\", which is about the value, not your token. Fix them in .game_loop/config.json."])


def _upstream_baseline():
    try:
        with open(UPSTREAM_F) as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def _upstream_fetch(repo, timeout=25):
    """({issue_no: updatedAt}, latest_release_tag, None) or (None, None, "why").

    A failure here must be DISTINGUISHABLE from an empty result all the way up. `{}` is "this repo
    has no open issues involving you", which is a fact; `None` is "nobody knows", which is not.
    """
    try:
        r = subprocess.run(
            ["gh", "search", "issues", "--involves", "@me", "--state", "open", "--repo", repo,
             "--json", "number,title,updatedAt", "--limit", "100"],
            capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return None, None, f"search did not return ({type(exc).__name__})"
    if r.returncode != 0:
        # NAME THE REPO BESIDE THE ERROR (#129). GitHub's message is generic and misdirects — "you
        # do not have permission" reads as an auth problem when the real fault is the value being
        # passed. The string is already in scope; not printing it cost a session of auth debugging.
        why = (r.stderr or "").strip().split("\n")[-1][:120] or "search failed"
        return None, None, "%s (asked for repo %r)" % (why, repo)
    try:
        items = json.loads(r.stdout or "[]")
    except ValueError:
        return None, None, "search returned output that is not JSON"
    issues = {str(i["number"]): {"updatedAt": i.get("updatedAt", ""), "title": i.get("title", "")}
              for i in items if isinstance(i, dict) and "number" in i}
    rel = ""
    try:                        # a missing release list is not a failed check: repos need no releases
        rr = subprocess.run(["gh", "release", "list", "--repo", repo, "--limit", "1",
                             "--json", "tagName"], capture_output=True, text=True, timeout=timeout)
        if rr.returncode == 0:
            tags = json.loads(rr.stdout or "[]")
            rel = tags[0].get("tagName", "") if tags else ""
    except (OSError, subprocess.TimeoutExpired, ValueError, IndexError, AttributeError):
        rel = None              # unknown, and unknown must not overwrite a known baseline
    return issues, rel, None


def upstream_check(write=True):
    """Compare watched repos against the stored baseline. Returns (lines, state).

    state: "off" | "first" | "movement" | "quiet" | "partial" | "outage".
    Never raises and never blocks — the whole value is in the report, and a watcher that can break
    a checkpoint is a watcher that gets removed before it ever reports anything.
    """
    repos = upstream_repos()
    # THE COMPLAINT COMES FIRST AND SURVIVES THE "off" PATH (#129). A config holding only paths
    # yields NO usable repos, so returning "off" here would report the watcher as switched off
    # when it is in fact misconfigured — the two look identical from outside and mean opposite
    # things. Naming the values is the whole fix: the old failure was four repos "unreachable"
    # every checkpoint with GitHub's permission error, which is about the value, not the token.
    warn = upstream_config_warning()
    pre = warn.split("\n") if warn else []
    if not repos:
        return (pre, "misconfigured") if pre else ([], "off")
    base = _upstream_baseline()
    first_run = not base.get("repos")
    stored = dict(base.get("repos") or {})
    moved, failed, checked = [], [], []
    for repo in repos:
        issues, rel, why = _upstream_fetch(repo)
        if issues is None:
            # THE BASELINE FOR AN UNCHECKED REPO MUST NOT ADVANCE. Advancing it here would make one
            # outage a permanent blind spot: everything that moved during it becomes part of the new
            # "before", and the next successful run reports calm.
            failed.append((repo, why))
            continue
        checked.append(repo)
        prev = stored.get(repo) or {}
        prev_issues = prev.get("issues") or {}
        if not first_run and prev:
            for num, cur in sorted(issues.items(), key=lambda kv: int(kv[0])):
                was = prev_issues.get(num)
                if was is None:
                    moved.append((repo, num, "NEW", cur.get("title", "")))
                elif was.get("updatedAt") != cur.get("updatedAt"):
                    moved.append((repo, num, "moved", cur.get("title", "")))
            for num, was in sorted(prev_issues.items(), key=lambda kv: int(kv[0])):
                if num not in issues:
                    # Gone from a state:open search. Closed is by far the likeliest reading and the
                    # one you most want — but it is an INFERENCE from an absence, so it is worded as
                    # one rather than asserted as a close.
                    moved.append((repo, num, "no longer open", was.get("title", "")))
            if rel is not None and prev.get("release") and rel and rel != prev["release"]:
                moved.append((repo, "", f"RELEASE {prev['release']} -> {rel}", ""))
        entry = {"issues": issues, "checked": now()}
        entry["release"] = prev.get("release", "") if rel is None else rel
        stored[repo] = entry
    if write and checked:
        try:
            with open(UPSTREAM_F, "w") as f:
                json.dump({"repos": stored}, f, indent=2)
        except OSError:
            pass
    n_iss = sum(len((stored.get(r) or {}).get("issues") or {}) for r in checked)
    if first_run and checked:
        return (pre + [f"upstream: baseline recorded — {n_iss} issue(s) involving you across "
                 f"{len(checked)} repo(s).",
                 "  Nothing is reported on a first run. Everything after this point is a CHANGE",
                 "  against this snapshot; if this gate had spoken now it would have handed you",
                 f"  {n_iss} historical item(s) at once, and a gate whose first act is a backlog is",
                 "  a gate somebody removes."]
                + ([f"  NOTE: {len(failed)} repo(s) could not be reached, so they are NOT in the "
                    "baseline", "  and will record theirs on a later run."] if failed else []),
                "first")
    if not checked:
        return (pre + [f"upstream: COULD NOT CHECK — {len(failed)} of {len(repos)} repo(s) failed.",
                 *[f"    {r}: {w}" for r, w in failed],
                 "  " + _UP_OUTAGE_CAVEAT], "outage")
    lines = []
    if moved:
        lines = pre + lines
        lines.append(f"upstream: {len(moved)} item(s) moved since the last check —")
        for repo, num, what, title in moved[:12]:
            where = f"{repo}#{num}" if num else repo
            lines.append(f"    {where}  {what}" + (f"  {title[:60]}" if title else ""))
        if len(moved) > 12:
            lines.append(f"    ... and {len(moved) - 12} more (all recorded; only 12 shown)")
    else:
        lines = pre + lines
        lines.append("upstream: no movement in the index across "
                     f"{len(checked)} repo(s), {n_iss} issue(s).")
    if failed:
        lines.append(f"  {len(failed)} of {len(repos)} repo(s) COULD NOT BE CHECKED:")
        lines += [f"    {r}: {w}" for r, w in failed]
        lines.append("  " + _UP_PARTIAL_CAVEAT)
    # ALWAYS, never only on the ambiguous runs. A caveat that appears only sometimes teaches that its
    # absence means certainty — which is the exact false green this repo exists to refuse.
    lines.append("  " + (_UP_MOVEMENT_CAVEAT if moved else _UP_QUIET_CAVEAT))
    return lines, ("partial" if failed else ("movement" if moved else "quiet"))


LEDGER_F = os.path.join(ROOT, "UPSTREAM_LEDGER.md")

_LEDGER_HEAD = """# Upstream review ledger

One line per review of hardened learnings, asking of each: does this name a TOOL's behaviour, or
this REPO's? The gate below reads the last timestamp here and counts `harden` entries after it.

"All of them were project-specific" is a COMPLETE answer — recording the review is what clears it.
A gate that only cleared on a filed issue would manufacture noise issues, which is worse than
silence.
"""


def _ledger_last():
    """(iso timestamp of the last review, or None). None means this project has never reviewed."""
    try:
        with open(LEDGER_F) as f:
            lines = [l for l in f if l.startswith("- ")]
    except OSError:
        return None
    for line in reversed(lines):
        m = re.match(r"- (\S+)", line)
        if m:
            return m.group(1)
    return None


def ledger_record(when, n, filed, note):
    """Append a review. Creates the ledger with its header if this is the first line."""
    fresh = not os.path.exists(LEDGER_F)
    with open(LEDGER_F, "a") as f:
        if fresh:
            f.write(_LEDGER_HEAD + "\n")
        f.write(f"- {when} — reviewed {n} learning(s); filed: {filed or 'none'}; "
                f"note: {note or '(none)'}\n")


def hardens_since_review():
    """Learnings hardened since the last ledger line. ([(t, learning)], baseline_just_written).

    THE FIRST ENCOUNTER RECORDS A BASELINE AND REPORTS NOTHING (#78). The reporter's version exits
    quiet with no ledger, to avoid a first appearance that is a 200-item wall of every harden ever
    recorded — right about the hazard, but it leaves the gate inert until a human bootstraps it,
    which is the manual-step-nobody-takes failure from #74. Recording the world instead gives the
    same protection and starts the gate on its own.
    """
    last = _ledger_last()
    if last is None:
        ledger_record(now(), 0, "none", "baseline — everything before this line is history, and "
                                        "reporting it would make this gate's first appearance a "
                                        "wall nobody reads")
        return [], True
    out = []
    try:
        with open(LOG_F) as f:
            for line in f:
                if '"harden"' not in line:
                    continue
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                if d.get("kind") == "harden" and (d.get("t") or "") > last:
                    out.append((d.get("t", ""), d.get("learning", "")))
    except OSError:
        return [], False
    return out, False


def upstream_review_nudge(s):
    """Are enough learnings unreviewed to be worth asking whose defect they were? (#78)

    Not a gate and not a block. The judgement — tool or repo — is unmakeable from a count, so this
    LISTS THE LEARNINGS and asks. That listing is the mechanism: the reporter said seeing four side
    by side is what made the pattern obvious, and that three of their four were phrased as facts
    about a TOOL, which is itself the tell.
    """
    every = config().get("upstream_review_every", 6)
    items, baseline = hardens_since_review()
    if baseline or len(items) < every:
        return None
    lines = [f"⚠ {len(items)} learning(s) hardened since your last upstream review.",
             "  For each: does it name a TOOL's behaviour, or THIS REPO's?", ""]
    for t, learning in items[-12:]:
        lines.append(f"    {t[:16]}  {learning[:96]}")
    if len(items) > 12:
        lines.append(f"    ... and {len(items) - 12} more")
    lines += [
        "",
        "  A learning phrased as a fact about a tool usually IS one. Encoded locally it is fixed",
        "  for one agent, in one repo, for as long as that harness copy survives — and everybody",
        "  else using that tool rediscovers it.",
        "",
        '  game_loop contribute --reviewed --filed "<urls, or none>" --note ".."',
        "",
        '  "All of them were project-specific" is a COMPLETE answer. Recording the review clears',
        "  this; a gate that only cleared on a filed issue would manufacture noise issues.",
        "  RAISING upstream_review_every is the cheapest way to silence this, and it is not the",
        "  finding. WHAT THIS CANNOT SEE: whether a learning generalises, whether an issue you",
        "  file is any good, or anything that never went through `harden` at all."]
    return "\n".join(lines)


def cmd_contribute(s, a):
    """Record an upstream review: N learnings looked at, what was filed, one line of judgement."""
    if not a.reviewed:
        die("contribute needs --reviewed (with --filed and --note).\n"
            "It records that you ASKED, of each learning hardened since your last review, whether "
            "it named a tool's behaviour or this repo's.")
    items, baseline = hardens_since_review()
    if baseline:
        out("✓ baseline recorded — nothing to review yet.",
            "  Everything hardened before now is history; the next review covers what follows.")
        return
    ledger_record(now(), len(items), a.filed, a.note)
    logline({"kind": "upstream_review", "n": len(items), "filed": a.filed, "note": a.note})
    out(f"✓ REVIEWED — {len(items)} learning(s), recorded in {os.path.basename(LEDGER_F)}.",
        f"  filed: {a.filed or 'none'}",
        f"  note : {a.note or '(none)'}",
        "",
        "WHAT THIS DOES NOT SAY: that the judgement was right, that a filed issue is any good, or",
        "that a learning which never went through `harden` was considered at all.")


def release_distance():
    """(commits ahead, newest marked sha, level) — or (0, None, None) when there is nothing to say.

    Nothing to say covers: no git, no marks at all (an unreleased project owes no distance), and
    HEAD already being the newest mark. Deliberately measured against the CONFIDENCE MARKS rather
    than against a branch: `stable`/`beta` are what this project tells consumers to install, and the
    gap that matters is between what exists and what they can get.
    """
    # TWO GIT PROCESSES PER TAG IS WHY A TURN-END TOOK SIXTEEN MINUTES. This loop ran
    # `rev-list -n 1 <tag>` and `rev-list --count sha..HEAD` for EVERY marked tag: at 254 tags that
    # is 508 subprocess spawns, measured at 263s inside one `checkpoint`, and a sample of the
    # running process was almost entirely Python import/exec — the cost of starting processes, not
    # of walking history.
    #
    # THE SHAPE WAS THE WORST AVAILABLE: the gate that guards RELEASING got slower every time you
    # released, so the project punished exactly the thing it was built to encourage. Ten tags
    # landed here in one day and each one made every future turn-end dearer.
    #
    # Three calls now, whatever the tag count. `for-each-ref` resolves every tag to its commit in
    # one pass; walking `rev-list HEAD` once finds the NEAREST marked ancestor, which is by
    # definition the smallest distance; and the exact count is then asked for that one tag only, so
    # the number this returns is the same number the loop returned.
    # `%(*objectname)` FIRST, AND THAT IS NOT A DETAIL. `confidence` writes ANNOTATED tags, so
    # `%(objectname)` is the sha of the TAG OBJECT, not of the commit — it never appears in
    # `rev-list HEAD`, so a lookup keyed on it matches nothing and this returns "nothing owed" for
    # every input. That is a gate which can never fire, and the first version of this fix had it.
    #
    # It survived the equivalence check because the old and new code agreed on six sampled heads —
    # both answering 0, for opposite reasons. Caught only by asking for a commit with no tag on it
    # and finding the list was wrong. The deref field is empty for a lightweight tag, so taking it
    # when present and falling back covers both kinds.
    want = {}
    for line in (_git("for-each-ref", "--format=%(*objectname) %(objectname) %(refname:short)",
                      "refs/tags/stable-*", "refs/tags/beta-*") or "").split("\n"):
        parts = line.split(None, 2)
        if len(parts) == 3:
            deref, direct, name = parts
            want.setdefault(deref or direct, name)
        elif len(parts) == 2:                       # lightweight: the deref field came back empty
            want.setdefault(parts[0], parts[1])
    if not want:
        return 0, None, None
    for sha in (_git("rev-list", "HEAD") or "").split("\n"):
        sha = sha.strip()
        if sha not in want:
            continue
        n = _git("rev-list", "--count", f"{sha}..HEAD")
        if n is None or not str(n).strip().isdigit():
            return 0, None, None
        n = int(n)
        if not n:
            return 0, None, None       # HEAD is itself marked: nothing owed
        return n, sha, want[sha].split("-")[0]
    # NO MARKED TAG IS AN ANCESTOR OF HEAD — a branch nobody has released from. The old loop would
    # have measured against a tag off to one side, which is a distance to a commit this history
    # does not contain. Saying nothing is owed is the honest answer and the safe direction: this
    # gate refuses handbacks, and refusing on an unanswerable question is how a gate gets removed.
    return 0, None, None


def newest_mark():
    """(tag, datetime) of the most recently created release mark, or (None, None).

    Read from the tag's own creation date rather than from anything this tool wrote down: the
    question below is whether an attachment ran AFTER the mark, and a remembered timestamp would
    make the tool the witness to its own release.
    """
    out = _git("for-each-ref", "--sort=-creatordate",
               "--format=%(refname:short)\t%(creatordate:iso-strict)",
               "refs/tags/stable-*", "refs/tags/beta-*")
    for line in (out or "").splitlines():
        if "\t" not in line:
            continue
        tag, iso = line.split("\t", 1)
        try:
            dt = datetime.datetime.fromisoformat(iso.strip())
        except ValueError:
            continue
        # Naive local, because that is what `now()` writes into the trigger records this is
        # compared against. Mixing an aware datetime with a naive one raises rather than lies,
        # which is the right failure — but it would raise inside a status line, so convert here.
        if dt.tzinfo is not None:
            dt = dt.astimezone().replace(tzinfo=None)
        return tag, dt
    return None, None


def publish_gap(s=None, mark=None, seen=None, attachments=None):
    """Marks made while a `confidence` attachment did NOT run — a release nobody can reach.

    A mark is a local tag. The attachment is what carries it outward, and nothing here ever
    compared the two: a mark whose publish was interrupted looked identical to one whose publish
    worked, and `release_distance` counted both as released. Observed on 2026-09-02 — a mark was
    made, the publish trigger was killed with the caller before it finished, the tags went to the
    remote, and a consumer reported hours later that the newest thing they could install was one
    commit short of the fix. `status` said "newest mark" and nothing else.

    WHAT IT CANNOT SEE (INV6): whether the attachment actually published anything. It compares
    two timestamps that already exist — when the mark was created, and when the attachment last
    recorded a run. An attachment that ran and silently did nothing reads here as fine.
    """
    if mark is None:
        mark = newest_mark()
    tag, when = mark
    if not tag or not when:
        return []
    if attachments is None:
        attachments = [str(t.get("name") or "(unnamed)") for t in triggers_for("confidence")]
    if not attachments:
        return []                    # nothing attached: a mark IS the whole of the release here
    if seen is None:
        seen = ((s if isinstance(s, dict) else load()).get("triggers") or {})
    behind = []
    for name in attachments:
        rec = seen.get(name) or {}
        at = rec.get("at")
        ran = None
        if at:
            try:
                ran = datetime.datetime.fromisoformat(str(at))
            except ValueError:
                ran = None
        if ran is None or ran < when:
            behind.append((name, at, bool(rec.get("ok"))))
    if not behind:
        return []
    L = [f"⚠ {tag} WAS MARKED WITHOUT {len(behind)} OF ITS ATTACHMENT(S) RUNNING:"]
    for name, at, ok in behind:
        if not at:
            L.append(f"    {name} — no run recorded at all")
        else:
            L.append(f"    {name} — last ran {at}" + ("" if ok else " (and FAILED)")
                     + ", BEFORE this mark")
    L += [
        "  The tag is local and pushable; the attachment is what carries the release OUTWARD.",
        "  A mark whose publish did not finish is indistinguishable from one whose publish worked,",
        "  and release_distance counts both as released — so `status` can say a fix is out while",
        "  every consumer following the channel still gets the commit before it. That happened",
        "  here: the trigger was killed along with the caller, three hours before a consumer said",
        "  the newest thing they could install did not carry the fix.",
        "",
        f"    game_loop confidence --mark <level> --notes \"..\"   # and let it FINISH",
        "",
        "  A publish attachment can be slow — this one has a 900s budget. A caller that kills it",
        "  early leaves the mark made and the release unmade, with nothing said either way.",
    ]
    return L


def deferral_standing(head=None, log_lines=None):
    """The reason a release was deferred FOR THIS HEAD, or None — read from the log, not remembered.

    THE DECISION WAS ALREADY MADE AND WRITTEN DOWN, AND NOTHING READ IT BACK. `checkpoint
    --release-deferred` logs the reason with the HEAD it was about, and then the very next
    checkpoint refused again unless the whole sentence was retyped. That converts a decision into a
    ritual, which is the failure the checkpoint's own ritual warning is about, three lines further
    down the same function.

    KEYED ON HEAD, deliberately. A deferral is a judgement about a specific set of finished
    commits: "these do not reach a consumer". Move HEAD and that judgement has not been made about
    the new work, so the gate fires again — which is the whole point of it firing at all.

    An unreadable log returns None, so the gate refuses as it always did. That is the safe
    direction here: the cost is retyping a sentence, and the cost of the other one is a release
    nobody gets.
    """
    if head is None:
        head = _git("rev-parse", "--short", "HEAD") or ""
    if not head:
        return None
    def _scan(lines):
        found = None
        for ln in lines:
            if '"release_deferred"' not in ln:
                continue
            try:
                r = json.loads(ln)
            except ValueError:
                continue
            if r.get("kind") == "release_deferred" and r.get("head") == head:
                found = r.get("reason") or ""     # the LAST one wins: a reason can be revised
        return found
    if log_lines is not None:
        return _scan(log_lines)
    try:
        with open(LOG_F) as f:
            return _scan(f)
    except (OSError, ValueError):
        return None


def current_pin_sha():
    """The sha this repo's own pinned checkout was cut from, or None — read, never remembered."""
    return _pin_marker_sha(os.path.join(REPO_ROOT, PINNED_DIRNAME, ".game_loop"))


def deferral_pin_note(head=None, log_lines=None, pin_now=None):
    """"...and the pin has MOVED since that decision", or "" — because the prose cannot know.

    A DEFERRAL'S REASON IS PROSE, AND PROSE GOES STALE WITHOUT ANYTHING TOUCHING IT. The reason is
    keyed on HEAD, so it lapses when the commits change; nothing lapsed it when the PIN changed, and
    the pin is what most of these reasons are actually about ("these commits are not dogfooded").

    Observed twice on 2026-09-03. First a reason claimed the pin was four commits behind when the
    stamp had matched HEAD for eight hours, and a release sat unmade. Then — after the verb that
    reports the pin was fixed to print it in both directions — a reason recorded a pin sha copied
    from the previous turn's message while the correct value sat in that same command's output. The
    second one matters more: the reader was corrected and the WRITER still had nothing checking it.

    AND THE PIN CAN MOVE WITH THIS SESSION DOING NOTHING. Session 2378d4b0 re-pinned this checkout
    at 13:48:20 while another session was mid-flight — one log record, no other activity. So a
    remembered pin value is not merely stale-able by its author; it is stale-able by somebody else.

    Silent when the record carries no pin (every deferral written before this existed), when there
    is no pin, and when they agree — this reports a CHANGE, and a note printed on every checkpoint
    is a note nobody reads by the third one.
    """
    if head is None:
        head = _git("rev-parse", "--short", "HEAD") or ""
    if not head:
        return ""
    if pin_now is None:
        pin_now = current_pin_sha()

    def _scan(lines):
        found = None
        for ln in lines:
            if '"release_deferred"' not in ln:
                continue
            try:
                r = json.loads(ln)
            except ValueError:
                continue
            if r.get("kind") == "release_deferred" and r.get("head") == head:
                found = r.get("pin")               # the LAST one wins, as with the reason
        return found

    if log_lines is not None:
        was = _scan(log_lines)
    else:
        try:
            with open(LOG_F) as f:
                was = _scan(f)
        except (OSError, ValueError):
            return ""
    if not was or not pin_now or was == pin_now:
        return ""
    return (f"the PIN has moved since that reason was written: {was[:8]} → {pin_now[:8]}. "
            "If the reason is about dogfooding, re-read it before trusting it.")


def release_owed():
    """(n, sha, level) when finished work is unreleased and the handback must not pass — else None.

    NARROW ON PURPOSE. A gate that fires while you are still working is one that gets routed around,
    and then it is gone for the cases it was built for. Three conditions, all required: something is
    past the newest mark, the tree is CLEAN (so this is a finished state), and HEAD is on the remote
    (so this is not the unpushed case, which already has its own gate).
    """
    n, sha, lvl = release_distance()
    if not n or not sha:
        return None
    if (_git("status", "--porcelain") or "").strip():
        return None                      # mid-work: edits in the tree, nothing to release yet
    head = _git("rev-parse", "HEAD") or ""
    if not head:
        return None
    # NOT remote_has_ref() — that asks `ls-remote --tags`, so it answers "is this TAG on the
    # remote", and a pushed COMMIT is not a tag. Using it here reported every pushed commit as
    # unpushed and the gate never fired: a function answering the neighbouring question, which is
    # the single most common way a check here goes quiet.
    try:
        r = subprocess.run(["git", "branch", "-r", "--contains", head],
                           cwd=REPO_ROOT, capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.TimeoutExpired):
        return None                      # could not ask: never refuse on an unanswerable question
    if r.returncode != 0:
        return None
    on_remote = bool((r.stdout or "").strip())
    if not on_remote:
        return None                      # unpushed — a different gate, with a different remedy
    return n, sha, lvl


def release_distance_warning():
    """Say it at the handback, where the human forms their picture of what exists (#: showrunner)."""
    n, sha, lvl = release_distance()
    if not n or n < 2:
        return None
    return "\n".join([
        f"⚠ THE NEWEST RELEASE IS {n} COMMIT(S) BEHIND THIS TREE.",
        f"    newest mark : {lvl} {sha[:8]}",
        f"    HEAD        : {(_git('rev-parse', '--short', 'HEAD') or '?')}",
        "  Committed and pushed is NOT released. A consumer who upgrades right now gets the mark,",
        "  not this tree — which is how a fix can be finished, verified, on the remote, and still",
        "  absent for everyone who installs it. That happened here: a consumer upgraded, did not",
        "  get the fix, and diagnosed it themselves.",
        "",
        "    game_loop confidence --mark beta|stable --notes \"..\"",
        "",
        "  WHAT THIS DOES NOT KNOW (INV6): whether anyone consumes this repo at all, or how many.",
        "  The number that would actually move you is 'N consumers are bound to the older one', and",
        "  that lives in a package manager's registry rather than in git — so this reports the",
        "  distance and declines to guess at the audience."])


# `_gl_impl.py`, NOT `game_loop`: the entry point is a ~30-line door that imports this file, so the
# code whose log records are being extracted lives HERE. Scanning the door finds no records and the
# schema comes back nearly empty — which reads as "this program writes almost nothing" rather than
# as a broken scan, since an extractor that finds nothing does not raise.
# THE GUARDS WRITE RECORDS TOO, and they were missing for a reason nobody decided: they are shell
# scripts, `ast.parse` raises SyntaxError on them, and the loop below CONTINUES on that — so they
# fell out silently rather than being excluded. Measured: 8 kinds the guards emit were absent from
# the extracted schema, including `commit_unedited`, which this repo's own log carries 11 times.
#
# That is not merely an incomplete reference. `trigger_dead_kinds()` treats this schema as the set
# of kinds that EXIST, so a trigger matching a real guard kind was REPORTED DEAD — driven and
# reproduced, not reasoned about. A false "your trigger cannot fire" is worse than no check.
_SHIPPED_SCRIPTS = ("_gl_impl.py", "watchdog", "notify.py", "verify", "flair.py",
                    "guard-writes-impl.sh", "guard-mcp-impl.sh")


def _python_trees(text):
    """Parsed ASTs for `text` — itself if it is Python, else each program embedded in it.

    The guards are shell wrappers around here-doc'd Python, so their record-writing code is real
    Python that simply is not at the top of the file. Parsing the wrapper fails; parsing what it
    runs does not. Returns [] rather than raising: a file that yields nothing must fall out of the
    scan the same way it always did, not take the scan down with it.
    """
    try:
        return [ast.parse(text)]
    except (SyntaxError, ValueError):
        pass
    trees, lines, i = [], text.split("\n"), 0
    op = chr(60) + chr(60)
    while i < len(lines):
        m = re.search(re.escape(op) + r"-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1", lines[i])
        if m:
            delim, body, i = m.group(2), [], i + 1
            while i < len(lines) and lines[i].strip() != delim:
                body.append(lines[i])
                i += 1
            try:
                trees.append(ast.parse("\n".join(body)))
            except (SyntaxError, ValueError):
                pass                      # not every here-doc is Python; prose and SQL live in them
        i += 1
    return trees


def log_kinds(code_dir=None):
    """{kind: sorted[field]} for every record this code can WRITE, read out of the source.

    EXTRACTED, NEVER TRANSCRIBED (#87). A hand-written schema table is a document describing code,
    which drifts from it — and a stale schema reference is worse than none, because it looks
    authoritative while being wrong. This walks the AST for dict literals carrying a constant
    "kind" and reports the sibling keys, so it is a view of the code rather than a copy of it.

    A trigger author was guessing at this and had nothing to check the guess against: they matched
    on `kind == "mandate"`, which this project has never emitted, and the guard exited 0 forever.
    """
    out = {}
    base = code_dir or os.path.join(CODE_ROOT, "bin")
    for name in _SHIPPED_SCRIPTS:
        try:
            with open(os.path.join(base, name)) as f:
                _text = f.read()
        except OSError:
            continue
        for n in [_n for _t in _python_trees(_text) for _n in ast.walk(_t)]:
            if not isinstance(n, ast.Dict):
                continue
            kind = None
            for k, v in zip(n.keys, n.values):
                if isinstance(k, ast.Constant) and k.value == "kind" and isinstance(v, ast.Constant):
                    kind = v.value
            if not isinstance(kind, str):
                continue
            fields = out.setdefault(kind, set())
            for k in n.keys:
                if isinstance(k, ast.Constant) and isinstance(k.value, str) and k.value != "kind":
                    fields.add(k.value)
    return {k: sorted(v) for k, v in sorted(out.items())}


def trigger_dead_kinds():
    """[(trigger file, kind it matches that NOTHING emits)] — their suggestion 3, and the gate.

    A reference nobody thinks to consult is rung 6. This is the rung above: a trigger whose source
    names a kind string this code never writes CANNOT FIRE, and that is decidable without running
    it. Checked against the extracted schema, so it cannot go stale either.
    """
    known = set(log_kinds())
    if not known:
        return []
    hits, d = [], os.path.join(ROOT, "triggers.d")
    try:
        names = sorted(os.listdir(d))
    except OSError:
        return []
    for name in names:
        p = os.path.join(d, name)
        try:
            with open(p) as f:
                src = f.read()
        except OSError:
            continue
        # Only strings compared against a `kind` field — not every quoted word in the file.
        for m in re.finditer(r"""kind["']?\s*(?:\)|\])?\s*==\s*["']([a-z_]+)["']""", src):
            k = m.group(1)
            if k not in known:
                hits.append((name, k))
        for m in re.finditer(r"""["']kind["']\s*:\s*["']([a-z_]+)["']""", src):
            k = m.group(1)
            if k not in known:
                hits.append((name, k))
    return sorted(set(hits))


def cmd_kinds(s, a):
    """Print the log schema this code writes, so a trigger author is not guessing (#87)."""
    ks = log_kinds()
    if not ks:
        die("could not read the shipped scripts to extract a schema — this is a COULD NOT ANSWER, "
            "not an empty schema.")
    out(f"{len(ks)} record kind(s) this code can write, extracted from the source:", "")
    for k, fields in ks.items():
        out(f"  {k}", *([f"      {' '.join(fields)}"] if fields else ["      (no other fields)"]))
    out("",
        "Read this rather than guessing: a trigger matching a kind that is never written exits 0",
        "forever, and exit 0 is also what a SATISFIED guard does — broken and quiet look identical",
        "from outside. `status` names a trigger that matches a kind nothing here emits.",
        "",
        "WHAT THIS DOES NOT COVER (INV6): a kind built by concatenation rather than written as a",
        "literal, records written by YOUR triggers, and every other way a trigger can be dead —",
        "a heredoc that eats its own stdin looks exactly like this one does.")


def cmd_checkpoint(s, a):
    """Declare that this turn-end REPORTS rather than ASKS. Buys exactly one turn-end.

    Cheap on purpose — no evidence required. Reporting progress is legitimate under a mandate; the
    thing being priced is the INTERRUPTION, not the update. But it is an explicit act, so a stop is
    always deliberate, and it is consumed, so it cannot silently cover a second one. It does NOT
    launder a question: the gate checks the closing message first and blocks a question-shaped ending
    even when checkpointed.
    """
    if not a.notes:
        die("checkpoint needs --notes: one line on what you did and what happens next.")
    # FINISHED WORK THAT NOBODY CAN INSTALL DOES NOT PASS THE HANDBACK (rung 3, replacing a rung-5
    # warning that failed twice in one day). That warning printed correctly at this exact moment,
    # both times, and was read past; the human then had to ASK, twice, whether the work was marked
    # and published. It was not. Informing is a thing a reader can decline, which is what rung 5
    # means — so the mechanism moves up rather than the wording getting louder.
    _standing = None if getattr(a, "release_deferred", None) else deferral_standing()
    # Error-swallowed: a note about a pin must never be the thing that stops a checkpoint.
    try:
        _pinmoved = deferral_pin_note() if _standing else ""
    except Exception:  # noqa: BLE001
        _pinmoved = ""
    if not getattr(a, "release_deferred", None) and not _standing:
        _owed = release_owed()
        if _owed:
            _n, _sha, _lvl = _owed
            die(f"REFUSED — {_n} commit(s) are finished, pushed, and RELEASED TO NOBODY.\n\n"
                f"  newest mark : {_lvl} {_sha[:8]}\n"
                f"  HEAD        : {(_git('rev-parse', '--short', 'HEAD') or '?')}\n\n"
                "The tree is clean and HEAD is on the remote, so this is FINISHED work, not work in\n"
                "progress. Committed and pushed is NOT released: a consumer who upgrades right now\n"
                "gets the mark, not this tree. That has already stranded one, who diagnosed it\n"
                "themselves after upgrading and not finding the fix.\n\n"
                "  game_loop confidence --mark stable --notes \"..\"   then push the two refs it prints\n\n"
                "OR SAY WHY NOT, and it goes on the record instead of being forgotten:\n"
                "  game_loop checkpoint --notes \"..\" --release-deferred \"<why this waits>\"\n\n"
                "Deferring is a decision. Not noticing is not.")
    s["stop_ok"] = True
    s["stop_ok_notes"] = a.notes
    s["stop_ok_setter"] = _writer_mark()
    save(s)
    if notify:
        notify.send("checkpoint", f"📍 checkpoint — {a.notes}")  # default-off event; opt in to page
    if getattr(a, "release_deferred", None):
        # THE PIN GOES IN THE RECORD, not only in the prose. A reason that talks about the pin
        # is the common case, and prose is exactly what stops being true without anyone editing it.
        logline({"kind": "release_deferred", "reason": a.release_deferred,
                 "head": _git("rev-parse", "--short", "HEAD"), "pin": current_pin_sha()})
    _rit = ritual_checkpoints()
    out("✓ CHECKPOINT — one turn-end allowed (reporting, not asking).",
        f"  {a.notes}",
        *([f"  release deferred for this HEAD, standing from an earlier checkpoint: {_standing}",
           "  It lapses the moment HEAD moves — a deferral is a judgement about THESE commits."]
          if _standing else []),
        *([f"  ⚠ {_pinmoved}"] if _standing and _pinmoved else []),
        *([f"⚠ {_rit + 1} CHECKPOINTS SINCE ANY EVIDENCE WORK — no commit anywhere in this repo,",
           "  and no claim, harden, proof, phase or retro logged in between. That is not progress",
           "  reported N times; it is the",
           "  same turn-end bought N times, and it is the shape a mandate gets ritualised into.",
           "  Nothing is blocked: this is cheap so a stop stays deliberate, and pricing it would",
           "  push the next agent toward `--park`, which lies about a human calling a break."]
          if _rit >= 2 else []),
        "→ if your closing message asks the human anything, the gate still blocks it. Report, don't ask.")
    # The handback is where the human forms their picture of what exists; "14 commits that only exist
    # here" belongs in that picture — and so does "the fix in those commits was never exercised".
    if (w := unpushed_warning(a.notes)):
        out(w)
    if (w := release_distance_warning()):
        out("", w)
    if (w := fix_warning(s, a.notes)):
        out(w)
    try:
        _up_lines, _up_state = upstream_check()
    except Exception:           # never let the watcher break the verb it reports inside of
        _up_lines, _up_state = [], "off"
    if _up_lines:
        out("", *_up_lines)
        logline({"kind": "upstream_check", "state": _up_state})
    flair_out(s, "checkpoint")


def cmd_arm(s, a):
    """Arm ONE T3 spend: one interruption of the human, backed by evidence.

    The keystone is identical to `claim --read`: naming a file that exists is the one check prose
    cannot satisfy. Here the paths mean the cheap rungs you ALREADY spent that failed to answer the
    question. If T0 answered it, you don't need T3 — the failure this gate stops is asking a question
    whose answer was already on disk.
    """
    if not a.question or not a.read or not a.predict:
        die("arm needs --question, --read <path[,path]>, and --predict.\n"
            "  --question : what you need from the human that you cannot get yourself\n"
            "  --read     : the source you ALREADY read that failed to answer it (this is the gate)\n"
            "  --predict  : what you expect them to say — if you can predict it, don't ask\n"
            "T3 is the most expensive rung on the ladder. Exhaust T0/T1/T2 first.")
    paths = [p.strip() for p in a.read.split(",") if p.strip()]
    resolved = {p: resolve_read(p) for p in paths}
    bad = [p for p, r in resolved.items() if r is None]
    if bad:
        die("these --read paths don't resolve to a real, non-empty file: " + ", ".join(bad) +
            "\nName the source you consulted before deciding to spend the human's attention. "
            "A question you cannot source is a question you haven't tried to answer.")
    s["t3_armed"] = {"question": a.question, "read": list(resolved.values()),
                     "predict": a.predict, "at": now(), "setter": _writer_mark()}
    s["stop_blocks"] = 0
    save(s)
    logline({"kind": "arm", "tier": "T3", "question": a.question,
             "read": list(resolved.values()), "predict": a.predict})
    if notify:
        # Page the human where they actually are (their phone), not just the terminal. On the
        # bot-token path the thread ts is kept so the watchdog can read their reply back into the
        # run; on the webhook path the page is one-way and the arm waits at the desk as before.
        tail = ("\nReply here — in the channel or in this thread — and the watchdog will carry your "
                "answer back into the run." if notify.can_read_replies() else "")
        ts = notify.send("arm", f"🙋 T3 — the Crawler needs you.\nQ: {a.question}\n"
                                f"predicts: {a.predict}{tail}")
        if isinstance(ts, str):
            s["t3_armed"]["slack_ts"] = ts
            save(s)
    out("✓ ARMED for ONE T3 spend (one interruption).",
        f"  Q: {a.question}",
        f"  already read (didn't answer it): {', '.join(paths)}",
        f"  predict: {a.predict}",
        "→ the next turn-end passes the gate exactly once, then consumes the arm.",
        "  If your prediction is confident, reconsider: a predicted answer is not worth a T3.")
    flair_out(s, "arm")


_MUTATE_MARKER = "GL_MUTATE_LIVENESS_PROBE"


def _py_parses(src):
    """Does this source still compile? None when the question does not apply."""
    try:
        ast.parse(src)
        return True
    except SyntaxError:
        return False


def mutation_liveness(orig, replace, path, run, fault=None):
    """Is the anchor ON the test's execution path? ("live"|"inert"|"unknown", why).

    THE POSITIVE CONTROL THIS VERB SHIPPED WITHOUT (#80). A green run under mutation has two very
    different causes — the test does not cover this line, or the mutation never executed — and they
    are indistinguishable from the outside. Reported as the first, the verb sends an agent to rewrite
    a test that was fine, and it is the answer that ENDS the investigation, so it is the one least
    likely to be questioned.

    The probe replaces the anchor with a bare `raise` and demands the test fail CARRYING THE MARKER.
    Failing for any other reason is not evidence: the reporter's own first cut matched the marker
    inside a PARSE ERROR and called a dead anchor live, which is why the compile check comes first
    and why the marker must appear in the output rather than merely somewhere in a red run.
    """
    # WHAT THE FILE IS, NOT WHAT IT IS CALLED. This gate read `path.endswith(".py")`, and every
    # program this project ships is extensionless Python — so the strongest control this verb has
    # was unavailable on its own binary, and it said "this file is not Python" about a file that is.
    # A label standing in for the fact it labels, in the verb whose job is refusing exactly that.
    # Nothing downstream needed the extension: the poisoned tree must PARSE before the probe runs,
    # so a JSON file that happens to read as a Python literal is still declined a line below.
    # A CALLER-SUPPLIED FAULT IS WHAT MAKES THIS WORK OFF PYTHON (#91). The CONTRACT here is
    # stack-agnostic — splice something unmistakably fatal at the anchor, demand the test fail
    # CARRYING THE MARKER — and only the fatal text is per-stack. So the tool keeps the contract and
    # the caller supplies the one string, exactly as it already supplies --replace and --with.
    # Without this, every non-Python consumer got "unknown" and the verb's strongest control was
    # unavailable to them with no way to opt in.
    if fault:
        marked = fault.replace("{marker}", _MUTATE_MARKER)
    elif not _py_parses(orig):
        return "unknown", ("this file does not parse as Python, and the built-in fault is the "
                           "only one this knows how to write. Supply --fault \"<text that aborts "
                           "here, containing {marker}>\" for your stack and the probe runs")
    else:
        marked = None
    at = orig.index(replace)
    line_start = orig.rfind("\n", 0, at) + 1
    prefix = orig[line_start:at]
    # THE ANCHOR OFTEN CARRIES ITS OWN INDENTATION ("    x = 1"), in which case the prefix is empty
    # and the raise would land at column 0 inside a function — an IndentationError that reads as
    # "not a whole statement" and hides a perfectly probeable anchor behind the unknown outcome.
    first = replace.split("\n", 1)[0]
    indent = prefix + first[:len(first) - len(first.lstrip())]
    if prefix.strip():
        return "unknown", ("the anchor starts mid-line, so a `raise` cannot be substituted for it "
                           "without changing the surrounding expression")
    # SPLICE FROM THE START OF THE LINE, never `orig.replace(anchor, indent + raise)`. The prefix is
    # still in the file, so re-adding it doubled the indentation and the poisoned tree failed to
    # compile — reported as "the anchor is not a whole statement", blaming an anchor that was fine.
    # An anchor written WITHOUT its own leading whitespace is the natural form and the one
    # `--replace-file` produces, so the tool's strongest control was quietly unavailable for it.
    # Found by taking a consumer's refutation seriously enough to run it here (lamp-owner, #91).
    body = marked if marked is not None else f'raise SystemExit("{_MUTATE_MARKER}")'
    poisoned = orig[:line_start] + indent + body + orig[at + len(replace):]
    # ONLY THE BUILT-IN FAULT IS CHECKED FOR COMPILATION, because only for that one does this know
    # what a program looks like. A supplied fault that does not compile is not silently excused: it
    # makes the test fail WITHOUT the marker, which is already the "something else broke it" branch
    # below — unestablished, never "live". The honest outcome arrives by the same road.
    if marked is None and not _py_parses(poisoned):
        return "unknown", ("the anchor is not a whole statement — replacing it with a `raise` does "
                           "not compile, so the probe cannot be run here")
    rc, out = run(poisoned)
    if rc is None:
        return "unknown", "the probe run timed out, so nothing was established either way"
    if rc != 0 and _MUTATE_MARKER in out:
        return "live", ("the supplied fault ran at that anchor and the test carried the "
                        "marker" if marked is not None else
                        "the probe raised and the test carried the marker")
    if rc != 0:
        return "unknown", ("the test failed under the probe but WITHOUT the marker, so something "
                           "other than the probe broke it and liveness is unestablished")
    return "inert", ("the test passed with the fault spliced at that anchor — it never "
                         "runs that line" if marked is not None else
                         "the test passed with a `raise` at that anchor — it never runs "
                         "that line")


# One line per runner, and the shapes are stable across their whole lifetimes. A parse that
# recognises NOTHING is not a zero — it is an unreadable count, which is a different outcome.
_TEST_COUNT_PATS = (
    re.compile(r"^\s*(\d+) passing\b", re.M),                      # mocha
    re.compile(r"\b(\d+) passed\b"),                               # pytest, vitest, jest, this repo
    re.compile(r"^Ran (\d+) tests?\b", re.M),                       # python unittest
    re.compile(r"^ok\s+(\d+)\b", re.M),                            # go test / TAP
    re.compile(r"^\+(\d+)\s*[-~]", re.M),                          # flutter test
    re.compile(r"\b(\d+) tests? ran\b", re.I),
)


def selected_tests(out):
    """(count, why) from a runner's output. (None, why) when no shape is recognised.

    ZERO IS THE FINDING (#85). A command that selects no tests exits 0, which is byte-identical to
    a suite that ran and passed — so a mutation "surviving" it means nothing, and neither does a
    mutation killing it. The reporter hit this from a linked worktree, where --file resolved against
    one root and the test ran in another.
    """
    if not out:
        return None, "the test produced no output to read a count from"
    for pat in _TEST_COUNT_PATS:
        m = pat.search(out)
        if m:
            n = int(m.group(1))
            fails = re.search(r"\b(\d+) (?:failing|failed)\b", out)
            return n + (int(fails.group(1)) if fails and n == 0 else 0), ""
    return None, "no recognised test-count line (mocha, pytest, unittest, go, flutter, TAP)"


def cmd_mutate(s, a):
    """Prove a test PINS something, by breaking the code and watching it go red (#71).

    The tool runs both halves. A self-report cannot satisfy it, which is the whole point: a reviewer
    mutation-tested eight leaves that had each reported a revert-proof in prose, and three stayed
    green with the bug reintroduced. The sentence reads identically either way.
    """
    if not (a.prove and a.test and a.file and a.replace is not None and a.with_ is not None):
        die("mutate needs --prove \"<what the test pins>\" --test \"<command>\" --file <path> "
            "--replace \"<text>\" --with \"<text>\".\n"
            "The tool runs the test twice and compares. You supply the mutation; it supplies the "
            "verdict — a revert-proof you report yourself reads the same whether or not it happened.")
    path = os.path.realpath(os.path.expanduser(a.file))
    if not os.path.isfile(path):
        die(f"--file is not a real file: {path}")
    orig = open(path).read()
    n = orig.count(a.replace)
    if n != 1:
        die(f"--replace must appear EXACTLY once in {a.file}; it appears {n} times.\n"
            "Ambiguity here would mutate a line you did not mean and prove something about it.")

    def run_test():
        r = subprocess.run(["bash", "-c", a.test], cwd=REPO_ROOT, capture_output=True, text=True,
                           timeout=int(a.timeout or 900))
        return r.returncode, (r.stdout or "") + (r.stderr or "")

    def run_source(src):
        """Run the test against `src` written to the file, restoring it afterwards. (rc, output)."""
        try:
            with open(path, "w") as f:
                f.write(src)
            r = subprocess.run(["bash", "-c", a.test], cwd=REPO_ROOT, capture_output=True,
                               text=True, timeout=int(a.timeout or 900))
            return r.returncode, (r.stdout or "") + (r.stderr or "")
        except subprocess.TimeoutExpired:
            return None, ""
        finally:
            with open(path, "w") as f:
                f.write(orig)

    try:
        before, before_out = run_test()
    except subprocess.TimeoutExpired:
        die("the test timed out on the UNMUTATED tree — nothing can be concluded. --timeout to raise.")
    n_sel, sel_why = selected_tests(before_out)
    if n_sel == 0:
        die(f"COULD NOT PROVE — the test command selected NO TESTS.\n\n"
            f"  {a.test}\n"
            f"  ran in : {REPO_ROOT}\n"
            f"  mutating: {path}\n\n"
            "A command that selects nothing exits 0, which is byte-identical to a suite that ran "
            "and passed. So a mutation 'surviving' it means nothing, and a mutation killing it "
            "would mean nothing either — this is refused in BOTH directions, because a "
            "zero-selection run is not a result.\n\n"
            "THE COMMON CAUSE IS TWO ROOTS. `--file` resolves against your cwd and the test runs in "
            "the tree above; from a linked git worktree those are different places, and a filter "
            "that matches nothing there fails silently. Compare the two paths printed above.")
    if before != 0:
        # THREE OUTCOMES, NOT TWO (#91). "Your test ran and failed" and "your test never started"
        # are opposite conclusions with the same observable — a non-zero exit. The reporter hit the
        # second and was told the first: `--test` runs in the repo root, their relative path did not
        # resolve there, and "get it green first" is impossible advice about a test that was green.
        if n_sel is not None:
            die(f"the test RAN and FAILED on the unmutated tree (exit {before}).\n\n"
                f"  {a.test}\n"
                f"  ran in : {REPO_ROOT}\n"
                f"  counted: {n_sel} test(s) selected, so the runner did start\n\n"
                "A red test proves nothing about what it pins: it is red either way. Get it green "
                "first.")
        tail = "\n".join("    " + ln for ln in
                         (before_out or "").strip().splitlines()[-8:]) or "    (no output at all)"
        die(f"COULD NOT TELL whether the test RAN — it exited {before} and printed no test count.\n\n"
            f"  {a.test}\n"
            f"  ran in : {REPO_ROOT}\n"
            f"  count  : {sel_why}\n\n"
            f"  its last lines:\n{tail}\n\n"
            "A test that ran and failed and a test that never started share this observable, and "
            "they take opposite remedies — so this refuses to pick one for you rather than telling "
            "you to fix a test that may already be green.\n\n"
            "THE COMMON CAUSE IS TWO ROOTS: `--test` runs in the repo root printed above, NOT your "
            "cwd, so a relative path in the command resolves somewhere else and the runner exits "
            "before selecting anything. Try `--test \"cd <your dir> && ...\"`.")
    # THE POSITIVE CONTROL, BEFORE THE RESULT IT QUALIFIES (#80). Run first so a green mutated run
    # can be attributed: without it, "the test does not cover this" and "the mutation never ran"
    # are the same observation, and the verb was reporting the first for both.
    # AN EMPTY --fault WAS SILENTLY DISCARDED. It is falsy, so it skipped the marker check below
    # AND the fault path in mutation_liveness, and the run fell back to the built-in Python probe
    # without a word — on a shell file, that means "unknown" and a COULD NOT PROVE the caller reads
    # as a fact about their test. They asked for a control and were given none, silently, which is
    # the substitution this verb exists to refuse. Passing the flag is a request; an empty one is a
    # mistake, and the two must not look the same.
    if getattr(a, "fault", None) == "":
        die("--fault was given but is EMPTY.\n\n"
            "An empty fault cannot abort anything, so the liveness probe would fall back to the\n"
            "built-in Python one — silently, and on a non-Python file that means it does not run\n"
            "at all. You would get COULD NOT PROVE and read it as a fact about your test.\n\n"
            "    --fault 'throw new Error(\"{marker}\")'\n\n"
            "Or drop the flag entirely, which asks for the built-in probe on purpose.")
    if getattr(a, "fault", None) and "{marker}" not in a.fault:
        die("--fault must contain {marker} — the tool substitutes its own token there.\n\n"
            f"  got: {a.fault!r}\n\n"
            "The marker is the ONLY thing separating 'the probe stopped this test' from 'something "
            "else did'. A fault that aborts without it produces a red run this cannot attribute, "
            "which is reported as liveness UNESTABLISHED — so an unmarked fault buys a probe that "
            "can never return `live`.\n\n"
            "    --fault 'throw new Error(\"{marker}\")'")
    live, live_why = mutation_liveness(orig, a.replace, path, run_source,
                                       fault=getattr(a, "fault", None))
    if live == "inert":
        die(f"YOUR MUTATION WOULD HAVE BEEN INERT — the anchor is not on this test's path.\n\n"
            f"  {a.file}: {a.replace!r}\n"
            f"  {a.test}\n"
            f"  probe: {live_why}\n"
            + (f"  fault  : {a.fault!r}\n\n" if getattr(a, "fault", None) else "\n")
            + "That fault at that exact anchor did NOT make the test fail, so nothing you "
            "put there can. This is NOT 'the test is vacuous' — that is the answer this "
            "verb used to give "
            "here, and it sends you to rewrite a test that may be fine. A docstring, a comment, a "
            "type annotation, an unreachable branch, or a line this test simply never reaches all "
            "look like this. Move the anchor to code the test executes.")
    mutated_src = orig.replace(a.replace, a.with_, 1)
    # SAME LABEL-FOR-FACT (see mutation_liveness): gated on the NAME, so a mutation that broke this
    # project's own extensionless Python went unchecked and its red run read as ✓ PROVED. Asking
    # whether the ORIGINAL parses is what makes this a Python question at all — a mutated JSON file
    # is not "no longer a program", it never was one, and must not be refused on those grounds.
    if _py_parses(orig) and not _py_parses(mutated_src):
        die(f"COULD NOT PROVE — the mutated file does not COMPILE.\n\n"
            f"  {a.file}: {a.replace!r} -> {a.with_!r}\n\n"
            "A test cannot fail 'because of your mutation' when the file has stopped being a "
            "program: it fails on import, for every test, whatever they cover. This verb used to "
            "report that red run as ✓ PROVED — the strongest thing it can say, about nothing at "
            "all. Write a mutation that compiles.")
    restored, after = False, None
    try:
        with open(path, "w") as f:
            f.write(mutated_src)
        # BUMP THE MTIME, or a same-size mutation is invisible to every cache keyed on (mtime, size).
        # Found by this verb returning NOT PROVED for a test that demonstrably DOES go red: `a + b`
        # -> `a - b` is byte-for-byte the same length, both writes landed inside one filesystem mtime
        # tick, and Python reused its .pyc. The verb built to catch a test that cannot fail was
        # itself reporting a confident wrong verdict for the same reason.
        _future = time.time() + 5
        try:
            os.utime(path, (_future, _future))
        except OSError:
            pass                    # best effort: a filesystem that refuses this is not a reason to
                                    # abandon the proof, but the caller may see a stale-cache pass
        try:
            after, _after_out = run_test()
        except subprocess.TimeoutExpired:
            after = None
    finally:
        try:
            with open(path, "w") as f:
                f.write(orig)
            restored = True
        except OSError as exc:
            print(f"\n!! COULD NOT RESTORE {path}: {exc}\n"
                  f"!! The file is MUTATED on disk. Restore it before anything else.",
                  file=sys.stderr)
    if not restored:
        die("refusing to record a proof while the tree is left mutated.")
    if after is None:
        die("the test timed out on the MUTATED tree. That is not a failure — it is a run that could "
            "not answer, and treating it as red would be the exact substitution this verb exists to "
            "stop.")
    # ONLY ON THE GREEN BRANCH, and the asymmetry is the whole point. A mutated run that goes RED
    # is self-evidencing: a command that selected nothing cannot fail, so the redness IS the proof
    # that tests ran and reacted. It is the GREEN result — "the test survived" — that a
    # zero-selection run impersonates, which is exactly the false NOT PROVED that was reported.
    #
    # My first cut refused on both branches and the suite caught it immediately: a bare assert
    # script prints no count, and a mid-line anchor cannot be probed, so both instruments are silent
    # for a perfectly good proof. Refusing there would have priced the honest case to buy nothing.
    if after == 0 and n_sel is None and live != "live":
        die(f"COULD NOT PROVE — the test PASSED under mutation, and nothing establishes it RAN.\n\n"
            f"  {a.test}\n"
            f"  ran in : {REPO_ROOT}\n"
            f"  mutating: {path}\n"
            f"  count  : {sel_why}\n"
            f"  probe  : {live_why}\n\n"
            "Two instruments, and neither answered: no recognised test-count line, and the liveness "
            "probe could not run here. Either one alone would have been enough — a count proves "
            "tests were selected, a probe proves the anchor is on their path. With both silent, a "
            "verdict in either direction would rest on nothing.")
    if after == 0:
        die(f"NOT PROVED — the test still PASSED with the mutation applied (exit 0).\n\n"
            f"  {a.file}: {a.replace!r} -> {a.with_!r}\n"
            f"  {a.test}\n\n"
            + ("The anchor IS on the test's path — a `raise` there does make this test fail — so "
               "this is the real finding: the test runs that line and does not notice what it "
               "does. A reviewer found three of eight leaves in exactly this state, each having "
               "reported a revert-proof in prose."
               if live == "live" else
               f"LIVENESS UNESTABLISHED ({live_why}), so this is NOT yet a finding about the test. "
               "The mutation may simply never have executed. Establish that the anchor runs before "
               "concluding anything about coverage."))
    logline({"kind": "mutate_prove", "prove": a.prove, "file": path, "test": a.test,
             "replace": a.replace[:120], "with": a.with_[:120], "before": before, "after": after})
    s["mutate_proofs"] = s.get("mutate_proofs", 0) + 1
    save(s)
    _proved = fire_triggers(s, "proved", {"event": "proved", "verb": "mutate", "what": a.prove,
                                          "artifact": [path],
                                          "project": config().get("project_name"),
                                          "session": SESSION})
    # THE APPLIED MUTATION IS PRINTED ON THE SUCCESS PATH TOO, and this is the only defence that
    # works here (#97). A shell rewrites `..` and $(..) BEFORE argparse sees the value, so by the
    # time this process runs, a mangled fragment carries no metacharacter to detect and an intact
    # one does — a content check would fire exactly when nothing went wrong and stay silent exactly
    # when it did. Measured: `--with "x  # `id`"` arrives as `x  # uid=501(..)`, no backtick left.
    # --replace is already covered, because a mangled one stops appearing exactly once in the file
    # and is refused loudly. --with had nothing: it is inserted verbatim, and if the result happens
    # to compile and redden the test, ✓ PROVED was reported for a mutation nobody typed. The
    # refusal paths printed the applied text and the success path did not, so the strongest verdict
    # was the one place you could not see what had actually been applied.
    out("✓ PROVED — the test goes RED when that line changes.",
        f"  pins   : {a.prove}",
        f"  file   : {a.file}",
        f"  applied: {a.replace!r} -> {a.with_!r}",
        f"  test   : {a.test}",
        f"  before : exit {before} (green, unmutated)   after: exit {after} (red, mutated)",
        "  tree restored.",
        "",
        "WHAT THIS DOES NOT SAY: that the test is good, that this mutation is the bug the fix was",
        "for, or that anything else is covered. It says this one line is pinned by that one test.",
        f"  liveness probe: {live} — {live_why}",
        (f"  tests selected: {n_sel}" if n_sel is not None
         else f"  tests selected: UNREADABLE ({sel_why}) — the probe above is what carries this"),
        *_proved)


# ── the hatch used as a config substitute ────────────────────────────────────────────────────────
#
# THE FAILURE THIS EXISTS FOR (this checkout's own log, read 2026-08-20): one task produced 22
# `authorize` grants carrying a single identical reason, one per repo — against 4 `authorized_write`
# entries in the whole log. A single-use human hatch had quietly become the way this machine did
# routine cross-repo work, which is the one thing `authorize` promises the log will NOT contain:
# every entry there is supposed to be a one-off somebody actually decided on. Spend it 22 times and
# the record still reads as 22 human decisions — the value of "single-use and logged" is that the
# log means something later, and this is precisely how it stops meaning anything.
#
# A RECURRING cross-repo write is a CONFIG question. `allow_write_roots` (or `mcp_standing_writes`
# for a tool) is a decision on the record, made once and reviewable; the hatch is for the one-off.
# Nothing said so at the moment it mattered. The ranking does exist — gl-refused puts config at step
# 3 and the hatch at step 4 — but a skill is rung 6, an instruction to a future self that surfaces at
# session start rather than at the 22nd grant.
#
# RUNG 2 (LOUD), NOT 3 (CHECKED), and the distinction is load-bearing: this must never REFUSE. A
# human may legitimately re-authorize one path (a retry, a second call inside one job, the
# write-then-delete pair that wants `--uses 2`), and INV5 forbids a guard that blocks its own fix —
# the fix for a wrong allow root is very often a write this hatch is the only way to make. So it
# shouts, names the count, and prints the line to add. It fires on the SECOND distinct path rather
# than the twenty-second, which is the entire point of putting it here.


def _tilde(p):
    """A home path written the way a config should carry it. An absolute /Users/... in a COMMITTED
    config.json ships a write permission to everyone who clones the repo (README, Configure)."""
    home = os.path.expanduser("~")
    return "~" + p[len(home):] if p == home or p.startswith(home + os.sep) else p


def authorize_recurrence(reason):
    """Paths of prior `authorize` grants in this checkout's log carrying the SAME reason, in order
    and WITH duplicates, so the caller can tell one path re-granted from many paths sharing a reason.

    The whole log is scanned rather than its tail: the grant that reveals the pattern is the one that
    scrolled out of the window months ago. Cheap because the JSON parse is gated on a substring, the
    same shape `shared_pins` uses.

    WHAT IT MATCHES is a reason REPEATED, never a reason reworded — normalized for case and
    whitespace and no further. This is prose, so it decides what gets SAID and never what gets
    refused (INV1), and any rephrasing walks straight past it exactly as `category_tell` does.
    """
    want = " ".join(str(reason).lower().split())
    seen = []
    try:
        with open(LOG_F) as f:
            for ln in f:
                if '"authorize"' not in ln:
                    continue
                try:
                    r = json.loads(ln)
                except ValueError:
                    continue
                if r.get("kind") != "authorize":
                    continue
                if " ".join(str(r.get("reason", "")).lower().split()) != want:
                    continue
                if r.get("path"):
                    seen.append(r["path"])
    except FileNotFoundError:
        return []                        # no log yet is genuinely no prior grants
    except OSError:
        # A LOG THAT EXISTS AND CANNOT BE READ IS NOT AN EMPTY ONE, and here the difference is a
        # bypass. Returning [] means "this reason has never bought a hatch", so a reason being spent
        # for the fifth time reads exactly like a first-time grant and the loud block never prints.
        # The hatch is the one escape from INV3 and the recurrence warning is what makes a pattern
        # of spending it visible; going quiet is the failure mode, not a safe default.
        return None                      # could not tell -- distinct from "none", see caller
    return seen


def recurrence_lines(reason, real, raw_path):
    """The LOUD block when this reason has bought a hatch before, or [] when it has not."""
    prior = authorize_recurrence(reason)
    if prior is None:
        return ["",
                "⚠ PRIOR GRANTS COULD NOT BE READ — the log exists and would not open, so whether "
                "these",
                "  exact words have bought a hatch before CANNOT be established. Absence of the "
                "warning",
                "  below is not evidence this is the first time."]
    if not prior:
        return []
    distinct = []
    for p in prior:
        if p not in distinct:
            distinct.append(p)
    others = [p for p in distinct if p != real]
    # One path re-granted ONCE is an ordinary retry and says nothing. Two or more distinct paths
    # under one reason is the config smell, and so is the same path bought a third time.
    if not others and prior.count(real) < 2:
        return []
    is_mcp = str(raw_path).startswith("mcp__")
    shown = distinct[:5]
    more = len(distinct) - len(shown)
    lines = ["",
             f"⚠ THIS REASON HAS BOUGHT A HATCH BEFORE — {len(prior)} prior grant(s) carry these "
             f"same words,",
             f"  across {len(distinct)} path(s). Already granted:"]
    lines += [f"    {_tilde(p)}" for p in shown]
    if more:
        lines.append(f"    … and {more} more")
    lines.append("  A single-use hatch spent again and again is not a one-off — it is this machine's")
    lines.append("  routine work, written into the log as if somebody decided on each one separately.")
    if is_mcp:
        lines += ["  If this tool is genuinely a standing, reviewed grant, that belongs in config:",
                  '    ~/.game_loop/config.json → "mcp_standing_writes": '
                  f'["{raw_path}"]']
    else:
        lines += ["  A RECURRING write outside the repo is a CONFIG question, not a hatch:",
                  '    ~/.game_loop/config.json → "allow_write_roots": '
                  f'["{_tilde(real)}"]   (machine-wide, committed by nothing)',
                  '    .game_loop/config.json   → same key — but that file IS COMMITTED, so write',
                  "                               paths as ~/… or every clone inherits a write root",
                  "                               only you have."]
    lines += ["  NOTHING IS BLOCKED: this authorization stands and spends as normal. INV5 — the fix",
              "  for a wrong allow root is often a write only this hatch can make.",
              "  WHAT THIS MISSES: a reason REWORDED. Vary the wording and this line never appears;",
              "  the config entry is the remedy, this is only the prompt to go add one."]
    return lines


# ── a grant that lapses ──────────────────────────────────────────────────────────────────────────
#
# "A GRANT THAT LAPSES IS NOT A REMINDER; IT IS THE GUARD CLOSING ITSELF." — wcs, who argued me out
# of the cheaper version of this and was right.
#
# THE HATCH IS "LOUD, NARROW, SINGLE-USE". Narrow has always meant narrow in PATH and narrow in
# COUNT, and unbounded in TIME — and time is the only one of the three that acts while nobody is
# looking, which is exactly the condition under which a stale grant is dangerous. wcs measured five
# live grants and thirteen unspent uses in their tree, one dated six weeks earlier with eight uses
# left, covering a repo root, an app container data dir, ~/.config/showrunner and an MCP verb.
#
# I PROPOSED THE CHEAPER RUNG AND IT WAS ALREADY REFUTED. My argument was that a lapse only helps
# where somebody remembers to set one, so status should name a grant's AGE instead. wcs's answer
# was to point at themselves: `status` printed "authorize grants: 5 live, 6 spent" on every run of
# a long session, they read past it every time, and then told the human it did not surface grants
# at all. Asking that same line to argue harder is asking a channel to succeed where it has just
# demonstrably failed, on the same reader. Both are built; neither is traded for the other.

_DUR_PAT = re.compile(r"^\s*(\d+)\s*([mhdw])\s*$", re.I)
_ISO_DATE_PAT = re.compile(r"^\s*(\d{4}-\d{2}-\d{2})\s*$")
_ISO_FULL_PAT = re.compile(r"^\s*(\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(?::\d{2})?)\s*$")
_DUR_SECONDS = {"m": 60, "h": 3600, "d": 86400, "w": 604800}


def parse_expires(spec, base_epoch=None):
    """An --expires value as an ISO instant, or None for "never". Raises ValueError on nonsense.

    ACCEPTS A DURATION OR A DATE, and refuses a bare number in either direction. "2" is the one
    input where a wrong guess is invisible: read as minutes it lapses during the call that set it,
    read as days it covers a week of unattended runs, and nothing downstream can tell which the
    human meant. `m` is MINUTES, deliberately, and months are not a unit here — a grant measured in
    months is the thing this exists to prevent.

    A DATE-ONLY VALUE MEANS THE END OF THAT DAY. Comparison downstream is lexicographic against
    now()'s "%Y-%m-%dT%H:%M:%S", so a bare "2026-09-20" would otherwise mean one second past
    midnight — a grant that lapses before the morning of the day the human named it for.
    """
    if spec is None:
        return None
    raw = str(spec).strip()
    if not raw or raw.lower() in ("never", "none", "off"):
        return None
    m = _DUR_PAT.match(raw)
    if m:
        n = int(m.group(1))
        if n <= 0:
            raise ValueError("a duration of %r lapses before the grant is written down" % raw)
        base = time.time() if base_epoch is None else base_epoch
        return datetime.datetime.fromtimestamp(
            base + n * _DUR_SECONDS[m.group(2).lower()]).isoformat(timespec="seconds")
    m = _ISO_DATE_PAT.match(raw)
    if m:
        return m.group(1) + "T23:59:59"
    m = _ISO_FULL_PAT.match(raw)
    if m:
        v = m.group(1).replace(" ", "T")
        return v if len(v) > 16 else v + ":00"
    raise ValueError(
        "--expires %r is neither a duration nor a date.\n"
        "  duration : 30m  2h  7d  1w   (m is MINUTES; months are not a unit here)\n"
        "  date     : 2026-09-30   or   2026-09-30T17:00\n"
        "  never    : --expires never\n"
        "A bare number is refused on purpose: read as minutes it lapses during this call, read as\n"
        "days it covers a week of unattended runs, and nothing downstream can tell which you meant."
        % raw)


def grant_expired(a, now_iso=None):
    """Has this grant lapsed? False when it carries no expiry, which is the default and the old
    behaviour exactly. Lexicographic on purpose: both sides are written by now()'s format."""
    exp = (a or {}).get("expires_at")
    if not exp:
        return False
    return str(now_iso or now()) >= str(exp)


def grant_live(a, now_iso=None):
    """The one definition of live, so status and the three guards cannot drift apart.

    THEY ALREADY COULD. Before this the gate was `uses_left > 0` written out by hand in four places
    — status, the write guard, the gh guard and the MCP guard — and adding a second condition to
    three of four is how a grant comes to be refused by one rail and honoured by another.
    """
    return int((a or {}).get("uses_left") or 0) > 0 and not grant_expired(a, now_iso)


def grant_matches(a, target):
    """Does grant `a` name `target`? Asked three ways, because `authorize` does not store what was
    typed: it realpaths `--path`, so a verb grant lands as `<cwd>/gh issue close` and the gh guard
    reads it back by BASENAME. A revoke that compared only the stored form would silently miss
    exactly the grants a human is most likely to name by hand.

    The basename form is accepted ONLY for a `gh ` verb. Matching any grant by basename would let
    `--revoke game_loop` disarm a grant on `/Users/x/dev/game_loop`, which is a different act than
    the one asked for.
    """
    stored = (a.get("path") or "").strip()
    t = (target or "").strip()
    if not stored or not t:
        return False
    if stored == t:
        return True
    base = os.path.basename(stored)
    if base.startswith("gh ") and base == t:
        return True
    return stored == os.path.realpath(os.path.expanduser(t))


def authorize_revoke(s, a):
    """Withdraw a live grant. DISARMED, NOT DELETED — and loud when it matched nothing.

    Reported by wcs, who had no verb for this and hand-edited state.json, which is the working-
    around this repo asks consumers to report instead of absorb. What they found when they looked
    properly: five live grants and thirteen unspent uses across two state files, one dated six
    weeks earlier with eight uses left. A grant is armed until something spends it, and nothing
    spends the ones nobody needed.

    Two decisions here are theirs, and both are right. DISARM rather than delete, because deleting
    takes with it the evidence that the hatch was ever opened, and "logged forever" is the entire
    value of the hatch. And record WHY and HOW MANY uses were withdrawn, because a grant zeroed
    with no other mark is indistinguishable afterwards from one somebody actually spent — the
    record would read as a bypass that happened.

    REFUSES WHEN NOTHING MATCHED. That is the load-bearing half. A revoke that prints success over
    an empty match set is this repo's recurring defect sitting in the worst available place: the
    human reads "revoked", the grant is still armed, and the next write through it is the one
    nobody is watching for. Silence here would be worse than having no verb at all.
    """
    target = a.revoke
    auth = [x for x in (s.get("authorized") or []) if isinstance(x, dict)]
    matched = [x for x in auth if grant_matches(x, target)]
    live_all = [x for x in auth if int(x.get("uses_left") or 0) > 0]
    if not matched:
        if live_all:
            have = ["  live grants, named as you must name them:"]
            have += ["    %3d left · %s" % (int(x.get("uses_left") or 0), x.get("path"))
                     for x in live_all[:8]]
            if len(live_all) > 8:
                have.append("    ... and %d more live" % (len(live_all) - 8))
        else:
            have = ["  This checkout holds no live grants at all."]
        die("REFUSED — no grant here names %r, so NOTHING WAS REVOKED.\n%s\n\n"
            "Said this loudly on purpose: a revoke that reported success over an empty match set\n"
            "would leave the hatch armed while the record said it was closed, and the write that\n"
            "went through it later would be the one nobody was watching for."
            % (target, "\n".join(have)))
    live = [x for x in matched if int(x.get("uses_left") or 0) > 0]
    if not live:
        out("✓ ALREADY DISARMED — %d grant(s) name that path and none has a use left."
            % len(matched),
            "  Nothing changed, and nothing needed to. A spent grant and a revoked one are both",
            "  harmless; the record keeps them either way so the hatch stays readable later.")
        return
    reason = a.reason or "revoked; no reason given"
    for x in live:
        n = int(x.get("uses_left") or 0)
        x["uses_left"] = 0
        x["revoked_at"] = now()
        x["revoked_reason"] = reason
        x["uses_revoked"] = n
    save(s)
    for x in live:
        logline({"kind": "authorize_revoke", "path": x.get("path"), "reason": reason,
                 "granted_reason": x.get("reason"), "granted_at": x.get("at"),
                 "uses_revoked": x.get("uses_revoked")})
    withdrawn = sum(int(x.get("uses_revoked") or 0) for x in live)
    out("✓ REVOKED — %d grant(s), %d unspent use(s) withdrawn." % (len(live), withdrawn),
        *["  %s (granted %s, %d use(s) left)"
          % (x.get("path"), (x.get("at") or "?")[:16], int(x.get("uses_revoked") or 0))
          for x in live],
        "  reason: %s" % reason,
        "→ disarmed, not deleted. The grant stays in state.json and in log.jsonl carrying the",
        "  human's original words, because the record that a hatch was opened outlives the hatch.")


def cmd_authorize(s, a):
    """Record ONE human-authorized mutation outside this repo. Consumed on use, logged forever.

    The write guard has no env override, deliberately — an override the agent can set itself is not a
    guard. But the human IS the escape hatch by design. This mirrors the primitive the whole tool
    rests on: arm -> gate -> CONSUME. One authorization buys exactly one mutation, and it writes a
    permanent log entry carrying the human's own words, so every bypass is readable forever.

    Honest about what it is: nothing here can verify the human really said it — the agent is the one
    typing. It does not make a bypass impossible; it makes a bypass LOUD, NARROW, SINGLE-USE and
    permanently attributable. That is the most a guard on this side of the keyboard can do.
    """
    if getattr(a, "revoke", None):
        return authorize_revoke(s, a)
    if not a.path or not a.reason:
        die("authorize needs --path <prefix> and --reason \"<the human's own words>\".\n"
            "This is a HUMAN escape hatch, not a convenience. Quote them, don't paraphrase.")
    # A BRIEF IS NOT A HUMAN (#68). An unattended Crawler spent this hatch twice on its own prompt,
    # recording "brief instructs: ..." as the human's words. From inside that session the brief IS
    # the instruction from its principal — the only voice it hears, arriving exactly as a human
    # prompt arrives — so the substitution is reasonable and the log still ends up carrying two
    # authorizations that read as human-sanctioned and were not. The whole value of single-use and
    # logged is that the log means something later.
    #
    # A NARROW NAMED CLASS, not a prose scan. This repo's rule is that a text detector NUDGES and the
    # flag enforces; the exception here is that the thing being detected is the agent citing ITSELF,
    # which no human phrasing needs. A human who really said "the brief says to" loses a rephrase.
    _low = " " + " ".join(str(a.reason).lower().split()) + " "
    _self_cited = [p for p in ("brief instruct", "brief says", "the brief", "my brief",
                               "my prompt", "the prompt says", "my instructions", "task says",
                               "instructions say", "per the brief", "as instructed")
                   if p in _low]
    if _self_cited:
        die("REFUSED — that reason cites the agent's own instructions, not a human.\n"
            f"  matched: {_self_cited[0]!r}\n\n"
            "A brief is text another agent wrote and handed you as a prompt. It arrives exactly the\n"
            "way a human's words arrive, which is why this is worth refusing rather than trusting —\n"
            "an unattended Crawler spent this hatch twice on its own brief, and the log then read as\n"
            "human-sanctioned when nobody had been asked.\n\n"
            "TWO REAL ROUTES:\n"
            "  * ask, and quote the answer — `game_loop arm --question .. --read .. --predict ..`\n"
            "    surfaces it to whoever is watching, and their reply is words you did not write.\n"
            "  * if you are dispatched and no human is reachable, the orchestrator that briefed you\n"
            "    is the one that must ask. Report the refusal upward; do not spend the hatch for it.\n\n"
            "The guard you hit will still be there. That is the point of it.")
    try:
        expires_at = parse_expires(getattr(a, "expires", None))
    except ValueError as e:
        die("REFUSED — %s" % e)
    real = os.path.realpath(os.path.expanduser(a.path))
    # BEFORE the append and the logline below, or this grant counts itself as its own precedent.
    recur = recurrence_lines(a.reason, real, a.path)
    # PROVENANCE THE AGENT DID NOT TYPE. `arm` is the T3 mechanism and it writes state; an
    # authorization raised while one was armed can be read later against the answer that came back.
    # Not a gate — an interactive human speaks directly and arms nothing — but the difference between
    # "a human was asked here" and "nobody was" stops being invisible in the record.
    _armed = s.get("t3_armed") or {}
    auth = {"path": real, "reason": a.reason, "at": now(), "uses_left": int(a.uses or 1),
            "expires_at": expires_at,
            "asked_via_arm": bool(_armed.get("question")),
            # A SPENT question is recorded SEPARATELY from a live one rather than folded into the
            # same flag. "This exact question is open" and "some question was put to the human
            # earlier in this session" are different claims, and collapsing them would recreate the
            # defect one level up — a later, unrelated hatch would inherit the diligence of a
            # question asked hours before. So the text is carried and the reader judges.
            "asked_spent": ((s.get("t3_last_asked") or {}).get("question") or None),
            "arm_question": (_armed.get("question") or None)}
    s.setdefault("authorized", []).append(auth)
    save(s)
    logline({"kind": "authorize", "path": real, "reason": a.reason, "uses": auth["uses_left"],
             "asked_via_arm": auth["asked_via_arm"], "asked_spent": auth["asked_spent"]})
    out("✓ AUTHORIZED — one mutation outside this repo.",
        f"  path  : {real}",
        f"  reason: {a.reason}",
        f"  uses  : {auth['uses_left']}",
        # SAID EITHER WAY. "no expiry" printed beside a grant is the one line that makes an
        # unbounded one a decision somebody saw rather than a default they inherited — which is
        # how a grant comes to sit armed for six weeks with nobody having chosen that.
        ("  lapses: %s — after this the guard refuses it, spending nothing" % expires_at
         if expires_at else
         "  lapses: NEVER — this stays armed until it is spent or `authorize --revoke`d.\n"
         "          `--expires 2h` / `7d` / `2026-09-30` bounds it. Time is the one dimension\n"
         "          of this hatch that acts while nobody is looking."),
        # NAME THE LIVE QUESTION TOO. The spent branch below was fixed to print WHICH question,
        # because "some question was asked earlier" would let an unrelated hatch inherit its
        # diligence — and this branch still had exactly that defect, one step over. Observed while
        # taking a hatch for GitHub writes with a question about the WATCHDOG armed: it printed
        # "via an armed question", truthfully, about a question with nothing to do with the act.
        # The tool cannot judge relevance and should not try; it can refuse to hide the question
        # from the person who can.
        (("  asked : via an armed question — the reply is words you did not write. IT ASKS:\n"
          "          \"" + (auth["arm_question"] or "").splitlines()[0][:100] + "\"\n"
          "          Judge for yourself whether that question covers THIS hatch.")
         if auth["asked_via_arm"] else
         ("  asked : a question WAS put to the human in this session and has been answered —\n"
          "          \"" + (auth["asked_spent"] or "").splitlines()[0][:100] + "\"\n"
          "          Named, not merely counted: judge for yourself whether it covers THIS hatch."
          if auth["asked_spent"] else
          "  asked : NO armed question in this session — the record says so, because a hatch spent "
          "with\n          nobody asked and one spent after asking must not read the same later")),
        "→ the guard will consume this and log the use. It is permanent in log.jsonl.",
        *recur)


# ── merge attribution ────────────────────────────────────────────────────────────────────────────
#
# THE FAILURE THIS EXISTS FOR (issue #29, and it was logged before it was built): the blast-radius
# warning compares a commit's staged files against what THIS session wrote through Write/Edit. That
# set is session-wide, deliberately and correctly — one session is one session however many trees it
# touches — which is exactly why it never contains what a SIBLING session wrote on a branch. The
# moment this session integrates that work, `git merge` brings the files in and every one of them
# reads as excess. Observed live across ~14 integration commits: the warning fired on 8, naming 2-10
# files each time, all of them the point of the commit. A warning that is wrong every time is one
# people learn to scroll past, and a rail nobody reads is a rail already routed around.
#
# The scoping is not the bug. The bug is that the check had no way to be told a commit's PROVENANCE.
#
# THE KEYSTONE, APPLIED TO PROVENANCE: a declaration names REFS, never filenames, and game_loop
# recomputes the file set from the ref itself. A JSON array of paths is precisely the plausible
# string a model produces for free and nothing can check; a ref is real, resolvable, and the
# recomputation IS the check — a ref that does not resolve is REFUSED, the same shape as
# `claim --read` refusing a path that is not there.
#
# NOT config.json -> generated_globs, deliberately, though it was the shortcut sitting right there.
# That list is keyed to PATHS rather than to provenance: it would suppress genuine findings on those
# paths forever, it grows monotonically as more of a repo gets orchestrated, and it lies — merged
# files are not generated. This is the opposite trade: narrow, single-use, logged, and it makes the
# check STRICTER rather than quieter, because what nothing accounts for becomes the only output.


def _git_out(tree, *args):
    """git in `tree`: stdout on success, None on any failure at all.

    Never raises, on purpose. A missing ref, a shallow clone, an unborn HEAD, a detached HEAD, git
    not installed — every one of them has to become a STATED refusal or silence, never a traceback
    out of a guard.
    """
    try:
        r = subprocess.run(["git", "-C", tree] + list(args), capture_output=True, text=True)
    except (OSError, ValueError):
        return None
    return r.stdout if r.returncode == 0 else None


def attribution_tree():
    """The tree an attribution is computed in: the git tree holding the cwd when that is the project
    itself or a tree nested inside it (a worktree), else the project.

    Same answer the commit gate resolves for the tree a commit LANDS in (#28), so the two sets
    describe one world. A cwd somewhere else entirely falls back to the project rather than
    attributing a foreign checkout's refs.
    """
    root = os.path.realpath(REPO_ROOT)
    try:
        cwd = os.getcwd()
    except OSError:
        return root
    top = _git_out(cwd, "rev-parse", "--show-toplevel") or ""
    top = os.path.realpath(top.strip()) if top.strip() else ""
    return top if top and (top == root or top.startswith(root + os.sep)) else root


def merge_files(tree, ref):
    """Recompute what a ref actually carries. Returns (paths, None) or (None, refusal).

    The set is `git diff --name-only $(git merge-base HEAD <ref>)..<ref>` — the files that ref brings
    that HEAD does not already have. Paths come back REPO-relative, the one space edited.txt and the
    blast-radius check both speak, so a worktree's paths carry the worktree's prefix.

    WHAT THIS MISSES, and it is an over-report in the widening direction: "HEAD does not already
    have" is answered from ANCESTRY, and a squash-merge rewrites the commit — so a ref whose work is
    already in HEAD is never an ancestor of it, and this replays the ENTIRE branch forever. The set
    is therefore too big, not too small, and it feeds `attribute`, which uses it to widen what the
    blast-radius check accepts. So the error excuses files rather than nagging about them.

    Three things bound that, none of them this function: an own-edited file is matched as an own
    edit BEFORE the attributed set is consulted, so nothing this session touched can be laundered
    through a stale ref; the declaration is spent by one commit; and it carries a required reason
    into log.jsonl permanently. What is left is files this session did not edit, that something else
    wrote, that also fall inside an over-broad ref diff — inside one commit, with a reason on the
    record. Observed as a BLOCKING failure in another harness (#125), where the same ancestry test
    demanded review of code that had already shipped; not observed here, so it is written down
    rather than gated (INV4).
    """
    if not _git_out(tree, "rev-parse", "--git-dir"):
        return None, "%s is not a git tree, so there is no ref to recompute anything from" % tree
    sha = (_git_out(tree, "rev-parse", "--verify", "--quiet", ref + "^{commit}") or "").strip()
    if not sha:
        return None, "'%s' does not resolve to a commit in %s" % (ref, tree)
    if not (_git_out(tree, "rev-parse", "--verify", "--quiet", "HEAD") or "").strip():
        return None, ("HEAD does not resolve in %s — with no commit to compare against there is no "
                      "set of files a merge would bring in" % tree)
    base = (_git_out(tree, "merge-base", "HEAD", sha) or "").strip()
    if not base:
        return None, ("HEAD and '%s' share no merge-base in %s — nothing connects the two histories, "
                      "so no set of files can be recomputed from that ref" % (ref, tree))
    diff = _git_out(tree, "diff", "--name-only", base + ".." + sha)
    if diff is None:
        return None, "git could not diff %s..'%s' in %s" % (base[:8], ref, tree)
    prefix = os.path.relpath(tree, os.path.realpath(REPO_ROOT))
    paths = []
    for line in diff.splitlines():
        p = line.strip()
        if p:
            paths.append(p if prefix == "." else os.path.normpath(os.path.join(prefix, p)))
    return paths, None


def cmd_attribute(s, a):
    """Declare that the next commit lands work a NAMED REF carries. One commit, consumed, logged.

    Mirrors `authorize` exactly — the arm -> gate -> CONSUME primitive the whole tool rests on. It
    buys one commit's worth of attribution and writes a permanent log entry carrying the reason, so
    every widening of what the blast-radius check will accept is readable forever.

    The load-bearing part is what it REFUSES to take: a list of filenames. Only refs, and the files
    are recomputed here from each ref. A ref that does not resolve is refused outright, because an
    attribution game_loop cannot recompute would suppress a real finding on nothing but a sentence.

    Honest about its own edges, and they are stated in the guard too: the declaration is spent by the
    next commit the blast-radius check actually EXAMINES (a session with no recorded edits of its own
    is already silent there, and does not burn it), and the check runs at PreToolUse — so a commit
    denied further down the same command has still spent it.
    """
    refs = [r.strip() for r in (a.merge or []) if r and r.strip()]
    if not refs or not a.reason:
        die("attribute needs --merge <ref> [--merge <ref> ...] and --reason \"<why this commit "
            "carries them>\".\n"
            "It names REFS, never filenames. A list of paths is a sentence anything can write; a ref\n"
            "is checkable, and game_loop recomputes the files from it. That recomputation IS the check.")
    tree = attribution_tree()
    files, per_ref = [], []
    for ref in refs:
        got, refusal = merge_files(tree, ref)
        if refusal:
            die("attribute REFUSES this declaration: " + refusal + ".\n"
                "Name a ref that resolves — a branch, a tag, a sha. An attribution that cannot be\n"
                "recomputed is a claim with nothing behind it, and it would silence a real finding.")
        per_ref.append({"ref": ref, "files": len(got)})
        files.extend(got)
    files = sorted(dict.fromkeys(files))
    head = (_git_out(tree, "rev-parse", "HEAD") or "").strip()[:12]
    rec = {"refs": refs, "per_ref": per_ref, "files": files, "reason": a.reason,
           "tree": tree, "head": head, "at": now(), "uses_left": 1}
    s.setdefault("attributed", []).append(rec)
    save(s)
    logline({"kind": "attribute", "refs": refs, "files": len(files), "reason": a.reason,
             "tree": tree, "head": head})
    out("✓ ATTRIBUTED — one commit's merges accounted for, recomputed from the refs.",
        *["  %s: %d file(s)" % (d["ref"], d["files"]) for d in per_ref],
        f"  total : {len(files)} distinct file(s)  (no filename you typed is in this — only the refs)",
        f"  reason: {a.reason}",
        "→ the next commit's blast-radius check partitions THREE ways: your own edits, these, and",
        "  whatever is in NEITHER — and only that third set is reported. Consumed there, logged there.")


# ── environment pins ─────────────────────────────────────────────────────────────────────────────
#
# THE FAILURE THIS EXISTS FOR: a run moved a dependency checkout to a non-default commit because the
# work needed an API only present there. Later, tidying up loose ends, it restored that checkout to
# its default branch — which silently removed the API, and the next build failed on a symbol that
# "does not exist". The required commit was written down in exactly one place: a comment inside a CI
# config. Recovering it meant reading CI config and a reflog.
#
# The trap works precisely BECAUSE reverting unexplained local state is good hygiene. The tidying
# instinct is correct; nothing warns it off. So the fix is not a rule to remember — it is to make the
# fact VISIBLE with its reason: a pin lives in resume state, `status` re-prints it after every
# compaction, and releasing one is an explicit, logged act. Reverting it becomes a decision on the
# record instead of an invisible one.
#
# Same keystone as claim/harden/arm: a pin must name something that really exists on disk. An LLM
# writes a plausible sentence about a pinned commit for free; it cannot conjure a path that resolves.

PIN_PROBE_MAX = 1 << 20   # don't slurp a huge file to re-check --expect; status must stay instant


def resolve_env(p):
    """Resolve a pin's anchor: a real file OR a real directory, as-is or under a read root.

    Deliberately looser than resolve_read() in two ways, because a pin means something different
    from a citation. A pin's subject is routinely a DIRECTORY — a dependency checkout, an installed
    SDK — and demanding a file there only pushes you to cite an arbitrary file inside it. And
    emptiness is not the test: resolve_read() insists on a non-empty file because you claim to have
    READ it; a pin claims the thing EXISTS. Existence is still the ungameable part, which is the
    whole reason the anchor is mandatory.
    """
    for cand in [p] + [os.path.join(r, p) for r in config().get("read_roots", [])]:
        cand = os.path.expanduser(cand)
        if os.path.exists(cand):
            return os.path.realpath(cand)
    return None


def pin_state(pin):
    """(symbol, note) for one pin: is its anchor still there, and does --expect still hold?

    WHAT THIS DOES NOT CATCH, said plainly: with no --expect this checks only that the anchor still
    EXISTS. The failure that prompted all of this — a checkout restored to its default branch —
    leaves a perfectly real directory behind, so an existence check alone would report a cheerful ✓
    on a pin that has already been undone. That is why --expect exists, and why its absence prints as
    "unchecked", never as ✓: a guard that overstates its reach buys false confidence.
    """
    real = resolve_env(pin.get("path") or "")
    if real is None:
        return "✗", f"MISSING — nothing at {pin.get('path')} any more"
    exp = pin.get("expect")
    if not exp:
        return "•", "present (UNCHECKED — no --expect, so a change inside it is invisible here)"
    try:
        if os.path.isdir(real):
            return "?", "unverifiable — --expect reads a file; this anchor is a directory"
        if os.path.getsize(real) > PIN_PROBE_MAX:
            return "?", "unverifiable — anchor too large to probe; anchor a smaller file"
        with open(real, errors="replace") as f:
            body = f.read()
    except OSError as e:
        return "?", f"unverifiable — {e}"
    if exp in body:
        return "✓", f"holds (still contains {exp!r})"
    return "✗", f"DRIFTED — no longer contains {exp!r}; the pin has been undone"


def shared_pins():
    """Every live pin in this CHECKOUT, read from the shared log — not from one session's state.

    #18 shipped these session-scoped, and the incident it was built from says why that was wrong.
    The failure was "later, cleaning up loose ends, it was restored to its default branch": a
    DIFFERENT moment, very often a different session — after a restart, after compaction, after a
    handback. The tidying instinct that does the damage is precisely the one that arrives fresh,
    with no memory of why the state was unusual. Session-scoped, the guard protected the only run
    that did not need protecting.

    #17 answered the identical question for refuted claims and answered it the other way, on stated
    reasoning: a negative result is knowledge about the CHECKOUT, and the run that must not re-walk
    it is a later session holding none of this one's state. That argument is stronger here, not
    weaker — a refutation is knowledge about a codebase, while a pin is knowledge about the
    ENVIRONMENT ON THIS MACHINE, which two sessions genuinely share. The fact is true for both of
    them whether or not either one recorded it.

    Each pin carries the session that registered it, so it is clear who established it and can be
    asked. WHAT THIS STILL MISSES (INV6): a pin whose session ended and whose fact was reverted by
    hand outside game_loop reads as live until its --expect notices, and a pin with no --expect
    cannot notice at all.

    The whole log is scanned rather than its tail: a pin scrolling out of a window is exactly the
    silent revert this exists to prevent. Cheap because the JSON parse is gated on a substring.
    """
    live, released = [], set()
    try:
        with open(LOG_F) as f:
            for ln in f:
                if '"pin' not in ln:
                    continue
                try:
                    r = json.loads(ln)
                except ValueError:
                    continue
                kind, pid = r.get("kind"), r.get("id")
                if kind == "pin_release" and pid:
                    released.add(pid)
                elif kind == "pin" and pid:
                    live.append(r)
    except FileNotFoundError:
        return []                        # no log yet is genuinely no pins
    except OSError:
        # "NONE REGISTERED" IS A CLAIM, AND THIS PATH COULD NOT MAKE IT. Returning [] here renders
        # as `pins: none registered` -- an affirmative statement that nothing is load-bearing --
        # when the truth is that the log would not open. That is the exact sentence #18 was built to
        # prevent somebody acting on: the incident was a pin TIDIED AWAY by a later session cleaning
        # up loose ends, and a status line volunteering that there is nothing to protect is an
        # invitation to do it again.
        return None                      # could not tell -- distinct from "none", see pins_report
    return [p for p in live if p.get("id") not in released]


def pins_report(s):
    """The pins block for `status` — surviving compaction is the entire point of putting it here."""
    pins = shared_pins()          # the checkout's, not this session's (#31)
    if pins is None:
        return ["", "PINS — THE SHARED LOG WOULD NOT OPEN, so whether this checkout has "
                    "load-bearing",
                "  environment facts CANNOT be established. This is NOT 'none registered': if a pin "
                "is",
                "  live, nothing here will tell you before you tidy it away, which is exactly the "
                "incident",
                "  pins exist to prevent. Repair .game_loop/log.jsonl."]
    if not pins:
        return ['pins: none registered — `game_loop pin --fact ".." --reason ".." --path <real path>` '
                "the moment local state becomes load-bearing"]
    lines = ["", "PINS — load-bearing environment facts. Do NOT tidy these away:"]
    for p in pins:
        sym, note = pin_state(p)
        who = p.get("sid")
        # SESSION[:8] is what logline stamps, so compare like with like: SESSION.startswith(who)
        # called any two sessions sharing a prefix the same session, and silently dropped the
        # attribution in exactly the case it exists for.
        mine = "" if not who or (SESSION and SESSION[:8] == who) else f"   (pinned by {who})"
        lines.append(f"  {sym} [{p.get('id')}] {p.get('fact')}{mine}")
        lines.append(f"      why    : {p.get('reason')}")
        lines.append(f"      anchor : {p.get('path')} — {note}")
        if p.get("restore"):
            lines.append(f"      restore: {p['restore']}")
    lines.append('  → reverting one is a DECISION: game_loop pin --release <id> --notes ".."')
    return lines


def cmd_pin(s, a):
    """Register (or list, or release) a load-bearing environment fact, WITH the reason.

    The reason is not paperwork — it is the whole payload. "dep is on abc123" invites a tidy-up;
    "dep is on abc123 because the merge API does not exist on the default branch" stops one. The
    anchor is the keystone, and --expect is what turns a displayed pin into a checked one.
    """
    pins = shared_pins()               # the checkout's pins, whoever registered them (#31)

    if a.list:
        if not pins:
            out("no pins registered.")
            return
        out(*pins_report(s)[1:])
        return

    if a.release:
        hit = next((p for p in pins if p.get("id") == a.release), None)
        if not hit:
            die(f"no live pin with id {a.release!r} in this checkout. `game_loop pin --list` shows "
                "them.")
        if not a.notes:
            die("pin --release needs --notes: say why this fact is no longer load-bearing.\n"
                f"  releasing: [{hit['id']}] {hit['fact']}\n"
                f"  it was kept because: {hit['reason']}\n"
                "Making the revert a STATED decision is the only job this verb has. An unexplained "
                "release is the invisible revert all over again.")
        logline({"kind": "pin_release", "id": hit["id"], "fact": hit["fact"],
                 "path": hit.get("path"), "notes": a.notes})
        # Releasing somebody ELSE's pin is the moment the human's judgement is worth spending: the
        # run tidying up is, by construction, the one that does not know why the state was unusual.
        foreign = hit.get("sid") and not (SESSION and SESSION[:8] == hit["sid"])
        out("✓ PIN RELEASED — the revert is on the record.",
            *([f"  ⚠ registered by ANOTHER session ({hit['sid']}) — that run established this "
               "state and is the one that knew why.",
               "    You are releasing it on its behalf."]
              if foreign else []),
            f"  was  : [{hit['id']}] {hit['fact']}",
            f"  kept because: {hit['reason']}",
            f"  notes: {a.notes}",
            "→ whatever depended on it is now free to be tidied away. That was the decision.")
        return

    if not a.fact or not a.reason or not a.path:
        die("pin needs --fact, --reason, and --path <real path>.\n"
            "  --fact   : the environment fact the build depends on (a pinned commit, a toolchain "
            "version, an installed SDK)\n"
            "  --reason : WHY it is load-bearing — what breaks when someone tidies it away\n"
            "  --path   : the real path the fact lives at (this is the gate)\n"
            "  --expect : optional text that must stay in that file — turns the pin into a CHECK\n"
            "  --restore: optional exact command that re-establishes it\n"
            "A fact with no reason cannot defend itself against a cleanup, and a fact with no path "
            "is a sentence about the environment rather than a handle on it.")
    real = resolve_env(a.path)
    if real is None:
        die(f"--path does not name anything on disk: {a.path}\n"
            "Name the checkout, file, or install dir the fact actually lives at (absolute, or "
            "relative to the repo / a read_root). If it isn't there, the pin is already broken.")
    # Sequence off the CHECKOUT's history, not this session's: two sessions each numbering from 1
    # would collide the moment the list became shared, and `pin --release p1` would be ambiguous.
    seq = 0
    try:
        with open(LOG_F) as f:
            seq = sum(1 for ln in f if '"kind": "pin"' in ln)
    except OSError:
        pass
    pin = {"id": f"p{max(seq, s.get('pin_seq', 0)) + 1}", "fact": a.fact, "reason": a.reason,
           "path": real, "expect": a.expect, "restore": a.restore, "at": now()}
    if a.expect:
        sym, note = pin_state(pin)
        if sym != "✓":
            die(f"--expect does not hold right now: {note}\n"
                "A pin records state you have ALREADY established, so its check must be green at "
                "registration. A check born red is a check nobody will believe later.")
    s["pin_seq"] = s.get("pin_seq", 0) + 1
    save(s)
    logline({"kind": "pin", **{k: pin[k] for k in ("id", "fact", "reason", "path", "expect",
                                                   "restore")}})
    out(f"✓ PIN registered [{pin['id']}] — carried in the CHECKOUT's log, re-shown by every "
        "`status`, in every session.",
        f"  fact   : {pin['fact']}",
        f"  why    : {pin['reason']}",
        f"  anchor : {real}" + (f"  (expect {a.expect!r} — CHECKED)" if a.expect else
                                "  (no --expect — status can only confirm it still exists)"),
        *([f"  restore: {a.restore}"] if a.restore else []),
        "→ this is now a visible fact, so reverting it is a decision: "
        'game_loop pin --release ' + pin["id"] + ' --notes ".."')


# ── effectors: things that ACT ───────────────────────────────────────────────────────────────────
#
# `pin` and `claim` cover things that ARE and things that were READ. An EFFECTOR is a third kind: a
# verb the run uses to act on the world — a click, a scroll, a keystroke, a synthetic tap. Nothing
# here governed those, and an effector that quietly does nothing is worse than a bad measurement:
#
#     AN EFFECTOR THAT FAILS QUIETLY DOES NOT PRODUCE ZERO FINDINGS, IT PRODUCES FALSE ONES,
#     AND THEY ARE INDISTINGUISHABLE IN TONE AND DETAIL FROM REAL ONES.
#
# The agent acts, reads the unchanged screen as THE APP'S behaviour, and writes it up. Four of these
# landed in one session driving a desktop app through synthetic input (the failures this gate is
# owed, per INV4 — every one of them EXITED ZERO):
#
#   1. A verb that was never a verb.       The scroll helper called `cliclick w:` — `w:` is *wait*,
#                                          not *wheel*. Top-severity finding: "the app cannot scroll
#                                          at all". The content was simply below the fold.
#   2. A verb fixed and never wired in.    A real scroller was written; the helper still called the
#                                          broken one. Fixed, and still live in the tool in use.
#   3. A verb that needed arithmetic.      Clicks took retina pixels and asked the caller to multiply
#                                          by 1.73. The author got the conversion wrong on the very
#                                          next run: the click landed in empty background, the app
#                                          correctly did nothing — indistinguishable from a dead
#                                          control. Hence --scale/--aim below: THE TOOL CONVERTS.
#   4. An environmental one.               The display slept, every screenshot came back solid black,
#                                          and the macOS lock screen was written up as an application
#                                          sign-in failure, with a plausible narrative attached.
#
# THE KEYSTONE. `claim`'s is "name a real file that resolves" — prose cannot satisfy it. That reaches
# evidence which is a DOCUMENT. Here the evidence is an ACT, and the equivalent un-fakeable check is:
#
#     TWO REAL ARTIFACTS, CAPTURED EITHER SIDE OF THE ACT, THAT **THIS TOOL** COMPARES AND FINDS
#     DIFFERENT.
#
# The caller never asserts that something changed; it hands over the before and the after and the
# tool does the comparing. That is deliberately the one thing a confident sentence cannot supply —
# and note what it costs the four failures above: in every one of them the screen genuinely did not
# change, so every one of them produces a byte-identical pair and is REFUSED. Case 4 refuses loudest:
# black before, black after.
#
# THE EXIT CODE IS NOT THE ASSERTION. There is deliberately no flag anywhere here that accepts a
# return code, a "succeeded", or a count of commands run. `--exit-code` exists ONLY to be refused by
# name, because it is the affordance a hurried run reaches for first and an argparse "unrecognized
# argument" would teach it nothing.

EFFECTOR_SCAN_MAX = 4 << 20   # --expect reads TEXT; don't slurp a 40MB capture to grep it


def _digest(path):
    """Short content digest of a real path, streamed — captures are binary and can be large."""
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()[:12]


def _scan_text(path):
    """The head of a file as text, for --expect. None when it is too big to be worth grepping."""
    if os.path.getsize(path) > EFFECTOR_SCAN_MAX:
        return None
    with open(path, "rb") as f:
        return f.read().decode("utf-8", "replace")


def effector_proof(s, name):
    return next((e for e in (s.get("effectors") or []) if e.get("name") == name), None)


def effector_state(e):
    """(symbol, note) for one proof — can its evidence still be inspected?

    WHAT THIS DOES NOT CATCH, said plainly: a proof is a POINT-IN-TIME fact about the environment,
    and failure 4 above happened MID-RUN. Nothing here expires a proof, so an effector proved while
    the display was awake still reads ✓ after it sleeps. That is why the age is printed rather than
    hidden: the check is CHECKED-rung, the staleness is VISIBLE-rung, and pretending otherwise would
    buy exactly the false confidence this whole verb exists to remove.
    """
    for role in ("before", "observed"):
        real = resolve_read(e.get(role) or "")
        if real is None:
            return "✗", f"MISSING — the {role} artifact is gone from {e.get(role)}"
        if _digest(real) != e.get(role + "_digest"):
            return "?", (f"unverifiable — the {role} artifact at that path is no longer the one that "
                         "was compared (overwritten by a later capture); the pair is in the log")
    if not e.get("expect"):
        return "•", ("acted (UNCHECKED — no --expect, so the pair only proves SOMETHING changed, "
                     "not that the asserted thing did)")
    return "✓", f"acted, and the change was the asserted one ({e['expect']!r} appeared)"


def effectors_report(s):
    """The effectors block for `status` — a proof the run depends on must survive compaction."""
    effs = s.get("effectors") or []
    if not effs:
        return ['effectors: none proved — `game_loop effector --prove <name> --known-state ".." '
                "--before <path> --observed <path>` before any finding leans on one acting"]
    lines = ["", "EFFECTORS — proved to actually act. A finding may lean on these and no others:"]
    for e in effs:
        sym, note = effector_state(e)
        lines.append(f"  {sym} {e.get('name')} — proved {e.get('at')}")
        lines.append(f"      known state: {e.get('known_state')}")
        lines.append(f"      observed   : {_short(e.get('before') or '')} → "
                     f"{_short(e.get('observed') or '')} ({note})")
        if e.get("scale"):
            lines.append(f"      coordinates: scale {e['scale']} — "
                         f"`game_loop effector --aim {e.get('name')} --at X,Y` converts. Never "
                         "multiply by hand.")
    lines.append("  → a proof is point-in-time: re-prove after the environment could have changed "
                 "(a display sleeping mid-run is failure 4).")
    return lines


def _aim(s, a):
    """Convert a point into the effector's own coordinate space, so the CALLER never multiplies.

    Failure 3 is the whole reason this exists: the helper asked its caller to multiply measured
    coordinates by 1.73, and the person who wrote that instruction got it wrong on the next run. A
    mis-aimed click lands in empty background, the app correctly does nothing, and that reads as a
    dead control. ARITHMETIC IN THE HARNESS IS A DEFECT GENERATOR — so the conversion lives here,
    where it is written once and checked, instead of in a sentence addressed to whoever is driving.
    """
    e = effector_proof(s, a.aim)
    if not e:
        die(f"no proved effector named {a.aim!r} in this session — nothing to aim.\n"
            "Prove it first; an unproved effector's coordinates are arithmetic on a guess.")
    if not e.get("scale"):
        die(f"effector {a.aim!r} was proved without --scale, so there is no conversion to apply.\n"
            "If it takes coordinates in the space you measure in, aim with your numbers unchanged. "
            "If it does not, re-prove it with --scale <factor> and let this verb do the multiplying.")
    try:
        x, y = (float(v) for v in (a.at or "").split(","))
    except (ValueError, TypeError):
        die("--aim needs --at X,Y (the point as YOU measured it, in your own coordinate space).")
    scale = float(e["scale"])
    out(f"✓ AIM converted for {a.aim} — use these numbers verbatim.",
        f"  measured : {x:g},{y:g}",
        f"  send     : {round(x * scale)},{round(y * scale)}",
        f"  scale    : {scale:g} (recorded at proof time; you did not compute this, and that is "
        "the point)")


def cmd_effector(s, a):
    """Prove (or list, or release, or aim) an effector — a verb the run acts on the world with.

    A proof names a state whose response you ALREADY KNOW — a view you know overflows, a control you
    know is live, a field you can read back — and hands over the capture from either side of the act.
    The tool compares them. Nothing the caller says about the outcome is load-bearing; the two files
    are. Same spirit as `pin --expect`, which must already hold at registration: a proof is recorded
    only once the change has ALREADY been demonstrated, because a proof taken on faith is a proof
    nobody will believe later.

    SESSION-SCOPED, on purpose, and unlike the RULED-OUT list. A refutation is knowledge about the
    CHECKOUT, so it lives in the shared log. An effector proof is the opposite: a perishable fact
    about THIS run's environment — this display awake, this helper wired to this binary, this app
    instance. Letting session B admit findings on the strength of a proof session A took against a
    screen B never saw is the original bug wearing a different hat: findings admitted on the strength
    of a success that belonged to something else. Every proof still APPENDS to the shared log, with
    both digests, so the audit trail is global even though the admission is not.
    """
    effs = list(s.get("effectors") or [])   # copy: never mutate the module-level DEFAULT_STATE list

    if a.list:
        if not effs:
            out("no effectors proved in this session.")
            return
        out(*effectors_report(s)[1:])
        return

    if a.aim:
        _aim(s, a)
        return

    if a.release:
        hit = effector_proof(s, a.release)
        if not hit:
            die(f"no proved effector named {a.release!r} in this session. `game_loop effector --list` "
                "shows them.")
        if not a.notes:
            die("effector --release needs --notes: say why this proof no longer stands.\n"
                f"  releasing: {hit['name']} (proved {hit['at']} against: {hit['known_state']})\n"
                "Findings that leaned on it were admitted on its strength, so retiring it is a "
                "stated decision, not a tidy-up.")
        effs.remove(hit)
        s["effectors"] = effs
        save(s)
        logline({"kind": "effector_release", "name": hit["name"], "notes": a.notes})
        out("✓ EFFECTOR PROOF RELEASED — no finding may lean on it now.",
            f"  was  : {hit['name']} — {hit['known_state']}",
            f"  notes: {a.notes}",
            "→ re-prove it before the next finding that depends on it acting.")
        return

    if a.exit_code is not None:
        die("THE EXIT CODE IS NOT THE ASSERTION. Every effector failure this gate exists for "
            "returned success:\n"
            "  · `cliclick w:` — that is WAIT, not wheel. Exit 0, nothing scrolled, and the run's "
            "top finding was \"the app cannot scroll at all\".\n"
            "  · a fixed scroller nobody wired in. Exit 0 from the broken one.\n"
            "  · a click mis-aimed by a hand-done conversion. Exit 0, into empty background.\n"
            "A return code reports that a COMMAND RAN, never that the WORLD MOVED. Prove it the only "
            "way that cannot be faked:\n"
            '  game_loop effector --prove <name> --known-state ".." --before <capture> '
            "--observed <capture>")

    if not a.prove or not a.known_state or not a.before or not a.observed:
        die("effector --prove needs --known-state, --before, and --observed.\n"
            "  --prove       : the verb you are about to depend on (scroll, click, type)\n"
            "  --known-state : a state whose RESPONSE YOU ALREADY KNOW — a view you know overflows, "
            "a control you know is live, a field you can read back\n"
            "  --before      : the capture taken BEFORE you acted\n"
            "  --observed    : the capture taken AFTER (this is the contract's --observed: the "
            "change, not the exit code)\n"
            "  --expect      : optional text that must appear in --observed and NOT in --before — "
            "turns 'something changed' into 'the asserted thing changed'\n"
            "  --scale       : optional coordinate factor; `--aim` then converts so you never do\n"
            "One capture is not a proof: a result with nothing to compare it against is a photograph "
            "of an assumption. The pair is the whole check, and this tool does the comparing.")

    real = {}
    for role, given in (("before", a.before), ("observed", a.observed)):
        r = resolve_read(given)
        if r is None:
            die(f"--{role} does not resolve to a real, non-empty file: {given}\n"
                "Capture the state to a file and name that file. An empty capture is the shape a "
                "dead screen-grab arrives in, so it is refused here rather than compared.")
        real[role] = r

    digest = {role: _digest(p) for role, p in real.items()}
    if digest["before"] == digest["observed"]:
        die(f"REFUSED — the before and after captures are IDENTICAL ({digest['before']}).\n"
            f"  before  : {real['before']}\n"
            f"  observed: {real['observed']}\n"
            "Whatever ran, the world did not move, and that is exactly the failure this verb exists "
            "to catch: an unchanged screen read as THE APP'S behaviour and written up as a defect. "
            "Before you blame the app, check the verb — is it the verb you think it is (`w:` is "
            "wait, not wheel), is the fixed one actually wired in, is the aim converted, is the "
            "display even awake?")

    if a.expect:
        body = {role: _scan_text(p) for role, p in real.items()}
        for role in ("before", "observed"):
            if body[role] is None:
                die(f"--expect reads TEXT and the {role} capture is too large to grep "
                    f"(> {EFFECTOR_SCAN_MAX >> 20}MB).\n"
                    "Anchor --expect to a text artifact — a UI dump, an accessibility read-back, the "
                    "field's own value — not a full-resolution image. Or drop --expect and take the "
                    "weaker UNCHECKED proof knowingly.")
        if a.expect not in body["observed"]:
            die(f"--expect {a.expect!r} does not appear in the observed capture.\n"
                "The pair differs, so SOMETHING changed — but not the thing you asserted. That gap "
                "is where a false finding is born.")
        if a.expect in body["before"]:
            die(f"--expect {a.expect!r} was ALREADY in the before capture.\n"
                "Then it is not evidence the act did anything; it is evidence it was already true. "
                "Name something the act BRINGS INTO BEING.")

    proof = {"name": a.prove, "known_state": a.known_state,
             "before": real["before"], "observed": real["observed"],
             "before_digest": digest["before"], "observed_digest": digest["observed"],
             "expect": a.expect, "scale": a.scale, "at": now()}
    effs = [e for e in effs if e.get("name") != a.prove] + [proof]   # a fresh proof supersedes
    s["effectors"] = effs
    save(s)
    logline({"kind": "effector_proof", **{k: proof[k] for k in
                                          ("name", "known_state", "before", "observed",
                                           "before_digest", "observed_digest", "expect", "scale")}})
    out(*fire_triggers(s, "proved", {"event": "proved", "verb": "effector",
                                     "what": proof.get("name"),
                                     "artifact": [proof.get("known_state")],
                                     "project": config().get("project_name"),
                                     "session": SESSION}))
    sym, note = effector_state(proof)
    out(f"{sym} EFFECTOR PROVED — {a.prove} actually acts. Findings may now lean on it.",
        f"  known state: {a.known_state}",
        f"  before     : {_short(real['before'])}  [{digest['before']}]",
        f"  observed   : {_short(real['observed'])}  [{digest['observed']}]",
        f"  verdict    : {note}",
        *([f"  coordinates: scale {a.scale} — `game_loop effector --aim {a.prove} --at X,Y` does the "
           "conversion. Do not multiply by hand; that is failure 3."] if a.scale else []),
        '→ cite it: game_loop claim --assert ".." --effector ' + a.prove,
        "→ WHAT THIS DOES NOT CATCH: that you proved the RIGHT effector, or that it still acts now — "
        "a proof is point-in-time and the display can sleep after it. Re-prove when the environment "
        "could have moved.")
# ── instruments ──────────────────────────────────────────────────────────────────────────────────
#
# An instrument is A TEST WHOSE SUBJECT IS REALITY. This project already holds that a test which
# cannot fail certifies the defect instead of catching it; a number admitted as evidence without
# controls is that same failure one layer out — and it does not fail quietly, it MANUFACTURES
# findings. `claim --read` cannot help here: every one of these incidents was run by an agent who
# could have cited a real file the whole time. Four refusals, four logged failures:
#
#   #14  A reading is a DELTA scoped to the interaction, never a lifetime total. A snapshot said 90%
#        of one component's operations returned short (157839 of 176001) — read as a rate that is a
#        catastrophic root cause, and it became the leading hypothesis. Deltas across the actual
#        interaction, same build, minutes later: ZERO in thirty trials. Every one of those had
#        accrued while idle, where returning short is correct. Two endpoints is the STRUCTURAL rule,
#        because demanding them is what makes the other two enforceable rather than advisory.
#   #11  A metric needs a NULL control (sample it while the phenomenon is ABSENT — non-zero means it
#        measures something else: 4053 units of "damage" per 4000 units of deliberately doing
#        nothing) and a POSITIVE control (a metric that only ever reads zero is equally
#        untrustworthy; it earns trust by CATCHING a known-real event, not by reading clean). That
#        one flaw produced three separate false findings, one presented as 8-for-8 deterministic.
#   #13  An optimized proxy must declare the user-visible harm it stands for AND how it connects to
#        it, because a 43% reduction at p=0.037, n=250 was real, reproducible, correctly computed —
#        and measured on a counter that had decoupled from user-visible harm in exactly the regime
#        the fix created. So when the number moves, the connection is RE-CHECKED, not assumed.
#   #12  A SUM IS NOT A DISTRIBUTION. An aggregate hides its own shape, and a run optimizing against
#        one reads structure into a single outlier. 1066.7 units of damage against 0.0 looked like a
#        total elimination and was written up as a finding; one event of thirty carried 96% of it,
#        and that event was the first after a known state transition — an artifact already identified
#        and dismissed EARLIER IN THE SAME SESSION. Excluding it: 1.5 per event against 0, two
#        occurrences against zero. Nothing about the totals revealed this; only the per-event values
#        did, and the same event produced three findings before anyone printed them.
#
# WHERE A GATE NEEDS A COMPUTATION, THE TOOL DOES IT. The caller names the numbers they saw; deltas,
# percentages and the dominance share are computed here. Arithmetic handed to the caller is a defect
# generator — the author of the sibling issue that says so got a coordinate conversion wrong on the
# very next run.
#
# STATE IS PER SESSION, like pins and deliberately unlike the ruled-out list. A refutation is
# durable knowledge about the CHECKOUT, so it lives in the shared log; a control is a MEASUREMENT
# taken in one run's regime, and a control inherited by a later session is precisely the "assumed to
# have survived the change" failure #13 is about. The READINGS still go to the shared log, where
# anyone can reproduce them — that is #14's own stated side benefit.

# INV6, printed by the guard itself: silence from a guard is not evidence of safety.
INSTRUMENT_MISSES = [
    "what these controls do NOT catch: whether this is the RIGHT metric. They say the chosen",
    "number is CONTROLLED — none of them can say it is the number that matters. #13's counter was",
    "structurally blind to a second fault mechanism, so the whole investigation searched one way.",
]

# INV6 again, for the shape check specifically: it holds you to LOOKING, not to being right.
DISTRIBUTION_MISSES = [
    "what the shape check does NOT catch: whether what remains is an effect at all. It holds you",
    "to reading the distribution before stating one — sample size, variance, and whether the events",
    "are even independent stay yours, and a perfectly flat distribution can be perfectly flat noise.",
]

# The share of a total one event may carry before the aggregate stops describing anything but that
# event. A half is deliberately generous — the incident's dominating event carried 96% — because a
# threshold that fires on ordinary skew is a threshold that gets switched off, and a guard disabled
# once is disabled forever (INV5).
DOMINANCE_SHARE = 0.5

# What an effect can be DERIVED from and still be a claim about a set of events rather than an
# observation. All three collapse a distribution into one number, and all three hide the same thing.
AGGREGATE_KINDS = {"sum": "sum", "mean": "mean", "pct": "percentage"}


def _num(x):
    """Format a reading for humans: an integral value prints as an integer, never as 4053.0."""
    return str(int(x)) if float(x).is_integer() else f"{x:g}"


def _scalar(x):
    """Normalize a parsed number for state and the log, so a counter reads back the way it read."""
    return int(x) if float(x).is_integer() else float(x)


def parse_number(label, text):
    try:
        return float(text)
    except (TypeError, ValueError):
        die(f"{label} must be a number, not {text!r} — paste what the counter actually read.")


def control_reading(flag, text):
    """A control is a reading too: `before,after`, with the subtraction done HERE.

    #14 applies to CONTROLS as hard as to the measurement. A control handed over as one absolute
    value is a lifetime total wearing the costume of a control, and it would smuggle the exact
    confound the control exists to catch back in through the gate.
    """
    parts = [p.strip() for p in (text or "").split(",") if p.strip()]
    if len(parts) != 2:
        die(f"{flag} takes TWO endpoint readings — before,after — not one absolute value: {text!r}\n"
            "A reading is a delta scoped to the sample, and that holds for a control too:\n"
            f"  {flag} 0,0   the counter before and after, sampled while the phenomenon was ABSENT\n"
            "The tool subtracts them. Never hand a gate a number you worked out yourself.")
    b, a = (parse_number(flag, p) for p in parts)
    return {"before": _scalar(b), "after": _scalar(a), "delta": _scalar(a - b)}


def parse_events(text):
    """Parse a per-event distribution — commas or whitespace, garbage refused, never a traceback.

    Two values is the floor. A "distribution" of one event is the total wearing a different hat: it
    satisfies the gate while showing nothing, which is precisely the failure this gate exists for.
    """
    parts = (text or "").replace(",", " ").split()
    if len(parts) < 2:
        die("--events takes the per-event values behind the total — at least two of them, not "
            f"{text!r}\n"
            "One value is the total wearing a different hat. Paste what each event read, in event\n"
            "order, zeros included, separated by commas or spaces:\n"
            '  --events "1024, 0, 0, ... , 42.7"')
    vals = []
    for i, p in enumerate(parts, 1):
        try:
            v = float(p)
        except (TypeError, ValueError):
            v = None
        if v is None or v != v or v in (float("inf"), float("-inf")):
            die(f"event {i} of --events is not a finite number: {p!r}\n"
                "Paste the per-event values as the counter read them. A distribution the tool cannot\n"
                "parse is a distribution nobody checked, and that is the state this gate is about.")
        vals.append(_scalar(v))
    return vals


def dominance(values):
    """Which single event carries how much of the total — computed HERE, never taken from the caller.

    The share is measured against the total MAGNITUDE (Σ|v|). That is what "one event carries the
    aggregate" actually means, and it keeps a pair of opposite-signed events from cancelling into a
    near-zero denominator and reporting a share of 10000%. An all-zero distribution has no share to
    dominate, and dividing into one is how a gate produces a traceback instead of a refusal.
    """
    mass = [abs(v) for v in values]
    total = sum(mass)
    if not total:
        return None
    top = max(range(len(mass)), key=mass.__getitem__)
    return {"event": top + 1, "value": values[top], "share": mass[top] / total,
            "pct": 100.0 * mass[top] / total, "total": _scalar(total), "n": len(values)}


def without_event(values, n):
    """The shape that remains once event n is dropped — stated by the tool, not left to be worked out.

    This is the number the incident never printed. "1066.7 against 0.0" read as a total elimination;
    "1.5 per event across 29, one non-zero occurrence" ends the conversation instead of starting one.
    """
    rest = [v for i, v in enumerate(values, 1) if i != n]
    total = sum(abs(v) for v in rest)
    return {"n": len(rest), "total": _scalar(total), "nonzero": sum(1 for v in rest if v),
            "per_event": (total / len(rest)) if rest else 0.0}


def parse_event_index(text):
    """--exclude names an event NUMBER, the one the refusal printed. Bad input refuses, never throws."""
    try:
        return int(str(text).strip())
    except (TypeError, ValueError):
        die(f"--exclude takes the event NUMBER the refusal named, not {text!r}.\n"
            "The refusal prints it — `event 1 read 1024` — so excluding it is answering the refusal\n"
            "rather than guessing at it:  --exclude 1 --because \"..\"")


def events_preview(values, keep=8):
    """The per-event values, in event order, truncated so a thirty-event line stays readable."""
    head = ", ".join(_num(v) for v in values[:keep])
    return head + (f", … (+{len(values) - keep} more)" if len(values) > keep else "")


def instrument_by_name(s, name):
    return next((i for i in (s.get("instruments") or []) if i.get("name") == name), None)


def die_unadmitted(name):
    """One refusal for every verb that needs an admitted instrument, so the route in is always the
    same sentence."""
    die(f"instrument {name!r} was never admitted in this session.\n"
        "A number is not evidence until it is CONTROLLED: sampled while the phenomenon is ABSENT,\n"
        "sampled while a KNOWN-REAL event happens, and pointed at the harm a user would notice.\n"
        f'  game_loop instrument --register {name} --measures ".." --connects ".." \\\n'
        "                       --null <before,after> --positive <before,after>\n"
        "  " + "\n  ".join(INSTRUMENT_MISSES))


def metric_movement(inst):
    """Has the metric MOVED since its first reading here, and by how much — computed by the tool.

    "Moved" means the magnitude of the delta SHRANK. That is the direction a run optimizing the
    number is pushing it, and it is exactly when a proxy quietly stops standing for the harm: #13's
    counter tracked the harm in the regime it was validated in and stopped tracking it in the regime
    the fix created. The percentage is computed here for the same reason the delta is — a gate that
    asks the caller for a ratio is a gate that will eventually be handed a wrong one.
    """
    rs = inst.get("readings") or []
    if len(rs) < 2:
        return None
    first, latest = abs(rs[0].get("delta", 0)), abs(rs[-1].get("delta", 0))
    if not first or latest >= first:
        return None
    return {"pct": 100.0 * (first - latest) / first, "first": rs[0], "latest": rs[-1]}


def admit_distribution(inst, reading, aggregate, exclude, because):
    """A SUM IS NOT A DISTRIBUTION — the #12 gate, run at the point the effect is CLAIMED.

    The distribution attaches to the READING (`measure --events`) because the reading is the thing
    that has a shape: the per-event values are the decomposition of that delta and of no other, and a
    breakdown supplied at claim time could have come off a different measurement entirely. The
    REFUSAL lives here because the claim is what states an effect, and it is stating the effect that
    the incident got wrong. Same split as everything else in this family: `measure` records what was
    read, `claim` is where a reading has to earn a sentence.

    The share is computed HERE, from the values the caller pasted. Never accept a percentage somebody
    worked out by hand — the sibling issue that says so had its own author botch a conversion on the
    very next run.

    ONE exclusion, and then the gate is done: dropping the outlier from the incident's own numbers
    leaves 29 zeros and one 42.7, which is 100% dominance of the remainder. Re-checking the remainder
    would refuse forever, and a guard with no path through it is a guard that gets switched off
    (INV5). So the escape hatch is exactly one named event plus a stated reason, both on the record,
    and what remains is PRINTED rather than re-judged.
    """
    events = reading.get("events") or []
    if exclude is not None:
        if not events:
            die(f"--exclude {exclude} names an event in a per-event distribution, and the reading "
                f"behind this claim has none.\n"
                "There is nothing recorded to exclude FROM. Read the events out and record them with\n"
                "the measurement first:\n"
                f"  game_loop measure --instrument {inst['name']} --before <n> --after <n> "
                '--events "<v,v,v,..>"')
        if not 1 <= exclude <= len(events):
            die(f"--exclude {exclude} is not one of this reading's {len(events)} events "
                f"(they are numbered 1..{len(events)}).\n"
                "Exclude the event the refusal NAMED. Excluding a different one leaves the dominating\n"
                "event sitting in the total, which is the whole thing being checked.")
        if not because:
            die(f"--exclude {exclude} needs --because: WHY that event does not belong in the total.\n"
                f"  dropping : event {exclude} — {_num(events[exclude - 1])}\n"
                "An unrecorded exclusion is rediscovered. In the incident the dominating event was an\n"
                "artifact that had ALREADY been identified and dismissed earlier in the same session,\n"
                "and it went on to produce a third false finding because nothing carried the reason\n"
                "forward. The reason is the deliverable here, not the exclusion.\n"
                f'  game_loop claim --assert ".." --metric {inst["name"]} --exclude {exclude} '
                '--because "first event after a known state transition; artifact already ruled out"')
    if aggregate and not events:
        die(f"this effect is derived from a {AGGREGATE_KINDS[aggregate]}, and the reading behind it "
            "has no per-event breakdown.\n"
            f"  instrument : {inst['name']}\n"
            f"  reading    : {_num(reading['before'])} → {_num(reading['after'])} "
            f"(Δ {_num(reading['delta'])})\n"
            "A SUM IS NOT A DISTRIBUTION. An aggregate hides its own shape, and a run optimizing\n"
            "against one will read structure into a single outlier: 1066.7 units of damage against\n"
            "0.0 looked like a total elimination and was written up as a finding. One event of thirty\n"
            "carried 96% of it. Nothing about the totals revealed that — only printing the per-event\n"
            "values did, and by then the same artifact had produced three findings in one session.\n"
            "Read the events out and record them with the measurement:\n"
            f"  game_loop measure --instrument {inst['name']} --before {_num(reading['before'])} "
            f"--after {_num(reading['after'])} --events \"<v,v,v,..>\"\n"
            "  " + "\n  ".join(DISTRIBUTION_MISSES))
    if not events:
        return None
    dom = dominance(events)
    if dom and dom["share"] > DOMINANCE_SHARE and exclude != dom["event"]:
        rest = without_event(events, dom["event"])
        wrong = (f"  you dropped: event {exclude} — which is not the one carrying the total\n"
                 if exclude is not None else "")
        die("ONE EVENT CARRIES THE AGGREGATE — this is a total, not a distribution.\n"
            f"  instrument : {inst['name']}\n"
            f"  events     : {dom['n']}, totalling {_num(dom['total'])}\n"
            f"  dominated  : event {dom['event']} read {_num(dom['value'])} — {dom['pct']:.1f}% of "
            "the total (computed here; you were never asked for that share)\n"
            f"  without it : {_num(rest['total'])} across {rest['n']} events — "
            f"{rest['per_event']:.1f} per event, {rest['nonzero']} non-zero\n"
            + wrong +
            "A SUM IS NOT A DISTRIBUTION. In the incident 1066.7 units of damage against 0.0 read as\n"
            "a total elimination and was written up as a finding — one event of thirty carried 96%,\n"
            "and it was the FIRST event after a known state transition, an artifact already identified\n"
            "and dismissed EARLIER IN THE SAME SESSION. Corrected, it was 1.5 units per event against\n"
            "0, two occurrences against zero: no effect at that sample size. The same event produced\n"
            "three separate findings before anyone printed the breakdown.\n"
            "Explain that event, or exclude it WITH the reason — the reason is what stops it being\n"
            "rediscovered a fourth time:\n"
            f'  game_loop claim --assert ".." --metric {inst["name"]} --exclude {dom["event"]} '
            '--because "first event after a known state transition; artifact already ruled out"\n'
            "  " + "\n  ".join(DISTRIBUTION_MISSES))
    dist = {"events": len(events), "values": list(events),
            "top_event": dom["event"] if dom else None,
            "top_value": dom["value"] if dom else None,
            "share_pct": round(dom["pct"], 1) if dom else 0.0,
            "total": dom["total"] if dom else 0,
            "aggregate": aggregate}
    if exclude is not None:
        rest = without_event(events, exclude)
        dist["excluded"] = {"event": exclude, "value": events[exclude - 1], "reason": because}
        dist["without"] = rest
    return dist


def admit_metric(s, name, recheck, aggregate=None, exclude=None, because=None):
    """The admission gate for evidence that is a MEASUREMENT rather than a document.

    `claim --read` demands a real file because that is the check prose cannot satisfy for a
    document. For a number the equivalent is not one check but five, and each of them was
    satisfiable-while-completely-wrong in a real incident: the instrument is admitted (#11), it
    declared the harm it stands for (#13), it has been READ across an interaction rather than
    snapshotted (#14), if the number has since moved the connection to the harm has been re-checked
    (#13), and an effect derived from an aggregate has shown the distribution under it (#12).

    Admission itself is enforced at REGISTRATION, the way a pin's --expect must already hold: a
    control that is not green when it is recorded is a check nobody believes later. So by the time a
    claim reaches here, a registered instrument is a controlled one.
    """
    inst = instrument_by_name(s, name)
    if inst is None:
        die_unadmitted(name)
    rs = inst.get("readings") or []
    if not rs:
        die(f"instrument {name!r} is admitted but has never been READ across an interaction.\n"
            "A snapshot answers 'since process start', which is almost never the question. Read it\n"
            "around the thing you actually did, and cite that:\n"
            f"  game_loop measure --instrument {name} --before <n> --after <n>")
    # The shape is checked BEFORE the movement, because a delta that is really one event has no
    # movement worth re-checking: "43% smaller" off a dominated total describes the outlier, not the
    # metric, and asking what it stands for would be answering the wrong question carefully.
    dist = admit_distribution(inst, rs[-1], aggregate, exclude, because)
    mv = metric_movement(inst)
    # A re-check is counted against the readings it was made at, so it answers for THIS movement
    # only: the next reading that moves the number demands a fresh one. That is the difference
    # between re-checking the connection and having once said something about it.
    if mv and not recheck and inst.get("recheck_n") != len(rs):
        die("the metric MOVED, and its connection to the harm has not been re-checked.\n"
            f"  instrument : {name}\n"
            f"  first read : Δ {_num(mv['first']['delta'])}\n"
            f"  latest read: Δ {_num(mv['latest']['delta'])}  — {mv['pct']:.1f}% smaller "
            "(computed here; you were never asked for that ratio)\n"
            f"  stands for : {inst.get('measures')}\n"
            f"  connects by: {inst.get('connects')}\n"
            "A proxy tracks the harm in the regime it was VALIDATED in and can stop tracking it in "
            "the regime\nthe fix created — which is the regime the work just moved into. A real 43% "
            "reduction at\np=0.037, n=250 was reported on a counter that had already decoupled from "
            "what a user notices.\nSo re-state the connection for THIS regime instead of assuming it "
            "survived:\n"
            f'  game_loop claim --assert ".." --metric {name} --recheck "what would a user notice, '
            'and did you measure THAT or something correlated with it?"')
    return inst, rs[-1], mv, dist


def instruments_report(s):
    """The instruments block for `status`.

    The declared harm has to OUTLIVE the context that declared it, or "re-check the connection when
    the number moves" is a promise rather than a check — and promises are what compaction breaks.
    """
    insts = s.get("instruments") or []
    if not insts:
        return ['instruments: none admitted — `game_loop instrument --register <name> --measures '
                '".." --connects ".." --null <b,a> --positive <b,a>` before a number is evidence']
    lines = ["", "INSTRUMENTS — a number is evidence only once it is controlled:"]
    for i in insts:
        rs = i.get("readings") or []
        nul, pos = i.get("null") or {}, i.get("positive") or {}
        lines.append(f"  ✓ [{i.get('name')}] stands for: {i.get('measures')}")
        lines.append(f"      connects  : {i.get('connects')}")
        lines.append(f"      controls  : null Δ {_num(nul.get('delta', 0))} (phenomenon absent) · "
                     f"positive Δ {_num(pos.get('delta', 0))} (known-real event)")
        if rs:
            last = rs[-1]
            lines.append(f"      readings  : {len(rs)} · latest {_num(last['before'])} → "
                         f"{_num(last['after'])} (Δ {_num(last['delta'])})")
            # The shape has to outlive the context that read it for the same reason the harm does:
            # the incident's outlier was already known and dismissed, and got rediscovered anyway.
            if (ev := last.get("events")):
                dom = dominance(ev)
                lines.append(f"      shape     : {len(ev)} events" + (
                    f" · event {dom['event']} carries {dom['pct']:.1f}%" if dom
                    else " · every one of them zero"))
            if (ex := last.get("excluded")):
                lines.append(f"      excluded  : event {ex['event']} ({_num(ex['value'])}) — "
                             f"{ex['reason']}")
        else:
            lines.append("      readings  : none yet — game_loop measure --instrument "
                         f"{i.get('name')} --before <n> --after <n>")
        mv = metric_movement(i)
        if mv and i.get("recheck_n") != len(rs):
            lines.append(f"      ⚠ MOVED {mv['pct']:.1f}% since the first reading — the connection "
                         "to the harm is UNCHECKED in this regime")
        elif i.get("recheck"):
            lines.append(f"      re-checked: {i['recheck']['text']}")
    lines.append("  → " + INSTRUMENT_MISSES[0])
    lines += ["    " + l for l in INSTRUMENT_MISSES[1:]]
    return lines


def cmd_instrument(s, a):
    """Admit (or list, or retire) a metric as evidence, WITH the controls that make it one.

    The controls are not paperwork, they are the payload. "the damage counter dropped 43%" invites a
    conclusion; "the damage counter reads 4053 while nothing is happening" ends one. Both controls
    are read as deltas, like every other reading, and this command does the subtraction.

    A name is admitted ONCE. Re-registering silently would let a run that just had a claim refused
    re-control the same number until the gate opened — so re-controlling goes through --release, and
    is on the record.
    """
    insts = list(s.get("instruments") or [])   # copy: never mutate the module-level DEFAULT_STATE

    if a.list:
        if not insts:
            out("no instruments admitted.")
            return
        out(*instruments_report(s)[1:])
        return

    if a.release:
        hit = instrument_by_name(s, a.release)
        if hit is None:
            die_unadmitted(a.release)
        if not a.notes:
            die("instrument --release needs --notes: say why this number is no longer trusted.\n"
                f"  retiring : [{hit['name']}] {hit.get('measures')}\n"
                "An instrument is retired because a control went bad, the harm moved, or a corrected "
                "one\nreplaced it — and the next run needs to know which. An unexplained retirement "
                "is the\ndecoupled proxy all over again, minus the evidence.")
        insts.remove(hit)
        s["instruments"] = insts
        save(s)
        logline({"kind": "instrument_release", "name": hit["name"],
                 "measures": hit.get("measures"), "notes": a.notes})
        out("✓ INSTRUMENT RETIRED — it no longer backs a claim.",
            f"  was      : [{hit['name']}] {hit.get('measures')}",
            f"  notes    : {a.notes}",
            "→ its readings stay in the log; what changed is that they no longer admit a claim.")
        return

    if not a.register:
        die("instrument needs --register <name> (or --list / --release <name>).\n"
            "The name is what a claim later cites: game_loop claim --assert \"..\" --metric <name>")
    if not a.measures:
        die("--measures is required: the USER-VISIBLE harm this number stands for.\n"
            "A proxy that never states its referent cannot be checked against it later — and a\n"
            "statistically significant improvement on an unstated proxy is more dangerous than a\n"
            "null result, because it feels like progress and closes the investigation.\n"
            '  --measures "dropouts the listener actually hears", not "underrun events"')
    if not a.connects:
        die("--connects is required: HOW the number reaches that harm.\n"
            "Stating the mechanism is what makes it RE-CHECKABLE when the number moves. Without it,\n"
            "'the metric still tracks the harm' has nothing to be false about.\n"
            '  --connects "each underrun empties the buffer, and an empty buffer plays as silence"')
    if not a.null:
        die("this instrument has no null control (--null <before,after>).\n"
            "Sample the metric while the phenomenon is NOT happening. Non-zero means it is not\n"
            "measuring what you think: one counter read 4053 units of 'damage' per 4000 units of\n"
            "deliberately doing nothing, and that single flaw produced three false findings.")
    if not a.positive:
        die("this instrument has no positive control (--positive <before,after>).\n"
            "A metric that only ever reads zero is exactly as untrustworthy as one that reads high.\n"
            "It earns trust by CATCHING a known-real event, not by reading clean. Cause the thing\n"
            "on purpose, read the counter around it, and record what it saw.")
    if instrument_by_name(s, a.register):
        die(f"instrument {a.register!r} is already admitted in this session.\n"
            "Re-registering would let a refused claim quietly re-control the number until the gate\n"
            "opened. Retire it first, with the reason:\n"
            f'  game_loop instrument --release {a.register} --notes ".."')
    nul = control_reading("--null", a.null)
    pos = control_reading("--positive", a.positive)
    if nul["delta"] != 0:
        die(f"the null control is NOT zero: Δ {_num(nul['delta'])} "
            f"({_num(nul['before'])} → {_num(nul['after'])}) while the phenomenon was ABSENT.\n"
            "Non-zero is the exact tell that this metric measures something other than the thing\n"
            "you are asking about, and it is NOT a detail to pass silently: a counter reading 4053\n"
            "per 4000 units of doing nothing produced three separate false findings, one of them\n"
            "presented as 8-for-8 deterministic.\n"
            "Fix the instrument (scope it to the activity, subtract the idle baseline, or pick a\n"
            "different counter) and register the corrected one. Do not proceed on this number.")
    if pos["delta"] == 0:
        die(f"the positive control never moved: Δ 0 "
            f"({_num(pos['before'])} → {_num(pos['after'])}) across a KNOWN-REAL event.\n"
            "A metric that only ever reads zero certifies whatever it is pointed at. It has not\n"
            "shown it can see the thing, so a clean reading from it means nothing. Cause the event\n"
            "for real, confirm the counter notices, then register it.")
    inst = {"name": a.register, "measures": a.measures, "connects": a.connects,
            "null": nul, "positive": pos, "readings": [], "at": now()}
    insts.append(inst)
    s["instruments"] = insts
    save(s)
    logline({"kind": "instrument", "name": inst["name"], "measures": inst["measures"],
             "connects": inst["connects"], "null": nul, "positive": pos})
    out(f"✓ INSTRUMENT ADMITTED [{inst['name']}] — controlled, so its readings can back a claim.",
        f"  stands for : {inst['measures']}",
        f"  connects by: {inst['connects']}",
        f"  null       : {_num(nul['before'])} → {_num(nul['after'])} (Δ 0 — reads nothing while "
        "the phenomenon is absent)",
        f"  positive   : {_num(pos['before'])} → {_num(pos['after'])} (Δ {_num(pos['delta'])} — it "
        "caught a known-real event)",
        f'→ read it as a DELTA: game_loop measure --instrument {inst["name"]} --before <n> --after <n>',
        "  " + "\n  ".join(INSTRUMENT_MISSES))


def cmd_measure(s, a):
    """Record ONE reading of an admitted instrument: two endpoints, delta computed here.

    Two endpoints rather than one absolute value is the whole verb. A lifetime counter answers
    "since process start", which is almost never the question, and it will be dominated by whichever
    regime the process spent its wall clock in — usually idle, for anything being interactively
    driven. It also has the side benefit the issue names: the measurement becomes reproducible by
    anyone reading the log later, because both endpoints are in it.

    `--events` attaches the SHAPE of that delta — the per-event values it is the total of. It is
    optional here and refuses nothing, because `measure` records what was read; the refusal belongs
    to `claim`, which is where an effect gets stated. What this command does do is PRINT the shape,
    since printing the per-event values is the entire thing nobody did in the incident.
    """
    if not a.instrument:
        die("measure needs --instrument <name> --before <n> --after <n>.")
    inst = instrument_by_name(s, a.instrument)
    if inst is None:
        die_unadmitted(a.instrument)
    if a.before is None or a.after is None:
        die("a reading is TWO endpoints, not one absolute value — --before AND --after.\n"
            "A lifetime total blends the regime under test with every idle second before it. One\n"
            "read 157839 of 176001 operations short (90%, and an obvious root cause); deltas across\n"
            "the actual interaction showed ZERO in thirty trials, because the rest had accrued while\n"
            "idle, where the behaviour is correct.\n"
            f"  game_loop measure --instrument {a.instrument} --before <n> --after <n>")
    b = parse_number("--before", a.before)
    af = parse_number("--after", a.after)
    events = parse_events(a.events) if a.events else None
    dom = dominance(events) if events else None
    reading = {"before": _scalar(b), "after": _scalar(af), "delta": _scalar(af - b),
               "events": events, "notes": a.notes, "at": now()}
    insts = list(s.get("instruments") or [])   # copy: never mutate the module-level DEFAULT_STATE
    inst = dict(inst, readings=[*(inst.get("readings") or []), reading])
    insts[[i.get("name") for i in insts].index(inst["name"])] = inst
    s["instruments"] = insts
    save(s)
    logline({"kind": "measure", "instrument": inst["name"], "measures": inst.get("measures"),
             "before": reading["before"], "after": reading["after"], "delta": reading["delta"],
             "events": events, "dominance": dom, "notes": a.notes})
    msg = [f"✓ READING recorded [{inst['name']}] — a delta scoped to the interaction, not a total.",
           f"  before  : {_num(reading['before'])}",
           f"  after   : {_num(reading['after'])}",
           f"  Δ {_num(reading['delta'])}   ← computed here, from your two endpoints"]
    if a.notes:
        msg.append(f"  over    : {a.notes}")
    if events:
        msg.append(f"  events  : {len(events)} — {events_preview(events)}")
        if dom is None:
            msg.append("  shape   : every event read zero — no event carries this total")
        else:
            msg.append(f"  shape   : event {dom['event']} carries {dom['pct']:.1f}% of "
                       f"{_num(dom['total'])}   ← computed here, never taken from you")
        if dom and dom["share"] > DOMINANCE_SHARE:
            rest = without_event(events, dom["event"])
            msg.append(f"⚠ ONE EVENT CARRIES {dom['pct']:.1f}% OF THIS TOTAL. Without event "
                       f"{dom['event']}: {_num(rest['total'])} across {rest['n']} events "
                       f"({rest['per_event']:.1f} per event, {rest['nonzero']} non-zero).\n"
                       "  A claim from this total is refused until that event is explained, or "
                       "excluded WITH a reason.")
    mv = metric_movement(inst)
    if mv:
        msg.append(f"⚠ the metric MOVED {mv['pct']:.1f}% since its first reading here. Before citing "
                   "it,\n  re-check that it still stands for: " + str(inst.get("measures")) +
                   '\n  game_loop claim --assert ".." --metric ' + inst["name"] + ' --recheck ".."')
    out(*msg)


# ── fixes: a verified DIAGNOSIS is not a verified FIX ────────────────────────────────────────────
#
# `effector` proves a verb ACTS. This proves a FIX HOLDS — and they are different claims, which is
# exactly what the observed failure (#27) mistook. A bug was diagnosed exhaustively: the wrong
# behaviour reproduced, the root cause read at the real source, the mechanism understood. Then a fix
# was written and shipped as a public PR whose produced code DID NOT COMPILE. Three signals were
# green and every one answered a question nobody had asked:
#
#   · the code generator's own tests compared its output to a FIXTURE — which the fix never touched;
#   · the analyzer ran on the GENERATOR, not on the code the generator emits;
#   · the diagnosis's reproduction still reproduced — it was never a test of the fix at all.
#
#     EFFORT SPENT VERIFYING THE DIAGNOSIS MANUFACTURES FALSE CONFIDENCE ABOUT THE FIX.
#
# A diagnosis is proven by REPRODUCING THE BAD BEHAVIOUR. A fix is proven by EXERCISING WHAT THE FIX
# PRODUCES against the outcome it promises — compile the generated code, run the patched path, watch
# the bad behaviour come back good. The cruelty is that the two feel like one thing, and the ratio
# runs the wrong way: the more thoroughly the diagnosis was verified, the more convincing the
# unverified fix feels.
#
# .game_loop/verify.yaml's header already argues the near half of this — "if a change has an OUTPUT
# that is not the thing you edited, no verification counts until the output's real consumer has
# consumed it ... three green signals, all vacuous, none lying." That is a rule about WHAT TO RUN
# while the work is open. This is the same rule at HANDBACK, where nothing runs any more and all
# that is left is what the run says it did.
#
# THE KEYSTONE is `effector`'s, because the shape is identical — the previously-bad behaviour coming
# back good IS a before/after pair:
#
#     TWO REAL ARTIFACTS, CAPTURED EITHER SIDE OF THE FIX, THAT **THIS TOOL** COMPARES.
#
# Plus one refusal that belongs to this verb alone: THE PROOF MAY NOT BE THE REPRO. The diagnosis's
# artifact is named at proof time so the tool can hand it back — if one artifact can satisfy both
# claims, the gate is already defeated, because that identity IS the bug. A repro that still
# reproduces is the diagnosis holding, not the fix.
#
# NOT AN EFFECTOR, and deliberately its own small registry rather than a mode on that one: `claim
# --effector <name>` admits findings on the strength of a verb having acted, and `status` prints
# "EFFECTORS — proved to actually act. A finding may lean on these and no others". A fix proof
# filed there would make both of those sentences false. The MACHINERY is shared (resolve_read,
# _digest, _scan_text, the same UNCHECKED-never-✓ posture); the meaning is not.


def fix_proof(s, name):
    return next((f for f in (s.get("fixes") or []) if f.get("name") == name), None)


def fix_state(f):
    """(symbol, note) for one fix proof — can its evidence still be inspected?

    WHAT THIS DOES NOT CATCH, said plainly, and it is `effector_state`'s admission again: a proof is
    a POINT-IN-TIME fact about the working tree. Nothing here expires one, so a fix proved and then
    edited over still reads ✓. The age is printed rather than hidden, because the check is
    CHECKED-rung and the staleness is only VISIBLE-rung.
    """
    if resolve_read(f.get("produces") or "") is None:
        return "✗", f"MISSING — the fix's own output is gone from {f.get('produces')}"
    for role in ("before", "observed"):
        real = resolve_read(f.get(role) or "")
        if real is None:
            return "✗", f"MISSING — the {role} verdict is gone from {f.get(role)}"
        if _digest(real) != f.get(role + "_digest"):
            return "?", (f"unverifiable — the {role} verdict at that path is no longer the one that "
                         "was compared (overwritten by a later run); the pair is in the log")
    if not f.get("expect"):
        return "•", ("holds (UNCHECKED — no --expect, so the pair only proves the verdict MOVED, "
                     "not that it moved to the promised outcome)")
    return "✓", f"holds — the verdict moved to what the fix promised ({f['expect']!r} appeared)"


def fixes_report(s):
    """The fixes block for `status` — what a handback is about to call done, and whether it holds."""
    fixes = s.get("fixes") or []
    if not fixes:
        return ['fixes: none proved — `game_loop fix --prove <name> --promises ".." --produces '
                "<the fix's own output> --diagnosis <the repro> --before <verdict> --observed "
                "<verdict>` before reporting one done"]
    lines = ["", "FIXES — proved by exercising what the fix PRODUCES, not by re-running the repro:"]
    for f in fixes:
        sym, note = fix_state(f)
        lines.append(f"  {sym} {f.get('name')} — proved {f.get('at')}")
        lines.append(f"      promises : {f.get('promises')}")
        lines.append(f"      produces : {_short(f.get('produces') or '')}")
        lines.append(f"      verdict  : {_short(f.get('before') or '')} → "
                     f"{_short(f.get('observed') or '')} ({note})")
        lines.append(f"      diagnosis: {_short(f.get('diagnosis') or '')} — the repro, kept "
                     "separate on purpose")
    lines.append("  → a fix proof is point-in-time: re-prove after the tree moves under it.")
    return lines


def cmd_fix(s, a):
    """Prove (or list, or release) that a FIX HOLDS, by exercising what the fix produces.

    A proof names the OUTCOME the fix promises, the fix's OWN OUTPUT, the diagnosis's repro, and the
    real consumer's verdict from either side of the change. The tool compares the verdicts and
    refuses the repro back. Nothing the caller says about it working is load-bearing; the files are.
    Same spirit as `pin --expect`, which must already hold at registration, and as `effector`, whose
    pair the caller never gets to summarize: a proof taken on faith is a proof nobody will believe.

    SESSION-SCOPED, like effector proofs and unlike the RULED-OUT list. A refutation is knowledge
    about the CHECKOUT; a fix proof is a fact about the working tree AT ONE MOMENT, and the tree
    moves — a later session inheriting "that is proved" about code it has since rewritten is the
    original failure in a fresh coat. Every proof still APPENDS to the shared log, with all three
    digests, so the audit trail stays global even though the admission is not.
    """
    fixes = list(s.get("fixes") or [])   # copy: never mutate the module-level DEFAULT_STATE list

    if a.list:
        if not fixes:
            out("no fixes proved in this session.")
            return
        out(*fixes_report(s)[1:])
        return

    if a.release:
        hit = fix_proof(s, a.release)
        if not hit:
            die(f"no proved fix named {a.release!r} in this session. `game_loop fix --list` shows "
                "them.")
        if not a.notes:
            die("fix --release needs --notes: say why this proof no longer stands.\n"
                f"  releasing: {hit['name']} (proved {hit['at']} — promised: {hit['promises']})\n"
                "A handback stopped warning about this fix because of that proof, so retiring it is "
                "a stated decision, not a tidy-up.")
        fixes.remove(hit)
        s["fixes"] = fixes
        save(s)
        logline({"kind": "fix_release", "name": hit["name"], "notes": a.notes})
        out("✓ FIX PROOF RELEASED — this run no longer claims that fix holds.",
            f"  was  : {hit['name']} — promised: {hit['promises']}",
            f"  notes: {a.notes}",
            "→ re-prove it before reporting the fix done again.")
        return

    if not a.prove or not a.promises or not a.produces or not a.diagnosis or not a.before \
            or not a.observed:
        die("fix --prove needs --promises, --produces, --diagnosis, --before and --observed.\n"
            "  --prove     : the fix you are about to report as done\n"
            "  --promises  : the OUTCOME it promises — what someone gets now that they did not\n"
            "  --produces  : the fix's OWN output — the generated file, the rendered template, the\n"
            "                patched artifact. NOT the source you edited: a generator's own test\n"
            "                comparing emitted text to emitted text is the vacuous green signal.\n"
            "  --diagnosis : the artifact that proved the BUG — the repro. Named here so this tool\n"
            "                can refuse to take it back as proof of the fix.\n"
            "  --before    : the REAL consumer's verdict on the unfixed output (the failing compile,\n"
            "                the wrong render, the bad run)\n"
            "  --observed  : that SAME consumer's verdict on the fixed output\n"
            "  --expect    : optional text the fixed verdict brings into being — turns 'the verdict\n"
            "                moved' into 'it moved to the outcome that was promised'\n"
            "A diagnosis is proven by reproducing the bad behaviour; a fix is proven by that\n"
            "behaviour coming back good. Reproducing it once more is the FIRST claim, again.")

    real = {}
    for role, given in (("produces", a.produces), ("diagnosis", a.diagnosis),
                        ("before", a.before), ("observed", a.observed)):
        r = resolve_read(given)
        if r is None:
            die(f"--{role} does not resolve to a real, non-empty file: {given}\n"
                "Name the file on disk. A fix reported from four descriptions of files is the "
                "report this verb exists to stop.")
        real[role] = r
    digest = {role: _digest(p) for role, p in real.items()}

    # The fix's output is not its diagnosis. Naming the repro as the thing the fix emits is the
    # collapse this verb is named after, arriving one flag early.
    if real["produces"] == real["diagnosis"]:
        die("REFUSED — --produces and --diagnosis are the same file.\n"
            f"  both: {real['produces']}\n"
            "The repro is what proved the BUG. The fix's output is what has to be exercised now. "
            "If they are one file, nothing here has been asked the second question.")

    # THE refusal that belongs to this verb. If the diagnosis's repro can stand as proof of the fix,
    # the gate is defeated — and it is defeated in exactly the way #27 describes, by a run that
    # verified the diagnosis so thoroughly it stopped noticing the fix was unverified.
    if real["observed"] == real["diagnosis"] or digest["observed"] == digest["diagnosis"]:
        die("REFUSED — the observed verdict IS the diagnosis's repro"
            + (" (byte-identical)." if real["observed"] != real["diagnosis"] else ".") + "\n"
            f"  diagnosis: {real['diagnosis']}\n"
            f"  observed : {real['observed']}\n"
            "That artifact proves the BUG, and it proved it before the fix existed. Handing it back "
            "here proves the diagnosis a second time — the claim you already had. A fix is proved by "
            "the previously-bad behaviour COMING BACK GOOD, so --observed must be what the fixed "
            "artifact does now, produced by the real consumer of the fix's output.")

    if digest["before"] == digest["observed"]:
        die(f"REFUSED — the before and after verdicts are IDENTICAL ({digest['before']}).\n"
            f"  before  : {real['before']}\n"
            f"  observed: {real['observed']}\n"
            "The consumer says exactly what it said unfixed. That is the shape a repro that STILL "
            "REPRODUCES arrives in, and it is the failure this verb exists for: the generated code "
            "still did not compile, and three green checks pointed elsewhere. Before you report the "
            "fix, check what you exercised — is it the fix's OUTPUT or the source you edited, is it "
            "the REAL consumer or the generator's own test, was the output regenerated at all?")

    if a.expect:
        body = {role: _scan_text(real[role]) for role in ("before", "observed")}
        for role in ("before", "observed"):
            if body[role] is None:
                die(f"--expect reads TEXT and the {role} verdict is too large to grep "
                    f"(> {EFFECTOR_SCAN_MAX >> 20}MB).\n"
                    "Anchor --expect to the consumer's own output — the compiler's line, the test "
                    "name, the rendered field. Or drop --expect and take the weaker UNCHECKED proof "
                    "knowingly.")
        if a.expect not in body["observed"]:
            die(f"--expect {a.expect!r} does not appear in the observed verdict.\n"
                "The verdicts differ, so SOMETHING moved — but not to the outcome you promised. A "
                "compile that fails differently is not a compile that passes.")
        if a.expect in body["before"]:
            die(f"--expect {a.expect!r} was ALREADY in the before verdict.\n"
                "Then it is not evidence the fix did anything; it is evidence it was already true. "
                "Name what the FIX brings into being.")

    proof = {"name": a.prove, "promises": a.promises, "produces": real["produces"],
             "diagnosis": real["diagnosis"], "before": real["before"], "observed": real["observed"],
             "produces_digest": digest["produces"], "diagnosis_digest": digest["diagnosis"],
             "before_digest": digest["before"], "observed_digest": digest["observed"],
             "expect": a.expect, "at": now()}
    fixes = [f for f in fixes if f.get("name") != a.prove] + [proof]   # a fresh proof supersedes
    s["fixes"] = fixes
    save(s)
    logline({"kind": "fix_proof", **{k: proof[k] for k in
                                     ("name", "promises", "produces", "diagnosis", "before",
                                      "observed", "produces_digest", "diagnosis_digest",
                                      "before_digest", "observed_digest", "expect")}})
    out(*fire_triggers(s, "proved", {"event": "proved", "verb": "fix",
                                     "what": proof.get("name"),
                                     "artifact": [proof.get("produces")],
                                     "project": config().get("project_name"),
                                     "session": SESSION}))
    s["work_since_stepback"] = s.get("work_since_stepback", 0) + 1
    save(s)          # this verb had no other reason to persist state; without it the count is lost
    sym, note = fix_state(proof)
    out(f"{sym} FIX PROVED — {a.prove} was exercised through what it produces.",
        f"  promises : {a.promises}",
        f"  produces : {_short(real['produces'])}  [{digest['produces']}]",
        f"  before   : {_short(real['before'])}  [{digest['before']}]",
        f"  observed : {_short(real['observed'])}  [{digest['observed']}]",
        f"  diagnosis: {_short(real['diagnosis'])}  [{digest['diagnosis']}] — the repro, and NOT "
        "what proved this",
        f"  verdict  : {note}",
        "→ the handback stops warning about an unproved fix while this stands.",
        "→ WHAT THIS DOES NOT CATCH: that --produces was really regenerated from what you edited; "
        "that the thing which wrote --observed is the REAL consumer rather than another stand-in for "
        "it; or that the outcome you promised is the one the reporter wanted. It holds you to a "
        "moved verdict on the fix's own output — not to the right fix.")


# Handback notes that read like a shipped fix. Same posture as _HANDBACK_ESCALATORS and
# _CATEGORY_TELLS, and for the same reason: a heuristic on prose decides what gets SAID, never what
# gets refused (INV1 — enforcement that depends on reading English is not enforcement). Deliberately
# generous: over-firing costs one paragraph, under-firing costs the afternoon somebody spends on top
# of a fix that never held.
_FIX_TELLS = re.compile(
    r"\b(fix(?:ed|es|ing)?|fixup|bug ?fix|hotfix|patch(?:ed|es|ing)?|repair\w*|"
    r"corrected|root[- ]?caused?|regression|"
    r"(?:no longer|stopped|doesn't|does not) (?:crash\w*|fail\w*|break\w*|hang\w*))\b", re.I)


def fix_warning(s, notes=None):
    """The handback line for a fix nobody exercised, or None. Logs when it fires, so how often a run
    reports a fix it never proved is a fact in log.jsonl rather than a hunch (INV4 wants the entry
    before anyone argues this should become a block — and INV5 says it must not)."""
    if not notes or not (m := _FIX_TELLS.search(notes)):
        return None
    if s.get("fixes"):
        return None
    logline({"kind": "fix_unproved", "tell": m.group(0), "notes": notes})
    return "\n".join([
        f"⚠ FIX CLAIMED, NOT PROVED — these notes report a fix (\"{m.group(0)}\") and nothing in "
        "this run has\n  exercised what that fix PRODUCES.",
        "  A verified diagnosis is not a verified fix: the diagnosis is proven by reproducing the "
        "bad\n  behaviour, the fix by running the fixed artifact against the outcome it promises. "
        "The worst\n  version of this shipped a PR whose generated code did not compile, under three "
        "green checks —\n  a generator test against an unchanged fixture, an analyzer pointed at the "
        "generator instead of\n  what it generates, and a repro that still reproduced. None of them "
        "was a test of the fix.",
        "  Not a block; some fixes are proved elsewhere and some notes just say \"fixed\". If this "
        "one holds,\n  prove it — or say in the handback where it was proved:",
        '    game_loop fix --prove <name> --promises ".." --produces <the fix\'s own output> \\',
        "        --diagnosis <the repro> --before <consumer's verdict, unfixed> "
        "--observed <verdict, fixed>",
        "  (Wording only — any rephrasing walks straight past it, and it cannot tell WHICH fix a "
        "standing\n   proof was for. Silence here is not evidence the fix holds.)"])


# ── the Stop gate ────────────────────────────────────────────────────────────────────────────────
#
# The gate makes the session stop SAYING the wrong thing at turn-end under a mandate. The watchdog
# (bin/watchdog) makes it DO the next thing when it goes idle. Together they are the autonomy engine.
#
# WHY A GATE AND NOT A REMINDER: the whole thesis is that a rule the agent must REMEMBER is followed
# only some of the time (long sessions + compaction), while a rule a hook CONSUMES holds every time.
# CLAUDE.md saying "be autonomous" is the reminder; this is the gate.

# Question-shaped endings aimed at the human. Matched against the agent's OWN last message.
#
# Yes, this is string matching — the thing the design rule warns is trivially defeated by writing
# plausible strings. It is sound HERE, and only here, because of which direction the matching runs: a
# `claim --read` check is defeated by inventing a convincing path (the model wins by lying). This
# check is "defeated" by NOT phrasing a question to the human — which IS the compliance. The cheat and
# the correct behaviour are the same act. Do not copy this pattern to a check where lying wins.
_ASK_MARKERS = [
    "want me to", "should i ", "shall i ", "would you like", "do you want",
    "let me know", "your call", "which would you", "would you rather",
    "prefer that i", "happy to either", "or should we", "thoughts?",
    # ADDED AFTER THE GATE MISSED ONE, reported by the human in the turn after it fired on a
    # DIFFERENT sentence and I complied. The miss: "I'll pick it up next unless you'd rather I
    # leave it session-scoped." No question mark, so the tail test could not see it, and
    # "you'd rather" is not "would you rather" — a contraction and a different word order.
    "you would rather", "unless you", "if you would prefer", "if you prefer",
    "say the word", "up to you", "your preference", "or i can ", "or i could ",
]

# CONTRACTIONS ARE WHY THE LIST MISSED IT, and expanding them is worth more than the two strings
# it would have taken to patch that one sentence. Every marker here is written expanded, so
# "you'd"/"you would" and "i'll"/"i will" are one entry rather than two, and the next contraction
# nobody thought of is already covered.
_CONTRACTIONS = (
    ("won't", "will not"), ("can't", "cannot"), ("n't", " not"),
    ("i'll", "i will"), ("we'll", "we will"), ("you'll", "you will"),
    ("i'd", "i would"), ("you'd", "you would"), ("we'd", "we would"),
    ("let's", "let us"), ("i'm", "i am"), ("you're", "you are"),
)

# A WORD INSERTED BETWEEN VERB AND PARTICLE also slipped past: the list had "i'll pick up" and the
# sentence said "I'll pick it up". Substring matching cannot see that, so the verb-particle forms
# are patterns rather than strings. Narrow on purpose — a first-person future verb about WORK.
_CONTINUE_PATTERNS = (
    r"\bi will (?:pick|take|carry|move|push|pull) (?:it|this|that|them|those|these) (?:up|on|over|forward|through)\b",
    r"\bi will (?:get|set) (?:it|this|that) (?:done|going|started)\b",
)


# EVERY ALTERNATIVE BELOW NAMES A META-VERB OF STARTING — start, begin, do, tackle, pick up, moving
# on — and that is the flaw wcs measured rather than argued. "Next I'm REBUILDING the artifact" uses
# a WORK verb, and the set of work verbs is open: pulling, wiring, drafting, checking, running. An
# alternation over them loses by construction, because the announcement just picks one nobody listed.
#
# They also found the narrow bug inside the broad one: `next\s+i\s` wants whitespace after the "i",
# so the branch that looks like it covers "next i ..." only covers a bare pronoun and "Next I'm"
# walks past it on the apostrophe. Reproduced here verbatim — 4 of their 7 shapes escaped this
# pattern, and 5 of 7 escaped `_promised_to_continue`, which is a second detector with the same hole.
#
# So match the SHAPE and leave the verb free: a signpost to future work with a first person behind
# it. Their patterns, kept as they wrote them, including the end-of-line anchor on the last — which
# is what keeps "I'm reading the record now, and it says X" a REPORT rather than a promise.
_FUTURE_WORK_PAT = re.compile(
    r"^(?:and |so |then )?next\b[^.!?\n]{0,40}\b(?:i'?m|i'?ll|i am|i will)\b|"
    r"\bnext,?\s+(?:i'?m|i'?ll|i am|i will)\b|"
    r"\bi'?m (?:going|about) to \w+|"
    r"\bi'?m \w+ing\b[^.!?\n]{0,60}\b(?:now|next)\b\s*[.!]?$", re.I | re.M)


def _normalise(text):
    """Lowercased, contractions expanded, whitespace collapsed — so one marker covers both spellings."""
    t = (text or "").lower()
    for a, b in _CONTRACTIONS:
        t = t.replace(a, b)
    return re.sub(r"\s+", " ", t)


def _asked_the_user(text):
    if not text:
        return False
    t = _normalise(text)
    if any(_normalise(mk) in t for mk in _ASK_MARKERS):
        return True
    tail = [ln.strip() for ln in (text or "").lower().strip().splitlines() if ln.strip()][-3:]
    return any(ln.endswith("?") for ln in tail)


# Announcing work and then handing back — WORSE than a question, because it is a false statement about
# the agent's own state: "Continuing now" followed by a turn-end. A question at least honestly hands
# control back; this claims to be mid-flight WHILE handing control back. Present-tense only: "next up
# is X" in a report is a plan; "continuing to X now" is a claim to be doing it.
_CONTINUE_MARKERS = [
    "continuing to", "continuing with", "continuing now", "i'm continuing", "im continuing",
    "moving on to", "proceeding to", "proceeding with", "starting on", "starting now",
    "i'll start", "ill start", "i'll now", "getting to work", "getting started",
    "i'll continue", "ill continue", "next i'll", "now i'll", "on to the next",
    # A FIRST-PERSON FUTURE VERB ABOUT WORK, reported by a consumer who hardened this exact rule as
    # a concept and then broke it the same day WITH THE RULE IN CONTEXT: "Next I'll pay those three
    # chat debts, then take #63." Their diagnosis is the useful half — a concept-level rule is
    # checked against INTENT, and the intent felt fine ("being helpful about what comes after"),
    # so the reasoning was never the broken part. The writing was. A word fires on the text at the
    # moment of composition, which is where the defect lives.
    #
    # Measured before adding: their sentence ALREADY fired on "next i'll", and so did "moving on
    # to". These two forms did not, and both are the same act.
    "after that i'll", "then i'll", "i'll take", "i'll pick up", "i'll move on",
    # DELIBERATELY NOT a bare "i'll". "I'll leave that to you" and "I'll report if it changes" are
    # handbacks, not commitments to keep working, and a ban that swallows them trades a visible
    # stall for an invisible one — which is the caveat the reporter asked to carry with the rule.
]


def _closing(text, lines=4):
    """The tail of the message, with quoted spans removed.

    Two things this protects against, both real failure modes:
      1. SCOPE — the violation is always in the CLOSING, so scanning the whole message flags a
         mid-prose mention the ending then contradicts.
      2. QUOTATION — the gate must not fire on the agent QUOTING a marker phrase while writing a
         postmortem about having said it. A guard that cannot be written about without tripping is a
         guard that gets switched off, and writing up failures next to the code is this tool's method.
    """
    if not text:
        return ""
    stripped = re.sub(r'"[^"]*"', " ", text)
    stripped = re.sub(r"`[^`]*`", " ", stripped)
    stripped = re.sub(r"\*\*[^*]*\*\*", " ", stripped)
    tail = [ln for ln in stripped.strip().splitlines() if ln.strip()][-lines:]
    text_tail = "\n".join(tail).lower()
    # TENSE — "I said I was continuing and then stopped" is narration ABOUT the failure, not a
    # commission of it. Drop past-tense sentences before matching. Errs toward letting a retro
    # through; the circuit breaker catches the rest.
    keep = []
    for sentence in re.split(r"(?<=[.!?])\s+", text_tail):
        if any(p in sentence for p in (" was ", " were ", "said ", " had ", "that was")):
            continue
        keep.append(sentence)
    return " ".join(keep)


def _promised_to_continue(text):
    # Normalised for the same reason the ask-check is: "i'll" and "i will" are one rule, and the
    # verb-particle patterns catch a word inserted between the two halves ("pick IT up").
    tail = _normalise(_closing(text))
    if any(_normalise(mk) in tail for mk in _CONTINUE_MARKERS):
        return True
    if any(re.search(pat, tail) for pat in _CONTINUE_PATTERNS):
        return True
    # THE SHAPE PATTERN RUNS ON THE RAW TAIL, NOT THE NORMALISED ONE, and that is not a detail:
    # `_normalise` expands "i'm" to "i am" for the marker list, and the shape pattern's `i'?m`
    # cannot match "i am" — so normalising first silently disarmed two of the four shapes. Caught by
    # the two-direction fixture, which is the only reason it is not shipped.
    #
    # Quotation immunity is preserved because `_closing` has already blanked quoted spans, which is
    # what lets a postmortem name these markers without tripping the guard it is about.
    return bool(_FUTURE_WORK_PAT.search(_closing(text)))


_TRANSCRIPT_TAIL = 250              # records kept from the end — a tail in LINES, never in bytes
_TRANSCRIPT_LINE_MAX = 128 * 1024   # a pasted image arrives as ONE base64 line north of 1MB
_DENIAL_DEPTH_MAX = 12              # how far the field walk descends before it gives up


def _denial_kinds(node, depth=0):
    """Every `toolDenialKind` carried as a FIELD of the decoded record, at any depth.

    Never a text match. That string turns up in a transcript as ordinary DATA — every file the crawl
    read that mentions it, every doc that documents it, echoed back verbatim — so grepping a session
    can match it many times with zero real refusals among them. Presence-of-string and
    presence-of-field are different questions, and only the field is evidence. This is the mirror of
    the write guard's problem, where quoted command text fakes a redirect: structure tells them
    apart, string presence never does.
    """
    if depth > _DENIAL_DEPTH_MAX:
        return
    if isinstance(node, dict):
        kind = node.get("toolDenialKind")
        if isinstance(kind, str) and kind.strip():
            yield kind.strip()
        for v in node.values():
            yield from _denial_kinds(v, depth + 1)
    elif isinstance(node, list):
        for v in node:
            yield from _denial_kinds(v, depth + 1)


def _scan_transcript(path):
    """One bounded, fail-soft pass over the live session transcript.

    Returns (tail, stats, why_not). tail is the last `_TRANSCRIPT_TAIL` decoded records; stats is
    {"lines", "skipped", "oversized", "denials": {kind: n}}; why_not is non-None when the transcript
    could not be read at all. NOTHING here raises — this runs inside a Stop hook, and a hook that
    raises takes the session with it.

    The transcript is appended to WHILE it is read, so:
      * the tail is capped in RECORDS, not bytes. A byte window lets one oversized line starve
        everything useful out of view — the readout goes blank at exactly the busiest moment;
      * an oversized line is truncated rather than carried, so a pasted image costs one slot instead
        of the whole read (and the whole of memory);
      * the final line is routinely half-written, so every line decodes under try/skip;
      * what was dropped is COUNTED. Silence from the reader is not evidence the transcript was
        clean — the drops are stated, not swallowed.

    What it does NOT catch (INV6): a denial or a message older than the record cap is invisible here,
    and a line that decodes into a well-formed but LYING record is counted as good. This bounds the
    read and reports its own drops; it does not verify the harness's own bookkeeping.
    """
    stats = {"lines": 0, "skipped": 0, "oversized": 0, "denials": {}}
    if not path or not os.path.isfile(path):
        return [], stats, f"transcript_path does not exist: {path}"
    tail = collections.deque(maxlen=_TRANSCRIPT_TAIL)
    try:
        # utf-8 explicitly, not the locale's default: a transcript is UTF-8 JSONL wherever it runs,
        # and errors="replace" means arbitrary unicode in tool output degrades instead of raising.
        with open(path, encoding="utf-8", errors="replace") as f:
            for raw in f:
                stats["lines"] += 1
                if len(raw) > _TRANSCRIPT_LINE_MAX:
                    # An image, near certainly. Truncated it cannot decode, so it lands as one
                    # counted skip — which is the point: it does not get to push the good records out.
                    raw = raw[:_TRANSCRIPT_LINE_MAX]
                    stats["oversized"] += 1
                line = raw.strip()
                if not line:
                    continue
                try:
                    rec = json.loads(line)
                except ValueError:
                    stats["skipped"] += 1     # malformed, truncated, or the half-written last line
                    continue
                if not isinstance(rec, dict):
                    stats["skipped"] += 1
                    continue
                # A PRE-FILTER ON THE RAW LINE, and it changes no verdict. Profiled 2026-08-25:
                # `status` cost 1.08s, of which _scan_transcript was 1.665s of a 1.99s exec and
                # _denial_kinds was called 2,395,704 times — a depth-12 walk of EVERY record in the
                # transcript, on a session that has none. The suite spawns this binary constantly,
                # so that walk was most of the suite's wall time and most of the sweep's.
                #
                # THE FIELD CANNOT BE PRESENT IF THE KEY IS NOT IN THE BYTES. JSON writes object
                # keys literally, so a record carrying `toolDenialKind` has that substring in its
                # line — UNLESS the encoder escaped it, which requires a backslash. So a line with
                # neither the key nor a backslash provably has no such field and is skipped without
                # walking. Everything else is walked exactly as before, and STRUCTURE still decides:
                # this is a cheap NECESSARY condition in front of the sufficient one, never a
                # replacement for it. The docstring's point stands — presence-of-string is not
                # evidence — and nothing here treats it as evidence.
                if "toolDenialKind" in line or "\\u" in line:
                    for kind in _denial_kinds(rec):
                        stats["denials"][kind] = stats["denials"].get(kind, 0) + 1
                tail.append(rec)
    except OSError as e:
        return list(tail), stats, f"transcript unreadable: {e}"
    return list(tail), stats, None


def _note_transcript_drops(path, stats):
    """Make the drops observable. A reader that skips a line and says nothing is a reader claiming a
    clean read it did not have — so the count lands in the shared log, where a later run can find it.
    """
    if not (stats["skipped"] or stats["oversized"]):
        return
    try:
        logline({"kind": "transcript_skipped", "transcript_path": path, "lines": stats["lines"],
                 "skipped": stats["skipped"], "oversized": stats["oversized"]})
    except OSError:
        pass  # observability that breaks the gate is worse than the gap it reports


def _last_assistant_text(payload):
    """The agent's most recent assistant message.

    Claude Code hands `last_assistant_message` over directly on the Stop payload. The transcript
    fallback stays because that field is an undocumented internal that may move, and a gate whose
    input silently vanishes is a gate that silently stops holding.

    The fallback reads through `_scan_transcript`, so it is bounded in records and fails soft per
    line, and anything it dropped is logged rather than swallowed.

    Returns (text, why_not). why_not is non-None when we could NOT check — surfaced, never swallowed.
    """
    direct = payload.get("last_assistant_message")
    if isinstance(direct, str) and direct.strip():
        return direct, None
    transcript_path = payload.get("transcript_path")
    if not transcript_path:
        return None, "no last_assistant_message and no transcript_path in the Stop payload"
    if not os.path.isfile(transcript_path):
        return None, f"transcript_path does not exist: {transcript_path}"
    tail, stats, why_not = _scan_transcript(transcript_path)
    _note_transcript_drops(transcript_path, stats)
    if why_not:
        return None, why_not
    for rec in reversed(tail):
        if rec.get("type") != "assistant":
            continue
        content = (rec.get("message") or {}).get("content")
        if isinstance(content, list):
            parts = [c.get("text", "") for c in content
                     if isinstance(c, dict) and c.get("type") == "text"]
            text = "\n".join(p for p in parts if p)
            if text.strip():
                return text, None
        elif isinstance(content, str) and content.strip():
            return content, None
    return None, "no assistant text found in transcript"


_NEXT_ACTION_PAT = re.compile(
    r"(?:^|[.;\n]\s*|\s—\s)(next(?:\s+up)?\s*[:,]|next\s+i\s|now\s+i'?ll\s|"
    r"moving\s+on\s+to\b|i'?ll\s+(?:start|begin|do|tackle|pick\s+up)\b|"
    r"then\s+i'?ll\s|about\s+to\s+start\b|starting\s+on\b)", re.I)

# The outs, per #81. A run that is genuinely blocked must pass, or this gate blocks the one state it
# has no business blocking and gets switched off within a day.
_BLOCKED_PAT = re.compile(
    r"blocked\s+on\b|needs?\s+a\s+decision\b|waiting\s+on\b|awaiting\b|"
    r"cannot\s+proceed\b|needs?\s+(?:the\s+)?human\b|needs-input\b", re.I)


# #84: THE SECOND GRAMMAR. Instead of naming a successor, the checkpoint ENUMERATES THE REMAINDER —
# "Mandate has 4108, 4109, 4111 left" — and every alternative in _NEXT_ACTION_PAT passes it. The
# reporter calls this the worse of the two, and they are right about why: a tidy summary of
# outstanding work reads as THOROUGH. It is what a good handoff looks like, so it does not feel like
# a deferral while you are writing it.
#
# BOTH HALVES ARE REQUIRED — a remaining-word AND a work-item token — because a remaining-word alone
# over-fires on legitimate findings. Their must-pass case: "the remaining 19 failures are
# pre-existing GCP credential errors" has the word, names no work item, and stays clean.
_DEFERS_WORK_PAT = re.compile(
    r"(?:\bmandate\b|\bepic\b|\bsprint\b|\bcycle\b|\bqueue\b|\bhas\b|\bhave\b)"
    r"[^.]{0,80}\bleft\b"
    r"|\bleft to (?:do|ship|land|start|pick up)\b"
    r"|\b(?:remaining|outstanding|still open|still to do)\b\s*[:\-]"
    r"|\b\d+ (?:items?|tickets?|stories|leaves|issues?) (?:left|remaining|outstanding)\b", re.I)


def deferral_in_checkpoint(notes):
    """The phrase in which a checkpoint named its own successor — or None. (#81)

    Narrow ON PURPOSE. This does not read intent, it reads a record: the agent wrote down what to do
    next in the act of stopping. A blocker named in the same notes clears it, because "I stopped and
    here is the fact I am stuck on" is a report, not a deferral.
    """
    if not notes:
        return None
    if _BLOCKED_PAT.search(notes):
        return None
    m = _NEXT_ACTION_PAT.search(notes) or _FUTURE_WORK_PAT.search(notes)
    if not m:
        m = _DEFERS_WORK_PAT.search(notes)
        if not m:
            return None
        tail = notes[m.start():m.start() + 140].strip()
        return tail.split("\n")[0]
    # `_FUTURE_WORK_PAT` has no capturing group — it matches a SHAPE, not a named opener — so
    # group 1 exists only for the older alternation. Asking for it unconditionally raised
    # IndexError on every shape match, which the two-direction fixture caught immediately.
    start = m.start(1) if m.lastindex else m.start()
    tail = notes[start:start + 140].strip()
    return tail.split("\n")[0]


def work_since_last_block():
    """Did anything happen since the Stop gate last refused? (True/False/None-for-unanswerable) (#82)

    `stop_hook_active` exists so a refusing gate cannot loop the agent forever, and in isolation that
    is right. Combined with what an agent actually does it becomes a reliable escape: a block reads
    as "your closing message was wrong", so the locally obvious response is to REWRITE THE MESSAGE.
    Doing the work costs a tool call; re-stopping costs a sentence. The pricing is inverted from the
    intent, and the enforcement budget for a turn-end turns out to be exactly one refusal — cheapest
    spent on prose.

    Measured by a consumer across two overnight strandings: both times the gates fired correctly,
    `consecutive` never reached the stand-down bound, and the turn ended anyway.

    None means UNANSWERABLE (no log, unreadable) and callers must treat it as "allow", never as
    "nothing happened" — a gate that cannot read its own record must not start refusing on that.
    """
    BOOKKEEPING = {"stop_gate_block", "stop_after_block", "checkpoint", "watchdog_quiet",
                   "stop_gate_exhausted", "mandate_park_stop", "t3_spend"}
    try:
        with open(LOG_F) as f:
            recs = [l for l in f if '"kind"' in l]
    except OSError:
        return None
    seen_block = False
    for line in reversed(recs):
        try:
            d = json.loads(line)
        except ValueError:
            continue
        k = d.get("kind")
        if k == "stop_gate_block":
            return False if not seen_block else True
        if k not in BOOKKEEPING:
            seen_block = True          # real work, newer than any block below it
    return None                        # no block on record at all — nothing to launder


def _stop_verdict(s, payload):
    """Decide whether this turn-end may proceed. Returns (allow: bool, reason: str, log: dict|None).

    Pure decision, no I/O beyond reading the transcript — so a test suite can drive every branch.

    The pricing is the point. Under a mandate:
      * REPORTING is cheap    -> `game_loop checkpoint --notes ..`   (deliberate + logged, no evidence)
      * ASKING is expensive   -> `game_loop arm --question --read --predict`  (must name what you read)
      * FINISHING is explicit -> `game_loop mandate --clear --notes ..`
    Blocking every turn-end equally would price a progress report the same as an interruption and
    decay into a nag that gets ignored. A gate that cries wolf is a gate that gets switched off.
    """
    m = s.get("mandate") or {}
    if not m.get("active"):
        # WITH ONE EXCEPTION, ADDED BECAUSE THE INERTNESS HAD A HOLE EXACTLY WHERE IT HURT. Clearing
        # a mandate switches this gate off, and the turn-end most likely to be a stall is the one
        # right after that: clear, say "I'll start on that now", and stop. The announce-then-stop
        # detector for that exact sentence lives 80 lines below and was unreachable, because the
        # clear had already returned here.
        #
        # Reported by the human across SEVERAL agents, not one. Measured here afterwards: 4 of this
        # repo's 7 clears are followed within ONE MINUTE by the watchdog going quiet, which is the
        # log's shape for "cleared it and stopped".
        #
        # ARMED FOR THREE TURN-ENDS, NOT FOREVER. The docstring above is right that blocking every
        # turn-end equally decays into a nag that gets ignored — so this is not "the gate is always
        # on". It is the one detector that is about a FALSE STATEMENT rather than about asking, kept
        # alive across the moment it was written for. After three turn-ends it goes quiet again.
        # READ ONLY HERE. This function's docstring promises a pure decision so a suite can drive
        # every branch, and the first version of this counted the turn-end and saved state inside
        # it — which would have made the branch untestable without a real state file, in the
        # function whose whole design note is that it is testable.
        if m.get("cleared_at") and s.get("stops_since_clear", 0) < 3:
            _t, _ = _last_assistant_text(payload)
            if _promised_to_continue(_t):
                return False, "cleared-then-announced", (
                    "STOP GATE — you cleared the mandate and then said you were carrying on.\n\n"
                    "  cleared: %s\n\n"
                    "Those two cannot both be true at a turn-end. Clearing says the work is done;\n"
                    "announcing says it is not, and stopping says neither. This is the stall the\n"
                    "gate stays armed for — three turn-ends after a clear and no longer.\n\n"
                    "Either DO the thing you just named, or end with what is actually true:\n"
                    "the work is finished and you are waiting for them."
                    % (m.get("cleared_at") or "?"))
        # With no mandate bound, this gate is otherwise INERT. It must never sit between the human
        # and a normal conversation, or it earns its own removal.
        return True, "no mandate bound — gate inert", None

    if payload.get("stop_hook_active"):
        # #82: `stop_hook_active` must not LAUNDER a reworded stop. It is here so a refusing gate
        # cannot loop forever — but if the gate refused and then NOTHING happened, this is the same
        # turn-end wearing new prose, and allowing it spends the whole enforcement budget on a
        # sentence. Unanswerable (no log) allows, because a gate that cannot read its record must
        # not start refusing on that.
        _worked = work_since_last_block()
        if _worked is False:
            return False, (
                "STOP GATE CLOSED — you were refused, and nothing has happened since.\n\n"
                f"  MANDATE: {m.get('text')}\n\n"
                "No commit, no claim, harden, proof, phase or retro is on the record between that\n"
                "refusal and this turn-end. A block reads as 'your closing message was wrong', so\n"
                "the cheap response is to rewrite the message — doing the work costs a tool call,\n"
                "re-stopping costs a sentence. That is the pricing this refuses to accept.\n\n"
                "THIS BUDGET IS NOT UNLIMITED, and you should know the number: after two\n"
                "consecutive blocks the circuit breaker stands this gate down and your next\n"
                "turn-end succeeds regardless. That exists so a gate can never trap a session — it\n"
                "is not an invitation to spend it. Rewording again reaches it without doing\n"
                "anything; one tool call clears this honestly.\n\n"
                "  Go and do the next thing. Then stop, if you still want to."), {
                "kind": "stop_after_block", "outcome": "refused-again-nothing-happened",
                "mandate": m.get("text")}
        # Log the OUTCOME of a block, not just the block (#82). Nothing recorded whether a refused
        # turn then ended anyway, so "are this gate's refusals being obeyed or spent?" — the single
        # most useful number in the file — could only be answered by hand-diffing a transcript.
        return True, "stop_hook_active — harness is already re-entering; not stacking a block", (
            {"kind": "stop_after_block", "outcome": "allowed-after-work"}
            if _worked else None)

    armed = s.get("t3_armed")
    text, why_not = _last_assistant_text(payload)
    asking = _asked_the_user(text)

    if armed and not armed.get("spent"):
        # A T3 SOMEBODY ELSE ARMED (#94). `arm` writes a PERMISSION the same way `checkpoint` does,
        # and this is where it is SPENT -- the turn-end that carries the question to the human. So
        # this is the last moment anybody could notice the question is not theirs, which is the same
        # argument that put the checkpoint notice at its own spend rather than at its write.
        #
        # The issue was answered "there is no equivalent moment to print at, because a T3 is
        # consumed by a human". That was wrong about this code: a human answers the question, but
        # the GATE is what spends the arm, right here, and it runs in the tree that will be
        # interrupted. Recording the mark and never surfacing it left the record for nobody.
        _as = armed.get("setter") or {}
        _a_unknown = not _as.get("cwd")
        _a_cross = (not _a_unknown
                    and os.path.realpath(_as["cwd"]) != os.path.realpath(os.getcwd()))
        return True, "T3 armed — spending it now", {
            "kind": "t3_spend", "question": armed.get("question"),
            "read": armed.get("read"), "predict": armed.get("predict"),
            "setter": _as or None, "arm_cross_tree": bool(_a_cross),
            "arm_writer_unknown": bool(_a_unknown)}

    if asking:
        return False, (
            "STOP GATE CLOSED — you are asking the human a question, unarmed, under an autonomy "
            "mandate.\n\n"
            f"  MANDATE: {m.get('text')}\n"
            f"  PHASE  : {(s.get('phase') or {}).get('milestone')} · "
            f"{(s.get('phase') or {}).get('doing')}\n\n"
            "Your closing message hands a decision back to the human — the most expensive rung on the\n"
            "ladder — and you have not shown the cheap rungs couldn't answer it.\n\n"
            "Do ONE of these:\n"
            "  1. ANSWER IT YOURSELF AND CARRY ON. Almost always correct. The next step is nearly\n"
            "     always already written down (your plan / the mandate). Offering a choice between two\n"
            "     documented options is not a question; it is a decision you are equipped to make.\n"
            "  2. game_loop arm --question \"..\" --read <source that DIDN'T answer it> --predict \"..\"\n"
            "     Only when the answer is genuinely not derivable — a preference, a priority, a fact\n"
            "     only the human holds. If you can predict the reply, don't ask.\n"
            "  3. Rewrite the ending as a statement of what you did and what you are doing next, then\n"
            "     game_loop checkpoint --notes \"..\" to report without asking.\n"
        ), {"kind": "stop_gate_block", "reason": "asked-the-user", "mandate": m.get("text"),
            "phase": (s.get("phase") or {}).get("doing")}

    if _promised_to_continue(text):
        return False, (
            "STOP GATE CLOSED — you said you are continuing. So continue.\n\n"
            f"  MANDATE: {m.get('text')}\n"
            f"  PHASE  : {(s.get('phase') or {}).get('milestone')} · "
            f"{(s.get('phase') or {}).get('doing')}\n\n"
            "Your closing message claims you are carrying on with work RIGHT NOW, then ends the turn\n"
            "and hands control back. Both cannot be true. This is worse than asking a question: a\n"
            "question honestly gives the human the floor; this claims to be mid-flight while giving\n"
            "them the floor — dead air until they come back to ask why nothing is happening.\n\n"
            "Do ONE of these:\n"
            "  1. ACTUALLY DO IT. You already named the next action. Go run it. This is the answer.\n"
            "  2. If you are genuinely stopping, rewrite the ending in the past and future tense —\n"
            "     what you DID and what REMAINS — then game_loop checkpoint --notes \"..\".\n"
            "  3. game_loop arm --question .. --read .. --predict ..   if you truly need the human.\n"
        ), {"kind": "stop_gate_block", "reason": "announced-then-stopped",
            "mandate": m.get("text"), "phase": (s.get("phase") or {}).get("doing")}

    # A human-called break. Deliberately BELOW the two block checks above: a park is a break, not an
    # amnesty, so it cannot launder a question or an announce-then-stop. Like the checkpoint and the
    # arm it is CONSUMED (cmd_stopgate marks it spent), so it buys one turn-end and never disarms the
    # gate — which is what makes this exit narrower than the `--clear` an interrupted run used to
    # fabricate, rather than a new way out.
    parked = (m.get("parked") or {})
    if parked and not parked.get("spent"):
        return True, "mandate parked at the human's request — the break may take effect", {
            "kind": "mandate_park_stop", "mandate": m.get("text"), "by": parked.get("by"),
            "reason": parked.get("reason"), "next": parked.get("next")}

    if s.get("stop_ok"):
        # A CHECKPOINT THAT NAMES THE NEXT ACTION IS A DEFERRAL (#81). Every gate here passes it —
        # this one because a checkpoint was declared, which is checkpoint's contract; the ritual
        # counter because real work HAD shipped; the watchdog because the session is not idle, it
        # stopped. The hole is between the gates, and the distinguishing fact is mechanical: the
        # agent wrote down what to do next, and then did not do it.
        _defer = deferral_in_checkpoint(s.get("stop_ok_notes"))
        # waiting_state() answers "is a probe CONFIGURED", which is truthy on every tree that has
        # one — a different question from "is this run waiting on something". Reading the config as
        # the verdict made this gate inert wherever a probe existed, which is exactly the tree it
        # most needed to work on. Caught by its own assertions.
        _wait = (waiting_state() or {}).get("last") or {}
        if _defer and not armed and not _wait.get("waiting"):
            return False, (
                "STOP GATE CLOSED — your checkpoint names the next action, and then ends the turn.\n\n"
                f"  MANDATE : {m.get('text')}\n"
                f"  YOU WROTE: ...{_defer}...\n\n"
                "Nothing is dispatched and nothing is armed, so there is nobody to wait for. You\n"
                "wrote down what to do next in the act of stopping, which makes it the human's job\n"
                "to re-issue an instruction you had already formed.\n\n"
                "THE PHRASE IS THE SYMPTOM; THE UNSTARTED WORK IS THE FINDING. Deleting 'next' from\n"
                "the checkpoint clears this gate and changes nothing about the run — if you do that,\n"
                "you have taught yourself to write worse checkpoints.\n\n"
                "  1. GO AND DO IT. You already named it. This is nearly always the answer.\n"
                "  2. If you are genuinely blocked, SAY WHAT ON: 'blocked on <fact>', 'needs a\n"
                "     decision about <x>'. A named blocker clears this, because that is a report.\n"
                "  3. game_loop arm --question .. --read .. --predict ..   if you need the human.\n\n"
                "BLIND SPOT (INV6): this reads your CHECKPOINT, not your closing message. A next\n"
                "action named only in the prose passes — the record is stable and checkable, a\n"
                "message is neither."), {
                "kind": "stop_gate_block", "reason": "checkpoint-names-next-action",
                "mandate": m.get("text"), "phrase": _defer}
        # WHOSE TURN-END IS BEING SPENT (#94). checkpoint writes a permission and this is where it
        # is consumed, so this is the last moment anybody could notice it was bought by somebody
        # else. A dispatched subagent inherits the session id, so its checkpoint lands here and buys
        # THIS session a turn-end nobody here asked for. Naming the crossing costs one line and only
        # when there IS one -- the same shape as the spent-grant notice on the write guard.
        # THREE STATES, AND THE ABSENT ONE USED TO READ AS THE REASSURING ONE (lamp-owner,
        # 2026-08-25). A checkpoint written before this build carries no setter at all, and
        # `_cs.get("cwd")` is then falsy — byte-identical to "written right here, nothing to see".
        # That is the multi-hop erasure they describe: the distinction survives the function that
        # makes it and dies where a MISSING KEY is read as a default, in a different function. I got
        # this right for the pidfile's legacy format the same morning and wrong here, which is the
        # freshness correlation rather than the age one.
        #
        # Bounded and self-healing: `checkpoint` always writes the mark now, so a tree pays this at
        # most once per checkpoint that predates the change.
        _cs = s.get("stop_ok_setter") or {}
        _unknown_writer = not _cs.get("cwd")
        _cross = (not _unknown_writer
                  and os.path.realpath(_cs["cwd"]) != os.path.realpath(os.getcwd()))
        # WHAT THIS CANNOT SEE (INV6): an in-process subagent in the SAME tree. It shares the
        # session id and the cwd, so nothing mechanical separates it from this session — #88 reached
        # the same wall and answered it the same way, by showing the WORDS. Words you do not
        # recognise are the tell; there is no identity check underneath this and it must not be read
        # as one.
        return True, "checkpoint declared — reporting, not asking", {
            "kind": "checkpoint", "notes": s.get("stop_ok_notes"),
            "setter": _cs or None, "cross_tree": bool(_cross),
            "writer_unknown": bool(_unknown_writer),
            "checked_question": why_not is None, "unchecked_because": why_not}

    # Circuit breaker. A guard that can trap the session forever is worse than the bug it prevents,
    # and a guard must never block its own fix — including "let me talk to the human about the guard".
    # Two consecutive blocks and it stands down, LOUDLY (logged), so a gate that keeps giving up is
    # visible rather than quietly useless.
    if s.get("stop_blocks", 0) >= 2:
        return True, "circuit breaker — blocked twice already, standing down", {
            "kind": "stop_gate_exhausted", "mandate": m.get("text"),
            "note": "gate stood down after 2 consecutive blocks; it did not hold"}

    if parked:
        # The park was spent on the turn-end that took the break. Something is running again, so the
        # break is over or was never the reason — either way the parked work needs dispositioning
        # rather than a second silent exit on the human's name.
        return False, (
            "STOP GATE CLOSED — the mandate is PARKED, and that park is already spent.\n\n"
            f"  MANDATE: {m.get('text')}  (parked {parked.get('at')} — {parked.get('by')})\n"
            f"  THEIR WORDS: {parked.get('reason')}\n"
            f"  NEXT STEP  : {parked.get('next') or '(none recorded)'}\n\n"
            "A park buys ONE turn-end — the break itself. This turn is a second one, so the break is\n"
            "over or something else woke you. The work was never closed; say what is true now:\n\n"
            "  game_loop mandate --resume                        they're back — pick the next step up\n"
            "  game_loop mandate --park --reason \"<their words>\"  still their break, freshly on record\n"
            "  game_loop mandate --clear --notes \"..\"             it turned out to be finished\n"
            "  game_loop checkpoint --notes \"..\"                  you worked and are reporting back\n"
        ), {"kind": "stop_gate_block", "reason": "park-spent", "mandate": m.get("text")}

    return False, (
        "STOP GATE CLOSED — turn-end under an autonomy mandate, with no checkpoint declared.\n\n"
        f"  MANDATE: {m.get('text')}\n"
        f"  PHASE  : {(s.get('phase') or {}).get('milestone')} · "
        f"{(s.get('phase') or {}).get('doing')}\n\n"
        + (f"  ⚠ could not inspect your closing message ({why_not}) — running the conservative path;\n"
           "    it cannot tell a report from a question, so it blocks.\n\n" if why_not else "")
        + "Ending your turn spends the human's attention. If there is work left in the mandate, go do\n"
        "it. Otherwise say so explicitly:\n\n"
        "  game_loop checkpoint --notes \"..\"                 report progress and hand back (no question)\n"
        "  game_loop arm --question .. --read .. --predict ..  ask something you genuinely can't derive\n"
        "  game_loop mandate --clear --notes \"..\"            the mandate is actually satisfied\n"
    ), {"kind": "stop_gate_block", "reason": "no-checkpoint", "mandate": m.get("text"),
        "unchecked_because": why_not}


# After this many CONSECUTIVE blocks from ONE attachment, it stands down and the turn ends.
#
# THE BOUND IS THE POINT, AND IT IS NOT OPTIONAL. Every other way this gate blocks is satisfiable
# from INSIDE the session in one command — checkpoint, arm, mandate --clear all reset it. A `stop`
# attachment's condition is EXTERNAL, and the dangerous case is not a crash and not a timeout: it is
# a perfectly working command returning a perfectly correct "still owed" that nobody present can
# clear, because the thing it asks about is unreachable. Failing open on error does not cover that
# at all. Unbounded, it would be a gate no session in this tree could ever pass — the harness itself
# preventing every agent from finishing, which is the worst failure this repo can ship (INV5).
#
# THREE, counted as turns rather than rounded: one to TELL the agent (the first block is the first
# it has heard of the obligation), one for the attempt it makes in response, and one for the attempt
# it makes after reading why the first attempt did not clear it. A fourth consecutive block is no
# longer evidence that the condition is agent-satisfiable, and the likelier reading is that it is
# not satisfiable from here at all. The mandate gate's own breaker stands down at 2, deliberately
# tighter: what it asks for is a command in this session, where a `stop` attachment asks for an
# effect somewhere else, and an effect somewhere else legitimately needs a retry.
STOP_TRIGGER_BLOCK_LIMIT = 3


def stop_trigger_block(s, payload, notices):
    """Run this project's `stop` attachments. Returns the text that BLOCKS turn-end, or None.

    Non-zero exit blocks and its stderr goes back to the model — cmd_stopgate's contract, handed to
    a command this repo did not write.

    Loud fail-open notices are appended to `notices` rather than returned, and the split is the
    whole of INV5 here: those belong to a turn that is ENDING. A notice that had to block to be
    delivered would be the failure it is reporting.
    """
    trigs = triggers_for("stop")
    if not trigs:
        return None                  # silent when nothing is attached, like every other moment
    # The host's own Stop fields are passed THROUGH rather than summarised. An attachment deciding
    # whether a turn may end wants the same evidence this gate uses — the closing message above all,
    # since "did it answer the question" is a question about that text — and re-deriving it from the
    # transcript is work the harness has already done.
    fields = ("session_id", "transcript_path", "stop_hook_active", "last_assistant_message")
    tp = {k: payload.get(k) for k in fields if payload.get(k) is not None}
    tp.update({"event": "stop", "project": config().get("project_name"), "session": SESSION})
    blocks, seen = [], s.setdefault("stop_triggers", {})
    for t in trigs:
        # ALL OF THEM RUN, even after one has already said no, and that is a decision rather than an
        # oversight. Short-circuiting would save nothing on the passing path (every attachment must
        # pass for the turn to end, so all of them run anyway) and would cost two things on the
        # blocking one: the agent gets ONE turn-end and should be told everything it owes rather
        # than discovering the second obligation only after clearing the first — N attachments would
        # otherwise cost N turns to surface — and a skipped attachment can neither increment nor
        # reset its own count, so its bound would stop being measured in turn-ends and could sit on
        # a stale streak indefinitely. The latency is the sum of the timeouts either way.
        name, ran, code, body, err = _run_trigger(s, t, "stop", tp, default_timeout=10.0)
        rec = seen.setdefault(name, {})
        n = rec.get("consecutive", 0)
        if not ran:
            # COULD NOT TELL, which is not a pass and not a refusal. Fail open, loudly — a guard
            # must never block its own fix, and an attachment that times out while somebody is
            # repairing it would otherwise hold the session shut with the repair inside.
            #
            # The streak is left ALONE: not incremented (it did not block) and not reset (it did not
            # pass). A run of blocks broken by an unanswered question is still a run of blocks, and
            # letting "could not tell" launder the count would hand back the unbounded case through
            # a trigger that fails every other turn.
            rec.update({"at": now(), "verdict": "failed_open_error", "detail": err[:200],
                        "consecutive": n})
            logline({"kind": "stop_trigger_failed_open", "name": name, "why": "errored",
                     "detail": err[:200], "consecutive": n})
            notices.append(
                f"⚠ STOP TRIGGER FAILED OPEN — `{name}` could not answer ({err}).\n"
                "  The turn is ending UNCHECKED. This is not a pass: nothing was decided, and\n"
                "  whatever it exists to catch was not looked for on this turn. It is recorded in\n"
                "  the log and `game_loop status` names it until it answers again.")
            continue
        if code == 0:
            # THE RESET, and the only thing that performs one. Blocking is cheap to enter and must
            # be cheap to leave: the moment the attachment is satisfied once, the count is gone and
            # it is back to full strength on the next turn.
            rec.update({"at": now(), "verdict": "passed", "detail": body[:200], "consecutive": 0})
            continue
        n += 1
        detail = err or body or "(exited non-zero, saying nothing at all)"
        rec.update({"at": now(), "detail": detail[:200], "consecutive": n})
        if n > STOP_TRIGGER_BLOCK_LIMIT:
            rec["verdict"] = "stood_down"
            logline({"kind": "stop_trigger_stood_down", "name": name, "consecutive": n,
                     "limit": STOP_TRIGGER_BLOCK_LIMIT, "detail": detail[:200]})
            notices.append(
                f"⚠ STOP TRIGGER STOOD DOWN — `{name}` has blocked {n} consecutive turn-ends, past "
                f"its bound of\n  {STOP_TRIGGER_BLOCK_LIMIT}, and is now OVERRIDDEN. The turn is "
                "ending. It is still being run, and it\n  is still saying no:\n"
                + "\n".join("     " + l for l in detail.splitlines()) + "\n"
                "  Either nobody present can satisfy it, or it is wrong. A block nobody can clear\n"
                "  would gate every turn in this tree forever, so the harness stops honouring it\n"
                "  rather than becoming the thing that prevents every agent from finishing (INV5).\n"
                "  One pass resets the count and puts it back in charge.")
            continue
        rec["verdict"] = "blocked"
        logline({"kind": "stop_trigger_block", "name": name, "consecutive": n,
                 "limit": STOP_TRIGGER_BLOCK_LIMIT, "detail": detail[:200]})
        blocks.append((name, n, detail))
    if not blocks:
        return None
    lines = ["STOP GATE CLOSED — this project attached a check to turn-end, and it says no.\n"]
    for name, n, detail in blocks:
        lines.append(f"  TRIGGER: {name}   (consecutive block {n} of {STOP_TRIGGER_BLOCK_LIMIT})")
        lines.extend("     " + l for l in detail.splitlines())
    lines.append(
        "\nThis is your project's own rule, running as a command instead of sitting in prose —\n"
        "which is the entire reason it holds every time rather than most times. Do ONE of these:\n\n"
        "  1. DO WHAT IT ASKS, then end the turn again. Nearly always correct: the check is cheap\n"
        "     and it passes the moment the thing it wants is true.\n"
        "  2. If it is WRONG, it is not a law — it is a line in .game_loop/triggers.json. Fix the\n"
        "     command or detach it. Nothing here stops you editing the file that configures it.\n\n"
        f"It stands down after {STOP_TRIGGER_BLOCK_LIMIT} consecutive blocks and lets the turn end,\n"
        "so an attachment whose condition nobody present can satisfy cannot trap this session.")
    return "\n".join(lines)


def record_session_activity(s, now_iso=None):
    """One monotonic counter per session, written whether or not a mandate is bound.

    REPORTED BY wcs, AND IT IS THE SAME STRUCTURAL GAP AS THE MANDATE SUBSTRATE, one level up.
    They went to sample the population the unbound-mandate notice exists FOR — sessions that ran
    without binding anything — and found that game_loop's own state cannot describe it. Every
    unbound session in their tree recorded exactly one thing, that it oriented, and the nine were
    byte-identical at 666 bytes. No claims, no pins, no checkpoints, no stop-gate blocks, because
    with no mandate the gate is inert, so there is nothing to block and nothing to record.

    MEASURED HERE TOO, at larger scale: 161 of 163 sessions in this repo never bound a mandate,
    and 158 of them hold `oriented`, `version` and `transcript_path` and nothing else. So a SHORT
    session that rightly needed no mandate and a LONG unattended run that should have bound one
    are the same 650 bytes. "90% never bound one" is a true rate that supports no conclusion at
    all about whether any of them warranted one.

    THE TRANSCRIPT IS NOT THE WAY OUT, which I checked before accepting the argument rather than
    after: 159 of those 161 transcripts are gone from disk here. Asking how many unbound sessions
    exceeded a megabyte returns 0 over a denominator of TWO — the short-denominator failure this
    repo keeps finding, and it would have read as "the gap is small".

    NOTHING READS THIS. It is the substrate, recorded so that "unbound AND long" becomes an
    answerable question next month, exactly as `finish_line_facts` was recorded so a clear-side
    gate could become answerable later. The sessions most worth seeing are currently the ones the
    tool writes least about, and that is backwards for a structural reason: the recording hangs
    off the mandate, and these are the sessions with no mandate.

    Three facts and no verdict. `turns` is monotonic; the two stamps give DURATION, which is the
    other half of "long" and is not derivable from a count.
    """
    n = now_iso or now()
    s["turns"] = int(s.get("turns") or 0) + 1
    s.setdefault("first_turn_at", n)
    s["last_turn_at"] = n
    return s


def cmd_stopgate(s, a, payload):
    """Stop-hook entrypoint. exit 0 = may stop · exit 2 = blocked, stderr goes back to the model.

    Wired at .claude/settings.json -> hooks.Stop. Exit-2-blocks-and-feeds-stderr is the documented
    Stop-hook contract: a non-zero exit with stderr is surfaced to the model as feedback. The payload
    is parsed in main() — its session_id decides WHICH session's state this gate reads, so it must be
    known before load().
    """
    # Observability over guessing: record the real payload so its schema is READ, not assumed.
    try:
        os.makedirs(os.path.join(ROOT, "probe"), exist_ok=True)
        with open(os.path.join(ROOT, "probe", "stop-payload.json"), "w") as f:
            json.dump(payload, f, indent=2)
            f.write("\n")
    except OSError:
        pass  # a probe that fails must never take the gate down with it
    # EXERCISE, not a stamp: check the claim against the payload this host actually delivered.
    # Unconditional, unlike the stop-payload probe above it — a claim checked only when a debug
    # flag is set is a claim nobody checks.
    record_hook_claim_observation(payload)
    # #45: the handoff is maintained HERE, at every turn-end, rather than demanded at the cliff.
    # A limit death then costs at most one turn, in any host, with no number to invent.
    refresh_handoff(s)
    if (_u := trailing_usage(payload.get("transcript_path"))):
        logline({"kind": "usage_window", **_u})   # output_tokens is evidence; context_tokens gates
        # The one place the context reading is taken. Turn-end is where transcript_path has actually
        # been OBSERVED on the payload, and the number only changes once a turn — so the gate reads
        # this cache rather than re-parsing a transcript on every tool call.
        record_context_reading(s, _u.get("context_tokens"), time.time())

    # Remember where the live transcript is. The gate fires every turn-end, so this is the reliable
    # way `status` can later count the harness's own tool-denials; the watchdog records the same key.
    if isinstance(payload.get("transcript_path"), str) and payload["transcript_path"]:
        s["_tpath"] = payload["transcript_path"]

    allow, reason, rec = _stop_verdict(s, payload)
    # BEFORE the mandate branch below and outside it, which is the entire point: this counter must
    # be written for the sessions that never bind anything, because those are the ones nothing else
    # here describes. Placing it under any mandate condition would reproduce the gap it closes.
    record_session_activity(s)
    # The post-clear window is counted HERE, not in the verdict: that function is documented as a
    # pure decision so the suite can drive it, and a counter that writes state would end that.
    _mand = s.get("mandate") or {}
    if not _mand.get("active") and _mand.get("cleared_at"):
        s["stops_since_clear"] = s.get("stops_since_clear", 0) + 1
    save(s)
    if rec:
        logline(rec)
    if allow:
        # THE PROJECT'S OWN CHECK, BEFORE ANYTHING IS CONSUMED (#64). Ordering is the whole safety
        # of this: a checkpoint, an arm and a park are each single-use, and spending one on a
        # turn-end that then gets blocked would burn the human's interruption on a turn that never
        # ended. Blocked here, they are all still declared, so satisfying the attachment costs one
        # turn and nothing else.
        #
        # It runs on the ALLOWING path only. A turn-end the mandate gate has already refused is not
        # a turn-end, so the attachment's question is moot — and asking it anyway would spend its
        # timeout on every blocked turn and count a block against a bound measured in turn-ends.
        #
        # It DOES run under stop_hook_active, where the mandate gate declines to stack. That gate can
        # afford to defer because what it wants is satisfiable in this session; deferring here would
        # make the check vacuous — the attachment would fire once per continuation and never verify
        # that what it asked for happened. The consecutive bound is what makes that safe.
        notices = []
        # A TURN-END SOMEBODY ELSE BOUGHT (#94). checkpoint writes a permission and this is where it
        # is spent, so this is the last moment anyone could notice it was not theirs. A dispatched
        # subagent inherits the session id, so its checkpoint lands in THIS state file and clears
        # THIS gate. It goes on `notices` rather than into the verdict because a passing gate is
        # silent by design: the reason is logged, and stderr is the only thing a run actually reads.
        if isinstance(rec, dict) and rec.get("writer_unknown"):
            notices.append(
                "⚠ THIS TURN-END WAS BOUGHT BY A CHECKPOINT THAT RECORDS NO WRITER.\n"
                f"    its words  : {(rec.get('notes') or '')[:160]!r}\n"
                "  It predates the writer mark, so whether it was written in THIS tree cannot be\n"
                "  established — which is not the same as knowing it was. Said once; the next\n"
                "  checkpoint records a writer and this stops.")
        if isinstance(rec, dict) and rec.get("cross_tree"):
            _st = rec.get("setter") or {}
            notices.append(
                "⚠ THIS TURN-END WAS BOUGHT BY A CHECKPOINT FROM ANOTHER TREE.\n"
                f"    written in : {_st.get('cwd')}\n"
                f"    at         : {_st.get('at')}\n"
                f"    its words  : {(rec.get('notes') or '')[:160]!r}\n"
                "  A dispatched subagent inherits this session id, so its checkpoint lands here and\n"
                "  clears YOUR gate. If those words are not yours, the turn-end you just spent was\n"
                "  not either — and the work you were mandated to do is still open.\n"
                "  Give a subagent its own state: GAME_LOOP_SESSION=<unique> game_loop ..\n"
                "  BLIND SPOT: an in-process subagent in the SAME tree shares this cwd and cannot be\n"
                "  told apart here at all. The words are the only tell, which is where #88 landed too.")
        # THE ARM HALF OF #94, with its own words on purpose: a turn-end somebody else BOUGHT and a
        # question somebody else ARMED are different events with different consequences, and one
        # wording covering both would make the record useless exactly where it is needed.
        if isinstance(rec, dict) and rec.get("arm_writer_unknown") and rec.get("kind") == "t3_spend":
            notices.append(
                "⚠ THE T3 QUESTION BEING SPENT HERE RECORDS NO WRITER.\n"
                f"    asks : {(rec.get('question') or '')[:160]!r}\n"
                "  It predates the writer mark, so whether it was armed in THIS tree cannot be\n"
                "  established — which is not the same as knowing it was. The next `arm` records one.")
        if isinstance(rec, dict) and rec.get("arm_cross_tree"):
            _at = rec.get("setter") or {}
            notices.append(
                "⚠ THE T3 QUESTION BEING SPENT HERE WAS ARMED IN ANOTHER TREE.\n"
                f"    armed in : {_at.get('cwd')}\n"
                f"    at       : {_at.get('at')}\n"
                f"    asks     : {(rec.get('question') or '')[:160]!r}\n"
                "  A dispatched subagent inherits this session id, so its `arm` lands here and it is\n"
                "  YOUR turn-end that spends it. If that question is not yours, the human is about to\n"
                "  be interrupted with somebody else's — and the work you were mandated to do is\n"
                "  still open, because spending the arm is what ends this turn.\n"
                "  Give a subagent its own state: GAME_LOOP_SESSION=<unique> game_loop ..\n"
                "  BLIND SPOT: an in-process subagent in the SAME tree shares this cwd and cannot be\n"
                "  told apart here at all. The words are the only tell, which is where #88 landed too.")
        try:
            tblock = stop_trigger_block(s, payload, notices)
        except Exception as exc:  # noqa: BLE001 — belt beside the braces in _run_trigger
            # That runner already turns everything a command can do into an answer, so reaching here
            # means the promise was wrong. This is the one case that would gate every turn-end in
            # the tree, so it fails open and says so rather than trusting the layer below it.
            tblock = None
            notices.append(f"⚠ STOP TRIGGERS CRASHED INSIDE THE HARNESS — {exc}\n"
                           "  The turn is ending UNCHECKED. Nothing your project attached to `stop`\n"
                           "  was consulted; a harness fault must not cost a session its exit.")
            try:
                logline({"kind": "stop_trigger_failed_open", "why": "harness-crash",
                         "detail": str(exc)[:200]})
            except OSError:
                pass
        if notices:
            # Loud where somebody is watching, and DURABLE where nobody is: the log has every one of
            # these, and `status` re-states them for the next session. Turn-end is proceeding, so
            # this text cannot rely on the block channel it is reporting the absence of.
            print("\n".join(notices), file=sys.stderr)
        if tblock:
            # A trigger-sourced block is COUNTED like any other, so "how often did the gate hold"
            # keeps its meaning. `stop_blocks` is deliberately NOT touched: that counter is the
            # mandate breaker's fuel, and letting an attachment spend it would let one gate stand
            # another one down for a reason that has nothing to do with it.
            s["stop_gate_blocks_total"] = s.get("stop_gate_blocks_total", 0) + 1
            save(s)
            print(tblock, file=sys.stderr)
            sys.exit(2)
        # THE RETRO OWES ITS ENCODING (and a PARKED mandate is exempt — a human called that break
        # and must not be trapped by a bookkeeping debt). Checked after the trigger block so an
        # attachment's verdict still comes first, and before the consume block so it does not spend
        # a checkpoint the agent will still need.
        # OVERDUE BEATS UNPAID: being told to run a retro you have skipped twice over is more use
        # than being told to encode a retro you have not had. Same park exemption.
        _over = retro_overdue(s)
        if _over and not ((s.get("mandate") or {}).get("parked")):
            s["stop_gate_blocks_total"] = s.get("stop_gate_blocks_total", 0) + 1
            save(s)
            print("STOP GATE CLOSED — the retro is overdue and the nudge did not work.\n\n"
                  f"  {_over}\n\n"
                  "`status` has been saying this is due. A printed nudge is a thing to remember, and\n"
                  "this project's first invariant is that a rule the agent has to remember is followed\n"
                  "only some of the time. So it is a gate now, one full threshold past the nudge.\n\n"
                  "  game_loop stepback --notes \"what worked, where I deviated, what to encode\"\n\n"
                  "It will then hold again until you ENCODE something from it, or say on the record\n"
                  "that there was nothing to encode. The reflection was never the point.",
                  file=sys.stderr)
            sys.exit(2)
        _debt = retro_debt_open(s)
        if _debt and not ((s.get("mandate") or {}).get("parked")):
            s["stop_gate_blocks_total"] = s.get("stop_gate_blocks_total", 0) + 1
            save(s)
            print("STOP GATE CLOSED — you ran a retro and encoded nothing from it.\n\n"
                  f"  the retro landed at {_debt}, and no `harden` has been logged since.\n\n"
                  "A retro that lists learnings and encodes none is indistinguishable, a week later,\n"
                  "from one that never happened — both leave a session where nothing got enforced.\n"
                  "The reflection was never the point; the encoding is.\n\n"
                  "  game_loop harden --learning \"..\" --artifact <real path> --mechanism \"..\" --rung <1..6>\n\n"
                  "If this chapter genuinely taught nothing, that is a legitimate outcome and costs\n"
                  "one sentence on the record:\n\n"
                  "  game_loop stepback --nothing-to-harden --reason \"<why>\"\n\n"
                  "This gate exists because the printed instruction was not enough: a consumer ran\n"
                  "the retro, produced a full reflection, and hardened nothing.",
                  file=sys.stderr)
            sys.exit(2)
        if (rec or {}).get("kind") == "mandate_park_stop":
            # CONSUME: one park == one turn-end (the break itself). The mandate stays parked — it is
            # not a closure — but the pass is gone, so the gate is live again on the next turn-end.
            s["mandate"]["parked"]["spent"] = True
        if s.get("t3_armed") and not s["t3_armed"].get("spent"):
            # CONSUME: one arm == one interruption. A Slack-paged arm keeps its thread ts alive —
            # marked spent, not nulled — so the watchdog can still poll the human's reply back into
            # the run (poll_slack_replies reads t3_armed.slack_ts). `spent` stops the SAME arm from
            # re-opening the gate on a later turn-end, so the one-interruption invariant still holds.
            # A plain arm (no slack_ts) is nulled outright, exactly as before.
            # KEEP WHAT WAS ASKED. The arm is the only record that a human was put in front of a
            # question, and nulling it destroyed that record at the exact moment it was earned —
            # so `authorize` two minutes later, acting ON the answer, read the live arm, found
            # nothing, and logged `asked_via_arm: false` permanently. Its own line says a hatch
            # spent with nobody asked and one spent after asking must not read the same later, and
            # this made them read the same, in the direction that matters: the diligent order —
            # ask, get an answer, then act — was the one recorded as careless. Observed twice in
            # one session, on two authorizations the human had explicitly granted out loud.
            s["t3_last_asked"] = {"question": (s["t3_armed"].get("question") or ""),
                                  "at": now()}
            if s["t3_armed"].get("slack_ts"):
                s["t3_armed"]["spent"] = True
            else:
                s["t3_armed"] = None
            s["t3_spend_count"] = s.get("t3_spend_count", 0) + 1
        s["stop_ok"] = False                # CONSUME: one checkpoint == one turn-end
        s["stop_ok_notes"] = None
        s["stop_blocks"] = 0
        save(s)
        sys.exit(0)
    s["stop_blocks"] = s.get("stop_blocks", 0) + 1
    s["stop_gate_blocks_total"] = s.get("stop_gate_blocks_total", 0) + 1
    fl = flair_lines(s, "stopgate")   # a fun "kept me on track" line + any milestone shout-out
    save(s)
    if fl:
        reason = reason + "\n\n" + "\n".join(fl)
    print(reason, file=sys.stderr)
    sys.exit(2)


# ── phase / status / notes ───────────────────────────────────────────────────────────────────────

def cmd_trans(s, a):
    ph = s.setdefault("phase", {})
    frm = ph.get("tier")
    if a.tier:
        ph["tier"] = a.tier
    if a.milestone:
        ph["milestone"] = a.milestone
    if a.doing is not None:
        ph["doing"] = a.doing
    ph["since"] = now()
    # STAMP THE COMMIT, NOT ONLY THE DATE. `since` has been recorded since the beginning and the
    # date alone cannot catch a phase that went stale within the hour it was written — measured
    # here, a phase written at 00:22 was three commits behind by 00:47 and the date note was
    # correctly silent the whole time. None when git cannot answer, which phase_head_note reads
    # as "nothing to compare" rather than as agreement.
    ph["head"] = _git("rev-parse", "--short", "HEAD")
    # A task-only update (just --doing) refreshes the current task without counting as a phase move,
    # so naming every task doesn't spam the retro nudge into being ignored.
    is_move = bool(a.tier or a.milestone)
    if is_move:
        s["trans_since_stepback"] = s.get("trans_since_stepback", 0) + 1
    save(s)
    logline({"kind": "trans", "from": frm, "to": ph.get("tier"),
             "milestone": ph.get("milestone"), "doing": ph.get("doing"),
             "doing_only": not is_move})
    out(render_banner(s, frm))
    if is_move and (n := retro_nudge(s)):
        out(n)


def _hooks_stale_warning(probe_f):
    """The probe EXISTS — but existence is a fact about history, and the question is present tense.

    REGISTERED, FIRED and LISTENING NOW are three different claims (#43). The check tested `isfile`
    and nothing else, so a Stop hook that fired an hour ago and has since died read exactly like a
    healthy one, for the rest of the session. The mtime was sitting right there, unused.

    Judged against THIS RUN'S OWN activity rather than an invented constant: a Stop hook fires at
    every turn-end, so a probe much older than the work this session is doing is evidence of a hook
    that stopped, not of a quiet run. An idle session moves neither marker and correctly triggers
    nothing. The slack is there because one long turn is the honest false positive — activity with
    no turn-end yet is not a dead hook.

    Nothing re-arms a long-lived hook while a session is idle: only a turn-end or a session start
    does, and an idle agent produces neither. So the window this covers is exactly the one an
    unattended run spends most of its time in.

    WHAT IT STILL CANNOT PROVE (INV6): a probe shows the hook ran AT THAT MOMENT, never that it will
    run at the next one. No check makes a live process a guarantee. The goal is "you would find
    out", not "it cannot happen" — which is why this reports and never blocks.
    """
    try:
        probe_age = time.time() - os.path.getmtime(probe_f)
    except OSError:
        return None
    acts = []
    for f in (STATE_F, LOG_F):          # both are written by ordinary work, so they track the RUN
        try:
            acts.append(time.time() - os.path.getmtime(f))
        except OSError:
            pass
    if not acts:
        return None
    activity_age = min(acts)
    slack = float(config().get("hooks_probe_slack_sec", 1800))
    if probe_age <= activity_age + slack:
        return None
    return (
        "\u26a0 THE STOP GATE MAY HAVE STOPPED FIRING \u2014 its probe is "
        f"{probe_age / 60:.0f} min old, while this\n"
        f"  session was working {activity_age / 60:.0f} min ago. A Stop hook fires at EVERY "
        "turn-end, so a probe much\n"
        "  older than the work is evidence of a hook that died, not of a quiet run. Nothing "
        "re-arms a\n"
        "  long-lived hook while a session is idle \u2014 only a turn-end or a session start does "
        "\u2014 so this is\n"
        "  the window an unattended run spends most of its time in.\n"
        "  \u2192 Reload the window (VSCode) or start a new session to re-register, then re-read "
        "this line.\n"
        "  (It proves the hook ran AT THAT MOMENT, never that it will run at the next one. One long "
        "turn\n"
        "   with no turn-end yet is the honest false positive: widen hooks_probe_slack_sec.)")


def hooks_live_warning():
    """Are the hooks actually WIRED IN to the running session, not merely on disk?

    Claude Code snapshots hook configuration when a session starts. `install.sh` writes
    `.claude/settings.json` mid-session, so on the install session — and only that one — every hook
    is registered on disk and never invoked. Nothing errors. The gate is silent because it is not
    running, which is indistinguishable from a gate that is running and content.

    That cost a full unattended session: a T3 arm sat unspent for 22 hours across dozens of
    turn-ends, and the human's read was "you must not be on the game_loop" — which was exactly right.

    The tell is the probe. `cmd_stopgate` writes `probe/stop-payload.json` on EVERY invocation, so
    its absence means no Stop hook has been recorded here. Rung 5 of the harden ladder: the fact is
    REPORTED rather than left to be guessed.

    WHAT THE PROBE DOES NOT PROVE, and this is the correction that earned this paragraph: absence is
    a statement about the PROBE'S lifetime, not the hook's. A checkout that was working before the
    probe existed reads identically to one that never fired, until its next Stop. So this says "no
    record", never "never fired" — a guard that overstates its reach buys false confidence (INV6),
    and a diagnostic is least trustworthy exactly when someone first runs it to decide whether to
    trust the wiring. Another project adopting this pattern had its own tool report a hook as
    never-fired that its author had watched work minutes earlier.

    THE REMEDY DEPENDS ON THE HOST. Claude Code as the VSCode extension registers hooks with the
    session at WINDOW LOAD, so reloading the window is what actually wires them — cheaper than, and
    sufficient without, a restart. Detected by CLAUDE_CODE_ENTRYPOINT (`claude-vscode`), never by
    TERM_PROGRAM: that is equally true of a plain `claude` in VSCode's integrated terminal, where the
    remedy really IS a restart, and it is unset here entirely — so keying off it does not merely
    misdirect, it detects nothing and falls through, which is the silent failure again.
    """
    probe_f = os.path.join(ROOT, "probe", "stop-payload.json")
    if os.path.isfile(probe_f):
        # It fired at least once. That answers "registered" and "has fired" — never "listening now".
        return _hooks_stale_warning(probe_f)
    if True:
        vscode = os.environ.get("CLAUDE_CODE_ENTRYPOINT") == "claude-vscode"
        remedy = ("Reload the VSCode window — the extension registers hooks at window load, so a\n"
                  "  hook written mid-session stays inert until then (a restart also works, and "
                  "costs more)."
                  if vscode else
                  "Start a new session — hooks are read at session start (or /hooks).")
        return ("⚠ HOOKS NOT LIVE — no record of the Stop gate firing in this checkout (no "
                "probe/stop-payload.json).\n"
                "  Claude Code reads hooks when a session starts; install.sh wrote "
                ".claude/settings.json\n"
                "  after this one began, so nothing here is enforced yet.\n"
                f"  → {remedy}\n"
                "  (This tracks the PROBE's lifetime, not the hook's: a checkout that fired before\n"
                "   probing shipped reads the same way until its next Stop.)")
    return None


def limits_inert_warning(snap):
    """The usage-limit family has exactly ONE source of truth, and it can go missing in silence.

    `rate_limits` is carried by the statusline payload and nothing else — verified against the
    shipped CLI binary, where the field is built as `(v.five_hour||v.seven_day)&&{rate_limits:v}`
    beside `context_window` and `vim.mode`, and appears nowhere near `hook_event_name`. So when no
    snapshot exists, THREE gates fail open at once and none of them says a word: `limitgate` never
    demands a handoff, the watchdog never parks, and nothing rings the run awake when the window
    resets. A run can burn to its limit and stop dead while every check reports fine.

    That is the whole reason this speaks. Absence of the snapshot is absence of SIGNAL, never
    evidence of headroom, and the old status line ("the tap hasn't fired ... it fills on the first
    API response") read as a benign not-yet — the failure it describes is indistinguishable from
    success until the limit arrives, which is the one moment nothing can be done about it.

    Returns None only when a snapshot actually carries a window; both "no file" and "file with no
    windows" are inert and say so, because for the human waiting on a page they are the same thing.
    """
    if snap and (snap.get("windows") or {}):
        return None
    cost = ("  While this is true: no page at the threshold, no park at exhaustion, and no ring "
            "when the\n  window resets — a limit will stop the run silently.")
    if os.environ.get("CLAUDE_CODE_ENTRYPOINT") == "claude-vscode":
        return ("⚠ USAGE-LIMIT PROTECTION IS INERT — no limits snapshot, and this host is the "
                "VSCode\n  extension (CLAUDE_CODE_ENTRYPOINT=claude-vscode), whose UI renders no "
                "terminal statusline.\n" + cost + "\n"
                "  → Treat it as UNAVAILABLE here rather than pending. A session run from a "
                "terminal\n    (`claude` in a shell) does fire the tap; in this window, hand off "
                "on your own clock.")
    if snap is None:
        return ("⚠ USAGE-LIMIT PROTECTION IS INERT — the statusline tap has never fired in this "
                "checkout,\n  so no snapshot exists.\n" + cost + "\n"
                "  → Check that `statusLine` is registered in .claude/settings.json (install.sh "
                "wires it)\n    and that this host renders one. It fills on the first statusline "
                "refresh.")
    return ("⚠ USAGE-LIMIT PROTECTION IS INERT — the tap fired, but the payload carried no usage "
            "windows.\n  That is what API-key auth looks like: limits are exposed to subscription "
            "sessions only.\n" + cost + "\n"
            "  → Nothing to fix if this account is API-key based; the gates simply cannot arm.")


SESSION_TTL_DAYS = 30


def _prune_stale_sessions():
    """Opportunistic GC, run from `status` (the verb every session runs first). A session dir whose
    state hasn't been touched in SESSION_TTL_DAYS and holds no active mandate is a finished run's
    residue — prune it. An ACTIVE mandate is never pruned, however old: age is not evidence the work
    was abandoned, and deleting a live mandate would silently disarm its session's gates."""
    cutoff = time.time() - SESSION_TTL_DAYS * 86400
    pruned = 0
    try:
        entries = os.listdir(SESSIONS_DIR)
    except OSError:
        return
    for d in entries:
        if d == SESSION:
            continue
        sdir = os.path.join(SESSIONS_DIR, d)
        sf = os.path.join(sdir, "state.json")
        try:
            if os.path.getmtime(sf) > cutoff:
                continue
            with open(sf) as f:
                if (json.load(f).get("mandate") or {}).get("active"):
                    continue
        except (OSError, ValueError):
            try:
                if os.path.getmtime(sdir) > cutoff:   # stateless/unreadable: prune on dir age alone
                    continue
            except OSError:
                continue
        shutil.rmtree(sdir, ignore_errors=True)
        pruned += 1
    if pruned:
        logline({"kind": "sessions_pruned", "count": pruned, "ttl_days": SESSION_TTL_DAYS})


def _sibling_sessions():
    """(other-session count, how many of those hold an active mandate) — visibility, not enforcement."""
    others = active = 0
    try:
        for d in os.listdir(SESSIONS_DIR):
            if d == SESSION:
                continue
            try:
                with open(os.path.join(SESSIONS_DIR, d, "state.json")) as f:
                    st = json.load(f)
            except (OSError, ValueError):
                continue
            others += 1
            if (st.get("mandate") or {}).get("active"):
                active += 1
    except OSError:
        pass
    return others, active


def legacy_mandate_warning():
    """An active mandate left in the repo-global state.json gates NOBODY once state is per-session.

    That is a silent behavior change for a session that bound its mandate before the upgrade — its
    stop gate and watchdog just go quiet. Silence is the one failure mode this tool never accepts,
    so say it everywhere status is read until the owning session re-binds (or clears the old file).
    """
    if not SESSION:
        return None
    try:
        with open(LEGACY_STATE_F) as f:
            legacy = json.load(f)
    except FileNotFoundError:
        return None                      # no legacy file is genuinely nothing to report
    except (OSError, ValueError) as exc:
        # A FILE THAT EXISTS AND CANNOT BE READ IS NOT AN ABSENT ONE. Both used to return None, so a
        # CORRUPT state.json holding an active mandate rendered exactly like a project that never
        # had one -- in the function whose own docstring says silence is the failure this tool never
        # accepts. Demonstrated: truncating the JSON took the warning from one line to none, with
        # nothing anywhere saying a file had been skipped.
        #
        # The recovery is the same either way (re-bind the mandate), so this does not block; it
        # refuses to let "could not tell" wear the face of "nothing to report".
        return ("⚠ LEGACY MANDATE FILE UNREADABLE — .game_loop/state.json exists and could not be\n"
                f"  parsed ({exc.__class__.__name__}). Whether a pre-per-session mandate is still\n"
                "  active there CANNOT be established, and if one is, it gates nothing and nothing\n"
                "  will say so. Read or repair that file; if the work is still open, re-bind it:\n"
                "  game_loop mandate --set \"..\"")
    if not (legacy.get("mandate") or {}).get("active"):
        return None
    return ("⚠ LEGACY MANDATE — .game_loop/state.json (repo-global, pre-per-session) still holds an\n"
            "  active mandate. It no longer gates ANY session. The session that owns that work must\n"
            "  re-bind it:  game_loop mandate --set \"..\"  — then clear the old file's mandate with\n"
            "  GAME_LOOP_SESSION= game_loop mandate --clear --notes \"migrated to per-session state\"")


UPDATE_CACHE_TTL = 21600   # 6h — how long a latest-sha lookup is trusted before re-checking


def installed_version():
    """The game_loop commit sha this .game_loop/ was installed from, or None if unknown.

    install.sh writes it; its absence means an old install (or the game_loop source repo itself, which
    doesn't ship a VERSION — you read git there). No VERSION => the update check simply stays silent."""
    try:
        with open(VERSION_F) as f:
            v = f.read().strip()
        return v or None
    except OSError:
        return None


def _git_sha(path):
    """HEAD of the checkout at `path`, or None. Best effort: never raises, never stalls a report."""
    try:
        r = subprocess.run(["git", "-C", path, "rev-parse", "HEAD"],
                           capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return None
    return r.stdout.strip() or None if r.returncode == 0 else None


def running_version():
    """The commit the CODE now executing came from, which is not always the one installed here.

    installed_version() answers "what did install.sh put in this .game_loop/" — a fact about the
    HOME. Under a pin those are two different commits, and "the pinned copy is behind the repo" is
    invisible unless both are printed. A pin written by `self --pin` stamps VERSION; one made by
    hand (a `git worktree add`) has none, so git answers for it.
    """
    try:
        with open(os.path.join(CODE_ROOT, "VERSION")) as f:
            if (v := f.read().strip()):
                return v
    except OSError:
        pass
    return _git_sha(CODE_ROOT)


def _latest_version(repo, api_base):
    """Latest sha on the source repo's main, cached in .update_cache.json for UPDATE_CACHE_TTL. Best
    effort: on any network/parse failure return the last cached value if we have one, else None. This
    must never raise or stall status — it is a courtesy line, not a gate."""
    try:
        with open(UPDATE_CACHE_F) as f:
            cache = json.load(f)
        if (cache.get("repo") == repo and cache.get("latest")
                and time.time() - float(cache.get("checked_at", 0)) < UPDATE_CACHE_TTL):
            return cache["latest"]
    except (OSError, ValueError):
        cache = {}
    try:
        import urllib.request
        req = urllib.request.Request(
            f"{api_base.rstrip('/')}/repos/{repo}/commits/main",
            headers={"User-Agent": "game_loop-update-check",
                     "Accept": "application/vnd.github+json"})
        with urllib.request.urlopen(req, timeout=4) as resp:
            sha = (json.loads(resp.read().decode() or "{}") or {}).get("sha")
        if sha:
            try:
                with open(UPDATE_CACHE_F, "w") as f:
                    json.dump({"repo": repo, "latest": sha, "checked_at": time.time()}, f)
            except OSError:
                pass
            return sha
    except Exception:  # noqa: BLE001 — offline / rate-limited / parse error: fall back, never crash
        pass
    return cache.get("latest")   # stale-but-better-than-nothing, or None


BEHAVIOUR_F = os.path.join(ROOT, "behaviour.json")


def behaviour_changes(blob):
    """The entries in a behaviour record, ordered by seq. Tolerant by design: a malformed or
    truncated record is NO INFORMATION — never a crash, and never a confident 'nothing changed'."""
    try:
        d = json.loads(blob) if isinstance(blob, str) else blob
        entries = d.get("changes") if isinstance(d, dict) else None
        return sorted((e for e in (entries or [])
                       if isinstance(e, dict) and isinstance(e.get("seq"), int)),
                      key=lambda e: e["seq"])
    except (ValueError, AttributeError, TypeError):
        return []


def installed_behaviour_seq():
    """The highest seq this install SHIPPED with. A missing file means an install from before the
    record existed, which is 0 — it has seen none of them, and that is the honest reading."""
    try:
        with open(BEHAVIOUR_F) as f:
            return max((e["seq"] for e in behaviour_changes(f.read())), default=0)
    except OSError:
        return 0


def _remote_behaviour(repo, raw_base):
    """The record on main, or None. Best effort and bounded, exactly like the sha check: a status
    line must never stall on the network, and 'could not fetch' must not read as 'nothing changed'.
    """
    try:
        import urllib.request
        req = urllib.request.Request(
            f"{raw_base.rstrip('/')}/{repo}/main/.game_loop/behaviour.json",
            headers={"User-Agent": "game_loop-update-check"})
        with urllib.request.urlopen(req, timeout=4) as resp:
            return resp.read().decode()
    except Exception:  # noqa: BLE001 — offline, 404, parse error: no information, never a crash
        return None


def _compare_versions(repo, api_base, base, head):
    """Where `head` sits relative to `base` upstream: 'identical' / 'ahead' / 'behind' / 'diverged',
    or None when it cannot be determined.

    Ancestry is the question the update notice is actually asking, and INEQUALITY IS NOT IT (#49):
    installed != latest is true both when the install is behind (a real update) and when it is ahead
    (a false alarm), and those are opposite conditions. An install that runs ahead of a cached check
    reported backwards, and the suggested remedy was a no-op that left the notice in place.

    Best effort and bounded, like every other network call here: an answer nobody could fetch must
    not become a confident one in either direction.
    """
    try:
        import urllib.request
        req = urllib.request.Request(
            f"{api_base.rstrip('/')}/repos/{repo}/compare/{base}...{head}",
            headers={"User-Agent": "game_loop-update-check",
                     "Accept": "application/vnd.github+json"})
        with urllib.request.urlopen(req, timeout=4) as resp:
            return (json.loads(resp.read().decode() or "{}") or {}).get("status")
    except Exception:  # noqa: BLE001 — offline, rate-limited, unknown sha: no information
        return None


def waiting_state():
    """The waiting seam as data: configured? last verdict? failing? (#67)

    THE READ SIDE ONLY, DELIBERATELY. There is no setter and there will not be one: `waiting_probe`
    is config-only because a wait an agent can declare for itself is an off switch for the watchdog,
    and a verb that sets it is callable by the agent being watched. `--waiting-probe true` is a probe
    that always exits 0, which is the watchdog disarmed by the thing it watches. An orchestrator IS a
    different process and could be trusted with it — but the verb cannot tell who called it, and a
    guard that cannot identify its caller must assume the worst caller.

    To ARM it, write config.local.json: it is not an owned file, not byte-compared between a parent
    and its worktrees, and every config reader merges it — so a layer above can set this without
    authoring rules it does not own, which was the actual problem behind the request for a setter.
    """
    cmd = str(((config().get("watchdog") or {}).get("waiting_probe") or "")).strip()
    out = {"configured": bool(cmd), "command": cmd or None,
           "armed_in": None, "last": None, "failing": None,
           "set_it_by": ".game_loop/config.local.json -> watchdog.waiting_probe (NOT config.json, "
                        "which is a rule file byte-compared at spawn)"}
    if cmd:
        # WHICH FILE actually carries it, so a caller fixing a wrong value knows where to look
        # rather than editing the tracked one and having it byte-compare as drift.
        for name in ("config.local.json", "config.json"):
            try:
                with open(os.path.join(ROOT, name)) as f:
                    if str(((json.load(f).get("watchdog") or {}).get("waiting_probe") or "")).strip():
                        out["armed_in"] = name
                        break
            except (OSError, ValueError):
                continue
    if not cmd:
        return out
    last = None
    try:
        with open(LOG_F) as f:
            for ln in f:
                if '"watchdog_wait' not in ln:
                    continue
                try:
                    r = json.loads(ln)
                except ValueError:
                    continue
                if r.get("kind") in ("watchdog_waiting", "watchdog_wait_held"):
                    last = r
    except OSError:
        last = None
    if not last:
        return out                       # configured and never run: last stays None, not a verdict
    out["failing"] = last.get("answered") is False
    out["last"] = {"at": last.get("t"), "detail": last.get("detail") or "",
                   "waiting": bool(last.get("waiting")
                                   or last.get("kind") == "watchdog_wait_held"),
                   "answered": last.get("answered") is not False}
    return out


def stop_seam(s):
    """Is this session blocked at a turn-end gate — since when, by which attachment, how many?

    THE STATE WAS ALWAYS HERE AND NOTHING READ IT OUT. A consumer that wanted to tell a blocked
    session from a working one had to parse session state, which is the coupling every --porcelain
    in this tool exists to end. Reported for the SESSION this state belongs to; a caller asking about
    a Crawler reads that Crawler's own tree.

    NOT A FRESH EVALUATION. It reports what the gate last decided, exactly as waiting_state does —
    re-running attachments to answer a question about the past would spend their budget and could
    return a different answer than the one that actually blocked the turn.
    """
    trig = s.get("stop_triggers") or {}
    blocking = {n: r for n, r in trig.items()
                if isinstance(r, dict) and r.get("verdict") == "blocked"}
    stood = {n: r for n, r in trig.items()
             if isinstance(r, dict) and (r.get("consecutive") or 0) >= STOP_TRIGGER_BLOCK_LIMIT}
    return {
        "blocked": bool(blocking),
        "blocks_total": int(s.get("stop_gate_blocks_total", 0) or 0),
        "limit": STOP_TRIGGER_BLOCK_LIMIT,
        "attachments": {n: {"verdict": r.get("verdict"),
                            "consecutive": r.get("consecutive", 0),
                            "at": r.get("at"),
                            "stood_down": (r.get("consecutive") or 0) >= STOP_TRIGGER_BLOCK_LIMIT,
                            "detail": (r.get("detail") or "")[:200]}
                        for n, r in trig.items() if isinstance(r, dict)},
        "stood_down": sorted(stood),
        # THE BOUND COUNTS CONSECUTIVE BLOCKS, so it catches a gate that keeps refusing and CANNOT
        # catch one refusal that leaves the session inert — a session that never attempts another
        # turn-end never produces a second block. Said here because a consumer reading `limit` would
        # otherwise reasonably assume it bounds the time a session can be stuck, and it does not.
        "bound_covers": ("repeated blocking by the same attachment. It does NOT bound a single "
                         "block: one refusal with nothing able to deliver 'go back to work' never "
                         "increments again, so the stand-down is never reached."),
    }


def cmd_watchdog(s, a):
    """Report the waiting seam. READ ONLY — see waiting_state for why there is no setter."""
    st = waiting_state()
    st["stop_gate"] = stop_seam(s)
    if getattr(a, "porcelain", False):
        out(json.dumps(st, indent=2))
        return
    _sg = st["stop_gate"]
    if _sg["blocked"]:
        for _n, _r in sorted(_sg["attachments"].items()):
            if _r.get("verdict") != "blocked":
                continue
            out(f"stop gate: BLOCKED at turn-end by `{_n}` since {_r.get('at') or 'an unknown time'}"
                f" ({_r.get('consecutive')} consecutive of {_sg['limit']})",
                "  A blocked session looks exactly like a working one from outside — live pid, exit "
                "0, artifacts on disk.",
                "  In a HEADLESS run nothing in this harness can deliver 'go back to work' by "
                "itself; the wake has to",
                "  come from outside. The stand-down bounds REPEATED blocking, not one block that "
                "leaves a session inert.")
    if not st["configured"]:
        out("waiting probe: NOT CONFIGURED — the watchdog rings on idle with no way to know whether "
            "this run is",
            "  waiting on work it dispatched. Arm it by setting watchdog.waiting_probe in",
            "  .game_loop/config.local.json — NOT config.json, which is a rule file byte-compared "
            "between a",
            "  parent checkout and its worktrees, so writing it there reports as drift.",
            "  There is no verb that sets it: a wait a session can declare for itself is an off "
            "switch for",
            "  the watchdog, and this verb cannot tell a session from the orchestrator above it.",
            "  THAT SENTENCE IS NARROWER THAN IT READS, and the difference is the whole of what "
            "this",
            "  protects. No VERB sets it, and config.local.json — which holds the pointer, and "
            "idle_sec",
            "  and ring_cap beside it — is a POLICY FILE the write guard refuses, by tool write "
            "and by",
            "  shell redirect alike. The SCRIPT it names is refused too, resolved from the config "
            "value",
            "  rather than by name, so repointing does not escape it.",
            "",
            "  WHAT IS STILL OPEN, because a guard that overstates itself is the failure this "
            "whole",
            "  message is about: idle_sec and settle_sec also honour WATCHDOG_IDLE_SEC / "
            "WATCHDOG_SETTLE_SEC,",
            "  and reaching a hook's environment means .claude/settings.json, which this guard "
            "does not",
            "  cover. ring_cap has no env override. So the file doors are shut and the "
            "environment door",
            "  is not.",
            "",
            "  Measured here: this repo's own agent extended its probe mid-run to treat a long "
            "measurement",
            "  as a wait — objective, bounded, failing toward ringing, done carefully. THE CARE "
            "IS NOT THE",
            "  POINT: a session deciding when its own watchdog stops ringing is the defect "
            "regardless of",
            "  how well it decides, and a careless version would have been easier to see.",
            "",
            "  PASTE THIS, adjusting the command — one file, once per install:",
            '    {"watchdog": {"waiting_probe": "<your command>"}}',
            f"    -> {os.path.join(ROOT, 'config.local.json')}")
        return
    out(f"waiting probe: configured in {st['armed_in'] or 'an unknown file'}",
        f"  {st['command']}")
    if st["failing"]:
        out("  ⚠ FAILING — it is not answering. Until it does, 'no work outstanding' and 'the probe "
            "is broken'",
            "    look the same from here.")
    elif st["last"]:
        out(f"  last verdict: {'WAITING' if st['last']['waiting'] else 'not waiting'} "
            f"as of {st['last']['at']}"
            + (f" · {st['last']['detail']}" if st["last"]["detail"] else ""))
    else:
        out("  the watchdog has not run it yet — no verdict to report, which is not the same as a "
            "verdict of 'not waiting'.")


def waiting_report():
    """What the watchdog last concluded about a declared wait. Silent unless a probe is configured.

    "What is this run blocked on" is the first question a resumed session asks, and before #32 there
    was nowhere to read it. Shown from the LOG rather than by re-running the probe: status must stay
    cheap, and the interesting fact is what the watchdog acted on, not what a fresh run would decide.
    """
    if not str(((config().get("watchdog") or {}).get("waiting_probe") or "")).strip():
        return []
    last = None
    try:
        with open(LOG_F) as f:
            for ln in f:
                if '"watchdog_wait' not in ln:
                    continue
                try:
                    r = json.loads(ln)
                except ValueError:
                    continue
                if r.get("kind") in ("watchdog_waiting", "watchdog_wait_held"):
                    last = r
    except OSError:
        return []
    if not last:
        return ["waiting: a probe is configured, but the watchdog has not run it yet — its verdict "
                "appears here once it does."]
    detail = last.get("detail") or ""
    # A probe that could not ANSWER is a third state, and it used to be absorbed into "not waiting"
    # — where it is invisible for as long as there is work, then wrong the moment there is not.
    if last.get("answered") is False:
        return [f"⚠ THE WAITING PROBE IS FAILING, not answering — as of {last.get('t', '?')}"
                + (f" · {detail}" if detail else ""),
                "  It must exit 0 (waiting) or 1 (not waiting); anything else means it could not "
                "tell, and",
                "  the watchdog rings. Until it answers, 'no work outstanding' and 'the probe is "
                "broken' look",
                "  the same from here — which is the failure this probe exists to prevent, one "
                "level out."]
    verdict = "WAITING on dispatched work" if last.get("waiting") or \
              last.get("kind") == "watchdog_wait_held" else "not waiting"
    return [f"waiting: {verdict} — as of {last.get('t', '?')}" + (f" · {detail}" if detail else ""),
            "  (the watchdog's own last verdict, not a fresh one; it is conservative toward NOT "
            "waiting)"]


SESSION_START_PROBE = os.path.join(ROOT, "probe", "session-start.json")


def cmd_sessionstart(s, a, payload):
    """Run `status` at session start (and after a compaction), and inject it into the session.

    THE GAP THIS CLOSES is discoverability, not enforcement. The PreToolUse guards already fire
    without being asked, so the write guard and the MCP guard were never subject to this. What was
    subject to it is everything behind a VERB -- the claim gate, harden, the mandate machinery, the
    retro, and `status` itself. A tree could carry a perfectly provisioned harness and still run
    completely bare, because nothing made the entry point run.

    A BANNER WOULD HAVE BEEN THE WRONG FIX. "The harness is here, run status" holds only while the
    agent chooses to act on it, which is rung 6 of the ladder applied to the gap that decides whether
    any other rung runs at all (INV1). So this runs the verb, not an advertisement for it.

    PostCompact matters as much as SessionStart: compaction is exactly when a run loses the mandate,
    the pins and the invariants, and this repo's own instruction has always been "run status every
    session AND after any compaction". Now the harness does it.

    THREE THINGS IT HAS TO GET RIGHT, or it becomes the defect it fixes:
      * NEVER BLOCKS. A first impression that bricks a session is one nobody gives a second chance,
        so every failure path exits 0 with no output.
      * IT MUST BE OBSERVABLE THAT IT FIRED, or this is the statusline tap (#45) and the Stop probe
        (#43) again -- a check whose silence is indistinguishable from never having run.
      * IT DEGRADES DURING INSTALL AND UPGRADE. Mid-install, or on a branch with no .game_loop/, it
        says nothing rather than erroring: a guard must never block its own fix (INV5).

    THE `session_start` TRIGGER MOMENT INHERITS ALL THREE (#63), and inherits them the hard way: an
    attachment is a project's ARBITRARY command running on the one path every session crosses. So it
    is bounded by the trigger timeout, wrapped so nothing it does can raise out of here, and its
    outcome is written to state where `triggers_report` prints it in the very block this returns.
    """
    if not config().get("session_start", True):
        return                       # a project that wants silence gets silence, opt-out not opt-in
    try:
        os.makedirs(os.path.dirname(SESSION_START_PROBE), exist_ok=True)
        with open(SESSION_START_PROBE, "w") as f:
            json.dump({"at": now(), "session": SESSION,
                       "source": payload.get("source") or payload.get("hook_event_name") or ""}, f)
    except OSError:
        pass                         # the probe is evidence, never a precondition
    # FIRED BEFORE STATUS IS RENDERED, on the `stepback` precedent — there the attachment runs first
    # so what it read is an INPUT to the reflection rather than an appendix to it, and here the same
    # ordering buys the observability: the attachment acts, its outcome lands in state, and the
    # TRIGGERS block `status` is about to print therefore reports THIS run rather than the previous
    # session's. One moment, one text, no second place to look.
    #
    # Its OWN try/except, not the status one, and the split is the whole of INV5 here: this is the
    # only code in the entry point that runs a command nobody in this repo wrote. If it explodes the
    # session still gets its status, because an attachment is an addition to the moment and never a
    # precondition for it. fire_triggers already promises not to raise; the wrapper is for the
    # promise being wrong, which is the case that would gate EVERY session in the tree.
    fired = []
    try:
        fired = fire_triggers(s, "session_start", {
            "event": "session_start",
            "source": payload.get("source") or payload.get("hook_event_name") or "",
            "project": config().get("project_name"), "session": SESSION})
    except Exception:  # noqa: BLE001 — no attachment gets to cost a session its start
        fired = []
    parts = []
    try:
        import io
        import contextlib
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            cmd_status(s, a)
        if (text := buf.getvalue().strip()):
            parts.append(text)
    except Exception:  # noqa: BLE001 — mid-install, half-written state, anything: say nothing
        pass           # ...about STATUS. A trigger that has already ACTED still gets to report it:
        #                dropping its output would leave a session that was acted upon and not told.
    if fired:
        parts.append("\n".join(fired))
    if not parts:
        return
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": payload.get("hook_event_name") or "SessionStart",
        "additionalContext": "\n".join(parts)}}))


def session_start_warning():
    """Silent unless a session start SHOULD have been seen and was not (#48).

    Same shape as the Stop probe's age check (#43), and for the same reason: registered, fired, and
    firing now are three different claims. A SessionStart hook that silently stops firing takes the
    whole entry point with it, and nothing else would notice.
    """
    if not config().get("session_start", True):
        return []
    if os.path.isfile(SESSION_START_PROBE):
        return []
    return ["⚠ NO SESSION START RECORDED — the SessionStart hook has not fired in this checkout, so "
            "nothing runs",
            "  `status` for you automatically and a fresh session learns none of this exists. It is "
            "registered by",
            "  install.sh; hooks are read when a session starts, so reload the window (VSCode) or "
            "start a new",
            "  session. (This tracks the PROBE's lifetime, not the hook's — a checkout that fired "
            "before probing",
            "   shipped reads the same until its next start.)"]


AUTO_HANDOFF_MARK = "<!-- game_loop:auto -->"


def build_handoff(s):
    """The run's state as a handoff, assembled from what the harness already knows.

    #45's real fix. The usage-limit gate's purpose was never "know the number" -- it was "do not die
    with your state only in your head". Warning was one way to buy that, and it is the way that
    depends on a number this host cannot have: rate_limits rides the statusline payload and nothing
    else, so in an editor session the gauge can never arm.

    So instead of predicting the cliff, never be far from the edge. A handoff refreshed at every
    turn-end means a limit death costs at most one turn, in ANY host, with no calibration and no
    configured budget standing for nothing.

    Assembled rather than written: everything here is already recorded, so this cannot go stale the
    way prose does, and it costs the agent nothing to maintain. WHAT IT IS NOT (INV6): it is not
    the agent's own account of its reasoning. It says what the run was DOING, not why -- a
    hand-written handoff is still better, and `checkpoint --notes` is what puts words in this one.
    """
    m = s.get("mandate") or {}
    ph = s.get("phase") or {}
    lines = [AUTO_HANDOFF_MARK,
             "# HANDOFF — written automatically at every turn-end",
             "",
             f"_Generated {now()} by game_loop. Overwritten each turn; edit `checkpoint --notes` to",
             "put your own words in it, not this file._",
             "",
             "## The job"]
    lines.append(f"- mandate: {m.get('text') or '(none bound)'}")
    if ph.get("milestone") or ph.get("doing"):
        lines.append(f"- phase: {ph.get('milestone') or '?'} · {ph.get('doing') or '?'}")
    last = None
    kinds = {"checkpoint": "checkpoint", "mandate_set": "mandate bound",
             "stepback": "retro", "harden": "hardened", "claim": "claim"}
    recent = []
    try:
        with open(LOG_F) as f:
            for ln in f:
                try:
                    r = json.loads(ln)
                except ValueError:
                    continue
                if r.get("kind") in kinds:
                    recent.append(r)
                    if r.get("kind") == "checkpoint":
                        last = r
    except OSError:
        pass
    # STATE first, log second. A checkpoint is logged by the Stop gate when it CONSUMES it, and
    # this runs earlier in the same invocation — so the freshest report is the one still pending in
    # state, and reading only the log would always be one turn behind.
    pending = s.get("stop_ok_notes")
    lines += ["", "## Last reported progress",
              ("- " + pending) if pending else
              ("- " + (last.get("notes") or "(no notes)")) if last
              else "- no checkpoint recorded yet in this checkout"]
    if recent:
        lines += ["", "## The last few recorded moves"]
        for r in recent[-8:]:
            what = r.get("notes") or r.get("learning") or r.get("assert") or r.get("text") or ""
            lines.append(f"- {r.get('t', '?')} · {kinds[r['kind']]}: {str(what)[:110]}")
    pins = shared_pins()
    if pins:
        lines += ["", "## Do NOT tidy these away"]
        lines += [f"- [{p.get('id')}] {p.get('fact')} — {p.get('reason')}" for p in pins]
    ahead, branch, upstream = ahead_of_upstream()
    if ahead:
        lines += ["", f"## Unpushed: {ahead} commit(s) on {branch} not on {upstream}"]
    lines += ["", "## Where to pick up",
              "- `./.game_loop/bin/game_loop status` first: it re-injects the invariants, the "
              "mandate, the pins and the ruled-out list."]
    return "\n".join(lines) + "\n"


def refresh_handoff(s):
    """Write the handoff, unless a HUMAN-authored one is sitting there.

    A generated file must never overwrite somebody's own words. The marker is how it tells its own
    output apart from a hand-written file -- absent marker, absent write.
    """
    p = handoff_path()
    try:
        if os.path.isfile(p):
            with open(p) as f:
                if AUTO_HANDOFF_MARK not in f.read(200):
                    return False        # somebody wrote this by hand; it outranks anything generated
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as f:
            f.write(build_handoff(s))
        return True
    except OSError:
        return False                    # a handoff that cannot be written must not break the gate


_USAGE_TAIL_BYTES = 2 * 1024 * 1024


def trailing_usage(transcript_path, window_sec=5 * 3600):
    """Two readings from ONE pass over the transcript's tail, or None.

    `output_tokens` is EVIDENCE, GATING NOTHING. There is no honest threshold to compare it against:
    the raw counts do not map to the account's real limit -- one session showed 1.59M output against
    766G cache-read, weighted server-side in ways nothing local can see -- and a limit being hit
    leaves no trace in any transcript, so it cannot learn the number by watching itself get cut off.

    Recording it anyway is INV4 applied to ourselves: no gate without a logged, observed failure. A
    threshold invented today would be a number standing for nothing, which is exactly the defect the
    landed half of #45 fixed. A threshold in a few weeks would be measured.

    `context_tokens` IS load-bearing -- the context trigger reads it -- and it is a different kind
    of number entirely: input_tokens + cache_read_input_tokens + cache_creation_input_tokens on the
    last assistant record is exactly what was sent on that call. Nothing is mapped, weighted or
    guessed, so unlike the output count there is a threshold it can honestly be compared against.
    It is computed HERE rather than by a second reader, because two transcript parsers is two
    chances to disagree about which record is last.

    It is taken from the last record in the file rather than the last inside `window_sec`: the Stop
    hook runs seconds after the turn it is reading, so the newest record IS this turn, and filtering
    it by a five-hour cutoff would only ever drop a reading in a session that had gone quiet.
    Sidechain records are skipped -- a subagent's turn carries its own context, and reading one as
    the main thread's would report a collapse the parent never had.

    Bounded: only the transcript's tail is read, so a long session does not pay for its own history.
    """
    if not transcript_path:
        return None
    try:
        with open(transcript_path, "rb") as f:
            f.seek(0, os.SEEK_END)
            start = max(0, f.tell() - _USAGE_TAIL_BYTES)
            f.seek(start)
            lines = f.read().decode("utf-8", "replace").splitlines()
    except OSError:
        return None
    if start and lines:
        lines = lines[1:]               # a tail read can slice a line in half
    cutoff = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=window_sec)
    total, seen, ctx = 0, 0, None
    for ln in lines:
        if '"usage"' not in ln:
            continue
        try:
            r = json.loads(ln)
        except ValueError:
            continue
        u = (r.get("message") or {}).get("usage") or {}
        ts = r.get("timestamp")
        if not u:
            continue
        if not r.get("isSidechain"):
            try:
                ctx = (int(u.get("input_tokens") or 0)
                       + int(u.get("cache_read_input_tokens") or 0)
                       + int(u.get("cache_creation_input_tokens") or 0)) or ctx
            except (TypeError, ValueError):
                pass                    # a record that will not add up is not a reading of zero
        if not ts:
            continue
        try:
            when = datetime.datetime.fromisoformat(str(ts).replace("Z", "+00:00"))
        except ValueError:
            continue
        if when < cutoff:
            continue
        total += int(u.get("output_tokens") or 0)
        seen += 1
    if not seen and not ctx:
        return None
    rec = {"output_tokens": total, "records": seen, "window_sec": window_sec}
    if ctx:
        rec["context_tokens"] = ctx
    return rec


# ── successor ────────────────────────────────────────────────────────────────────────────────────

SUCCESSOR_PROMPT = ("Read {handoff} in full, then continue the work it describes. "
                    "It is a handoff from a previous session; you have no other context.")

SUBJECT_MAX = 100


# A heading is a subject only when it NAMES THE WORK. These spellings name a SESSION instead —
# `# Handoff — session 6acce140`, `# Handoff — 6acce140-e2c3-4cb0-badb-8d90585d9713`, `# Handoff —
# session verify-e2e` — and all of them are written by this harness's own conventions, which is why
# the check lives here rather than in advice about writing better headings.
#
# THE SECOND ARM CAME FROM THE LIVE RUN THAT VERIFIED THE FIRST. A real handover through saggar on
# 2026-08-25 carried `# Handoff — session verify-e2e`: not hex, so the id rule let it through, and
# the terminal Claude titled off that prompt came out "Verify e2e" — the same nothing, spelled
# differently. `session <one token>` names a session whatever the token is; only a description
# after it says what the session is DOING.
#
# Anchored whole, in both arms: `session 6acce140 — merge into main` survives, because an id in
# front of a description is a prefix and the description is the label.
ID_LABEL_RE = re.compile(r"^(?:session\s+)?[0-9a-f]{8}"
                         r"(?:-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})?$"
                         r"|^session\s+\S+$", re.I)


def _is_id_label(text):
    return bool(ID_LABEL_RE.match(" ".join(str(text or "").split())))


def successor_subject(hp, about=None, s=None):
    """The short line that says WHAT IS BEING WORKED ON, prepended to the successor's prompt.

    `successor` refuses to paraphrase the handoff into the prompt, for a reason that has not
    changed: a paraphrase is a second copy of the state, free to disagree with the first, in the one
    session with no way to check. THIS IS THE EXCEPTION, and it is one because the thing it fixes is
    not a gap in the successor's knowledge — the successor reads the file — but a gap in the
    HUMAN'S. `Read /repo/.game_loop/sessions/8aae5d8f/HANDOFF.md in full` is the first line of the
    new session, the command in the tab config, and the row a person scans in a screen of eight
    terminals asking which one is doing the thing they care about. It answers that with a UUID.

    So the subject is a LABEL — never an instruction, never a status, never a next step, all of
    which live in the file the prompt already points at. And it is DERIVED rather than authored,
    which is what keeps it from becoming the second copy: a label lifted out of something that
    already exists cannot disagree with it.

    THE ORDER IS THE INTERESTING PART, because game_loop knows something a handoff file does not.

    1. `--about`, when a human said what this is about. `--about ""` turns the subject off.
    2. The document's own `# ` heading — the hand-written handoff's one-line description.
    3. THE MANDATE. The generated handoff's heading is boilerplate ("written automatically at every
       turn-end") and describes nothing, so it is skipped rather than used; but a session running
       under a mandate has already been told, in a human's words, what it is for. That is a better
       subject than any heading, and it is the case that matters most — an unattended run handing
       over at 3am is exactly when nobody is there to have written a heading.
    4. The phase, when there is no mandate but the run said what it was doing.
    5. Nothing. No subject beats an invented one.
    """
    if about is not None:
        subject = about
    else:
        subject = ""
        try:
            with open(hp) as f:
                for line in f:
                    if line.startswith("# "):
                        subject = line[2:].strip()
                        break
        except OSError:
            subject = ""
        for kind in ("HANDOFF", "Handoff", "Delegation", "Work order"):
            for sep in (" — ", " – ", " - ", ": "):
                if subject.startswith(kind + sep):
                    subject = subject[len(kind + sep):]
            if subject == kind:
                subject = ""
        # The generated handoff describes when it was written, not what the run is doing. Using it
        # would put "written automatically at every turn-end" on every unattended handover.
        if "written automatically" in subject:
            subject = ""
        # AND A HEADING THAT IS A SESSION ID IS THE FAILURE THIS WHOLE FEATURE REPLACES. Observed
        # 2026-08-25: override_canvas handed over under `# Handoff — session 6acce140`, so the
        # subject was "session 6acce140" and the successor's prompt opened with the UUID the
        # docstring above names as the thing it exists to stop — the row a human scans answering
        # "which tab is doing the thing I care about" with the one string nobody can read. Skipped
        # rather than trusted, exactly as the generated heading is, and the fall-through below
        # reaches the MANDATE: a human's own words about the same run.
        if _is_id_label(subject):
            subject = ""
        if not subject and s is not None:
            m = (s.get("mandate") or {})
            if m.get("active") and m.get("text"):
                subject = str(m["text"])
            else:
                ph = (s.get("phase") or {})
                subject = str(ph.get("doing") or ph.get("milestone") or "")
    subject = " ".join(str(subject).split())
    if len(subject) > SUBJECT_MAX:
        subject = subject[:SUBJECT_MAX - 1].rstrip() + "\u2026"
    return subject

# The flag that starts a session with permission prompts bypassed. Read off the running binary
# (2.1.241) rather than remembered, and it sits there beside the refusal "Cannot set permission mode
# to bypassPermissions because the session was not launched with --dangerously-skip-permissions" —
# which is the whole reason this belongs to `successor` at all. It is a LAUNCH decision: a successor
# that starts without it cannot grant itself the bypass afterwards, so the only moment anybody can
# make it is the moment the command line is built, and by then the predecessor may be out of road.
SKIP_PERMISSIONS_FLAG = "--dangerously-skip-permissions"


# Warp's own identification of itself to child processes. Read off a live environment rather than
# guessed: TERM_PROGRAM=WarpTerminal, beside TERM_PROGRAM_VERSION=v0.2026.07.29.09.05.stable_02.
WARP_TERM_PROGRAM = "WarpTerminal"


def in_warp():
    """Whether THIS process is running under Warp.

    WHAT IT MISSES, which is the whole reason detection is a resolvable default and not a fact:
    TERM_PROGRAM is set by the terminal for its shell's children, so it reaches a verb the agent
    runs through Bash — which is how `successor` is invoked — and it is UNSET in a hook's
    environment (test/run.py asserts exactly that). A hook-invoked caller therefore reads
    "not Warp" whether or not Warp is on screen, and falls through to `print`. That is the safe
    direction — the fallback is a command a human can run anywhere — but it is a blind spot, not a
    negative result, so nothing here may report "you are not in Warp" as a finding.

    Nor does it distinguish Warp from something else exporting the same string; it is a self-report
    by the host, which is all any terminal offers.
    """
    return os.environ.get("TERM_PROGRAM") == WARP_TERM_PROGRAM


# saggar's own identification of itself to child processes. Read off a live environment rather than
# guessed: TERM_PROGRAM=saggar, beside SAGGAR=1 and SAGGAR_SESSION=<uuid naming THIS terminal>.
SAGGAR_TERM_PROGRAM = "saggar"

# Bounded because a parent chain that cycles must end a WALK, not a run. Eight is well past the
# deepest real tree measured here (python → zsh → claude is three), and the cost of guessing high
# is one extra `ps` on a machine that was already going to answer.
CLAUDE_ANCESTOR_HOPS = 8

# The agent process to look for when climbing. Overridable because the WALK is the part worth
# testing and the walk cannot be exercised against a process this suite is allowed to have: a test
# that arranged a real `claude` in its ancestry would be a test that kills one. Named rather than
# hardcoded, so what a test substitutes is visible in its environment instead of monkeypatched in.
AGENT_COMM = os.environ.get("GAME_LOOP_AGENT_COMM") or "claude"


def in_saggar():
    """Whether THIS process is running inside a saggar terminal.

    It reads SAGGAR_SESSION rather than TERM_PROGRAM, and the difference is the entire reason this
    detection is worth more than in_warp()'s. TERM_PROGRAM is unset in a hook's environment — the
    blind spot in_warp() documents and cannot close, and the reason `warp-tab` has to exist as a
    forced override at all. SAGGAR_SESSION reaches hooks: saggar's own Claude Code presence hook
    (~/.saggar/claude-presence-hook.sh) exits 0 immediately on an empty SAGGAR_SESSION and names its
    output file after the variable, and ~/.saggar/presence/<SAGGAR_SESSION>.json exists carrying this
    repo's live claude session id. That file could not have been written if the variable were absent
    where hooks run. So a hook-invoked `successor` resolves saggar correctly where it cannot resolve
    Warp, and `saggar-agent` needs no counterpart to the `warp-tab` override.

    WHAT IT MISSES, stated because a mode that resolves is not a mode that works: SAGGAR_SESSION
    names a TERMINAL, never a running app. A shell that outlived the app that spawned it, or an
    environment inherited by something detached, still carries the variable at a moment nothing is
    listening — and saggar answers that with exit 3. This resolves a mode; whether the mode acts is
    observed afterwards, which is why failure falls back to the printed command instead of dying.

    Nor does it distinguish saggar from something else exporting the same variable; like every
    terminal check here it is a self-report by the host, which is all any terminal offers.
    """
    return bool(os.environ.get("SAGGAR_SESSION"))


SUCCESSOR_MODES = ("auto", "print", "warp-tab", "saggar-agent")


def skip_permissions_grant():
    """Whether the successor's command carries SKIP_PERMISSIONS_FLAG, WHICH FILE granted it, and
    whether a grant was found in a file that is NOT allowed to make one.

    Returns (granted, source, ignored_in_tracked_config).

    TWO FILES MAY GRANT IT, and neither is the tracked one:
      ~/.game_loop/config.json      — machine-wide. "My successors do not stop to ask" is a fact
                                      about this MACHINE, and having to re-decide it in every repo
                                      is the ask that brought this layer into existence.
      .game_loop/config.local.json  — this checkout only. Read LAST, so a repo can say no where the
                                      machine says yes. That direction is the one that matters: a
                                      narrow file must be able to WITHDRAW a broad grant, and a
                                      reader that treated `false` as merely "no grant here" would
                                      leave the machine-wide one standing — the opposite of what
                                      somebody wrote it to mean.

    `ignored` is the reason this is a function rather than a dict lookup: the same key in the
    tracked config.json used to work, and a key that silently stops working is worse than one that
    never did. Somebody sets it, reads nothing, walks away -- and the unattended run they armed
    stalls on the first prompt at 3am, which is the precise failure this whole verb exists to
    prevent. So the tracked value is read for the sole purpose of SAYING IT WAS IGNORED.

    WHAT KEEPS THE MACHINE-WIDE GRANT HONEST is the property that already keeps the local one
    honest, arrived at from the other side. config.local.json is refused BY NAME by both write
    rails; the home file is refused because it is OUTSIDE THIS REPO, which is INV3 and covers it
    without needing a rule of its own. Either way a session cannot grant itself the bypass: a human
    spends an `authorize` and their own words land in log.jsonl permanently. successor_cfg() names
    the blind spots that does NOT close, and they are unchanged by the new layer.

    WHAT IT COSTS, said here because the breadth is both the point and the risk: a grant in the home
    file reaches EVERY project on this machine, including ones nobody has opened yet. That is what
    was asked for, not a side effect -- but a bypass whose scope nobody restates is one nobody
    re-chooses, so `successor` and `status` both name the file it came from rather than reporting a
    bare true.

    Read DIRECTLY rather than through config(), and that is no longer a question of merge depth --
    the merge is deep now and would carry this key correctly. It is a question of WHICH LAYERS MAY
    SPEAK: config() includes the tracked file by design, and a permission bypass is the one setting
    that has to be able to say "not from there".
    """
    ignored = False
    try:
        with open(CONFIG_F) as f:
            d = json.load(f)
        tracked = ((d.get("limits") or {}).get("successor") or {})
        ignored = bool(isinstance(tracked, dict) and tracked.get("skip_permissions"))
    except (OSError, ValueError, AttributeError):
        pass                    # unreadable is config()'s problem to report, not this one's
    granted, source = False, None
    for f_ in (CONFIG_GLOBAL_F, CONFIG_LOCAL_F):
        try:
            with open(f_) as f:
                d = json.load(f)
            c = ((d.get("limits") or {}).get("successor") or {})
            # PRESENCE, not truthiness. `in` is what lets an explicit false withdraw the grant above
            # it; `c.get(...)` alone would make a repo's refusal indistinguishable from a repo that
            # never mentioned the key, and the machine-wide true would survive both.
            if isinstance(c, dict) and "skip_permissions" in c:
                granted = bool(c.get("skip_permissions"))
                source = f_ if granted else None
        except (OSError, ValueError, AttributeError):
            continue            # absent is the DEFAULT and the safe direction: no bypass
    return granted, source, ignored
def successor_cfg():
    """How `successor` starts the next session: AUTO by default — open a Warp tab under Warp, ask
    saggar for a new agent terminal under saggar, and print the command everywhere else.

    `print` is the portable floor: every host can run a printed command, and only some have Warp.
    But a printed command is also a step a tired human has to perform, at exactly the moment the
    run has no road left, and the mode string that avoided it was something you had to know existed
    — which made "open the tab" a thing sessions REMEMBERED rather than something the tool did.

    So the terminal is READ instead of configured, and the config keeps the two overrides that
    matter: `print` pins the portable floor even under Warp, `warp-tab` forces the tab even where
    detection is blind (a hook, a tmux pane that does not forward TERM_PROGRAM).

    THE INV3 COST, stated because it is real: warp-tab WRITES OUTSIDE THIS REPO (a tab config under
    ~/.warp/), and auto makes that the default under Warp rather than a choice each install records.
    What keeps it honest is that the write is named in the output every time, and the opt-out is
    printed beside it — a default nobody can inherit silently.

    saggar-agent does NOT pay that cost: `saggar agent` is a call to a running app, so it writes
    nothing anywhere. It pays a different one, and the difference is worth knowing before choosing a
    terminal. `saggar agent` takes a provider and a TASK, not argv, so it builds its own claude
    invocation: the successor's session id cannot be handed to it, and --task/--title do not reach
    it either. The printed command still carries both, which is why it is printed in every mode
    rather than only when nothing was opened.

    WHAT NAMES THE TERMINAL IS NOT US, and this was believed wrong here until it was measured. Two
    live handovers on 2026-08-25 (sibling repo, the handoff skill's port of this verb) came out
    named `HANDOFF-<timestamp> continuation` — the second one after leading its prompt with a
    subject, which the namer ignored. What saggar displays is `session_name` from Claude Code's own
    status-line payload, mirrored by ~/.saggar/claude-status-bridge.sh: Claude's auto-generated
    CONVERSATION TITLE, which in every sample keyed off the handoff FILENAME. So nothing this verb
    passes can name a saggar terminal, the subject earns its place by being read rather than by
    naming anything, and a run that wants a legible terminal names its handoff file well.

    `skip_permissions` (default FALSE) appends --dangerously-skip-permissions to that command. An
    unattended run hands over at the worst possible moment — the gate closed, the context full, the
    human asleep — and a successor that opens on a permission prompt is a handover that stalls where
    nobody is watching. This is the only place the decision can be made, because the flag is read at
    LAUNCH: the successor cannot grant it to itself once it is running.

    It is A CONFIG KEY AND NOT A FLAG, deliberately. A `--skip-permissions` argument would let a
    session decide its own successor runs unprompted, which is a session widening its permissions
    across a handover and calling the result a new session.

    AND IT IS READ FROM config.local.json ONLY -- never from the tracked config.json. Two reasons,
    and the second is the one that has already cost this project a commit:

    ENFORCEMENT. Both write rails refuse that file by name: Write/Edit since #65, and the shell path
    (a redirect, `sed -i`, `tee`, a copy onto it) since #86. config.local.json is refused WHETHER OR
    NOT IT EXISTS, so there is no provisioning arm to slip through. A session that wants the bypass
    must therefore spend `authorize`, which writes a human's own words into log.jsonl permanently --
    the grant cannot happen without leaving the record of who granted it. That is what makes "a
    human decided this" a checkable fact rather than a sentence in a docstring.

    WHAT THAT STILL DOES NOT COVER, said here because a guard goes quiet exactly where it is blind
    (INV6): a `python3 -c` that writes the file, a path built from a shell variable, or any MCP
    tool. The guard names those three in its own refusal text. No choice of config layer closes
    them -- ~/.game_loop/config.json falls to the identical one-liner -- so this buys a logged,
    refused-by-default door, not an unpickable lock.

    LEAKAGE. config.json is TRACKED and is the seed a fresh install copies from (install.sh:339),
    so a bypass granted there would be handed to everyone who clones the checkout and everyone who
    installs from it. This project shipped exactly that leak once, for the length of one commit,
    about a different key. A permission bypass has a stronger claim on an untracked layer than the
    key that taught us did.

    THE OTHER UNTRACKED LAYER IS ~/.game_loop/config.json, and it may grant this too. It is the
    same argument reaching further: a preference about how YOUR successors start is a fact about
    your machine, and the per-repo file made you restate it in every checkout or forget to. Nothing
    is loosened by admitting it — the home file is outside this repo, so INV3 already refuses every
    write to it, and the grant still costs an `authorize`. What IS wider is the blast radius, which
    is why the file that granted it is named in the output instead of a bare "BYPASSED".

    Read DIRECTLY rather than through config(). That used to be about merge depth and is not any
    more — config() merges deeply now, and would carry this key correctly. It is about WHICH LAYERS
    MAY SPEAK: config() reads the tracked file by design, and this is the one setting that has to be
    able to refuse a value found there.

    WHAT IT DOES NOT REACH, for the same reason the session id does not: saggar-agent. `saggar agent`
    takes a provider and a task, not argv (`saggar --help`: `saggar agent <agent> <task…>`), so it
    builds its own claude invocation and nothing here can add a flag to it. That is said in the
    output rather than left for a run to discover by stalling on a prompt at 3am.
    """
    lc = (config().get("limits") or {})
    c = lc.get("successor") if isinstance(lc.get("successor"), dict) else {}
    skip, skip_from, ignored = skip_permissions_grant()
    configured = str(c.get("mode") or "auto")
    if configured not in SUCCESSOR_MODES:
        configured = "auto"
    detected = in_warp()
    host = "warp" if detected else ("saggar" if in_saggar() else "")
    auto = {"warp": "warp-tab", "saggar": "saggar-agent"}.get(host, "print")
    mode = auto if configured == "auto" else configured
    return {"mode": mode, "configured": configured, "detected": detected, "host": host,
            "term_program": os.environ.get("TERM_PROGRAM") or "",
            "skip_permissions": skip, "skip_permissions_ignored": ignored,
            "skip_permissions_from": skip_from,
            "name": str(c.get("name") or "game-loop-successor")}


def successor_why(sc):
    """The one line explaining WHY a mode resolved — always naming the evidence, never the verdict
    alone, so a surprising mode can be argued with rather than merely read."""
    if sc["host"] == "warp":
        return "Warp detected (TERM_PROGRAM=" + WARP_TERM_PROGRAM + ")"
    if sc["host"] == "saggar":
        return "saggar detected (SAGGAR_SESSION set)"
    return ("no Warp and no saggar detected (TERM_PROGRAM="
            + (sc["term_program"] or "unset") + ", SAGGAR_SESSION unset)")


# A tab is NARROW. Prose guidance did not hold this in the sibling launcher — a real handoff shipped
# `O | push and scope backups`, which a narrow tab truncates into uselessness — so the limit is a
# refusal, and --title stays uncapped as the deliberate override.
TASK_MAX_WORDS, TASK_MAX_CHARS = 3, 20


def tab_label(subject, trim=True):
    """A <=TASK_MAX_CHARS label for a tab, trimmed out of a subject that may be five times that.

    THE TRIM IS A PROPERTY OF THE SURFACE, NOT OF THE LABEL, so `trim=False` returns the subject
    whole. A Warp tab is one cell in a row of eight and genuinely cannot show more; a saggar
    terminal is a named row in its project's own folder, which is not that shape. Dropped there on
    the user's instruction, 2026-08-27 — the same call as the `<R> | ` prefix, and for the same
    reason: both spend a narrow tab's scarcest characters on a surface that is not narrow.

    IT TRIMS WHERE `--task` REFUSES, and the asymmetry is the point. `--task` is a human naming the
    job, so too long is a correctable mistake and the refusal teaches the convention. A subject is
    DERIVED — from a mandate, a heading, a phase — and refusing one would break the handover of
    every session whose mandate runs past twenty characters, which is most of them. A gate that
    fires on the common case is not a gate, it is an outage.

    The ellipsis is load-bearing: a trimmed label must not read as a complete one. "scope the
    backups and push" cut to "scope the backups" would name a DIFFERENT, smaller job and nothing
    would say so; cut to "scope the backu\u2026" it cannot be mistaken for the whole.
    """
    words = " ".join(str(subject or "").split()).split()
    if not words:
        return ""
    if not trim:
        # Whitespace is still collapsed: a subject carrying a newline would break the TOML line and
        # a run of spaces reads as a gap in the name. Only the SHORTENING is off.
        return " ".join(words)
    label = " ".join(words[:TASK_MAX_WORDS])
    clipped = len(words) > TASK_MAX_WORDS
    # THE ELLIPSIS COUNTS TOWARD THE BUDGET. Appending it in the word-clip branch could push a label
    # that was exactly at the limit one character past it: three words totalling exactly
    # TASK_MAX_CHARS, with a fourth word to signal, returned TASK_MAX_CHARS + 1. Narrow, but the
    # docstring above promises a bound and `--task` REFUSES anything over it, so the same invariant
    # was enforced on one path and quietly broken on the other. Measured, not reasoned about:
    # "aaa aaa bbbbbbbbbbbb tail words" came back 21 characters against a limit of 20.
    if len(label) + (1 if clipped else 0) > TASK_MAX_CHARS:
        label = label[:TASK_MAX_CHARS - 1].rstrip() + "\u2026"
    elif clipped:
        label += "\u2026"
    return label


def successor_title(task=None, title=None, cwd=None, subject=None, mode=None):
    """What that session is doing — under Warp prefixed `<R> | ` with the repo's initial, under
    saggar not. Same convention as the handoff skill's new-tab.sh on the Warp side.

    THE PREFIX EXISTS TO DISAMBIGUATE A FLAT LIST, so it is spent where there is one and saved
    where there is not. A Warp window is a single row of tabs from every repo at once, and `G | `
    is the only thing telling two of them apart. saggar groups terminals under the project they
    belong to and prints that project's name above them, so the initial re-states in four
    characters what the surrounding folder already says — and it spends them at the FRONT, which
    is the end that survives truncation. Dropped on the user's instruction, 2026-08-27.

    THE ELLIPSIS GOES WITH IT, on the same instruction and the same reasoning. Cutting "scope the
    backups and push" down to "scope the backups\u2026" is a cost paid for a width saggar does not
    impose, and what it buys back is a name that says the job is longer than this without saying
    what the rest of it was. Warp keeps the trim, because there the width is real.

    THE TAB IS THE SURFACE THE HUMAN ACTUALLY SCANS, and until now it was the one place the subject
    did not reach. #b6a0276 gave the successor's PROMPT a subject — derived from the mandate, the
    heading, the phase — and put it in the printed block and the saggar terminal's name, but the
    Warp tab kept its own default and went on reading `G | successor`. A row of eight tabs all
    saying "successor" is the exact complaint that fix was answering, still unanswered on the one
    display that shows eight things at once. So when nothing is named explicitly, the tab falls
    back to the SUBJECT before it falls back to a noun that describes every session equally.

    The refusals differ from that script's on purpose, because the quoting does. new-tab.sh embeds
    the title in a single-quoted shell word inside a heredoc, so a single quote breaks it; here the
    title is written straight into a TOML basic string with `\\` and `"` escaped, so a quote is
    safe and refusing it would be cargo-culted. A NEWLINE still breaks the TOML line, and `{{` is
    read by Warp as a parameter — both are refused.
    """
    if task and title:
        die("--task and --title are mutually exclusive: --task names the work and this builds the\n"
            "  title around it; --title is the verbatim override.")
    if task:
        words = task.split()
        if len(words) > TASK_MAX_WORDS or len(task) > TASK_MAX_CHARS:
            die(f"--task is too long: \"{task}\" ({len(words)} words, {len(task)} chars)\n"
                f"  limit: {TASK_MAX_WORDS} words and {TASK_MAX_CHARS} chars — a tab is narrow, so "
                "the tail gets cut off.\n"
                "  Name the successor's job, not the whole plan: \"scope backups\", not \"push and\n"
                "  scope backups\". Use --title to override verbatim.")
    if not title:
        # "successor" is the floor, not a description: it is true of every session this verb ever
        # starts, so it distinguishes nothing. Reached only when there is no subject either — and
        # then it is honest, because at that point the harness genuinely does not know the job.
        body = task or tab_label(subject, trim=mode != "saggar-agent") or "successor"
        # The one mode with a folder around the name is the one that does not repeat it.
        initial = (os.path.basename(cwd or REPO_ROOT) or "?")[:1].upper() or "?"
        title = body if mode == "saggar-agent" else f"{initial} | {body}"
    if "\n" in title:
        die("--task/--title must be a single line — the tab config writes it on one.")
    if "{{" in title:
        die("--task/--title must not contain {{ — Warp reads that as a parameter placeholder.")
    return title


def successor_id_lines(sid, mode, dry_run, found, why_not):
    """WHOSE id this is — the question the printed block used to answer with a guess.

    Under every mode but saggar-agent the id is ours: `successor` mints it and puts it on the
    command line, so the session that starts is the session named. `saggar agent` builds its own
    invocation, so the id minted here will never run — and the successor's real one is read back
    from saggar's presence directory afterwards. Which of the two is on screen is SAID, because a
    recovered id printed in the same shape as the command's would send the next reader — human or
    successor — to a session that does not exist.
    """
    if mode != "saggar-agent":
        return [f"successor session id : {sid}"]
    if dry_run:
        return [f"successor session id : {sid}  (the printed command's — `saggar agent` mints its "
                "own,",
                "                      and a dry run starts nothing to read one back from)"]
    if found:
        return [f"successor session id : {sid}",
                "                      READ BACK from " + SAGGAR_PRESENCE_DIR + " after the "
                "terminal opened —",
                "                      this is the session that actually started, and it is what "
                "the handover",
                "                      recorded. The id in the command below was minted here and "
                "ran nowhere."]
    return [f"successor session id : {sid}  (the printed command's — `saggar agent` mints its own)",
            "                      NOT RECOVERED: "
            + (why_not or "nothing started, so there was no terminal to read back from") + ".",
            "                      So nothing here names the session that started — `saggar list` "
            "and the",
            "                      terminal itself still do."]


def terminal_name_lines(mode, title):
    """What will actually be on the tab in THIS mode — never the string this verb computed as though
    every mode could apply it.

    ONLY warp-tab APPLIES IT. `title` reaches a terminal through _warp_tab's TOML and nowhere else,
    and printing `tab title           : O | session 6acce140` under saggar-agent put a field a
    reader has no reason to doubt five lines above the paragraph contradicting it. On 2026-08-25 a
    session read that field, reported its successor as "titled O | session 6acce140", and the tab
    said "Game loop implementation". A field that cannot act in the mode it is printed in is not a
    field, it is a rumour with a colon in it.

    print mode keeps a title because there it is honest: the human runs the command in a tab they
    already have, so the string is advice to them and is marked as advice.
    """
    if mode == "warp-tab":
        return [f"tab title           : {title}  (written into the tab config, which sets it)"]
    if mode == "saggar-agent":
        # THIS FIELD HAS BEEN WRONG IN BOTH DIRECTIONS. First it printed `tab title` in a mode that
        # could not apply one; then it said NOT SET FROM HERE and named the gap as ours — true,
        # and a paragraph is not a fix, so it stayed true while `_saggar_agent` went on calling the
        # untitled form and every terminal it opened read saggar's default "Terminal". It is a
        # field again because the call now passes `--title`, and the difference between those two
        # states is one argv element, not one more sentence.
        return [f"terminal name       : {title}  (passed to `saggar agent --title`, which names "
                "the terminal)"]
    return [f"tab title           : {title}  (a SUGGESTION — the printed command sets no title)"]


def _warp_tab(name, cwd, cmd, title):
    """Write a Warp tab config and open it; returns the config path.

    The mechanism, read off a working launcher rather than guessed: a tab config at
    ~/.warp/tab_configs/<name>.toml opened via `warp://tab_config/<name>` starts a new tab in the
    ACTIVE window and runs the commands in its pane. The older launch_configurations/*.yaml route
    also runs a command but always opens a new WINDOW, since that format is defined in terms of
    `windows:` — which is the wrong shape for a successor that should sit beside its predecessor.
    """
    conf = os.path.expanduser(os.path.join("~", ".warp", "tab_configs", name + ".toml"))
    os.makedirs(os.path.dirname(conf), exist_ok=True)
    esc = lambda v: v.replace("\\", "\\\\").replace('"', '\\"')  # noqa: E731 — TOML basic string
    with open(conf, "w") as f:
        f.write(f'name = "{esc(name)}"\ntitle = "{esc(title)}"\n\n'
                f'[[panes]]\nid = "main"\ntype = "terminal"\n'
                f'directory = "{esc(cwd)}"\ncommands = ["{esc(cmd)}"]\n')
    subprocess.run(["open", f"warp://tab_config/{name}"], check=False)
    return conf


# Where saggar's own Claude Code presence hook writes one file per TERMINAL, carrying the claude
# session id running in it. Read off the live directory (`~/.saggar/presence/<terminal-uuid>.json`,
# `{"agent":"claude","event":"SessionStart",...,"claudeSessionID":"e0becca4-…"}`), which is also
# what in_saggar()'s docstring rests on — this is the same file, used for the other question it can
# answer.
SAGGAR_PRESENCE_DIR = os.path.join("~", ".saggar", "presence")
# A new terminal writes its file when the successor's SessionStart hook fires, so the wait is a
# process booting, not a network. Env-overridable because a TEST must be able to pin it: the suite
# runs on a machine whose real presence directory is live, and an unbounded look there would race
# whatever the developer happens to open.
SAGGAR_DISCOVER_SEC = 20.0
SAGGAR_DISCOVER_POLL_SEC = 0.5


def _saggar_presence_names():
    """The presence directory's filenames, or None when there is no directory to read."""
    try:
        return set(os.listdir(os.path.expanduser(SAGGAR_PRESENCE_DIR)))
    except OSError:
        return None


def _saggar_discover(before):
    """The successor's REAL claude session id, recovered after `saggar agent` minted it.

    Returns (session_id, why_not); exactly one is ever non-None, and it never raises.

    WHY THIS IS NOT A NICETY. `saggar agent` builds its own claude invocation, so the id in the
    printed command is one nothing ever ran — and that fiction was what got RECORDED. Observed
    2026-08-25 in override_canvas: `successor` reported d773d651 while the terminal that opened ran
    e0becca4, so `handed_off.to` named a session with no state, the predecessor's watchdog rang it
    back into a mandate the successor already owned, the chain could never join to the successor's
    own log lines, and the human was handed an id that resumes nothing. Every one of those is the
    same missing read.

    SILENCE IS NOT A VERDICT. A miss means "could not confirm", never "did not start": the terminal
    may still be booting, the presence hook may be uninstalled (it is a toggle in saggar's
    settings), or the directory may not exist at all. And TWO new terminals inside the window is
    reported as ambiguous rather than resolved by guessing — another session opening a terminal
    beside ours is exactly the case where a guess would record the wrong id confidently.
    """
    if before is None:
        return None, ("no " + SAGGAR_PRESENCE_DIR + " to read — saggar's Claude Code presence hook "
                      "is what writes it, and it is a toggle in Saggar \u25b8 Settings")
    try:
        budget = float(os.environ.get("GAME_LOOP_SAGGAR_DISCOVER_SEC", SAGGAR_DISCOVER_SEC))
    except ValueError:
        budget = SAGGAR_DISCOVER_SEC
    deadline = time.time() + max(0.0, budget)
    seen_empty = True
    while True:
        after = _saggar_presence_names()
        new = sorted((after or set()) - before)
        if len(new) > 1:
            return None, ("%d terminals appeared while this ran (%s) — which one is the successor "
                          "cannot be told apart, so nothing is recorded rather than the wrong one"
                          % (len(new), ", ".join(os.path.splitext(n)[0][:8] for n in new)))
        if len(new) == 1:
            seen_empty = False
            try:
                with open(os.path.join(os.path.expanduser(SAGGAR_PRESENCE_DIR), new[0])) as f:
                    got = (json.load(f) or {}).get("claudeSessionID")
            except (OSError, ValueError):
                got = None
            if got:
                return str(got), None
        if time.time() >= deadline:
            break
        time.sleep(SAGGAR_DISCOVER_POLL_SEC)
    if seen_empty:
        return None, ("no new terminal appeared in %s within %gs — it may still be booting, "
                      "and `saggar list` can still say" % (SAGGAR_PRESENCE_DIR, budget))
    return None, ("the new terminal's presence file carries no claudeSessionID yet after %gs — "
                  "the session had not reached its SessionStart hook" % budget)


# `saggar_argv` LIVED HERE AND IS GONE, which is the honest outcome rather than a merge casualty.
# It existed because the flag's POSITION could not be read on the machine that added it — no saggar
# there — so it tried `agent --title <t> claude <task>` and fell back to the bare call on exit 2.
# That guess was wrong in the one way a guess can be: the options go AFTER the agent name. Read off
# `saggar --help` on a machine that has it (2026-08-27): `saggar agent <agent> <task…>`, with
# `--title`, `--cwd` and `--` listed as the agent's options. Then exercised — a live terminal came
# back as `claude --session-id <minted> --name "GL | flag probe"` with its cwd where --cwd pointed.
#
# So the fallback is not merged forward. It bought insurance against a parse failure that does not
# happen, and its cost was real: a second `saggar agent` on any exit 2, which its own docstring
# flagged as possibly opening a second terminal. Measurement removes the need for the insurance and
# the risk together. Effector `saggar-agent-flags`.
def _saggar_agent(cwd, prompt, title=None):
    """Ask saggar for a new agent terminal beside this one; returns (started, detail, id, why_not).

    The mechanism, read off the CLI saggar ships rather than guessed: `saggar agent claude <task>`
    starts an independent claude session in a new terminal in the CALLING terminal's project, and
    the skill in the app bundle describes that terminal as one "the user can inspect, redirect, or
    take over" — which is the successor's job description. That is why this does not reach for
    `saggar quick`, whose window folds itself away on a clean exit, or `saggar monitor`, which docks
    a card meant to be watched rather than typed into.

    IT RETURNS A VERDICT INSTEAD OF RAISING, because every way this fails is a way the run still has
    a road: the shim may not be installed (it is a one-time toggle in Saggar's settings, not
    something a repo can do for a user), the app may not be running (exit 3), or the call may be
    refused (exit 1). None of those are worth ending a handoff over when the portable command is
    already printed directly above the failure.

    THE TITLE IS PASSED, and for a while it was not. `saggar agent` gained `--title <title>` on
    2026-08-26; this code went on calling the two-positional form for a day afterwards, so every
    terminal it opened read saggar's default "Terminal" while the printed block explained at length
    that the name was our gap. The explanation was correct and it was not a fix. Re-read here off
    `saggar --help` on 2026-08-27 (the shim at ~/.local/bin/saggar), which is also where `--` comes
    from: it "ends agent options before the task", and the task is a PROMPT — a subject-prefixed
    sentence this repo builds, not a string anybody vetted for a leading dash. Without the
    separator a prompt that happens to start with one is parsed as an option and the handover fails
    on the shape of its own first word.

    `--cwd` COMES FROM THE SAME READING and closes the same kind of gap: the terminal used to open
    wherever the CALLING terminal happened to be, which is this repo only while nobody has cd'd
    away — and a successor that opens in the wrong tree reads a handoff path that does not resolve.
    `subprocess.run(cwd=...)` is not a substitute: it places the SHIM, and the shim is a message to
    a running app that decides the new terminal's directory itself. Both are set, because the one
    that acts is the flag.

    BOTH FLAGS ARE EXERCISED, not merely read. A live probe on 2026-08-27 — `saggar agent claude
    --title "GL | flag probe" --cwd /tmp -- <task>`, invoked FROM this repo so the caller's project
    and `--cwd` disagree — came back as `claude --session-id <minted> --name "GL | flag probe" --
    <task>` with the process's cwd at `/private/tmp`. So `--title` becomes claude's own `--name`,
    and `--cwd` places the session. The control is a terminal opened by the OLD call in another
    repo the same hour: `--name Terminal`, cwd the caller's project. Recorded as effector
    `saggar-agent-flags`.

    THE INSTRUMENT THAT WOULD HAVE LIED. `saggar list --json` reports `projectPath`, and for the
    probe it read this repo — not /tmp — which reads as "--cwd was ignored". It is not the process
    cwd; it is the saggar PROJECT the terminal is docked under, which stays the caller's either
    way. The question is answered by `lsof -a -p <pid> -d cwd`, and a session that had reached for
    the JSON field would have reverted a flag that works.
    """
    exe = shutil.which("saggar")
    if not exe:
        return False, ("no `saggar` on PATH. The CLI shim is a one-time toggle in Saggar ▸ Settings "
                       "▸ General, which installs it to ~/.local/bin/saggar"), None, None
    # BEFORE the call, because the whole method is a delta: one new file in a directory that also
    # holds every other terminal on this machine.
    before = _saggar_presence_names()
    # ONE INVOCATION, because the shape is measured rather than guessed. `--` is from the same
    # reading: it "ends agent options before the task", and the task is a PROMPT this repo builds,
    # never a string vetted for a leading dash — without the separator a prompt beginning with one
    # is parsed as an option and the handover fails on the shape of its own first word.
    argv = [exe, "agent", "claude"]
    if title:
        argv += ["--title", title]
    if cwd:
        argv += ["--cwd", cwd]
    argv += ["--", prompt]
    try:
        r = subprocess.run(argv, capture_output=True, text=True, cwd=cwd, timeout=30)
    except (OSError, subprocess.SubprocessError) as e:
        return False, f"`saggar agent` could not run: {e}", None, None
    if r.returncode == 0:
        found, why_not = _saggar_discover(before)
        # NO "the label was lost" ARM ANY MORE, and its absence is deliberate. It belonged to the
        # retry ladder: with two invocations, a success could mean the titled call worked OR that
        # the bare fallback did, and the two had to be told apart. One invocation makes the
        # distinction vanish — a zero exit IS the titled call succeeding — and a branch that can
        # no longer fire is a check that cannot fail, which reads as coverage and is not.
        return True, " ".join((r.stdout or "").split()), found, why_not
    hint = {1: "saggar understood and refused", 2: "saggar could not parse the call",
            3: "saggar is not running, or this is not a saggar terminal"}.get(r.returncode, "")
    msg = " ".join(((r.stderr or "") + " " + (r.stdout or "")).split()) or "no message"
    return (False, f"`saggar agent` exited {r.returncode}" + (f" ({hint})" if hint else "")
            + f": {msg}", None, None)


def _claude_ancestor():
    """The pid of the `claude` this verb is running underneath, with the start time that identifies
    it — or (None, None).

    WALKED, NOT GUESSED. A game_loop verb runs as claude → shell → python, and the depth is not
    fixed: a Bash tool call adds a wrapper, a hook adds another. So this climbs `ps -o ppid=,comm=`
    until it meets a process whose comm IS AGENT_COMM, which on this machine is the literal string
    (read off a live tree on 2026-08-27: /bin/zsh → claude → -zsh → Saggar.app). It stops at init
    and it stops after a bounded number of hops, because a cycle in a parent chain should end a
    walk rather than a run.

    THE START TIME COMES BACK WITH IT and is not optional. Whatever reads this pid later will
    SIGNAL it, and by then the OS may have given the number to somebody else. A pid without the
    identity that pins it is a stranger's pid with extra steps — the same reasoning bin/watchdog's
    pidfile is built on, and deliberately the same helper.
    """
    pid = os.getpid()
    for _ in range(CLAUDE_ANCESTOR_HOPS):
        try:
            r = subprocess.run(["ps", "-o", "ppid=,comm=", "-p", str(pid)],
                               capture_output=True, text=True, timeout=5)
        except (OSError, subprocess.SubprocessError):
            return None, None
        parts = (r.stdout or "").split(None, 1)
        if len(parts) < 2:
            return None, None
        ppid, comm = parts[0], parts[1].strip()
        if os.path.basename(comm) == AGENT_COMM:
            return pid, watchdog_pid_identity(pid)
        try:
            pid = int(ppid)
        except ValueError:
            return None, None
        if pid <= 1:
            return None, None
    return None, None


def own_saggar_terminal():
    """THIS session's saggar terminal and the claude sitting in it, or None.

    Recorded at handover so the SUCCESSOR can retire it later. It cannot be recorded by the
    successor and it cannot be acted on by this session: `saggar close` refuses a terminal with a
    live process in it (measured 2026-08-27 — "<name> is still running", exit 1), and the process
    it would be refusing is the one calling this function. So the predecessor writes down who it
    is, and somebody else does the closing. Which is also why the pid carries an identity: by the
    time it is read, this process is meant to be dead.

    THE ID IS ASKED FOR, NOT READ OFF THE ENVIRONMENT, and this cost a live chain to learn.
    SAGGAR_SESSION looks like the obvious answer and this code used it: it names a terminal, it
    keys ~/.saggar/presence/<id>.json, and it is what in_saggar() detects on. It is also a
    DIFFERENT UUID from the one saggar's CLI resolves. Measured 2026-08-27 in this terminal:
    SAGGAR_SESSION=84F15D66, `saggar read 84F15D66` → "no terminal matching"; the addressable id
    was B80719A7, and `saggar read B80719A7` returned this terminal's own tail. A live A→B chain
    failed on exactly that, with `saggar close` answering "no terminal matching <SAGGAR_SESSION>".

    `saggar read [id|name]` defaults to THIS terminal and `--json` prints its metadata, so the one
    place both facts meet is saggar itself. --lines 1 because the tail is not wanted; the id is.
    """
    tid = saggar_self_id()
    if not tid:
        return None
    pid, identity = _claude_ancestor()
    if not pid or not identity or identity == PROC_GONE:
        return None
    return {"id": tid, "pid": pid, "identity": identity}


def saggar_self_id():
    """The addressable id of the terminal this process is in, or None.

    ITS OWN FUNCTION BECAUSE THE SELF-GUARD USES IT, and a guard must not inherit the failure modes
    of a question it is not asking. Folded into own_saggar_terminal(), this returned None whenever
    the PID WALK failed — and the guard reads a None as "not me" and proceeds to signal. The one
    check whose failure mode is a session killing itself would have failed open on an unrelated
    `ps`. Asked separately, it fails on its own terms only, and the caller treats a None as
    "cannot tell", which is the closed direction.
    """
    if not in_saggar():
        return None
    exe = shutil.which("saggar")
    if not exe:
        return None
    try:
        r = subprocess.run([exe, "read", "--json", "--lines", "1"],
                           capture_output=True, text=True, timeout=15)
        return (json.loads(r.stdout) or {}).get("id") if r.returncode == 0 else None
    except (OSError, subprocess.SubprocessError, ValueError):
        return None


RETIRE_EXIT_WAIT_SEC = 10       # how long to wait for a signalled claude to actually go
RETIRE_POLL_SEC = 0.25


def _predecessor_record():
    """The session that handed over to THIS one, if it left a terminal to retire — or None.

    Read across every session in the checkout rather than from a pointer, because there is no
    pointer: `handed_off` lives in the PREDECESSOR's state and names its successor, and a successor
    is never told who it came from. That direction is not an oversight to fix here — it is what
    makes the record survive a successor that never boots.
    """
    try:
        names = os.listdir(SESSIONS_DIR)
    except OSError:
        return None, None
    for name in names:
        if name == SESSION:
            continue                        # a session cannot be its own predecessor
        f = os.path.join(SESSIONS_DIR, name, "state.json")
        try:
            with open(f) as fh:
                st = json.load(fh)
        except (OSError, ValueError):
            continue
        ho = st.get("handed_off")
        if not isinstance(ho, dict) or ho.get("to") != SESSION:
            continue
        if not isinstance(ho.get("from_terminal"), dict) or ho.get("terminal_retired"):
            continue
        return name, st
    return None, None


def _mark_retired(name, st, verdict):
    """Write the outcome into the PREDECESSOR's state, so this is attempted once whatever happened.

    Once, including on failure. A retire that could not find the process, or that saggar refused,
    is a retire that has been TRIED, and re-trying it on every status of a long session turns one
    quiet miss into a per-turn `ps` and a per-turn `saggar close` against a terminal that is not
    going anywhere. The verdict is kept rather than a boolean, because "did not act, and why" is
    the whole of what a reader wants from this field.
    """
    st.setdefault("handed_off", {})["terminal_retired"] = {"at": now(), "verdict": verdict}
    f = os.path.join(SESSIONS_DIR, name, "state.json")
    try:
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(f), prefix=".state.", suffix=".tmp")
        with os.fdopen(fd, "w") as fh:
            json.dump(st, fh, indent=2)
            fh.write("\n")
        os.replace(tmp, f)
    except OSError:
        pass


def retire_predecessor():
    """Close the saggar terminal this session was handed over FROM. Returns report lines.

    THE ORDER IS THE DESIGN. `saggar close` refuses a terminal with a live process in it — measured
    2026-08-27, "<name> is still running", exit 1 — so the claude in it must go first, and this is
    therefore a KILL followed by a close, not a close. That is also why it is not the predecessor
    doing it: the process `close` would refuse is the one that would have to call it.

    PROOF OF LIFE FIRST, and the proof is this session's own state file — the same artifact
    bin/watchdog accepts as evidence a successor is real, deliberately the same test. A successor
    that dies during boot must leave its predecessor's terminal and scrollback standing, because at
    that point the predecessor's terminal is the only place the run still exists. Killing it first
    and booting second would turn a failed handover into a lost one.

    THE GUARDS ARE THE FEATURE. It refuses to act on its OWN terminal (a value that would match
    only if SAGGAR_SESSION were somehow shared, and the cost of being wrong is this session killing
    itself mid-turn); it refuses a pid whose start time is not the one recorded, because the OS
    recycles numbers and what follows is a SIGTERM; and it marks the attempt either way so a
    refusal is not retried on every status for the rest of a long session.

    WHAT IT COSTS WHEN IT WORKS: the predecessor's scrollback. That is not recoverable, it is the
    point of the verb, and it is the reason every arm below reports what it did rather than
    returning quietly.
    """
    if not SESSION or not successor_seen(SESSION):
        return []                           # not proven alive; nothing may be destroyed yet
    name, st = _predecessor_record()
    if not name:
        return []
    ft = st["handed_off"]["from_terminal"]
    tid, pid, recorded = ft.get("id"), ft.get("pid"), ft.get("identity")
    head = f"predecessor terminal : {tid} (session {name[:8]})"
    # THE ONE THAT WOULD BE FATAL, and therefore the one that fails CLOSED. Everything below
    # signals and closes; if the target were this terminal, this session would be killing itself
    # mid-turn. So "I could not find out which terminal I am" refuses too — the cost of stopping is
    # a tab left on screen, and the cost of guessing is the run.
    mine = saggar_self_id()
    if not mine:
        _mark_retired(name, st, "refused: could not identify this terminal")
        return [head, "                       REFUSED — nothing here could establish which terminal "
                      "THIS session is in, so it",
                      "                       cannot rule out that the two are the same. Not "
                      "signalled, not closed."]
    if tid == mine:
        _mark_retired(name, st, "refused: that is THIS terminal")
        return [head, "                       REFUSED — that is this session's own terminal. Not "
                      "signalled, not closed."]
    exe = shutil.which("saggar")
    if not exe:
        _mark_retired(name, st, "no saggar on PATH")
        return [head, "                       left alone — no `saggar` on PATH to close it with."]
    live = watchdog_pid_identity(pid) if pid else None
    if live is None:
        _mark_retired(name, st, "could not check the pid")
        return [head, "                       left alone — `ps` did not run, so nothing here knows "
                      "whether that pid is still",
                      "                       the predecessor. NOT signalled: a recycled number is "
                      "somebody else's process."]
    if live == PROC_GONE:
        note = f"claude pid {pid} had already exited"
    elif live != recorded:
        _mark_retired(name, st, "pid was recycled")
        return [head, f"                      pid {pid} is NOT the predecessor's claude — it "
                      "exited and the OS gave its",
                      "                       number to another process. NOT signalled, and the "
                      "terminal is left standing."]
    else:
        try:
            os.kill(pid, 15)
        except OSError as e:
            _mark_retired(name, st, f"could not signal: {e.__class__.__name__}")
            return [head, f"                      could not signal pid {pid} "
                          f"({e.__class__.__name__}) — terminal left standing."]
        deadline = time.time() + RETIRE_EXIT_WAIT_SEC
        while time.time() < deadline and watchdog_pid_identity(pid) not in (PROC_GONE, None):
            time.sleep(RETIRE_POLL_SEC)
        note = f"stopped claude pid {pid}"
    # WAITED FOR, NOT ASSUMED. A close issued while the process is still winding down is refused,
    # and the refusal reads exactly like the flag not working.
    try:
        r = subprocess.run([exe, "close", str(tid)], capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError) as e:
        _mark_retired(name, st, f"close could not run: {e.__class__.__name__}")
        return [head, f"                      {note}, but `saggar close` could not run ({e})."]
    msg = " ".join(((r.stdout or "") + " " + (r.stderr or "")).split()) or "no message"
    if r.returncode == 0:
        _mark_retired(name, st, "closed")
        logline({"kind": "predecessor_retired", "from": name, "terminal": tid, "pid": pid})
        return [head, f"                       CLOSED — {note}, then `saggar close` said: {msg}",
                "                       That session's scrollback is gone; the log and its state "
                "file are not."]
    _mark_retired(name, st, f"close refused: {msg}")
    return [head, f"                      {note}, but `saggar close` refused (exit "
                  f"{r.returncode}): {msg}",
            "                       The terminal is still on screen — close it by hand."]


THREAD_ID_CHARS = 8


def handover_edges():
    """Every handover this checkout has recorded, oldest first, read off the SHARED log.

    THE EDGES WERE ALREADY ON DISK AND NOBODY JOINED THEM UP. `logline` stamps every record with
    the session that wrote it (`sid`, truncated to 8) and the handed_off record names the session it
    started (`to`, in full) — so A->B->C has always been three lines that happen to share endpoints.
    This joins them. It deliberately does NOT write a second record of the chain: a chain file
    beside the log would be free to disagree with it, and the disagreement would surface in the one
    place nobody looks.
    """
    edges = []
    try:
        with open(LOG_F) as f:
            for ln in f:
                try:
                    r = json.loads(ln)
                except ValueError:
                    continue
                if r.get("kind") == "handed_off" and r.get("to") and r.get("sid"):
                    edges.append(r)
    except OSError:
        pass
    return edges


def thread_for(session, edges=None):
    """The thread `session` is already part of, read off the edge that STARTED it — or None.

    Matched on the SHORT id, because `logline` records the writer as SESSION[:8] while `to` is a
    full uuid; the join has to happen at the narrower of the two. Eight hex characters inside one
    checkout's log is a 32-bit space, so a collision needs two sessions in the same repo sharing a
    prefix. If that ever happens the symptom is two chains printed as one, which the hop list makes
    VISIBLE rather than silent — that is the reason the hops are printed and not just counted.

    The LAST matching edge wins. A session handed to twice is a session somebody re-pointed, and
    the most recent pointing is the one that describes where it now sits.
    """
    if not session:
        return None
    short = str(session)[:8]
    for r in reversed(edges if edges is not None else handover_edges()):
        if str(r.get("to"))[:8] == short and isinstance(r.get("thread"), dict):
            return r["thread"]
    return None


def successor_thread(subject):
    """The thread this handover belongs to, and whether it was inherited or minted here.

    MINTED ONCE, AT THE HEAD OF A CHAIN, AND INHERITED UNCHANGED AFTER THAT. The label is the
    subject of the FIRST handover, not the latest, and that is deliberate: a name that drifts with
    every hop is not an identity, it is a status, and the human's complaint was that they could not
    tell which chain was which — which is a question only a stable name answers. Where the work has
    genuinely moved on, the per-hop `about` records it and `threads` prints both, so drift is shown
    rather than hidden or overwritten.

    IT IS NOT KEPT IN SESSION STATE, and that is what keeps it correct across the two places that
    deliberately erase a handover (`mandate --set` and `mandate --resume`, which pop `handed_off` so
    a re-driven session's watchdog re-arms). Those pops are about an ENGINE being stood down. A
    session being driven again does not unmake the chain it was part of, and a lineage that
    evaporated when somebody re-bound a mandate would be a chain that lies by omission.
    """
    th = thread_for(SESSION)
    if th:
        return th, True
    return {"id": uuid.uuid4().hex[:THREAD_ID_CHARS], "label": subject or "",
            "started": now()}, False


def handover_chains():
    """The recorded handovers, walked into chains: [{thread, label, hops, head}], newest last.

    Walked as a GRAPH rather than grouped by thread id, so this reads a log written before threads
    existed. Those edges carry no thread and would group into one meaningless bucket; followed
    from -> to they still form exactly the chains they always described. A chain that predates
    threads is printed with its identity named as absent, never invented.
    """
    edges = handover_edges()
    by_from = {}
    targets = set()
    for r in edges:
        by_from.setdefault(str(r["sid"])[:8], []).append(r)
        targets.add(str(r["to"])[:8])
    chains = []
    # EVERY RECORDED HANDOVER IS ON SOME CHAIN, AND TAKING ONLY THE LATEST DROPPED WHOLE ONES. This
    # followed `by_from[cur][-1]`, so a session that handed off TWICE kept its most recent successor
    # and silently lost the earlier one — along with everything downstream of it. That is not exotic:
    # `mandate --set` and `mandate --resume` deliberately re-drive a session that has already handed
    # over, which is precisely how a second edge out of one session appears.
    #
    # Measured on a three-edge log (A->B, B->D, then A re-driven and handing to C): one chain came
    # back, and B and D appeared nowhere at all. A verb whose entire job is "which chain is this"
    # answered by not mentioning the chain. The earlier successor is not superseded — it RAN, and
    # the log shows it handing on.
    #
    # So a branch point starts a branch: each edge out of a session continues its own path, and the
    # per-path `seen` set stops a cycle without stopping a diamond that legitimately rejoins.
    for root in [f for f in by_from if f not in targets]:
        stack = [(root, [], frozenset())]
        while stack:
            cur, hops, seen = stack.pop()
            nxt = [] if (cur in seen or len(hops) >= 200) else by_from.get(cur, [])
            if not nxt:
                if hops:
                    th = next((h["thread"] for h in hops
                               if isinstance(h.get("thread"), dict)), None)
                    chains.append({"thread": (th or {}).get("id"),
                                   "label": (th or {}).get("label") or "",
                                   "hops": hops, "head": str(hops[-1]["to"])})
                continue
            for r in nxt:
                stack.append((str(r["to"])[:8], hops + [r], seen | {cur}))
    chains.sort(key=lambda c: c["hops"][-1].get("t") or "")
    return chains


def cmd_threads(s, a):
    """Which handover chain is which — the verb that answers "which handoff is for which task".

    THE QUESTION WAS ALREADY ANSWERABLE AND COST TOO MUCH TO ASK. Every hop was recorded; joining
    them meant opening one state file per session in a checkout that routinely holds twenty-eight,
    and matching uuids by eye. Nobody does that, so in practice the answer was "start again and
    hope". A chain is only useful at a glance, so this prints it at a glance.
    """
    chains = handover_chains()
    # --json ANSWERS FIRST, INCLUDING THE EMPTY CASE. Emitting the prose here and the JSON only when
    # there was something to say is the shape that makes a consumer crash on exactly the state it is
    # least able to handle: `json.loads` on a sentence. Found by this suite's own --json assertion,
    # which died on it and took 1554 later assertions with it — turning a 7-kill producer into a
    # 1554-kill reading indistinguishable from a catastrophic regression.
    if a.json:
        out(json.dumps(chains, indent=2))
        return
    if not chains:
        out("no handover chains recorded in this checkout.",
            "  Nothing has run `successor` here yet — or every hop predates the log this reads.")
        return
    out(f"{len(chains)} handover chain(s) in this checkout, oldest first:")
    for c in chains:
        ident = c["thread"] or "(no thread id — this chain predates them)"
        label = c["label"] or "(unlabelled — no subject was recorded at the first handover)"
        out("", f"thread {ident} — {label}",
            f"  {len(c['hops'])} hop(s) · first {c['hops'][0].get('t')} · "
            f"last {c['hops'][-1].get('t')}")
        for h in c["hops"]:
            about = h.get("about") or ""
            drift = f"   about: {about}" if about and about != c["label"] else ""
            out(f"    {str(h['sid'])[:8]} → {str(h['to'])[:8]}   {h.get('t')}{drift}")
        # The SAME test successor_seen uses, and it must stay the same one: a listing that reads
        # "live" where the watchdog reads "nobody came" is the disagreement nobody would check.
        seen = successor_seen(c["head"])
        out(f"  head : {c['head'][:8]} — "
            + ("live (it has written state)" if seen else "NOT SEEN YET — no state file of its own"),
            f"  reads: {c['hops'][-1].get('handoff') or '(not recorded)'}")
    out("", "WHAT THIS DOES NOT SEE — a rail goes quiet exactly where it is blind:",
        f"  · a session dir pruned by `status` after {SESSION_TTL_DAYS} days still has its EDGES in "
        "the log, but no",
        "    state file — so an old chain's head reads NOT SEEN YET, which is indistinguishable "
        "here from a",
        "    successor that never started. Age is the tell; this cannot make it for you.",
        "  · handovers in ANOTHER checkout. The log is per-checkout, so a chain that crossed "
        "worktrees shows",
        "    only the half that happened here.",
        "  · a session that took over by hand — somebody reading the handoff and carrying on — "
        "records no edge",
        "    at all, and is not a chain as far as this is concerned.")


def cmd_successor(s, a):
    """Start the session that takes over from this one — the capability the handoff never had.

    game_loop has WRITTEN a handoff at every turn-end since #45 and has never started the session
    that reads it. That gap is why "hand off when the context gets big" stayed something a run had
    to REMEMBER: the gate could refuse work, but the only way out of a large context was an action
    no verb performed, so the refusal had nowhere to send anyone. This performs it.

    It never copies state into the prompt. The handoff file IS the state; a prompt that paraphrased
    it would be a second copy, free to disagree with the first, and the disagreement would surface
    in the one session with no way to check.

    It does not refuse an auto-generated handoff the way the GATE does. The gate is asking the agent
    for its own account and must not accept a file that writes itself; this is the last action of a
    session that may be out of road, and the generated floor beats starting the successor blind.
    It says which one it is handing over, so nobody has to guess.
    """
    hp = os.path.abspath(os.path.expanduser(a.handoff)) if a.handoff else handoff_path()
    # THE FLOOR IS WRITTEN HERE WHEN THERE IS NONE, and the reason is a timing nobody would guess.
    # The generated handoff is a TURN-END artifact: refresh_handoff() runs in the Stop gate and
    # nowhere else, so a session that has not yet finished a turn has no handoff at all — and
    # handing over inside the first turn is exactly what a fresh session spawned to do one job
    # does. Measured 2026-08-27 by a live A→B chain: A ran `checkpoint` then `successor` in one
    # turn and `successor` refused, because no Stop hook had fired between them.
    #
    # The old refusal told the reader to run `checkpoint --notes ".."`. That advice could not work:
    # checkpoint records notes for the NEXT generation, it does not generate. A remedy that names
    # the wrong mechanism is worse than none — it sends the reader to run a command, watch it
    # succeed, and hit the same refusal.
    #
    # Generating is consistent with what this verb already says two paragraphs up: it does not
    # refuse an auto-generated handoff the way the GATE does, because the generated floor beats
    # starting the successor blind. An EXPLICIT --handoff is never generated over: naming a file
    # that does not exist is a typo, and inventing content at that path would bury it.
    generated = False
    if not a.handoff and (not os.path.isfile(hp) or os.path.getsize(hp) == 0):
        generated = refresh_handoff(s)
    if not os.path.isfile(hp) or os.path.getsize(hp) == 0:
        die(f"no handoff to hand over: {hp}\n"
            "  A successor with nothing to read is a session that starts from zero, which is the\n"
            "  cost this verb exists to avoid. The generated one is written at TURN-END by the Stop\n"
            "  gate, and writing one here just now did not work either — so write it by hand, or\n"
            "  pass --handoff <path> to hand over a file you name.")
    try:
        with open(hp) as f:
            auto = AUTO_HANDOFF_MARK in f.read(200)
    except OSError:
        auto = False
    sid = a.session_id or str(uuid.uuid4())
    cwd = a.cwd or REPO_ROOT
    subject = successor_subject(hp, a.about, s)
    prompt = SUCCESSOR_PROMPT.format(handoff=hp)
    # Prepended, not appended: everything that displays this string displays its FRONT — a tab row
    # truncates, a terminal list prints one line, and the successor's own first message opens with
    # it.
    if subject:
        prompt = f"{subject} \u2014 {prompt}"
    sc = successor_cfg()
    argv = ["claude", "--session-id", sid]
    if sc["skip_permissions"]:
        argv.append(SKIP_PERMISSIONS_FLAG)
    argv.append(prompt)
    cmd = " ".join(shlex.quote(x) for x in argv)
    thread, inherited = successor_thread(subject)
    title = successor_title(a.task, a.title, cwd, subject, sc["mode"])
    why = successor_why(sc)
    # The id line is built LAST (below), because under saggar-agent the id that matters is one this
    # process cannot know yet: it is minted by the terminal saggar opens and read back afterwards.
    lines = []
    if subject:
        lines.append(f"about               : {subject}")
    # WHICH CHAIN THIS IS. The `about` line says what the work is; this says which running thread of
    # work it belongs to, which is the question a human with four tabs open actually has.
    lines.append(f"thread              : {thread['id']} · "
                 + (thread["label"] or "(unlabelled)")
                 + ("  — inherited, this continues an existing chain" if inherited
                    else "  — NEW chain, minted here"))
    lines += [f"reads               : {hp}"
              + ("  ⚠ GENERATED JUST NOW — this session had not finished a turn, so no "
                 "turn-end handoff existed" if generated
                 else "  ⚠ the GENERATED handoff" if auto else ""),
              f"working directory   : {cwd}"]
    lines += terminal_name_lines(sc["mode"], title)
    lines.append(f"command             : {cmd}")
    # SET IN THE WRONG FILE. Printed on its own terms, before and independent of the grant: the
    # failure being prevented is somebody writing the key into the tracked config, reading a normal
    # successor line, and walking away believing the run is armed. Silence there is the 3am stall.
    if sc["skip_permissions_ignored"]:
        lines += ["permissions         : \u26a0 limits.successor.skip_permissions is set in "
                  ".game_loop/config.json",
                  "                      and was IGNORED. That file is TRACKED and seeds every "
                  "fresh install, so a",
                  "                      bypass written there would be handed to everyone who "
                  "clones this checkout.",
                  "                      Move it to .game_loop/config.local.json (this repo) or "
                  "~/.game_loop/config.json",
                  "                      (every repo on this machine) if you meant it."]
    # Only when it is ON. The default is the safe direction and announcing it every run would make
    # the exceptional case one more line in a wall of them; a bypass is the thing worth a line.
    if sc["skip_permissions"]:
        _from = sc["skip_permissions_from"] or ""
        _machine = bool(_from and _from == CONFIG_GLOBAL_F)
        lines += ["permissions         : BYPASSED — the command carries "
                  + SKIP_PERMISSIONS_FLAG + ",",
                  "                      set by limits.successor.skip_permissions in "
                  + _tilde(_from),
                  "                      — a file both write rails refuse ("
                  + ("outside this repo, which is INV3" if _machine
                     else "by name, since #65 and #86")
                  + "), so this grant",
                  "                      cost an `authorize` and a human's words are in log.jsonl.",
                  "                      The successor will not prompt for anything, including the "
                  "calls this",
                  "                      session would have been asked about."]
        # NAMED BECAUSE IT IS WIDER THAN THE PAGE IT IS PRINTED ON. A repo-local grant is a decision
        # about the checkout the reader is looking at; a machine-wide one already applies to
        # projects they have not opened, and the moment they are reading a bypass line is the only
        # moment that difference can be put in front of them.
        if _machine:
            lines += ["                    \u26a0 MACHINE-WIDE — this grant is not this repo's. It "
                      "applies to EVERY project",
                      "                      on this machine, including ones nobody has opened "
                      "yet. Set",
                      "                      limits.successor.skip_permissions to false in "
                      ".game_loop/config.local.json",
                      "                      to withdraw it here without touching the others."]
        # The gap that costs the most, so it is said beside the setting rather than left in the
        # mode's own paragraph: skip_permissions is turned on precisely because nobody will be
        # there, and saggar-agent is the one mode that drops it. It is stated here because here it
        # is true in every sub-case — dry run, terminal opened, or call refused — where the started
        # branch it would otherwise live in is the one seam no test may run for real.
        if sc["mode"] == "saggar-agent":
            lines += ["                    \u26a0 MODE saggar-agent DOES NOT CARRY IT. `saggar "
                      "agent` takes a task, not argv,",
                      "                      so a terminal it opens WILL prompt — and an "
                      "unattended successor stalls on",
                      "                      the first one. Only the printed command above carries "
                      "the flag; mode",
                      "                      \"print\" or \"warp-tab\" is how the bypass "
                      "actually reaches the successor."]

    # Did a SESSION start, or only a suggestion? Everything below turns on this: the handover is
    # recorded — and this session's autonomy engine stood down — only where somebody is actually
    # there to take over. "print" mode hands over a COMMAND, which is not a successor until a
    # human runs it, and a mandate left with no engine because of a tab nobody opened is a stall
    # nothing would report.
    handed = False
    found, found_why = None, None
    if a.dry_run:
        lines.append(f"mode                : {sc['mode']} — {why}, configured "
                     f"\"{sc['configured']}\" (DRY RUN — nothing was started)")
    elif sc["mode"] == "saggar-agent":
        started, detail, found, found_why = _saggar_agent(cwd, prompt, title)
        handed = bool(started)
        if started:
            lines += [f"mode                : saggar-agent — {why}. Opened a new agent terminal"
                      + (f" ({detail})" if detail else "") + ".",
                      "                      Nothing outside this repo was written — this is a call "
                      "to a running app, not a",
                      "                      config file, so it costs none of what warp-tab costs.",
                      f"                      NAMED: --title carried \"{title}\" to the "
                      "terminal, so the row a human scans",
                      "                      later reads the job rather than saggar's default "
                      "\"Terminal\".",
                      f"                      DIRECTED: --cwd carried {cwd}, so the session "
                      "opens there rather than",
                      "                      wherever the calling terminal had wandered. Both "
                      "flags exercised 2026-08-27",
                      "                      (effector saggar-agent-flags); note `saggar list "
                      "--json`'s projectPath is the",
                      "                      DOCKED PROJECT, not the cwd, so it will keep saying "
                      "this repo either way.",
                      "                      WHAT STILL DOES NOT REACH IT: the session id on the "
                      "command — `saggar agent`",
                      "                      takes a task, not argv. "
                      + ("The id was READ BACK afterwards."
                         if found else "The id was not recovered either."),
                      "                      Set limits.successor.mode to \"print\" in "
                      ".game_loop/config.json to keep",
                      "                      it and run the command yourself."]
        else:
            lines += [f"mode                : saggar-agent — {why}, but NOTHING STARTED: {detail}",
                      "                      RUN THE COMMAND ABOVE to start the successor by hand — "
                      "it is the portable",
                      "                      floor, and it carries the session id this mode could "
                      "not pass on."]
    elif sc["mode"] == "warp-tab":
        conf = _warp_tab(sc["name"], cwd, cmd, title)
        handed = True
        lines += [f"mode                : warp-tab — {why}. Wrote {conf} and opened it.",
                  "                      That path is OUTSIDE this repo; pin "
                  "limits.successor.mode to \"print\"",
                  "                      in .game_loop/config.json to keep it that way."]
    else:
        lines.append("mode                : print — RUN THE COMMAND ABOVE to start the successor.")
        if sc["configured"] == "print":
            lines.append("                      (pinned by limits.successor.mode; \"auto\" starts "
                         "it under Warp or saggar.)")
        else:
            lines += [f"                      ({why}. Under Warp \"auto\" opens a tab; under saggar "
                      "it asks for an agent",
                      "                       terminal. Warp detection is blind in a hook, where "
                      "TERM_PROGRAM is unset, so",
                      "                       set limits.successor.mode to \"warp-tab\" in "
                      ".game_loop/config.json to force it —",
                      "                       that writes a config under ~/.warp/, outside this "
                      "repo. saggar needs no such",
                      "                       override: SAGGAR_SESSION reaches hooks, so "
                      "\"auto\" resolves it there too.)"]
    # WHOSE ID GETS RECORDED. Everything below turns on `sid`: handed_off.to, the watchdog's
    # stand-down, the thread the chain joins on, and the line a human reads. Under saggar-agent the
    # minted id is a session that never ran, so recording it made all four point at nothing —
    # observed 2026-08-25 (override_canvas reported d773d651; the terminal ran e0becca4).
    if found:
        sid = found
    lines = successor_id_lines(sid, sc["mode"], bool(a.dry_run), found, found_why) + lines

    # ── stand this session's autonomy engine down ────────────────────────────────────────────
    #
    # A watchdog rings an idle session back to work. After a handover that is exactly wrong: the
    # session it rings has given its mandate away, and the ring produces two sessions driving one
    # goal. That is not hypothetical — it is what happened in landlord on 2026-08-18 (48641588 →
    # 9187f2e8): six worktrees for three problems, and a T3 spend to ask a human which one was
    # driving. The predecessor's watchdog was still alive six days later holding that question.
    #
    # The flag is the gate; the kill is only latency. Killing the armed process alone would be
    # undone by the very next turn-end, which arms a fresh one — so what stands the engine down is
    # `handed_off` in this session's state, which bin/watchdog reads on every arm and again after
    # every sleep. The kill just stops the one already sleeping from waking up to learn it.
    if handed:
        s["handed_off"] = {"to": sid, "at": now(), "handoff": hp, "mode": sc["mode"],
                           "thread": thread}
        # WHO TO CLOSE, WRITTEN DOWN BY THE ONLY PROCESS THAT KNOWS. SAGGAR_SESSION names THIS
        # terminal and reaches nothing else — the successor is a different terminal with a
        # different value, and by the time it could ask, this session is meant to be gone. Recorded
        # under every mode, not just saggar-agent: a run configured to `print` still opens its
        # successor in a saggar terminal often enough, and a record nobody reads costs one dict.
        if (own := own_saggar_terminal()):
            s["handed_off"]["from_terminal"] = own
        save(s)
        pid, note = disarm_watchdog()
        lines += ["", "handover recorded    : this session's watchdog is STOOD DOWN — "
                      f"{sid[:8]} owns the mandate now.",
                  f"                       armed watchdog: {note}.",
                  "                       It will not ring you back into work you just handed over.",
                  "                       Binding a NEW mandate here re-arms it (`mandate --set`)."]
        # The thread and the hop's own subject ride the LOG record, because the log is the only
        # per-checkout, append-only, shared thing here — which is exactly the shape a chain needs.
        logline({"kind": "handed_off", "to": sid, "mode": sc["mode"], "watchdog_pid": pid,
                 "watchdog": note, "thread": thread, "about": subject})
        if (m := s.get("mandate") or {}).get("active"):
            lines.append(f"                       still-open mandate  : {m.get('text')}")
        if s.get("t3_armed"):
            q = (s["t3_armed"].get("question") or "") if isinstance(s.get("t3_armed"), dict) else ""
            lines += ["", "⚠ A T3 QUESTION IS ARMED HERE AND IT DOES NOT TRAVEL. The arm lives in this "
                          "session's state;",
                      "  the successor never sees it, and nothing is left listening for the answer.",
                      f"  armed: {q[:120]}",
                      "  → put the question, and what you would do under each answer, in the handoff "
                      "file above."]
    elif not a.dry_run:
        lines += ["", "handover NOT recorded: nothing started, so this session still owns the "
                      "mandate and its",
                  "                       watchdog stays ARMED — a mandate with no engine and "
                  "nobody told is worse",
                  "                       than one wasted wake-up. Run the command above; the "
                  "successor's first",
                  "                       turn-end is what makes the handover real."]

    if auto:
        lines += ["",
                  "⚠ THIS IS THE GENERATED HANDOFF, not your own account of the run. It says what "
                  "the run was",
                  "  DOING, never why. `checkpoint --notes \"..\"` puts your words in it — worth one "
                  "turn before",
                  "  the successor starts, because it is the only part nothing can reconstruct."]
    logline({"kind": "successor", "session_id": sid, "handoff": hp, "mode": sc["mode"],
             "thread": thread["id"], "thread_inherited": inherited,
             "configured_mode": sc["configured"], "warp_detected": sc["detected"],
             "host": sc["host"], "title": title,
             "skip_permissions": sc["skip_permissions"],
             "skip_permissions_ignored": sc["skip_permissions_ignored"],
             "skip_permissions_from": sc["skip_permissions_from"],
             "dry_run": bool(a.dry_run), "auto_handoff": auto, "handed": handed})
    out("\n".join(lines))


# ── confidence ───────────────────────────────────────────────────────────────────────────────────
#
# A consumer cloning this repo gets whatever was on main that morning -- mid-refactor included. The
# author pushes while a feature is half-landed, because that is what working in the open looks like,
# and nothing in a clone distinguishes "I am partway through a refactor" from "this is the commit I
# run my own agent on".
#
# A SELF-DECLARED LEVEL WOULD BE PROSE, which is the thing this project refuses everywhere else. So
# each level is an ARTIFACT the marker cannot fabricate and the consumer can re-check:
#
#   alpha   the DEFAULT, applied by nobody. It is the ABSENCE of a mark, so silence can never read
#           as confidence -- the failure mode every other gate here exists to prevent.
#   beta    the full suite passed on this exact tree, with nothing uncommitted. Refused otherwise.
#   stable  beta, AND the owning agent has been running its own harness on this commit. That is
#           dogfooding as a fact rather than a promise, and it is the strongest thing this project
#           can honestly say about a sha.
#
# Carried by annotated git TAGS: they travel with an ordinary clone, cost nothing, touch no file,
# and are per-commit rather than a list that rots. The annotation carries the evidence, so a reader
# gets the reasoning and not just the verdict.
CONFIDENCE_LEVELS = ("alpha", "beta", "stable")


def _tags_at(ref="HEAD"):
    out = _git("tag", "--points-at", ref)
    return [t.strip() for t in (out or "").split("\n") if t.strip()]


def confidence_of(ref="HEAD"):
    """(level, tag, evidence-text). ALPHA when nothing marks it — never an error, never a guess."""
    best, tag = "alpha", None
    for t in _tags_at(ref):
        for lvl in ("stable", "beta"):
            if t.startswith(lvl + "-") and CONFIDENCE_LEVELS.index(lvl) > \
                    CONFIDENCE_LEVELS.index(best):
                best, tag = lvl, t
    body = _git("tag", "-l", tag, "--format=%(contents)") if tag else ""
    return best, tag, (body or "").strip()


def remote_has_ref(ref, timeout=20):
    """Is `ref` on the default remote? True / False / None for COULD NOT ASK — never conflated.

    None is the whole point. An `ls-remote` that fails offline, or against a repo with no remote at
    all, must not render as "it is up there": a confidence record that exists only locally is the
    unpushed-work failure one level up, and reporting it as published is worse than saying nothing.
    """
    try:
        r = subprocess.run(["git", "ls-remote", "--tags", "origin", ref],
                           cwd=REPO_ROOT, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if r.returncode != 0:
        return None
    return bool((r.stdout or "").strip())


def mark_publication_state(tag, channel):
    """The LAST word after a mark: are the refs consumers install from actually reachable?

    Ordering is the mechanism this exists for. `--mark` prints its push instructions and THEN fires
    the confidence triggers, so a publish trigger's success banner is the final thing on screen —
    announcing to consumers a commit whose tag is still local. Twice here. The remedy is not to move
    the instructions (they belong where they are, beside what they describe) but to give the ending
    to the thing the ending was being mistaken for.
    """
    immutable, pointer = remote_has_ref(tag), remote_has_ref(channel)
    if immutable is None or pointer is None:
        return ["", "⚠ COULD NOT CHECK whether the remote has these refs — `git ls-remote` did not "
                "answer.",
                "  That is NOT 'they are pushed'. Nothing was compared. If a publish trigger",
                "  announced a release above, it announced one this check cannot confirm anyone",
                "  else can reach."]
    if immutable and pointer:
        return ["", f"✓ the remote has BOTH refs — {tag} and the {channel} pointer. Consumers can "
                "reach this."]
    missing = [n for n, ok in ((tag, immutable), (f"{channel} (the channel pointer)", pointer))
               if not ok]
    return ["", "⚠ THESE REFS ARE STILL ONLY LOCAL: " + " · ".join(missing),
            "",
            "  Anything printed above about a release — a wish granted, consumers behind — is",
            f"  about a commit the remote cannot serve. A consumer following it finds the",
            "  PREVIOUS release, or no tag at all.",
            "",
            "  This is the last line on purpose: the push instructions are further up, and a",
            "  publish trigger's success banner is what a reader sees last. That ordering has",
            "  ended two marks here with the record local and the announcement already out.",
            "",
            f"    git push origin HEAD",
            f"    git push origin {tag}",
            f"    git push origin --force {channel}"]


def cmd_confidence(s, a):
    """Report what this project is willing to say about a commit — or mark one, with the evidence.

    The reader half is for CONSUMERS and answers the question a clone cannot: is this commit
    something the author stands behind, or a Tuesday afternoon?
    """
    ref = a.ref or "HEAD"
    sha = _git("rev-parse", ref) or "?"
    if not a.mark:
        lvl, tag, body = confidence_of(ref)
        out(f"CONFIDENCE: {lvl.upper()} — {sha[:8]}" + (f"  ({tag})" if tag else ""))
        if lvl == "alpha":
            out("  Nothing marks this commit, and that is the default rather than a judgement.",
                "  Treat it as MID-FLIGHT: the author pushes while features are half-landed, and a",
                "  clone gives you whatever was on main that morning.",
                "  → For something the author stands behind, check out a tag: `git tag -l 'beta-*' "
                "'stable-*'`")
        else:
            out(*["  " + l for l in body.splitlines()] or ["  (no evidence recorded)"])
            out("  → Re-check it yourself rather than trusting the tag: "
                "`game_loop confidence --recheck`")
        out("",
            "  WHAT NO LEVEL MEANS (INV6): none of these say the code is correct, only what was",
            "  CHECKED and by whom. beta says a suite passed; stable says the author's own agent ran",
            "  on it. Neither is a promise about your project.")
        return

    if a.mark not in ("beta", "stable"):
        die(f"--mark takes beta or stable. alpha is the ABSENCE of a mark: it is what every "
            "unmarked commit already is, so marking one would say nothing.")
    if _git("status", "--porcelain"):
        die("the working tree has uncommitted changes.\n"
            "A confidence mark describes a COMMIT, not a desk. What you would be marking is not "
            "what anyone else can check out.")
    stale = run_verify_check()
    if stale:
        die("this commit's owed checks have not run since its last change:\n  " + stale + "\n"
            "beta means THE SUITE PASSED ON THIS TREE. Run `./.game_loop/bin/verify`, then mark.")
    pin = pinned_sha()
    if a.mark == "stable" and (not pin or not sha.startswith(pin[:8])):
        die("stable is for a commit the owning agent runs, and THE PIN DOES NOT NAME THIS ONE.\n"
            f"  pinned : {pin[:8] if pin else '(nothing pinned)'}\n"
            f"  this   : {sha[:8]}\n"
            "Run `game_loop self --pin " + sha[:8] + "`, work on it, then mark it stable.\n\n"
            "WHAT THIS CHECK ESTABLISHES, exactly: that the recorded pin equals this commit. It is\n"
            "a value comparison. It does NOT establish that anything ran under that pin — no\n"
            "elapsed time, no observed turn, and not even that the pinned checkout is WIRED (`self`\n"
            "reports that separately, and an unwired pin changes nothing about what executes).\n"
            "`self --pin` followed immediately by this verb satisfies it; that has happened here,\n"
            "27 seconds apart, which is why this paragraph exists (#104).\n"
            "Dogfooding is still the evidence — the pin is how you DECLARE it, not proof you did it.")
    tag = f"{a.mark}-{sha[:8]}"
    lines = [f"{a.mark} — marked {now()}",
             "",
             "evidence:",
             "  tree clean at mark time (this describes the commit, not a working copy)",
             "  verify: every owed check had run since the last change to a gated file"]
    if a.mark == "stable":
        lines.append("  dogfooded: the owning agent's own harness was pinned to this commit")
        lines.append("            (a DECLARED pin, not observed running — see #104: the gate is a "
                     "value comparison)")
    if a.notes:
        lines += ["", "notes: " + a.notes]
    lines += ["", "this says what was CHECKED, never that the code is correct."]
    msg = "\n".join(lines)
    r = subprocess.run(["git", "tag", "-a", tag, "-m", msg], cwd=REPO_ROOT,
                       capture_output=True, text=True)
    remark = False
    if r.returncode != 0:
        # A MARK IS ONE-SHOT, AND ITS TRIGGERS ARE NOT THE SAME THING AS ITS RECORD. Observed here:
        # the mark landed, its publish trigger declined because HEAD was not pushed YET, I pushed,
        # and the re-run died on `tag already exists`. The record existed; the publication it exists
        # to cause did not; and the only recovery was running the trigger script by hand from a path
        # nobody but its author knows. Meanwhile consumers stayed on the previous stable.
        #
        # So an existing tag AT THE SAME COMMIT is not an error — it is a retry, and the thing worth
        # retrying is the triggers. At a DIFFERENT commit it still dies: the immutable record of what
        # was checked must never be silently rewritten, which is the whole reason it is immutable.
        _at = _rev(tag)
        if _at and _at == sha:
            remark = True
        else:
            die("could not create the tag: " + (r.stderr or "").strip()
                + ("\n  it names " + _at[:8] + ", not this commit — that record stands."
                   if _at else ""))
    # AND MOVE THE CHANNEL POINTER (#61). `stable-<sha>` is the immutable record of one mark;
    # `stable` is "the newest thing marked at that level", and it exists so that NOBODY DOWNSTREAM
    # HAS TO ORDER TAGS.
    #
    # Ordering them is a trap, and it is not a hypothetical one. The marks are ANNOTATED, so tag
    # order is not commit order, and the two plausible sorts disagree — `--sort=-creatordate` is
    # right, `--sort=-committerdate` returns something much older, and both look reasonable. A
    # consumer who picks wrong silently pins an older commit, and the installer then correctly
    # stamps THAT commit as stable, so nothing downstream ever contradicts it.
    #
    # The remote sort is not an answer either: `git ls-remote --sort=-creatordate` has to READ the
    # tag objects to sort them, so in a fresh checkout that does not have them it fails with
    # "missing object" — it works from a clone of this repo and fails for exactly the consumer it
    # would be for. Measured, after I shipped it and tried it from a bare directory.
    #
    # So the ordering happens HERE, once, by the only party that already knows the answer: the one
    # doing the marking. A consumer asks for `stable` and gets a ref. Force-moved on purpose — a
    # channel pointer that could not move would not be a channel.
    ch = subprocess.run(["git", "tag", "-f", a.mark, sha], cwd=REPO_ROOT,
                        capture_output=True, text=True)
    moved = ch.returncode == 0
    logline({"kind": "confidence", "level": a.mark, "sha": sha, "tag": tag,
             "channel_moved": moved, "notes": a.notes})
    out(f"✓ MARKED {a.mark.upper()} — {tag}" if not remark else
        f"✓ RE-MARKED {a.mark.upper()} — {tag} already records this commit, unchanged. The record "
        f"was already made;\n  what is being retried is everything the mark CAUSES, below.",
        *["  " + l for l in lines],
        "")
    # IS THIS COMMIT ACTUALLY ON THE BRANCH CONSUMERS TRACK? Pushing the channel pointer at a commit
    # that is not on main hands every consumer a tree reachable only by that tag — and if the commit
    # is later rebased away, the pointer names something no branch contains.
    #
    # NOT HYPOTHETICAL. I did it today, to this repo: another agent pushed to main while I worked,
    # my `git push origin main` was REJECTED as non-fast-forward, and I pushed the tag and the
    # channel anyway because they were separate commands and the failure was three lines up. For
    # several minutes `stable` named a commit missing that agent's work, which my own rebase then
    # orphaned. A consumer installing in that window would have got it, and nothing would have said so.
    upstream = subprocess.run(["git", "rev-parse", "--abbrev-ref", "@{upstream}"], cwd=REPO_ROOT,
                              capture_output=True, text=True)
    on_upstream = None
    if upstream.returncode == 0 and upstream.stdout.strip():
        anc = subprocess.run(["git", "merge-base", "--is-ancestor", sha, upstream.stdout.strip()],
                             cwd=REPO_ROOT, capture_output=True, text=True)
        on_upstream = anc.returncode == 0
    if moved and on_upstream is False:
        out("⚠ THIS COMMIT IS NOT ON YOUR UPSTREAM BRANCH YET, so pushing the channel pointer now",
            "  would aim every consumer at a commit no branch contains — and a rebase would orphan",
            "  it entirely. PUSH THE BRANCH FIRST and only push the pointer once that SUCCEEDS:",
            f"    git push origin HEAD          # if this is rejected, STOP — do not push below",
            f"    git push origin {tag}",
            f"    git push origin --force {a.mark}",
            "  The order is load-bearing, not tidiness.")
    elif moved:
        out(f"→ push these IN ORDER, and stop if one is rejected:",
            f"    git push origin HEAD                  # the branch consumers track — FIRST",
            f"    git push origin {tag}",
            f"    git push origin --force {a.mark}      # the channel pointer consumers install from",
            f"  `{a.mark}` now names this commit, so `GAME_LOOP_CHANNEL={a.mark} ./install.sh <dir>`",
            f"  installs it without anyone having to sort tags — which is the step that goes wrong "
            f"silently.")
    else:
        # Stated, not swallowed: without the pointer the channel install keeps serving the PREVIOUS
        # stable, which is a wrong answer that looks exactly like a right one.
        out(f"⚠ the {tag} tag was created but the `{a.mark}` CHANNEL POINTER could not be moved:",
            "    " + (ch.stderr or "").strip()[:200],
            f"  Until it moves, GAME_LOOP_CHANNEL={a.mark} keeps installing the PREVIOUS commit —",
            f"  a stale answer indistinguishable from a current one. Fix with: git tag -f {a.mark} "
            f"{sha[:8]}")
    out(*fire_triggers(s, "confidence", {
        "event": "confidence", "level": a.mark, "sha": sha, "tag": tag, "notes": a.notes,
        "project": config().get("project_name"), "session": SESSION}))
    out(*mark_publication_state(tag, a.mark))


def pinned_sha():
    """The sha the owning agent's harness is pinned to, or None."""
    try:
        with open(os.path.join(REPO_ROOT, PINNED_DIRNAME, ".game_loop", "VERSION")) as f:
            return f.read().strip()
    except OSError:
        return None


def run_verify_check():
    """'' when nothing is owed, else the text of what is stale. Never raises."""
    # CODE_ROOT, not ROOT: the binary comes from wherever this process's code came from — pinned or
    # central dispatch both keep reading that code's verify, never a copy that may not exist locally
    # at all. Same reasoning as coverage_report() just below; this one had drifted from it.
    v = os.path.join(CODE_ROOT, "bin", "verify")
    if not os.path.isfile(v):
        return ""
    try:
        r = subprocess.run([v, "--check"], cwd=REPO_ROOT, capture_output=True, text=True,
                           timeout=120)
    except Exception:  # noqa: BLE001 — cannot check is not the same as clean, but it must not crash
        return "verify --check could not run"
    return "" if r.returncode == 0 else (r.stdout or r.stderr or "stale").strip()[:400]


def installed_confidence_report():
    """What level the installed harness came from. Silent when nothing recorded it (an older install).

    ALPHA is stated OUT LOUD rather than left blank, because the whole scheme fails if absence reads
    as reassurance -- which is the failure every other gate in this file exists to prevent.
    """
    try:
        with open(os.path.join(ROOT, "CONFIDENCE")) as f:
            lvl = f.read().strip()
    except OSError:
        return []
    if lvl == "alpha":
        return ["⚠ INSTALLED FROM AN ALPHA COMMIT — nothing marked it, which is the DEFAULT rather "
                "than a judgement.",
                "  The author pushes while features are half-landed, so treat this copy as "
                "mid-flight.",
                "  → For a commit they stand behind: `git tag -l 'beta-*' 'stable-*'` in the source "
                "clone, then re-install."]
    # EVERY OTHER VALUE USED TO READ AS STABLE. The line below was `"a suite passed on it" if
    # lvl == "beta" else "the author's own agent was running on it"`, so ANY level this build does
    # not know — a future one, a typo, a half-written file — printed the STRONGEST claim the scheme
    # can make. An empty CONFIDENCE rendered as "installed from a  commit — the author's own agent
    # was running on it". That is absence reading as reassurance, in the one function whose
    # docstring says the whole scheme fails if absence reads as reassurance. Found by measuring:
    # this producer was THIN, and the arm nobody had written is the arm that was wrong.
    if not lvl:
        return ["⚠ CONFIDENCE IS PRESENT BUT EMPTY — an install recorded a level and it did not "
                "survive.",
                "  This is NOT the same as an older install with no file, which is silent on "
                "purpose, and it",
                "  is not a level: nothing about this copy is established either way. Re-install "
                "from a source",
                "  clone to record one."]
    if lvl not in ("beta", "stable"):
        return [f"⚠ CONFIDENCE SAYS {lvl!r}, WHICH IS NOT A LEVEL THIS BUILD KNOWS.",
                "  Either the file is damaged or this copy predates a level added later. Nothing "
                "is established",
                "  by it — an unrecognised mark is not a weak mark, it is no mark. "
                "`git tag -l 'beta-*' 'stable-*'`",
                "  in the source clone shows what the author actually stands behind."]
    return [f"confidence: installed from a {lvl.upper()} commit — "
            + ("a suite passed on it" if lvl == "beta"
               else "the author's own agent was running on it") + "."]


INSTALLED_BY_F = os.path.join(ROOT, "installed-by.json")


def installed_by():
    """{"name", "upgrade"} when a packager placed this payload — else None.

    THE ALERT WAS RIGHT AND THE REMEDY WAS DESTRUCTIVE, reported by a consumer who nearly ran it.
    `status` told every install to re-run the curl installer. For a payload placed by a package
    manager that would overwrite a blessed, stamped release with whatever is on main at that
    instant, drop the CONFIDENCE file, and revert the integration the consumer had just finished.
    A correct detection wired to one remedy for two populations.

    The distinguishing fact is on disk and free to read, so the notice can name the right command
    per consumer instead of the same one for everybody. That is this repo's own rule -- the thing
    you RECORD and the thing you ACT ON must come from the same place -- applied to a suggestion
    rather than to a check, which is where I had not thought to apply it.

    THE COMMAND IS PRINTED, NEVER RUN. A file that game_loop executed would be a code-execution
    vector wearing a helpful face; displaying it leaves the decision and the typing with the human.
    """
    try:
        with open(INSTALLED_BY_F) as f:
            d = json.load(f)
    except (OSError, ValueError):
        return None
    if not isinstance(d, dict):
        return None
    up = str(d.get("upgrade") or "").strip()
    if not up or "\n" in up:
        return None            # a multi-line "command" is not a command; say nothing rather than guess
    return {"name": str(d.get("name") or "the packager that installed this").strip()[:60],
            "upgrade": up[:200]}


CLAIMS_F = os.path.join(ROOT, "claims.json")


def _partial_reread(claim):
    """True when a claim's own re-read says it established only part of itself.

    The word is the claim's, not this function's judgement: a reader who checked one half writes
    PARTIAL into `verified_how`, and before this nothing ever looked at it. Kept to an explicit
    marker rather than prose-sniffing -- guessing at hedged wording would fire on careful writing,
    which is the opposite of what should be encouraged.
    """
    return "PARTIAL" in str((claim or {}).get("verified_how") or "")


def running_host_version():
    """(version, how) for the Claude Code actually running this session — or (None, why not).

    BEST EFFORT, AND THE FIRST OBVIOUS ANSWER IS WRONG. `claude --version` reads whatever is on
    PATH, which is NOT necessarily the binary running this session: measured on this machine, PATH's
    claude said 2.1.145 while CLAUDE_CODE_EXECPATH pointed at a 2.1.222 install. A check built on
    the PATH answer would confidently name the wrong subject, which is worse than naming none.

    So the execpath is preferred -- it names the running binary -- and its version is read from the
    path rather than by forking it, because this runs inside `status` and a fork per status is a
    cost nobody asked for. Neither is guaranteed: absence returns None with a reason, and every
    caller must treat that as UNKNOWN rather than as agreement.
    """
    p = os.environ.get("CLAUDE_CODE_EXECPATH") or ""
    m = re.search(r"claude-code[-_]?v?(\d+\.\d+\.\d+)", p)
    if m:
        return m.group(1), "the running binary's path"
    if p:
        return None, "CLAUDE_CODE_EXECPATH is set but carries no version"
    return None, "no CLAUDE_CODE_EXECPATH in the environment"


def _statusline_claim_live():
    """A description of the live evidence that the host still sends rate_limits — or None.

    THE TAP IS THE EXERCISE. game_loop's own statusline writes limits.json straight from the host's
    payload, so a snapshot carrying the expected shape is not a record of somebody having checked:
    it is the claim holding, on this machine, this run. Absence is NOT disproof — the tap may simply
    never have run, which is the normal case on a host with no terminal statusline — so this returns
    None and the caller says it cannot tell which, rather than reporting the claim broken.
    """
    try:
        with open(limits_file()) as f:
            d = json.load(f)
    except (OSError, ValueError):
        return None
    if not isinstance(d, dict):
        return None
    # THE WINDOWS ARE NESTED, and the first version of this read them at the top level — so it could
    # never report the claim confirmed, on any host, however well the tap was working. An exercise
    # that cannot fire positive is worse than no exercise: it reports "not observed" forever and
    # that reads as the claim failing rather than as the check being wrong. Found only when a real
    # snapshot finally existed to compare against, which is the argument for producing one.
    ws = d.get("windows") or {}
    for w in ("five_hour", "seven_day"):
        v = ws.get(w)
        if isinstance(v, dict) and "used_percentage" in v:
            return f"{w} snapshot with used_percentage present"
    return None


def _windows_claim_live():
    """Evidence about "only five_hour and seven_day windows appear" — or None if none was produced.

    THE POSITIVE CONTROL IS WHAT MAKES AN ABSENCE MEAN ANYTHING (showrunner). "No third window" is
    trivially true of an empty file, of a missing file, and of a parser that stopped working: the
    claim would read as confirmed by every kind of nothing. So this reports only when at least one
    KNOWN window is present — that is the mechanism demonstrably firing — and then says whether a
    window nobody expected came with it.

    Which is the sharper form of the rule I got wrong and stated publicly: the discriminator is not
    presence versus absence, it is whether you control the input that would produce the effect. I
    control this one, because our own tap writes the snapshot.
    """
    try:
        with open(limits_file()) as f:
            d = json.load(f)
    except (OSError, ValueError):
        return None
    if not isinstance(d, dict):
        return None
    windows = {k for k, v in (d.get("windows") or {}).items()
               if isinstance(v, dict) and "used_percentage" in v}
    known = windows & {"five_hour", "seven_day"}
    if not known:
        return None                      # no control fired; an absence here proves nothing
    extra = sorted(windows - {"five_hour", "seven_day"})
    if extra:
        return (False, "a window this claim says does not exist is present: " + ", ".join(extra))
    return (True, f"{len(known)} known window(s) present and no others — the read worked and the "
                  "unexpected window is genuinely absent")


HOOK_CLAIM_F = os.path.join(ROOT, "probe", "claims-observed.json")


def _rate_limit_keys(obj, path="", depth=0, out=None):
    """Every key anywhere in a payload whose name mentions a rate limit. Bounded, because this runs
    inside the Stop gate and a pathological payload must not become a hang."""
    if out is None:
        out = []
    if depth > 6 or len(out) > 8:
        return out
    if isinstance(obj, dict):
        for k, v in obj.items():
            p = f"{path}.{k}" if path else str(k)
            if "rate_limit" in str(k).lower():
                out.append(p)
            _rate_limit_keys(v, p, depth + 1, out)
    elif isinstance(obj, list):
        for i, v in enumerate(obj[:20]):
            _rate_limit_keys(v, f"{path}[{i}]", depth + 1, out)
    return out


def record_hook_claim_observation(payload):
    """Exercise 'no hook payload carries rate-limit data' against the payload actually delivered.

    THE CLAIM DECLARED ITS OWN CONTROL AND THEN SAT AS A DEBT. Its `exercisable_why` already named
    session_id as the positive control — a payload carrying it was genuinely read, so rate_limits
    being absent from THAT is an absence that discriminates, rather than the absence of a payload,
    of a parse, or of a hook that never fired. Everything needed was written down; only the code
    was missing, which is the shape of every stale claim in this file.

    Never raises. This runs inside the Stop gate, and an exercise that can take the gate down is a
    worse defect than the staleness it fixes.
    """
    if not isinstance(payload, dict):
        return
    try:
        # ATTRIBUTION TRAVELS WITH THE READING, for the reason recorded at record_context_window:
        # an observation that cannot name the build it watched leaves `verified_against` to be
        # inferred later from mtimes. Unknown is an explicit null with its reason.
        _hv, _hw = running_host_version()
        rec = {"claim": "no-rate-limits-in-hooks",
               "control": bool(payload.get("session_id")),
               "rate_limit_keys": _rate_limit_keys(payload),
               "top_level_keys": sorted(str(k) for k in payload),
               "hook": str(payload.get("hook_event_name") or ""),
               "host_version": _hv, "host_version_how": _hw,
               "observed_at": int(time.time())}
        os.makedirs(os.path.dirname(HOOK_CLAIM_F), exist_ok=True)
        tmp = HOOK_CLAIM_F + ".tmp"
        with open(tmp, "w") as f:
            json.dump(rec, f, indent=2)
            f.write("\n")
        os.replace(tmp, HOOK_CLAIM_F)
    except (OSError, ValueError, TypeError):
        pass


def _hooks_claim_live():
    """Evidence about "no hook payload carries rate-limit data" — or None if none was produced."""
    try:
        with open(HOOK_CLAIM_F) as f:
            d = json.load(f)
    except (OSError, ValueError):
        return None
    if not isinstance(d, dict) or not d.get("control"):
        return None                      # no control fired; an absence here proves nothing
    hits = [h for h in (d.get("rate_limit_keys") or []) if isinstance(h, str)]
    if hits:
        return (False, "a hook payload carried rate-limit data at " + ", ".join(hits[:4]))
    n = len(d.get("top_level_keys") or [])
    return (True, f"a real payload was read ({n} keys, session_id among them) and carried no "
                  "rate-limit key anywhere in it")


def external_claims_report():
    """What this harness believes about its HOST, when it last checked, and against what.

    Rung 5 on purpose. Nothing here can decide whether a claim still holds -- that needs a person
    reading a doc -- so this refuses to imply it did. It makes "these have never been re-checked"
    visible instead of buried in a ledger nobody opens.
    """
    try:
        with open(CLAIMS_F) as f:
            d = json.load(f)
    except FileNotFoundError:
        return []                        # a project that makes no external claims is the norm
    except (OSError, ValueError) as exc:
        # THE FAILURE verify.yaml ALREADY NAMES, CLOSED AT RUNTIME. Its own comment says a malformed
        # claims record "degrades to silence: external_claims_report returns nothing and status
        # simply stops mentioning the host, which looks exactly like a harness with no external
        # claims to make" -- and the answer was a commit-time rule over THIS repo's copy. That does
        # nothing for a consumer whose file is truncated by a half-finished write or a bad merge.
        #
        # Measured: a corrupt claims.json and an absent one produced byte-identical status output.
        # Absent is the norm and stays silent; unreadable now says so, because a load-bearing belief
        # about the host that nobody can read is worse than one nobody made.
        return [f"  claims : .game_loop/claims.json EXISTS AND COULD NOT BE READ "
                f"({exc.__class__.__name__}).",
                "           What this harness believes about its host cannot be listed, which is "
                "NOT the",
                "           same as believing nothing. Repair or delete that file — a silent record "
                "is the",
                "           failure it exists to prevent."]
    blocks = [(k, v) for k, v in d.items() if k != "//" and isinstance(v, dict)]
    if not blocks:
        return []
    lines = []
    for _k, b in blocks:
        n = len(b.get("claims") or [])
        on, against = b.get("verified_on") or "?", b.get("verified_against")
        head = f"  claims : {n} load-bearing claim(s) about {b.get('subject', _k)}"
        lines.append(head)
        # PER-CLAIM FIRST. A block stamp cannot express "one of these was re-read last Tuesday",
        # and reporting the block value alone would speak one re-verification as six.
        claims = b.get("claims") or []
        redone = [c for c in claims if c.get("verified_against")]
        run, how = running_host_version()
        for c in redone:
            # NAMED APART from the block's `on`/`against` on purpose: a Python loop variable
            # outlives its loop, and the first version of this leaked the per-claim date into the
            # block line below — which then reported one re-reading as though it were all six.
            _cv, _con = c["verified_against"], c.get("verified_on", "?")
            # ONLY THE HOST BLOCK IS COMPARED TO THE HOST'S VERSION (#107). `running_host_version()`
            # answers "which Claude Code is serving this session", and comparing a claim about some
            # OTHER subject to it asks a question with no true answer: a claim verified against
            # "saggar's installed bridge, 2026-08-19" can never equal "2.1.241", so it reads ⚠
            # FOREVER — a warning nobody can clear, which is how a report earns being ignored.
            #
            # Live the moment a second subject appeared: a `saggar` block landed on 2026-08-25 and
            # its one claim went permanently stale against a Claude Code release number. The report
            # still SAYS what it was verified against; it just stops pretending it can judge it.
            if _k != "claude_code":
                lines.append(f"           · '{c['id']}' re-read {_con} against {_cv}. NOT compared "
                             "to the running host: this claim is about a different subject, and "
                             "nothing here knows that subject's version.")
            elif run and _cv != run:
                lines.append(f"           ⚠ '{c['id']}' was re-read {_con} against {_cv}; RUNNING "
                             f"{run} ({how}) — re-read it.")
            elif run and _partial_reread(c):
                # A PARTIAL RE-READ CLEARED THIS WARNING EXACTLY LIKE A FULL ONE. The staleness
                # check compares a DATE and a VERSION, and both advance whether the reader
                # re-established the whole claim or one corner of it. Live: two claims were re-read
                # at 2.1.246 and recorded as partial in the same breath -- one confirmed its field
                # NAMES survive without re-measuring what the values mean, the other confirmed the
                # payload still carries two windows while the binary had grown a vocabulary that
                # could not be compared to anything. Both then reported as fully current.
                #
                # The reader wrote PARTIAL down. Nothing read it. So the ✓ is split rather than the
                # word being trusted to travel: a claim that says so about itself gets a verdict of
                # its own, and the honesty of whoever wrote it is no longer load-bearing.
                lines.append(f"           ◑ '{c['id']}' re-read {_con} against {_cv} (what is "
                             "running) — but that re-read records itself as PARTIAL. Read")
                lines.append("             `verified_how` before quoting this: something in it was "
                             "checked and something was not.")
            elif run:
                lines.append(f"           ✓ '{c['id']}' re-read {_con} against {_cv}, and that is "
                             "what is running.")
            else:
                lines.append(f"           · '{c['id']}' re-read {_con} against {_cv}; running "
                             f"version UNKNOWN ({how}).")
        if redone and len(redone) < len(claims):
            lines.append(f"           the other {len(claims) - len(redone)} have NOT been re-read "
                         "since the original reading below.")
        # THE BLOCK STAMP, under the same rule as the per-claim ones above (#107): only the host
        # block is judged against the host's version. Any other subject is REPORTED and not graded,
        # because nothing here can read that subject's version to compare it with.
        if _k != "claude_code" and against:
            lines.append(f"           verified against {against} — not compared to the running "
                         "host, which is a different subject.")
        elif against and run and against != run:
            lines.append(f"           ⚠ VERIFIED AGAINST {against}, RUNNING {run} ({how}) — re-read "
                         "them; the subject moved.")
        elif against and run:
            lines.append(f"           verified against {against}, and that is what is running.")
        elif not against:
            # The absence IS the report. Saying "up to date" here would be the exact silence this
            # whole file exists to remove.
            lines.append(f"           last verified {on}, against an UNRECORDED version — so "
                         "nothing can be compared")
            lines.append("           and no run since has re-checked them. The first "
                         "re-verification records a version")
            lines.append("           and makes them checkable; until then this is a date, not an "
                         "assurance.")
        else:
            lines.append(f"           last verified {on}; the running version is UNKNOWN ({how}), "
                         "so no comparison was made.")
        # AN EXERCISE OUTRANKS A STAMP, and is reported first when one exists (showrunner).
        # A stamp records that the AUTHOR verified something on the AUTHOR's machine and then
        # asserts it about a stranger's. An exercise checks it on the stranger's, every run, and
        # cannot go stale because there is no recorded answer to rot.
        # A CONDITIONAL absence, exercised through the same snapshot: the control is a known window
        # being present at all, and the claim is that no third one came with it.
        for c in (b.get("claims") or []):
            if c.get("id") != "no-weekly-opus-window":
                continue
            w = _windows_claim_live()
            if w is None:
                lines.append("           · 'no-weekly-opus-window' is exercisable and unobserved: "
                             "no snapshot, so its")
                lines.append("             positive control did not run, and its absence would "
                             "prove nothing.")
            elif w[0]:
                lines.append(f"           ✓ 'no-weekly-opus-window' CONFIRMED LIVE — {w[1]}.")
            else:
                lines.append(f"           ⚠ 'no-weekly-opus-window' IS NO LONGER TRUE — {w[1]}.")
        for c in (b.get("claims") or []):
            if c.get("id") != "no-rate-limits-in-hooks":
                continue
            h = _hooks_claim_live()
            if h is None:
                lines.append("           · 'no-rate-limits-in-hooks' is exercisable and unobserved: "
                             "no hook payload has been")
                lines.append("             read here yet, so its positive control did not run.")
            elif h[0]:
                lines.append(f"           ✓ 'no-rate-limits-in-hooks' CONFIRMED LIVE — {h[1]}.")
            else:
                lines.append(f"           ⚠ 'no-rate-limits-in-hooks' IS NO LONGER TRUE — {h[1]}.")
        # DECLARED DEBTS, not passes: exercisable, the control identified, nobody has written it.
        debts = [c for c in (b.get("claims") or []) if c.get("exercisable") == "yes-not-yet"]
        for c in debts:
            lines.append(f"           · '{c['id']}' is exercisable and NOT YET exercised — "
                         "a declared gap, not a pass.")
        hard = [c for c in (b.get("claims") or []) if c.get("exercisable") == "no"]
        if hard:
            lines.append(f"           the remaining {len(hard)} are UNCONDITIONAL: the case where "
                         "each is false is the one")
            lines.append("           that cannot be constructed, so there is nothing to provoke "
                         "and a stamp is the only")
            lines.append("           instrument there is. (Saying that of ALL of them was wrong, "
                         "and it was wrong here.)")
        # EACH CLAIM REPORTS ITS OWN EVIDENCE. The first version called the statusline check for
        # every exercised claim, so the weekly-window claim was reported twice — once correctly by
        # its own block above, and once carrying the statusline claim's evidence under its name.
        # A reading about the wrong subject, which is the defect this file exists to name.
        # AN ALLOW LIST, NOT A DENY LIST — and the difference was a false confirmation about the
        # wrong subject. This excluded the two claims with their own probes and then ran
        # `_statusline_claim_live()` for EVERY OTHER exercisable claim, reporting the statusline's
        # usage snapshot as that claim's evidence. Observed in this repo's own status:
        #
        #   ✓ 'saggar-terminal-name-is-not-ours' CONFIRMED LIVE here — five_hour snapshot with
        #     used_percentage present ... so it cannot be stale.
        #
        # A claim about what names a TERMINAL, confirmed by a rate-limit reading, in the confident
        # voice of a live observation — while that claim was in fact BROKEN, which another session
        # established the same day by actually running saggar.
        #
        # The comment above this block already names the defect and says the first version had it.
        # The fix was a deny list of the two ids that had probes, which repairs the two cases
        # somebody was looking at and leaves the shape intact for every claim added afterwards. A
        # deny list has to be extended by whoever adds the next claim; an allow list refuses by
        # default and makes the missing probe visible instead of inventing one.
        _PROBED = {"statusline-rate-limits": _statusline_claim_live}
        ex = [c for c in (b.get("claims") or [])
              if c.get("exercised_by") and c["id"] not in
              {"no-weekly-opus-window", "no-rate-limits-in-hooks"}]
        for c in ex:
            probe = _PROBED.get(c["id"])
            if probe is None:
                # THE THIRD OUTCOME. Not confirmed, and not refuted either: nothing here can look.
                lines.append(f"           · '{c['id']}' is exercisable and NOTHING HERE CAN OBSERVE "
                             "IT — this code has no")
                lines.append(f"             probe for that subject, so the date above is a stamp "
                             "and not a reading.")
                lines.append(f"             Re-run its own exercise to check it: "
                             f"{c.get('exercised_by') or '(none recorded)'}")
                continue
            live = probe()
            if live:
                lines.append(f"           ✓ '{c['id']}' CONFIRMED LIVE here — {live}. Observed on "
                             "this machine, not")
                lines.append("             taken from a stamp, so it cannot be stale.")
            else:
                lines.append(f"           ✗ '{c['id']}' is exercisable and has NOT been observed "
                             "here: no snapshot in the")
                lines.append(f"             expected shape. Either the tap has never run, or the "
                             "claim no longer holds —")
                lines.append("             this cannot tell which, and does not pretend to.")
        if b.get("why_it_matters"):
            lines.append(f"           if they moved: {b['why_it_matters']}")
    lines.append("  → this never checks whether a claim is TRUE. It only stops one going stale "
                 "quietly.")
    return lines


def update_notice():
    """A one-line 'a newer game_loop is on main — re-install' note, or None. Silent unless BOTH the
    installed sha (VERSION) and the latest sha are known and they differ."""
    cfg = config()
    if not cfg.get("update_check", True):
        return None
    inst = installed_version()
    if not inst:
        return None
    if inst.endswith("-dirty"):
        # A dirty install has no sha that describes it, so there is nothing to compare and no
        # honest way to say "up to date". Say what it IS instead of computing an answer about a
        # commit whose content was never installed.
        return (f"⚠ INSTALLED FROM AN UNCOMMITTED TREE — .game_loop/VERSION reads {inst[:8]}-dirty.\n"
                "  The payload was copied from a working tree with changes that are in no commit, so "
                "that sha\n"
                "  does NOT describe these files and no update check can be meaningful against it.\n"
                "  → Re-install from a clean checkout to get a stamp that means something.")
    latest = _latest_version(cfg.get("update_repo", "SupposedlySam/game_loop"),
                             cfg.get("update_api_base", "https://api.github.com"))
    if not latest or inst.startswith(latest) or latest.startswith(inst):
        return None
    repo = cfg.get("update_repo", "SupposedlySam/game_loop")
    api = cfg.get("update_api_base", "https://api.github.com")
    # Differing shas are not evidence of being BEHIND. Ask which way (#49).
    rel = _compare_versions(repo, api, latest, inst)
    if rel in ("identical", "ahead"):
        return None                    # at or past the latest this check knows about — nothing owed
    if rel == "diverged":
        # THE INSTALLED COMMIT IS NOT ON THE BRANCH AT ALL, and every other signal says fine: the
        # payload is complete, VERSION is stamped, CONFIDENCE may well say stable. That combination
        # is what a commit orphaned by a rebase or a force-push looks like from inside a consumer,
        # and until now this reported it as an ordinary "an update is available".
        #
        # I CAUSED ONE. A channel pointer was pushed at a commit whose branch push had been rejected,
        # so for minutes `stable` named a tree on no branch; my own rebase then orphaned it. The
        # producer-side guard that now prevents it only helps people who install AFTERWARDS —
        # anyone who installed during the window could not discover it, and depended on me noticing
        # and writing to everyone who might have. A downstream maintainer made that point and it is
        # the half that could not see anything. This is that half.
        return (f"⚠ THE COMMIT THIS WAS INSTALLED FROM IS NOT ON {repo}'s main.\n"
                f"  Installed {inst[:8]}; it is not an ancestor of {latest[:8]}, so it was very "
                f"likely orphaned\n"
                f"  by a rebase or a force-push after you installed. Everything else looks normal — "
                f"the payload\n"
                f"  is complete and VERSION is stamped — which is exactly why this needs saying.\n"
                f"  → re-install from a ref that a branch contains:\n"
                f"    export GAME_LOOP_CHANNEL=stable\n"
                f"    curl -fsSL https://raw.githubusercontent.com/{repo}/main/install.sh | "
                f"bash -s -- .")
    if rel is None:
        # Could not determine is not the same as behind. Say what is known and no more, rather than
        # sending somebody to re-install over a difference that may be their own copy running ahead.
        return (f"⬆ game_loop: installed {inst[:8]} differs from the latest this check saw "
                f"({latest[:8]}).\n"
                f"  Which is newer could NOT be determined — no re-install is implied by this line "
                f"alone.")
    _by = installed_by()
    if _by:
        # Placed by a packager: its own upgrade is the only remedy that keeps the vendored release,
        # its stamp and its CONFIDENCE intact.
        note = (f"⬆ game_loop update available — installed {inst[:8]}, latest {latest[:8]} on main.\n"
                f"  This payload was installed by {_by['name']}, so upgrade THROUGH it — the curl\n"
                f"  installer would replace a vendored release with whatever is on main right now:\n"
                f"    {_by['upgrade']}")
    else:
        note = (f"⬆ game_loop update available — installed {inst[:8]}, latest {latest[:8]} on main.\n"
                f"  Re-install to update (bin/ is refreshed; no session restart):\n"
                f"    curl -fsSL https://raw.githubusercontent.com/{repo}"
                f"/main/install.sh | bash -s -- .\n"
                f"  This installs whatever is on main AT THAT INSTANT, which may be ahead of any\n"
                f"  released or blessed commit. If a package manager placed this payload, upgrade\n"
                f"  through that instead and have it write .game_loop/installed-by.json so this\n"
                f"  line names your command rather than this one.")
    # WHAT changed, not merely THAT something did (#37). "An update is available" is true and
    # useless for deciding whether to care. A new verb costs nothing until you reach for it; an
    # existing verb that starts costing minutes, or refusing where it used to warn, changes
    # behaviour for someone who asked for nothing — and only that earns the interruption.
    remote = _remote_behaviour(repo, cfg.get("update_raw_base", "https://raw.githubusercontent.com"))
    if remote is None:
        return note                      # could not fetch: say nothing rather than 'nothing changed'
    seen = installed_behaviour_seq()
    fresh = [e for e in behaviour_changes(remote) if e["seq"] > seen]
    if not fresh:
        return note
    lines = [note, "",
             f"  ⚠ {len(fresh)} BEHAVIOUR CHANGE(S) to verbs you already use — not new features:"]
    for e in fresh:
        lines.append(f"    · {e.get('verb', '?')}: {e.get('change', '(unstated)')}")
    return "\n".join(lines)


RULED_OUT_SHOWN = 5          # newest N printed in full; the rest are counted and pointed at
_LOG_TAIL_BYTES = 512 * 1024  # the log is append-only and unbounded — read only its tail


def ruled_out():
    """The standing RULED-OUT list: claims recorded with `--outcome refuted`, newest first.

    Read from the SHARED log rather than per-session state, on purpose. A negative result is
    knowledge about the CHECKOUT, and the run that must not re-walk the dead path is usually a LATER
    session that holds none of this one's state — so state, which is compartmentalized by design,
    is exactly the wrong place for it. The log is the one artifact a resumed run inherits.

    Best effort and bounded: only the log's tail is read, and an unreadable or half-written line is
    skipped. A status that cannot print the list must still print everything else.
    """
    start = 0
    try:
        with open(LOG_F, "rb") as f:
            f.seek(0, os.SEEK_END)
            start = max(0, f.tell() - _LOG_TAIL_BYTES)
            f.seek(start)
            lines = f.read().decode("utf-8", "replace").splitlines()
    except OSError:
        return []
    if start and lines:
        lines = lines[1:]   # a tail read can slice a line in half — drop the fragment
    found = []
    for ln in lines:
        try:
            rec = json.loads(ln)
        except ValueError:
            continue
        if rec.get("kind") == "claim" and rec.get("outcome") == "refuted":
            found.append(rec)
    found.reverse()
    return found


def denials_report(s):
    """The HARNESS's own refusals, as enforcement evidence. Never raises.

    A "gates fired" count is the loop talking about itself — its blocks, its arms, its rings. A
    `toolDenialKind` in the transcript is something else entirely: the harness actually refusing a
    tool call. That is the referee firing, and it is the difference between showing enforcement and
    showing a dashboard. Read as a FIELD of the decoded record (`_denial_kinds`), at any depth, and
    never by text match — the string itself is all over a normal transcript as data.

    An empty result is the truth, not a blind spot: armed, nothing tripped it. What this does NOT
    catch (INV6): only the transcript this session's hooks last named is read, so refusals from a
    session whose transcript has rolled away are invisible, and a refusal the harness records under
    some other shape is not counted. Zero here means "none in THIS transcript", never "none ever".
    """
    tpath = s.get("_tpath")
    _, stats, why_not = _scan_transcript(tpath)
    if why_not:
        return ["denials: no transcript in reach — the harness's own refusals cannot be counted "
                "(absence of signal, not evidence that none happened)"]
    d = stats["denials"]
    if d:
        total = sum(d.values())
        lines = [f"denials: the harness refused {total} tool call{'' if total == 1 else 's'} in this "
                 "transcript — " + ", ".join(f"{k} ×{n}" for k, n in sorted(d.items())),
                 "  read as a field in the decoded record, never grepped — the string alone is data"]
    else:
        lines = ["denials: 0 — armed, nothing tripped it. The harness refused no tool call in this "
                 "transcript (read as a field, never grepped; 0 here is not proof of safety)"]
    if stats["skipped"] or stats["oversized"]:
        lines.append(f"  transcript: {stats['lines']} lines · {stats['skipped']} skipped "
                     f"· {stats['oversized']} oversized (truncated, not carried)")
    return lines


def _short(p):
    """A repo-relative path when it is under the repo, else the absolute one. Display only."""
    try:
        rel = os.path.relpath(p, REPO_ROOT)
    except (ValueError, TypeError):
        return p
    return p if rel.startswith("..") else rel


COVERAGE_SHOWN = 5


def coverage_report(s):
    """The COVERAGE block for `status` — what these rails are NOT looking at (issue #25).

    Two rails failed the same way in one project: a write guard armed with a denylist of ~10 repo
    names on a machine holding ~44, and an owed-checks manifest that only checked listed paths while
    a whole new package was built and committed. Both looked comprehensive, because the cases a
    denylist covers work perfectly — which is exactly what makes the omissions invisible.

    A denylist defaults to ALLOW; an allowlist defaults to DENY. The write guard is already an
    allowlist (bin/guard-writes-impl.sh), so it needs no fixing — but it still has one genuine
    denylist inside it (configured deploy verbs), and the manifest is still a list of paths. Where a
    denylist is unavoidable the gap has to be LOUD, because silence from a rail reads as safety and
    is not. So this block states the reach of each rail every session, whether or not anything is
    wrong, and names what none of them can see.
    """
    cfg = config()
    cov, cov_err = None, None
    try:
        # CODE_ROOT, not ROOT: the binary comes from wherever this process's code came from, so a
        # pinned run keeps reading pinned code. Which TREE it reports on is decided by the home it
        # inherits through GAME_LOOP_HOME, not by where the file sits. Identical when not pinned.
        r = subprocess.run([sys.executable, os.path.join(CODE_ROOT, "bin", "verify"),
                            "--coverage", "--porcelain"],
                           cwd=REPO_ROOT, capture_output=True, text=True, timeout=30)
        cov = json.loads(r.stdout) if r.returncode == 0 else None
        cov_err = (r.stderr or "").strip().splitlines()[-1:] or None
    except (OSError, ValueError, subprocess.SubprocessError):
        cov = None

    lines = ["", "COVERAGE — what these rails are NOT checking (a rail goes quiet exactly where it "
             "is blind):"]
    if cov is None:
        # UNKNOWN, said as UNKNOWN. Degrading to a clean-looking line here would recreate the very
        # failure this block exists to report.
        lines.append("  checks : UNREADABLE — `./.game_loop/bin/verify --coverage` did not answer"
                     + (f" ({cov_err[0][:70]})" if cov_err else "")
                     + ". Treat coverage as UNKNOWN, not clean.")
    elif not cov.get("rules"):
        lines.append(f"  checks : NO RULES in .game_loop/verify.yaml — nothing in this project is "
                     f"checked at commit.")
        lines.append(f"           {cov.get('scanned', 0)} changed path(s), "
                     f"{len(cov.get('unchecked') or [])} of them owing nothing at all. That is the "
                     "shipped")
        lines.append("           default, and it is not the same thing as safe. Add a rule that "
                     "FAILS when the thing breaks.")
    else:
        unchecked = cov.get("unchecked") or []
        lines.append(f"  checks : {cov['rules']} rule(s) · {cov.get('scanned', 0)} changed path(s) "
                     f"— checked {cov.get('checked', 0)} · excluded {cov.get('excluded', 0)} · "
                     f"UNCHECKED {len(unchecked)}")
        for f in unchecked[:COVERAGE_SHOWN]:
            lines.append(f"             {f}")
        if len(unchecked) > COVERAGE_SHOWN:
            lines.append(f"             … {len(unchecked) - COVERAGE_SHOWN} more")
        if unchecked:
            lines.append('           → add a rule, or list it under "unchecked-ok" in '
                         ".game_loop/verify.yaml")
    lines.append("  writes : ALLOWLIST — only this repo, the temp dir, agent memory and "
                 f"{len(cfg.get('allow_write_roots') or [])} configured allow_write_roots may be")
    lines.append("           written. Everything else is denied WITHOUT being named, so nothing "
                 "goes unprotected for")
    _mw = str(cfg.get("mcp_writes") or "gated").strip().lower()
    if _mw == "disabled":
        lines.append("  mcp    : WRITES DISABLED — a mutating MCP call is refused outright and no "
                     "authorization can")
        lines.append("           open it. The escape hatch is not offered, by this project's own "
                     "choice.")
    else:
        lines.append(f"  mcp    : writes are GATED (mcp_writes: {_mw!r}) — a mutating call is "
                     "refused, and the human")
        lines.append("           may open it once with `authorize`. Set mcp_writes: \"disabled\" "
                     "to remove that door.")
        # Standing doors are worth seeing without reading config, for the same reason the write
        # roots are: a human should be able to tell what is open without going to look (#56).
        # THE WIDEST DOOR FIRST, and unmissable. mcp_trusted_servers permits EVERYTHING from the
        # named servers -- irreversible verbs, landing verbs, argument-level findings -- because a
        # project that wrote a server already owns its blast radius. That is a legitimate thing to
        # declare and an illegitimate thing to hide, so it is reported above the narrow grain and in
        # capitals: somebody inheriting this repo must meet it before they meet anything else.
        _ts = [str(x) for x in (cfg.get("mcp_trusted_servers") or [])]
        if _ts:
            lines.append("           ⚠ WHOLLY TRUSTED SERVER(S) — EVERY call is allowed, including "
                         "irreversible and")
            lines.append("           landing verbs and mutating arguments: " + ", ".join(_ts))
            lines.append("           This is the project declaring it OWNS these servers. Nothing "
                         "here can check that")
            lines.append("           it does — only that somebody with commit access to config "
                         "said so.")
        _sw = [str(x) for x in (cfg.get("mcp_standing_writes") or [])]
        if _sw:
            lines.append(f"           STANDING, no human needed ({len(_sw)}): " + ", ".join(_sw))
            lines.append("           Exact name or whole-server prefix; never an irreversible verb, "
                         "never an")
            lines.append("           argument-level finding. A PREFIX also stops short of the "
                         "landing tier (merge,")
            lines.append("           publish, deploy, release, push) — those need the tool named "
                         "exactly (#57).")
    lines.append("           want of remembering it. 'This repo' includes its LINKED WORKTREES — "
                 "one project checked")
    lines.append("           out twice is still one project (#47) — and nothing else that shares a "
                 "parent directory.")
    extra = cfg.get("deploy_verbs") or []
    shown = ", ".join(DEPLOY_VERB_DEFAULTS[:2]) + f", +{len(DEPLOY_VERB_DEFAULTS) - 2} built-in"
    lines.append(f"  deploy : DENYLIST — {len(DEPLOY_VERB_DEFAULTS) + len(extra)} verb(s) blocked "
                 f"({shown}"
                 + (f", {len(extra)} from config.json" if extra else ", 0 from config.json") + ").")
    lines.append("           A deploy verb nobody listed is NOT blocked — this is the one rail here "
                 "that defaults to")
    lines.append('           ALLOW. Add yours: config.json → "deploy_verbs".')
    # The fan-out brake, stated whether or not it is armed — an OFF rail that says nothing reads
    # exactly like an ON one that has not fired yet, and this one is off by default.
    _cc = context_cfg()
    if not _cc["enabled"]:
        lines.append("  spawn  : NOT ARMED — limits.context.enabled is false, so a session of any "
                     "size may keep")
        lines.append("           starting Crawlers. Nothing here is watching the fan-out.")
    elif not _cc["block_spawn"]:
        lines.append("  spawn  : NOT ARMED — block_spawn is false. The context cap demands a "
                     "handoff and then OPENS,")
        lines.append("           which does not stop a big session spawning more work.")
    else:
        _tok = (s.get("context_reading") or {}).get("tokens")
        _now = f"now {int(_tok) / 1000:.0f}K" if _tok else "no reading yet — fails OPEN"
        lines.append(f"  spawn  : DENYLIST — {len(_cc['spawn_verbs'])} fan-out verb(s) refused over "
                     f"{_cc['spawn_threshold_tokens'] / 1000:.0f}K of context "
                     f"({', '.join(_cc['spawn_verbs'])}; {_now}).")
        lines.append("           It matches the BASH VERB and nothing else: the same spawn through "
                     "an MCP tool, a shell")
        lines.append("           alias, a python -c, or a Crawler spawning its own children is NOT "
                     "seen here. Nor are")
        lines.append("           Crawlers ALREADY running — this brake stops the fleet growing, it "
                     "never shrinks one.")
    # The rails above are what this repo controls. The claims below are what it does not, and a
    # coverage report that names only the first half implies the second half is settled.
    lines += external_claims_report()
    lines.append("  → NONE of this sees: a mutation made through an MCP tool, an interpreter "
                 "one-liner, or a path")
    lines.append("    built from a shell variable; nor whether a listed check is real or a "
                 "tautology; nor any path")
    lines.append("    that has not CHANGED — an untouched module nobody ever checked is invisible "
                 "here.")
    return lines


def main_checkout():
    """Absolute path of the MAIN checkout when THIS tree is a linked worktree — else None.

    `git worktree list --porcelain` lists the main worktree first; that is the whole detection. It
    never raises and never guesses: no git, not a repo, a detached HEAD, a BARE main worktree (no
    files to compare against), a parent directory that has been deleted — every one of them returns
    None, because a drift report that invents a parent is worse than no drift report at all.
    """
    listing = _git("worktree", "list", "--porcelain")
    if not listing:
        return None
    path = None
    for ln in listing.split("\n\n")[0].splitlines():   # the first record is the main worktree
        if ln.startswith("worktree "):
            path = ln[len("worktree "):].strip()
        elif ln.strip() == "bare":
            return None
    if not path or not os.path.isdir(path):
        return None
    try:
        if os.path.realpath(path) == os.path.realpath(REPO_ROOT):
            return None    # this IS the main checkout — there is no parent to compare against
    except OSError:
        return None
    return path


def working_tree():
    """(toplevel, git-common-dir) of the tree the CALLER is standing in — or (None, None).

    Deliberately NOT `_git`, which runs with cwd=REPO_ROOT and can therefore only ever describe the
    binary's own tree. That single detail is the whole of #47: every answer was about the checkout
    the CODE lives in, never the checkout the agent is working in, and the two are different exactly
    when it matters most.
    """
    try:
        r = subprocess.run(["git", "rev-parse", "--show-toplevel", "--git-common-dir"],
                           capture_output=True, text=True, timeout=GIT_TIMEOUT)
    except Exception:  # noqa: BLE001 — no git, no repo, a hung index: all mean "nothing to say"
        return (None, None)
    if r.returncode != 0:
        return (None, None)
    parts = r.stdout.strip().splitlines()
    if len(parts) < 2:
        return (None, None)
    top, common = parts[0].strip(), parts[1].strip()
    if not os.path.isabs(common):
        common = os.path.join(top, common)
    try:
        return (os.path.realpath(top), os.path.realpath(common))
    except OSError:
        return (None, None)


def working_tree_report():
    """LOUD when the tree being worked IN is not the tree this harness answers FOR (#47).

    Silent in the ordinary case — the binary's tree and the caller's tree are the same — which is
    every normal invocation, so this costs nobody a line they do not need.

    It exists because the failure was silent rather than wrong-looking. An agent in a sibling
    worktree, invoking a main checkout's binary by absolute path, got confident answers about a tree
    it was not in: `worktree` said "not a linked worktree" while `.git` proved otherwise, state
    landed in the other checkout's sessions/, and before the write-scope fix its writes were denied
    outright — twelve authorizations spent on ordinary work, with nothing anywhere saying why.
    """
    top, common = working_tree()
    if not top:
        return []
    try:
        here = os.path.realpath(REPO_ROOT)
    except OSError:
        return []
    if top == here:
        return []
    mine = _git("rev-parse", "--git-common-dir")
    if mine and not os.path.isabs(mine):
        mine = os.path.join(here, mine)
    try:
        mine = os.path.realpath(mine) if mine else None
    except OSError:
        mine = None
    kin = "a LINKED WORKTREE of this same project" if (mine and mine == common) else \
          "a DIFFERENT repository"
    return [
        f"⚠ YOU ARE NOT IN THE TREE THIS HARNESS ANSWERS FOR — the working tree is {kin}.",
        f"    working tree : {top}",
        f"    harness tree : {here}",
        "  Identity, state, rules and the log all belong to the harness tree, so `status`, "
        "`worktree`",
        "  and the verbs describe THAT tree — not the one you are editing. The write guard does "
        "reach a",
        "  linked worktree of the same project (#47), so ordinary work is not blocked; everything "
        "else",
        "  still reports on the other tree.",
        f"  → Give this tree its own harness:  <game_loop>/install.sh {top}",
    ]


def _same_bytes(a, b):
    """True / False / None — None means UNREADABLE, which is never allowed to read as 'same'."""
    try:
        with open(a, "rb") as fa, open(b, "rb") as fb:
            return fa.read() == fb.read()
    except OSError:
        return None


# `worktree --porcelain` verdicts, and what each is FOR. Only "clean" means compared-and-matching,
# and it is the only 0 — the ways of not knowing are deliberately NOT folded in with it, because a
# caller that reads "cannot determine" as "clean" is the exact silent-and-wrong failure this exists
# to stop. "drifted" and "notes-drifted" are separated for the same reason in the other direction:
# differing RULES mean the two trees enforce different things and a spawn should stop; a differing
# LEDGER.md is two trees taking their own notes, which is what they are supposed to do.
#
#   0 clean          every owned file matches
#   1 drifted        a RULE file differs — the trees enforce different things (block)
#   3 notes-drifted  rules match; a non-rule owned file differs (warn, do not block)
#   2 …              could not determine. NEVER read a 2 as clean.
# code-drifted is 1, not the default 2. A drifted SCRIPT is a DETERMINED finding — the files were
# read and they differ, so the two trees do not enforce the same rules, which is what 1 means. It
# fell to the default and reported "could not determine": safe, since 2 also blocks, but it told
# every consumer the tool had failed when the tool had in fact succeeded and found something.
WORKTREE_EXIT = {"clean": 0, "drifted": 1, "notes-drifted": 3, "code-drifted": 1,
                 "not-a-worktree": 2, "no-parent-harness": 2, "unreadable": 2}


def _compare(names, pdir):
    """Split `names` into matched / drifted / unreadable against the same file under `pdir`."""
    res = {"matched": [], "drifted": [], "unreadable": []}
    for name in names:
        same = _same_bytes(os.path.join(ROOT, name), os.path.join(pdir, name))
        res["unreadable" if same is None else "matched" if same else "drifted"].append(name)
    return res


def code_files(root):
    """Every executable in a harness's bin/, sorted. The set is game_loop's own, so a byte
    comparison needs no per-file semantics — same names, same bytes, same harness."""
    d = os.path.join(root, "bin")
    try:
        # FILES only: __pycache__ is a directory and read as an unreadable file it made every
        # comparison report "unreadable", which is the answer that must never be a false alarm.
        return sorted(f for f in os.listdir(d)
                      if not f.startswith(".") and os.path.isfile(os.path.join(d, f)))
    except OSError:
        return []


def _compare_code(pdir):
    """bin/ here against bin/ there (#38).

    `harness` used to be computed over OWNED_FILES only -- config.json, INVARIANTS.md, verify.yaml,
    LEDGER.md -- and bin/ is not in that set. So `harness.drifted == []` meant "the same RULES", and
    the field name promised something strictly larger. A downstream orchestrator reported to its own
    users, in good faith, that a spawn was "verified by the harness itself", which was true and
    narrower than it read. Two trees could match on every owned file and be running different code.

    Same defect class as the probe wording (#34) and the unnamed tree (#35): a report claiming more
    reach than its evidence supports. Widened rather than renamed, because "are these two trees
    running the same harness" is a legitimate question a caller previously had no way to ask -- and
    widening can only ever report MORE drift, never less.
    """
    res = {"matched": [], "drifted": [], "unreadable": []}
    for name in sorted(set(code_files(ROOT)) | set(code_files(pdir))):
        same = _same_bytes(os.path.join(ROOT, "bin", name), os.path.join(pdir, "bin", name))
        res["unreadable" if same is None else "matched" if same else "drifted"].append(name)
    return res


def pin_status(root):
    """(is this tree running pinned code, the pinned sha or None) -- for the tree at `root`."""
    marker = os.path.join(os.path.dirname(root), PINNED_DIRNAME, ".game_loop")
    if not os.path.isdir(marker):
        return False, None
    try:
        with open(os.path.join(marker, "VERSION")) as f:
            return True, f.read().strip()
    except OSError:
        return True, None


def worktree_drift():
    """Compare THIS tree's owned files against the main checkout's. Never raises.

    The one comparison, computed once: the `status` block and `worktree --porcelain` are two
    renderings of this dict, so a machine and a human can never be told different things.

    Answers BOTH questions, separately, because they warrant different responses:
      rules   — the gate-carrying files. Differ ⇒ the trees enforce different things.
      harness — every owned file, rules included. Differ ⇒ the trees are not the same install.

    status:  clean · drifted · notes-drifted · not-a-worktree · no-parent-harness · unreadable
    """
    empty = {"matched": [], "drifted": [], "unreadable": []}
    base = {"tree": REPO_ROOT, "main_checkout": None,
            "owned": [dict(o) for o in OWNED_FILES],
            "rule_files": list(RULE_FILES), "notes_files": list(NOTES_FILES),
            "rules": dict(empty), "harness": dict(empty)}
    parent = main_checkout()
    if not parent:
        return {**base, "status": "not-a-worktree",
                "detail": "this tree is not a linked worktree — there is no main checkout to "
                          "compare it against"}
    base["main_checkout"] = parent
    pdir = os.path.join(parent, ".game_loop")
    if not os.path.isdir(pdir):
        return {**base, "status": "no-parent-harness",
                "detail": f"the main checkout ({parent}) carries no .game_loop/ — this tree's rules "
                          "are compared against nothing"}
    rules = _compare(RULE_FILES, pdir)
    owned = _compare([o["path"] for o in OWNED_FILES], pdir)
    code = _compare_code(pdir)
    # `harness` now means what its name says: owned files AND the code. Widening only ever reports
    # MORE drift, so a caller that trusted the old narrower answer is not newly misled by this one.
    harness = {k: owned[k] + ["bin/" + n for n in code[k]] for k in owned}
    here_pinned, here_sha = pin_status(ROOT)
    there_pinned, there_sha = pin_status(pdir)
    base = {**base, "rules": rules, "owned_files": owned, "code": code, "harness": harness,
            # Say exactly what was compared, so a consumer never has to infer it from a field name
            # again -- which is the whole of this issue.
            "compares": {"rules": list(RULE_FILES),
                         "owned_files": [o["path"] for o in OWNED_FILES],
                         "code": ["bin/" + n for n in code["matched"] + code["drifted"]
                                  + code["unreadable"]]},
            "pinned": {"this_tree": here_pinned, "this_sha": here_sha,
                       "main_checkout": there_pinned, "main_sha": there_sha}}
    if rules["drifted"]:
        return {**base, "status": "drifted",
                "detail": f"{len(rules['drifted'])} RULE file(s) differ from the main checkout — "
                          "these trees enforce different things: " + ", ".join(rules["drifted"])}
    if rules["unreadable"]:
        return {**base, "status": "unreadable",
                "detail": "rule file(s) could not be read, so they are NOT known to match: "
                          + ", ".join(rules["unreadable"])}
    # These two ask about the OWNED files specifically. Testing `harness` here once `harness`
    # included code meant a drifted SCRIPT returned "notes-drifted" and never reached its own
    # branch -- the widening silently swallowing the finding it was added to surface.
    _local = _compare(["config.local.json"], pdir)
    base["local_override"] = _local
    base["compares"]["local_override"] = ["config.local.json"]
    if owned["drifted"]:
        return {**base, "status": "notes-drifted",
                    "detail": "config.local.json differs between these trees. It is not a rule file, "
                              "but its keys MERGE WITH UNION semantics — allow_write_roots, "
                              "deploy_verbs, read_roots and every mcp_* grant — so the two trees can "
                              "enforce different EFFECTIVE policy while every rule file is "
                              "byte-identical."
                              + (" Owned files also differ: " + ", ".join(owned["drifted"])
                                 if owned["drifted"] else "")}
        return {**base, "status": "notes-drifted",
                "detail": "the rules match; these owned-but-not-rule file(s) differ, which is "
                          "ordinary for per-tree notes: " + ", ".join(owned["drifted"])}
    if owned["unreadable"]:
        return {**base, "status": "unreadable",
                "detail": "owned file(s) could not be read: " + ", ".join(owned["unreadable"])}
    # THE BRANCH THAT WAS NEVER ADDED (#66). rules and owned each got one; `code` did not, when the
    # comparison was widened to include scripts. So a script that could not be READ fell through
    # every test and landed on `clean` — exit 0, with a detail sentence claiming every harness script
    # is byte-identical, about a file this verb never opened. Checked BEFORE the drifted branch:
    # "could not tell" outranks every determined finding, because a determined finding about the
    # files we could read says nothing about the one we could not.
    if code["unreadable"]:
        # A CONSUMER CANNOT RE-DERIVE THIS AFTER A MERGE, so the verb says it. The false `clean`
        # did not stop at a brief: an orchestrator refuses to integrate on rules-drifted or
        # undetermined, and a false clean walked through that gate and put a drifted Crawler's
        # branch on trunk. This flag is true exactly when the OLD code would have said clean --
        # everything else matched, and only an unreadable script stood between this tree and a
        # verdict it had not earned. Scanning trees for it is how somebody finds what was
        # mis-certified before the fix; nothing else records it.
        return {**base, "status": "unreadable",
                "false_clean_before_fix": not (rules["drifted"] or rules["unreadable"]
                                               or owned["drifted"] or owned["unreadable"]
                                               or code["drifted"]),
                "detail": "harness SCRIPT(s) could not be read, so they are NOT known to match — a "
                          "script this verb never opened cannot be reported as identical: "
                          + ", ".join(code["unreadable"])
                          + ". A game_loop before this fix reported THIS tree as clean, exit 0."}
    if code["drifted"]:
        return {**base, "status": "code-drifted",
                "detail": "the rules and notes match, but these harness SCRIPTS differ, so the two "
                          "trees do not enforce them the same way: " + ", ".join(code["drifted"])}
    # LAST, BELOW EVERY DETERMINED FINDING ABOUT THE HARNESS ITSELF. config.local.json changes
    # EFFECTIVE policy — its keys merge with UNION semantics, so allow_write_roots and every mcp_*
    # grant written there is additive and cannot be narrowed by the project's own config — but a
    # drifted RULE or SCRIPT is the stronger finding and must not be swallowed by this one. I put
    # this check above them first, which is the same widening-swallows-the-finding bug I fixed in
    # this function hours earlier.
    #
    # NOTES WEIGHT: the file is legitimately per-tree and gitignored. Exit 3 warns without blocking,
    # which is what a consumer asked for — the point is that the override stops being SILENT to the
    # layer above, not that it becomes an error.
    # BOTH SIDES MUST EXIST. A worktree that simply has no local wiring while the parent does is
    # the ORDINARY case — the file is gitignored and per-tree by design — and reporting that as
    # drift would make every adopted worktree notes-drifted on day one, which is a check nobody
    # would keep. The attack path (a session authoring one) is closed at the WRITE by #65; this
    # comparison exists so that two trees which BOTH carry local wiring and disagree stop looking
    # byte-identical to the layer above.
    if _local["drifted"]:
        return {**base, "status": "notes-drifted",
                "detail": "config.local.json differs between these trees. Not a rule file, but its "
                          "keys MERGE WITH UNION semantics — allow_write_roots, deploy_verbs, "
                          "read_roots and every mcp_* grant — so these trees can enforce different "
                          "EFFECTIVE policy while every rule file is byte-identical."}
    pin_note = ""
    if there_pinned and not here_pinned:
        # STATED, NOT AUTO-FIXED (#38). A pin is deliberately not carried into a worktree: a
        # worktree is where the harness gets EDITED, and pinning it would hide the change under
        # test. But an agent editing a gate is exactly what pinning protects, and it is more exposed
        # here than the orchestrator ever was -- so the verdict says so instead of leaving a caller
        # to infer it from a gitignore.
        pin_note = ("  NOTE: the main checkout runs PINNED code and this tree does not, so this "
                    "tree runs the harness it may be editing. Deliberate, not an oversight -- "
                    "pinning a worktree would hide the change under test. Run "
                    "`game_loop self --pin <ref>` here if this tree is editing gates.")
    return {**base, "status": "clean", "pin_note": pin_note,
            "detail": "every owned file AND every harness script is byte-identical to the main "
                      "checkout's" + (" " + pin_note if pin_note else "")}


def worktree_report(s):
    """The WORKTREE block for `status` — do this tree and the main checkout run the SAME rules? (#30)

    A linked worktree is a second working copy of ONE project, and the owned rule files are what that
    project enforces. When they differ, the tree is playing by a rule set nobody chose — and the
    dangerous direction is the silent one: a verify.yaml with no rules owes nothing, so the commit
    gate reports success while checking nothing. Reported whether or not anything is wrong, for the
    same reason COVERAGE is: a rail that only speaks up when it feels like it teaches nobody its reach.

    Empty in the ordinary case — a main checkout has no parent, so this block simply does not appear.

    What this does NOT catch (INV6): only THIS tree against the MAIN checkout, and only the owned
    files, and only by their bytes. A third worktree that drifted is invisible here; so is a divergent
    bin/, a divergent .claude/settings.json, and any rule file whose CONTENT is a tautology — two
    identical verify.yaml files say the trees agree, never that either one checks anything real.
    """
    d = worktree_drift()
    if d["status"] == "not-a-worktree":
        return []
    lines = ["", "WORKTREE — a second tree of one project must carry that project's rules (#30):",
             f"  main checkout: {d['main_checkout']}"]
    if d["status"] == "no-parent-harness":
        lines.append("  ⚠ the main checkout carries NO .game_loop/ — this tree's rules are compared "
                     "against nothing.")
        return lines
    rules, harness = d["rules"], d["harness"]
    if rules["drifted"]:
        lines.append(f"  ⚠ RULES DIFFER — {len(rules['drifted'])} of the gate-carrying file(s) are "
                     "not the main checkout's.")
        lines.append("    These two trees ENFORCE DIFFERENT THINGS. The quiet direction is the "
                     "dangerous one: a")
        lines.append("    verify.yaml with fewer rules owes less, and reports success while "
                     "checking nothing.")
        for name in rules["drifted"]:
            lines.append(f"      .game_loop/{name}")
        lines.append(f"    → adopt the main checkout's:  ./install.sh --same-as {d['main_checkout']} "
                     f"{REPO_ROOT}")
        lines.append("      (or diff them and decide — the difference may be the one you meant)")
    elif rules["matched"]:
        lines.append("  ✓ RULES MATCH the main checkout: "
                     + ", ".join(f".game_loop/{n}" for n in rules["matched"]))
    notes_drift = [n for n in harness["drifted"] if n in NOTES_FILES]
    if notes_drift:
        lines.append("  · notes differ (owned, but no gate reads them — two trees keeping their own "
                     "records is")
        lines.append("    ordinary, and this is a note, not a finding): "
                     + ", ".join(f".game_loop/{n}" for n in notes_drift))
    unreadable = harness["unreadable"]
    if unreadable:
        lines.append("  ? UNREADABLE — cannot be compared, so treat them as UNKNOWN, not matching: "
                     + ", ".join(f".game_loop/{n}" for n in unreadable))
    lines.append("  → NOT compared: .claude/settings.json · any OTHER worktree · whether a matching "
                 "rule is real")
    lines.append("  → provisioning trees? `game_loop worktree --porcelain` answers all of it as JSON "
                 "— `rules`")
    lines.append("    (differ ⇒ stop the spawn), `code` (bin/, differ ⇒ the trees do not enforce the "
                 "rules the")
    lines.append("    same way), `harness` (both), and `compares` listing exactly what was looked at "
                 "— so no")
    lines.append("    caller ever has to infer reach from a field name again (#38).")
    return lines


def cmd_worktree(s, a):
    """`game_loop worktree` — the drift answer on its own, for a human or for a spawn path (#30).

    Follows `verify --coverage --porcelain`: JSON on stdout, one object. Unlike that one this is
    allowed a non-zero exit, because it is answering a question rather than reporting coverage — but
    the exit code is never the ONLY signal. Read `status`: only "clean" was compared and matched.
    """
    d = worktree_drift()
    if a.porcelain:
        json.dump(d, sys.stdout)
        sys.stdout.write("\n")
    else:
        block = worktree_report(s)
        out(*(block or ["worktree: this tree is not a linked worktree — nothing to compare. "
                        f"({d['detail']})"]))
    sys.exit(WORKTREE_EXIT.get(d["status"], 2))


def cmd_owned(s, a):
    """Publish the owned-file set, so nothing outside game_loop has to hardcode it (#30)."""
    if a.porcelain:
        print(json.dumps({"owned": [dict(o) for o in OWNED_FILES],
                          "rule_files": list(RULE_FILES), "notes_files": list(NOTES_FILES)},
                         indent=2))
        return
    out("OWNED — the files this PROJECT owns. install.sh seeds them once and never overwrites them;",
        "  everything else under .game_loop/ is the tool (bin/, VERSION) or runtime state.")
    for o in OWNED_FILES:
        out(f"  {'rule ' if o['rule'] else 'notes'}  .game_loop/{o['path']}"
            f"   (fresh install copies {o['seed_from']})")
    out("",
        "  TWO sets, because there are two questions. `rule_files` are what the project ENFORCES —",
        "  two trees carrying different ones enforce different things, and that should stop a spawn.",
        "  `notes_files` are owned too, and drift there is ORDINARY: a ledger of findings is a record",
        "  of one tree's work, not a gate. Together they are the whole harness. Provisioning a tree?",
        "  Read this (`--porcelain` for JSON) rather than listing it again somewhere else: a",
        "  hardcoded copy goes wrong silently the moment game_loop adds a file.")


def pin_file_drift():
    """bin/ files whose bytes differ between the pinned copy and this repo — [] when identical.

    COMMIT EQUALITY IS NOT FILE EQUALITY, and the gap between them is the state you are in whenever
    you are FIXING a guard: pinned at HEAD, edits uncommitted, every one of them inert. The commit
    check above cannot see it, and its silence reads as "the pin is current".

    ([], None) vs ([], "why") is kept apart: if the two trees cannot be compared, that is not
    agreement between them.
    """
    if CODE_ROOT == ROOT:
        return [], None
    drift, checked = [], 0
    # EVERY FILE IN bin/, DERIVED — this was a hand-written tuple of seven and bin/ holds eleven.
    # The four it missed were `_gl_impl.py`, `guard-writes.sh`, `guard-mcp.sh` and `limit-probe.sh`:
    # the module holding essentially all the logic since #109 split the binary, plus the two thin
    # hook wrappers Claude Code actually invokes. So the check whose docstring describes "you are
    # FIXING a guard, pinned at HEAD, edits uncommitted, every one of them inert" could not see an
    # edit to the file a guard fix almost always lands in.
    #
    # The UNION of both trees rather than a listing of one, so the enumeration does not depend on
    # which side is asked. It does NOT make one-sided ABSENCE into drift — the loop below still
    # skips a file missing from either tree, deliberately: that is a DIFFERENT COMMIT, which the
    # commit check above already reports, and this one is only about same-commit-different-bytes.
    # (I first wrote the opposite in this comment and asserted it; the assertion failed, which is
    # the difference between describing what the code does and describing what I assumed.)
    _names = set()
    for _side in (CODE_ROOT, ROOT):
        try:
            _names |= {f for f in os.listdir(os.path.join(_side, "bin"))
                       if not f.startswith("__")
                       and os.path.isfile(os.path.join(_side, "bin", f))}
        except OSError:
            pass
    for name in sorted(_names):
        a_, b_ = os.path.join(CODE_ROOT, "bin", name), os.path.join(ROOT, "bin", name)
        try:
            with open(a_, "rb") as f:
                ab = f.read()
            with open(b_, "rb") as f:
                bb = f.read()
        except OSError:
            continue                     # absent on either side is not drift; it is a different tree
        checked += 1
        if ab != bb:
            drift.append(name)
    if not checked:
        return [], "no bin/ file could be read from both trees, so nothing was compared"
    return drift, None


def pinned_report():
    """Where the running CODE is, when that is not where the HOME is. Empty on the common path.

    Same reasoning as the coverage and drift reports: a configuration you cannot see is one you
    cannot verify. Running pinned changes what a gate is reading and what an upgrade will destroy,
    and inferring it from a hook command line nobody re-reads is exactly how it goes wrong. So it is
    printed, with both locations named and both commits shown, every session.
    """
    if CODE_ROOT == ROOT:
        return []
    code_v, home_v = running_version(), _git_sha(REPO_ROOT)
    lines = ["", "PINNED CODE — the harness guarding this session is NOT the code in this repo:",
             f"  code : {CODE_ROOT}" + (f"   @ {code_v[:8]}" if code_v else "   (no VERSION, not a "
                                                                           "git checkout)"),
             f"  home : {ROOT}" + (f"   (repo @ {home_v[:8]})" if home_v else "")]
    if code_v and home_v and not (code_v.startswith(home_v) or home_v.startswith(code_v)):
        lines.append("  ⚠ the pinned copy is a DIFFERENT commit from this repo's HEAD — edits to "
                     ".game_loop/bin/")
        lines.append("    here are inert until you re-pin. That is the point, and it is also how a "
                     "fix sits unused.")
    _drift, _drift_why = pin_file_drift()
    if _drift:
        lines.append("  ⚠ THESE FILES DIFFER BETWEEN THE TWO TREES RIGHT NOW: " + " ".join(_drift))
        lines.append("    Same commit is not same bytes. Uncommitted edits to those live here and "
                     "are INERT —")
        lines.append("    the hooks run the pinned copy. This is the state you are in while FIXING "
                     "a guard, and")
        lines.append("    it is the one the commit check above cannot see. → game_loop self --pin "
                     "HEAD")
    elif _drift_why:
        lines.append(f"  ⚠ COULD NOT COMPARE the two trees ({_drift_why}) — which is not the same "
                     "as agreement.")
    lines += ["  rules, state, log, pins and verified.json are read from and written to the HOME, "
              "never the",
              "  pinned copy — a check run against the copy would gate nothing, and state written "
              "there is",
              "  destroyed by the next re-pin. → game_loop self"]
    return lines


def _home_keyed(entry):
    """(tilde form, whose home) for an absolute path living under SOME account's home — the one
    shape a path cannot survive being committed in. None for anything else.

    Two cases, and both are the same mistake seen from opposite ends. Under THIS account's home,
    the tilde form IS the entry rewritten correctly, so it is returned. Under ANOTHER account's —
    which is precisely what someone who cloned the repo sees — the path does not exist here at all
    and there is no rewrite to offer, only the account name that gives the mistake away.
    """
    if not isinstance(entry, str) or not os.path.isabs(entry):
        return None
    p = os.path.normpath(entry)
    home = os.path.expanduser("~")
    if os.path.isabs(home) and (p == home or p.startswith(home + os.sep)):
        return ("~" if p == home else "~/" + p[len(home) + 1:]), None
    # Where accounts' homes sit (/Users, /home). Never os.sep itself: with home=/root that would
    # read every absolute path on the disk as somebody's home directory.
    holder = os.path.dirname(home)
    if os.path.isabs(holder) and holder != os.sep and p.startswith(holder + os.sep):
        account = p[len(holder) + 1:].split(os.sep)[0]
        if account:
            return None, account
    return None


def config_paths_report():
    """The CONFIG PATHS block for `status` — a TRACKED config granting a write on ONE machine.

    `.game_loop/config.json` is project config and belongs in git; the installer's inner .gitignore
    lists runtime state only, so it is tracked in every target. Two of its fields take filesystem
    paths, and the natural thing to type in them is an absolute one under the author's home. For
    `read_roots` that is merely useless to a stranger. For `allow_write_roots` it is a permission:
    the file is committed, so everyone who clones the repo inherits an allowlisted write root
    OUTSIDE the repo — the exact thing INV3 says there are none of by default — aimed at a path
    keyed to one account. That is what happened to the project that reported this.

    The remedy already works and nothing said so, which is why this is a check and not a docs note
    (INV6: take the highest rung that applies). `expanduser` is applied to every entry before it is
    matched (bin/guard-writes-impl.sh), so the tilde form resolves to EACH user's own home and is
    correct for all of them.

    Silent unless the file is genuinely TRACKED: a project that gitignores .game_loop/ has no
    exposure, and a warning that fires where there is no hazard is the kind that gets tuned out
    (INV5's argument from the other side). Silent on any git failure, missing or unreadable config
    too — it is `status` output, and it never blocks anything.
    """
    if not _git("ls-files", "--", CONFIG_F):   # untracked, or no git at all: nothing to leak
        return []
    cfg = config()
    repo_real = os.path.realpath(REPO_ROOT)
    found = []
    # Each field names WHO expands it, because they are different readers and a remedy that cites the
    # wrong file is a remedy nobody can check.
    for field, mark, expander in (
            ("allow_write_roots", "⚠", "the write guard, .game_loop/bin/guard-writes-impl.sh"),
            ("read_roots", "·", "claim --read, .game_loop/bin/game_loop")):
        entries = cfg.get(field)
        if not isinstance(entries, list):
            continue
        for entry in entries:
            keyed = _home_keyed(entry)
            if not keyed:
                continue
            real = os.path.realpath(os.path.expanduser(entry))
            if real == repo_real or real.startswith(repo_real + os.sep):
                continue      # inside the repo: non-portable, but it grants nothing new
            found.append((field, mark, expander, entry, keyed))
    if not found:
        return []
    lines = ["", "CONFIG PATHS — .game_loop/config.json is TRACKED, and these entries name ONE "
             "machine:"]
    for field, mark, expander, entry, (tilde, account) in found:
        lines.append(f"  {mark} {field}: {entry}")
        if field == "allow_write_roots":
            lines.append("      This file is committed, so EVERY clone of this repo inherits it — an "
                         "allowlisted WRITE")
            lines.append("      ROOT outside the repo, which INV3 says there are none of by default, "
                         "granted to people")
            lines.append("      who never chose it.")
        else:
            lines.append("      Committed and keyed to one account: no permission in it, just a read "
                         "root that is")
            lines.append("      useless to everyone else who clones this.")
        if tilde:
            lines.append(f"      → write it as  {tilde}  — every entry is run through expanduser "
                         "before use, so")
            lines.append("        the tilde form resolves to EACH user's own home and is correct "
                         "for all of them.")
        else:
            lines.append(f'      It is under the home of "{account}", which is NOT this account: it '
                         "came from")
            lines.append("      whoever committed the config, and names nothing that exists here.")
            lines.append("      → if it meant \"the user's own home\", write it with a leading ~ — "
                         "every entry is run")
            lines.append("        through expanduser before use, so the tilde form is correct for "
                         "every clone.")
        lines.append(f"        expanded by: {expander}")
    lines.append("  → a RELATIVE entry is NOT the fix: those resolve against the process's working "
                 "directory,")
    lines.append("    not the repo root, so the allowlist quietly differs per caller instead of "
                 "failing.")
    lines.append("  → NOT checked: whether this repo is published anywhere, whether an absolute path "
                 "OUTSIDE a")
    lines.append("    home directory is one you meant to share, or what any of these paths hold.")
    return lines


def hook_wiring(repo_root):
    """Which hook commands in .claude/settings*.json actually prefer the pinned checkout.

    `self` used to answer this from `CODE_ROOT == ROOT` alone. That expression is true of the
    process you just typed — and says nothing whatever about the hooks, which live in a file it
    never opened. Run by hand, which is the only way anybody runs it, it therefore told a repo
    whose hooks were wired correctly that "the hooks still point at the repo's own bin/", and
    handed over a wiring block whose own warning is about the double-wiring that following it
    from that state produces. Observed here at d6bdef8, with all six hooks wired. The fix is not
    a better inference; it is opening the file.

    Three answers that never share bytes: wired · unwired · unknown. "Unknown" is for no readable
    settings at all, and must not be reported as "unwired" — one means the guards are off, the
    other means nobody looked.
    """
    out_ = {"state": "unknown", "read": [], "unreadable": [], "pinned": [], "plain": [],
            "files_with_hooks": []}
    for name in ("settings.json", "settings.local.json"):
        p = os.path.join(repo_root, ".claude", name)
        if not os.path.exists(p):
            continue
        try:
            with open(p, encoding="utf-8") as fh:
                data = json.load(fh)
        except (OSError, ValueError) as e:
            out_["unreadable"].append(f"{name} ({e.__class__.__name__})")
            continue
        out_["read"].append(name)
        cmds = []
        hooks = data.get("hooks") if isinstance(data, dict) else None
        if isinstance(hooks, dict):
            for event, groups in hooks.items():
                if not isinstance(groups, list):
                    continue
                for g in groups:
                    if not isinstance(g, dict):
                        continue
                    for hk in (g.get("hooks") or []):
                        if not isinstance(hk, dict):
                            continue
                        c = hk.get("command")
                        if isinstance(c, str) and ".game_loop" in c:
                            cmds.append((event, c))
        if cmds:
            out_["files_with_hooks"].append(name)
        for event, c in cmds:
            (out_["pinned"] if PINNED_DIRNAME in c else out_["plain"]).append((event, c))
    if not out_["read"]:
        return out_
    if out_["pinned"] and not out_["plain"]:
        out_["state"] = "wired"
    else:
        out_["state"] = "unwired"
    return out_


def wiring_drift(code, w):
    """The pinned hook command lines as SETTINGS has them vs as this tool GENERATES them.

    Extracted so `self` and `status` cannot disagree about drift. Two hand-maintained copies of one
    comparison is the very defect the comparison exists to find, and putting a second copy in the
    report that runs every session would have been the joke writing itself.

    Returns None when there is nothing to compare — no generated block, or no pinned hooks.
    """
    gen = {l.strip() for l in self_hooks_block(code)
           if l.strip().startswith('d="$CLAUDE_PROJECT_DIR/')}
    have = {c.strip() for _e, c in w["pinned"]}
    if not gen or not have:
        return None
    return {"generated": gen, "in_settings": have}


def hook_integrity_report(w=None, code=None):
    """Whether the hook commands still match what this tool generates — IN THE REPORT EVERY SESSION
    RUNS.

    .claude/settings.json is where every gate is wired: the write guard, the MCP guard, the stop
    gate, the watchdog. The write guard does not cover that file, so a session can edit it — and
    the byte-identity check that would notice lived ONLY in `game_loop self`, a verb nothing runs
    automatically and which this project's own session-start instruction does not include. So the
    master switch was unguarded AND its detector was opt-in, which is the pair this repo exists to
    refuse: the check existed, and nobody was going to run it.

    This does not GATE the file. It makes tampering answer for itself in the report the next
    session reads, which is the cheap rung, and says plainly that it is detection rather than
    prevention.
    """
    # INJECTABLE, because the loud arm is the one that never fires on a healthy repo. Reading the
    # real settings.json only ever exercises the quiet branch, so the drift arm would ship having
    # never run — which is the failure this whole report is about, one level up.
    if code is None:
        code = os.path.join(REPO_ROOT, PINNED_DIRNAME, ".game_loop")
    # NO PIN IS NOT NO ANSWER, and gating the whole report on the pinned directory existing was
    # silence for exactly the installs most exposed: a consumer who never pins still has every gate
    # wired in the same unguarded settings.json, and "unknown" and "not pinned" are answers that
    # need no pinned tree to give. Only the BYTE COMPARISON needs one, so only it is skipped.
    if w is None:
        try:
            w = hook_wiring(REPO_ROOT)
        except Exception:
            return []
    if w["state"] == "unknown":
        return ["", "hook wiring: UNKNOWN — no readable .claude/settings*.json, so nothing here can "
                "say whether the gates are wired at all."]
    if w["state"] != "wired":
        return ["", "hook wiring: NOT pinned — the hooks run this tree's .game_loop/bin/, so an "
                "edit here changes the gates guarding this session."]
    if not os.path.isdir(code):
        return ["", "hook wiring: WIRED TO A PINNED CHECKOUT THAT IS NOT THERE — the hook commands "
                f"name {PINNED_DIRNAME}/, which does not exist.",
                "  Each falls back to this tree's own bin/, so the gates still run; what is lost is "
                "the protection",
                "  the pin exists for. `game_loop self --pin HEAD` restores it."]
    d = wiring_drift(code, w)
    if not d:
        return ["", "hook wiring: pinned, but nothing to compare — no generated block, or no pinned "
                "hook commands to compare it against."]
    extra = sorted(d["in_settings"] - d["generated"])
    missing = sorted(d["generated"] - d["in_settings"])
    if not extra and not missing:
        return ["", f"hook wiring: {len(d['in_settings'])} command(s) byte-identical to what "
                "`game_loop self` generates.",
                "  DETECTION, NOT PREVENTION: the write guard does not cover .claude/settings.json, "
                "so this",
                "  is the line that would notice if something rewrote the gates."]
    L = ["", "⚠ HOOK WIRING HAS DRIFTED FROM WHAT THIS TOOL GENERATES — the file that wires every",
         "  gate (write guard, MCP guard, stop gate, watchdog) does not match its own instructions."]
    L += ["    settings.json has : " + c for c in extra]
    L += ["    self would print  : " + c for c in missing]
    L += ["  Benign drift and a disabled gate look identical from here, so read them before "
          "assuming the first."]
    return L


def pin_wiring_lines(code, w):
    """What `self` says about a pin that exists, having READ the wiring rather than guessed it."""
    n_pin, n_plain = len(w["pinned"]), len(w["plain"])
    if w["state"] == "unknown":
        L = [f"a pinned checkout exists at {code}, and WHETHER THE HOOKS USE IT IS UNKNOWN.",
             "  No readable .claude/settings.json or settings.local.json under "
             f"{os.path.join(REPO_ROOT, '.claude')}."]
        if w["unreadable"]:
            L.append("  could not parse: " + ", ".join(w["unreadable"]))
        L += ["  This is NOT the same answer as \"not wired\": nobody looked, so wire from the",
              "  block below only after reading the file yourself — a second copy of these entries",
              "  runs every gate twice."]
        return L
    if w["state"] == "wired":
        L = [f"a pinned checkout exists at {code}, and the hooks ARE wired to prefer it.",
             f"  {n_pin} hook command(s) in {', '.join(w['files_with_hooks'])} name "
             f"{PINNED_DIRNAME}/, so the gates guarding",
             "  this session run the PINNED code — editing .game_loop/bin/ here cannot break them.",
             "  That is the whole point of the pin, and you have it."]
        if len(w["files_with_hooks"]) > 1:
            L.append("  ⚠ game_loop hooks appear in BOTH settings files, which MERGE rather than "
                     "override —")
            L.append("    every gate is running twice. Delete the ones in settings.local.json.")
        _d = wiring_drift(code, w)
        gen, have = (_d["generated"], _d["in_settings"]) if _d else (set(), set())
        if gen and have and gen != have:
            L += ["",
                  "  ⚠ WIRED — BUT NOT WITH THE WIRING THIS VERB GENERATES. These are two "
                  "hand-maintained",
                  "    copies of one command line, and the one that drifts is the one nobody "
                  "re-reads:"]
            L += ["      settings.json has : " + c for c in sorted(have - gen)]
            L += ["      this verb prints  : " + c for c in sorted(gen - have)]
        elif gen and have:
            L.append(f"  ✓ all {len(have)} are byte-identical to the wiring this verb prints, so "
                     "the tracked file")
            L.append("    and the instructions have not drifted apart.")
        # AGREEMENT USED TO BE SILENT HERE, and that is the whole defect (INV8: a pass that is
        # silence proves nothing). Divergence has always been loud; a pin that MATCHES printed
        # nothing at all, so this report named no commit and a reader carrying a stale belief about
        # the pin met nothing that contradicted it. Observed 2026-09-03: a release was held for
        # hours on a written claim that the pin was `4a4a114` while HEAD was `170f506`, when the
        # stamp had said `170f5064` since 08:00 that morning — and running this verb was the thing
        # that was supposed to settle it. It could not: it printed the wiring and no sha.
        pin_sha = _pin_marker_sha(code)
        head = _git_sha(REPO_ROOT)
        if pin_sha and head and not (pin_sha.startswith(head) or head.startswith(pin_sha)):
            L += ["",
                  f"  ⚠ the pin is {pin_sha[:8]} and HEAD is {head[:8]} — the gates are running "
                  "OLDER code than",
                  "    this tree. Edits here are inert until `self --pin <sha>`, which is both the "
                  "protection",
                  "    and how a shipped fix sits unused. Re-pinning takes effect immediately."]
        elif pin_sha and head:
            _at = (_pin_marker(code).get("at") or "").replace("T", " ")
            L += [f"  ✓ the pin names {pin_sha[:8]} and so does HEAD"
                  + (f", stamped {_at}" if _at else ""),
                  "    — the gates ARE this tree, so an edit to .game_loop/bin/ is live for them."]
        elif not pin_sha:
            L.append(f"  ⚠ the {PINNED_MARK} stamp is unreadable, so WHICH commit is pinned is "
                     "unknown — which is not the same answer as \"it matches\".")
        elif not head:
            L.append("  ⚠ git could not name HEAD here, so the pin was not compared to anything.")
        L += ["",
              f"  (this invocation ran {CODE_ROOT}, because that is the path you typed. That fact "
              "is about",
              "   the command, not the hooks, and answering the hook question from it is what "
              "this verb",
              "   used to do wrong.)"]
        return L
    L = [f"a pinned checkout exists at {code}, but THE HOOKS DO NOT ALL USE IT.",
         f"  read {', '.join(w['read'])}: {n_pin} command(s) prefer the pin, {n_plain} still exec "
         "the repo's own bin/."]
    if n_plain:
        L.append("  not preferring the pin: " + ", ".join(sorted({e for e, _ in w["plain"]})))
    if not n_pin and not n_plain:
        L.append("  in fact NO game_loop hook is registered at all — the guards are not running.")
    L.append("  Wire them (below) and reload.")
    return L


def _pin_marker(code):
    """A pinned checkout's PINNED stamp as a dict, or {} — the pin's own record of what it is.

    Split out of `_pin_marker_sha` because the stamp carries `at` as well as `sha`, and WHEN a pin
    was cut is half of what a reader needs: "the pin matches HEAD" and "the pin has matched HEAD
    since this morning" answer different questions, and only the second one contradicts a written
    claim that it does not.
    """
    try:
        with open(os.path.join(code, PINNED_MARK), encoding="utf-8") as fh:
            return json.load(fh) or {}
    except (OSError, ValueError, AttributeError):
        return {}


def _pin_marker_sha(code):
    """The commit a pinned checkout was cut from, per its own PINNED marker, or None."""
    return _pin_marker(code).get("sha") or None


def cmd_self(s, a):
    """`game_loop self` — run the harness from a pinned checkout, so editing it cannot break it.

    WHY THIS IS A VERB AND NOT A PARAGRAPH IN A README (INV1): the mechanism is two git commands, but
    the DANGEROUS part is the wiring, and the wiring is what a human writes by hand. Point the hooks
    at a pinned bin/ and forget GAME_LOOP_HOME and every gate silently reads the pinned copy's
    verify.yaml — the trap, wired by omission, reporting green. So the pin is stamped with a PINNED
    marker that makes that combination REFUSE, and the hooks block is generated rather than
    remembered. A setup whose only failure mode is a step you can forget belongs in a tool.

    Writes nothing outside the repo: the checkout lands in <repo>/.game_loop_self, and the hooks
    block is PRINTED for .claude/settings.local.json rather than written over a file that may hold
    the human's own settings.

    --dest overrides where the checkout lands, for the one caller outside this repo that needs a
    checkout somewhere else entirely: a machine-wide central install that `install.sh --central`
    points many *other* repos' dispatcher shims at (see docs/how-it-works.md). Everything above still
    applies to that copy — OWNED_FILES stripped, VERSION/PINNED stamped, resolve_home still refuses a
    bare run against it — this flag only changes WHERE, never the safety properties of what lands
    there.
    """
    if a.dest and not a.pin:
        die("self --dest: only meaningful with --pin — it names where the checkout should land.")
    dest = os.path.abspath(os.path.expanduser(a.dest)) if a.dest else os.path.join(REPO_ROOT, PINNED_DIRNAME)
    code = os.path.join(dest, ".game_loop")
    if not a.pin:
        if CODE_ROOT != ROOT:
            out(*(pinned_report()[1:]))
        elif os.path.isdir(code):
            wiring = hook_wiring(REPO_ROOT)
            out(*pin_wiring_lines(code, wiring))
            if wiring["state"] == "wired":
                return
        else:
            out("not pinned: this process runs the repo's own .game_loop/bin/, which is also what "
                "you edit.")
        out("", *self_hooks_block(code))
        return
    sha = _rev(a.pin)
    if not sha:
        die(f"self --pin: git cannot resolve {a.pin!r} in {REPO_ROOT} — name a commit, tag or "
            "branch that exists here.")
    if os.path.exists(dest):
        if not os.path.isdir(os.path.join(dest, ".game_loop")):
            die(f"self --pin: {dest} exists and does not look like a pinned checkout — refusing to "
                "delete it. Move it aside yourself.")
        shutil.rmtree(dest)
    os.makedirs(dest)
    try:
        _extract_game_loop(sha, dest)
    except Exception as e:  # noqa: BLE001 — a half-written pin is worse than none; clean up and say why
        shutil.rmtree(dest, ignore_errors=True)
        die(f"self --pin: could not extract .game_loop at {sha[:8]} — {e}")
    for f in sorted(os.listdir(os.path.join(code, "bin"))):
        p = os.path.join(code, "bin", f)
        if os.path.isfile(p):
            os.chmod(p, 0o755)
    # The pinned copy must not carry the project's identity files. They are the HOME's, and a second
    # copy sitting beside the code is a copy something will eventually read — the trap needs only one
    # such misread to report a green it did not earn. Removing them makes the misread impossible
    # rather than merely wrong (rung 1), and `resolve_home` refuses a home with no config.json.
    dropped = []
    for o in OWNED_FILES:
        p = os.path.join(code, o["path"])
        if os.path.exists(p):
            os.remove(p)
            dropped.append(o["path"])
    with open(os.path.join(code, "VERSION"), "w") as f:
        f.write(sha + "\n")
    with open(os.path.join(code, PINNED_MARK), "w") as f:
        # "home" names the ONE project this pin belongs to — meaningless for a --dest checkout meant
        # to serve many different consumers, so it is left null rather than naming whichever repo
        # happened to run the pin command.
        json.dump({"ref": a.pin, "sha": sha, "at": datetime.datetime.now().isoformat(
            timespec="seconds"), "home": None if a.dest else ROOT}, f, indent=2)
        f.write("\n")
    logline({"kind": "self_pin", "ref": a.pin, "sha": sha, "dest": code})
    out(f"pinned {a.pin} ({sha[:8]}) → {code}",
        f"  dropped the project's own files from the copy: {', '.join(dropped) or '(none present)'}",
        f"  stamped VERSION and {PINNED_MARK} — running this code without {HOME_ENV} now REFUSES,",
        "  rather than quietly checking the copy instead of the project.")
    if a.dest:
        out("  this is a --dest checkout, not the repo's own .game_loop_self — wire consumer repos",
            "  at it with `install.sh --central`, not with the hooks block below.")
    else:
        out(f"  add {PINNED_DIRNAME}/ to .gitignore if it is not there already.",
            "", *self_hooks_block(code))


def self_hooks_block(code):
    """The wiring, generated — an INLINE dispatcher for the TRACKED settings.json.

    The obvious route, a second copy of every hook in settings.local.json, is wrong and was tried
    first: Claude Code MERGES the two files rather than overriding, so every gate ran TWICE — two
    write guards, two stop gates, two watchdogs polling. Measured, not predicted: one commit printed
    the same blast-radius warning verbatim two times. Nothing breaks loudly, which is the problem.

    Deleting the tracked hooks to compensate is worse: a guard that exists but is not wired in is
    not a guard, and this repo's own suite refuses that state.

    So one entry decides at call time, and it is safe to track because it degrades to the ordinary
    wiring: no pin present, no behaviour change, and a fresh clone is fully guarded. It is also
    INLINE rather than a shim script, because another script would be one more file sitting in the
    edit zone — which is the exposure a pin exists to remove.
    """
    d = "$CLAUDE_PROJECT_DIR/" + PINNED_DIRNAME + "/.game_loop"
    def wire(script):
        return (f'    d="{d}"; [ -x "$d/bin/{script.split()[0]}" ] || '
                f'd="$CLAUDE_PROJECT_DIR/.game_loop"; '
                f'{HOME_ENV}="$CLAUDE_PROJECT_DIR/.game_loop" exec "$d"/bin/{script}')
    return [
        "WIRE IT IN THE TRACKED .claude/settings.json. Replace each game_loop hook command with the",
        "matching line below — one entry that prefers the pin and falls back to the repo's own bin/:",
        "",
        wire("guard-writes.sh"),
        wire("guard-mcp.sh"),
        wire("game_loop limitgate"),
        wire("game_loop stopgate"),
        wire("game_loop sessionstart"),
        wire("watchdog"),
        "",
        f"{HOME_ENV} is not optional in any of those: it is what keeps verify.yaml, the record of "
        "what",
        "was checked, and every byte of state in the REPO rather than in the copy, which the next",
        "re-pin destroys.",
        "",
        "DO NOT also wire these in .claude/settings.local.json. The two files MERGE, they do not",
        "override, and leaving both wired runs every gate twice — measured: one commit printed the",
        "same blast-radius warning verbatim two times. Duplicate output reads as the tool repeating",
        "itself rather than as two of it running.",
        "",
        "Re-pinning takes effect immediately — the hook execs whatever the pin directory holds now.",
        "A RELOAD is needed only when these command lines themselves change.",
    ]


def _rev(ref):
    """The commit `ref` names in this repo, or None."""
    try:
        r = subprocess.run(["git", "-C", REPO_ROOT, "rev-parse", "--verify", f"{ref}^{{commit}}"],
                           capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return None
    return r.stdout.strip() or None if r.returncode == 0 else None


def _extract_game_loop(sha, dest):
    """`git archive <sha> .game_loop` straight into dest, via stdlib tarfile — no `tar` dependency."""
    import tarfile
    p = subprocess.Popen(["git", "-C", REPO_ROOT, "archive", "--format=tar", sha, ".game_loop"],
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        with tarfile.open(fileobj=p.stdout, mode="r|") as tf:
            try:
                tf.extractall(dest, filter="data")   # 3.12+: refuse paths that escape dest
            except TypeError:
                tf.extractall(dest)
    finally:
        err = p.stderr.read().decode(errors="replace") if p.stderr else ""
        p.stdout.close()
        if p.wait() != 0:
            raise RuntimeError(err.strip() or f"git archive exited {p.returncode}")
    if not os.path.isfile(os.path.join(dest, ".game_loop", "bin", "game_loop")):
        raise RuntimeError(f"that commit carries no .game_loop/bin/game_loop")


def session_models(path=None):
    """Every model this session has answered on, in order — or None if it cannot be read.

    Returns {"models": [...], "first": str, "last": str, "changed": bool}.

    NOT A SCALAR, and that correction came from showrunner rather than from me. I first returned
    the last model named, which is wrong for the failure this exists to catch: `--fallback-model`
    does not fail at spawn, it degrades MID-RUN under load, silently. A single value reports
    whichever message happened to be read and cannot represent "started as Sonnet, fell back to
    Haiku at message 400" — and that is the shape most likely to happen on a real fan-out, when
    every Crawler hits the same limit at the same moment. A scalar there is a reading of the wrong
    subject.

    NO HOOK PAYLOAD CARRIES THE MODEL. Verified against a real captured Stop payload: cwd, effort,
    permission_mode, session_id, transcript_path, and no model anywhere. The statusline payload has
    `model.display_name` and is TUI-only, so an editor-hosted session never sees it. The transcript
    records it per assistant message and every hook payload points at the transcript, so this works
    on every host with nothing to configure.

    `<synthetic>` records are the harness talking rather than a model answering, and are skipped —
    counting them would report the harness to itself.
    """
    path = path or (load() or {}).get("transcript_path")
    if not path or not os.path.isfile(path):
        return None
    tail, _stats, why_not = _scan_transcript(path)
    if why_not:
        return None
    seen = []
    for rec in tail:
        m = ((rec.get("message") or {}) if isinstance(rec, dict) else {}).get("model")
        if isinstance(m, str) and m and not m.startswith("<") and (not seen or seen[-1] != m):
            seen.append(m)
    if not seen:
        return None
    # Ordered-unique-by-adjacency above, so an A→B→A flip keeps all three and `changed` stays true.
    return {"models": seen, "first": seen[0], "last": seen[-1],
            "changed": len(set(seen)) > 1}


MODEL_F = "model.json"


def write_model_verdict():
    """Publish what this session is running, where the PARENT can read it. Returns the verdict.

    THE READER IS NOT THIS SESSION. A status line about a model mismatch is read by the Crawler,
    which is the one party that can do nothing about it: it cannot switch its own model, and by the
    time it reads the line the run is already priced. The party that can act is the orchestrator
    that dispatched it — a different process, outside, reconciling from the parent.
    (showrunner's INV22: a caveat filed where the reader does not stand.)

    So the verdict is a FILE under this session's own directory, keyed by session id, which is what
    a parent already holds in its dispatch record. Written on every hook run, so it stays current
    without the Crawler cooperating or even knowing.
    """
    v = session_models()
    if not v or not SESSION:
        return None
    v = dict(v, session=SESSION, observed_at=now())
    try:
        d = os.path.join(SESSIONS_DIR, SESSION)
        os.makedirs(d, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=d, prefix=".model.", suffix=".tmp")
        with os.fdopen(fd, "w") as f:
            json.dump(v, f, indent=2)
            f.write("\n")
        os.replace(tmp, os.path.join(d, MODEL_F))
    except OSError:
        pass                      # a verdict nobody can write is not worth taking a hook down for
    return v


def model_report(s):
    """What model is running, and whether it CHANGED under the run's feet.

    ADVISORY, NEVER A GATE, and for a reason worth stating: a model mismatch is not a correctness
    failure, it is a COST failure. An Opus-priced Crawler doing Sonnet work produces perfectly good
    output, which is exactly why nothing notices and why it can run for a week. Bricking a
    deliberately-dispatched Crawler would be the guard doing more damage than the thing it guards.

    NOTHING HAS TO BE DECLARED for this to be useful, which is what makes the feature optional by
    construction rather than by a config default. The check that matters — did the model change
    mid-run — is answerable from the transcript alone, with no knob for anyone to forget to set.
    """
    # Take the path from the state handed in rather than re-reading the global: a report that
    # ignores its own argument cannot be exercised except through the whole binary.
    v = session_models((s or {}).get("transcript_path"))
    if not v:
        return []
    if not v["changed"]:
        return [f"model: {v['last']}"]
    return [f"⚠ MODEL CHANGED MID-RUN — {' → '.join(v['models'])}.",
            "  A fallback degrades under load rather than failing at spawn, so work you dispatched",
            "  for one model has been finishing on another. Not blocked: nothing can switch a live",
            "  session back, and the output is fine — this is a COST failure, not a correctness one.",
            f"  The parent can read this at sessions/{SESSION or '<id>'}/{MODEL_F}."]


def cmd_model(s, a):
    """Report the models this session has run on — the verb a parent or a human can call."""
    v = write_model_verdict() or session_models()
    if not v:
        die("cannot read this session's model: no transcript recorded yet.\n"
            "  A hook has to run once first — the transcript path arrives on a hook payload and\n"
            "  nowhere else. This is absence of the reading, never evidence of a model.")
    if a.json:
        out(json.dumps(v, indent=2))
        return
    out(f"models this session has answered on: {' → '.join(v['models'])}",
        f"  first {v['first']} · last {v['last']} · changed: {'YES' if v['changed'] else 'no'}",
        f"  machine-readable: {os.path.join(SESSIONS_DIR, SESSION or '<id>', MODEL_F)}")


def cmd_status(s, a):
    _prune_stale_sessions()
    # RUNNING status IS ORIENTATION (#60). A guard refusal carries a one-line pointer to this
    # command and the agent brief, once per session — and a session that arrived the documented way
    # has already read everything that line would point at. Marking it here is what keeps the
    # pointer aimed at sessions that arrived blind, which is the whole population it is for.
    if not s.get("oriented"):
        s["oriented"] = True
        save(s)
    # AFTER THAT SAVE AND BEFORE THE BANNER, and both halves of that are load-bearing. After,
    # because the proof this session is real is its own state file, and on a first status the save
    # above is what creates it — running the retire first would mean it never fired on the
    # SessionStart status, which is the only one that matters. Before the banner, because this is
    # the one thing here that DESTROYS something, and a closed-terminal line printed under thirty
    # lines of coverage summary is a line nobody reads until they go looking for a tab that is not
    # there.
    if (_retired := retire_predecessor()):
        out(*_retired)
    out(render_banner(s))
    if (_m := model_report(s)):
        out(*_m)
    if (n := retro_nudge(s)):
        out(n)
    m = s.get("mandate") or {}
    parked = m.get("parked") or {}
    if parked:
        # A parked mandate is OPEN work, not a finished one — say so where it cannot be missed, with
        # the human's own words and the step that was interrupted, so a resumed run picks up the
        # thread instead of rediscovering it.
        mandate_line = (f"MANDATE: {m.get('text')}\n"
                        f"  ⏸ PARKED — a {parked.get('by', 'human')} called this break. STILL OPEN, "
                        "not closed.\n"
                        f"    their words: {parked.get('reason')}\n"
                        f"    next step  : {parked.get('next') or '(none recorded)'}\n"
                        "    → game_loop mandate --resume   (or --clear --notes \"..\" if it is done)")
    elif m.get("active"):
        mandate_line = f"MANDATE: {m['text']}"
    else:
        mandate_line = "MANDATE: none (Stop gate inert)"
    if (ho := s.get("handed_off")) and isinstance(ho, dict):
        # A handed-over session reads exactly like a live one — same mandate, same state file — and
        # the difference is the whole story: nothing here rings any more. Say it on the line where
        # the mandate is, or the next reader spends a turn wondering why the engine is silent.
        seen = successor_seen(ho.get("to"))
        _th = ho.get("thread") if isinstance(ho.get("thread"), dict) else {}
        mandate_line += (f"\n  ⇢ HANDED OVER to {str(ho.get('to'))[:8]} at {ho.get('at')} — this "
                         "session's watchdog is STOOD DOWN.\n"
                         + (f"    thread     : {_th.get('id')} · "
                            f"{_th.get('label') or '(unlabelled)'}"
                            "   (`game_loop threads` for the whole chain)\n" if _th else "")
                         + f"    successor  : {'live (it has written state)' if seen else 'NOT SEEN YET — no state file of its own'}\n"
                         f"    it reads   : {ho.get('handoff')}\n"
                         "    → this session is retired. `mandate --set \"..\"` re-arms it if you "
                         "are driving again.")
    # AND WHY IT IS NONE, when the reason is that nobody could read the file. "no mandate was ever
    # set" and "your mandate is in a file this process could not parse" are opposite situations —
    # one means you are free, the other means an unattended run has quietly stopped being governed
    # — and they printed the same line. The bytes are set aside by load(); this is what points at
    # them, because a preserved copy nobody is told about is the same as no copy.
    # THE FILE IS THE EVIDENCE, not this process's flag. The WATCHDOG reads the same state.json
    # with its own loader and sets aside the same copy, so a corruption it noticed while this
    # process was not running still has to reach the human reading status afterwards.
    _kept_copy = STATE_UNREADABLE or (STATE_F + ".unreadable"
                                      if os.path.exists(STATE_F + ".unreadable") else None)
    if _kept_copy:
        mandate_line += ("\n  ⚠ AND THAT MAY BE WRONG: .game_loop/…/state.json EXISTS AND WOULD "
                         "NOT PARSE, so this session\n"
                         "    read as brand new — no mandate, gate counters at zero, retro debt "
                         "cleared. The original\n"
                         f"    bytes are kept at {_kept_copy}\n"
                         "    Recover the mandate from there and re-bind it, or clear it on the "
                         "record if it is done —\n"
                         "    then delete that copy, which is what stops this warning.")
    session_line = (f"session: {SESSION[:8]} (state: .game_loop/sessions/…)" if SESSION
                    else "session: none detected — repo-global state (.game_loop/state.json)")
    others, active = _sibling_sessions()
    if others:
        session_line += f" · other sessions here: {others} ({active} with an active mandate)"
    out("=== game_loop (v" + s.get("version", "?") + ") ===",
        session_line,
        f"claims sourced: {s.get('claim_count', 0)} · hardened: {s.get('hardened_count', 0)}",
        mandate_line,
        inv_oneline(),
        "",
        "COST LADDER (exhaust cheap rungs first):",
        *[f"  {k} — {v}" for k, v in TIER_NAMES.items()],
        "",
        "→ before asserting external behavior:",
        '   game_loop claim --assert ".." --read <real path> [--confidence ..]',
        '→ if the assertion is about a SET ("only X", "X is restricted"), a second member is the price:',
        '   game_loop claim --assert ".." --read <path> --scope "<category>" --probe <a> --probe <b>',
        "→ when local state becomes load-bearing (a pinned dep commit, a toolchain, an SDK path):",
        '   game_loop pin --fact ".." --reason ".." --path <real path> [--expect ..] [--restore ..]',
        "→ before a finding leans on a verb having ACTED (a click, a scroll, a keystroke):",
        '   game_loop effector --prove <name> --known-state ".." --before <capture> --observed '
        "<capture>",
        "→ before reporting a FIX done (a verified diagnosis is not a verified fix — prove the "
        "OUTPUT):",
        '   game_loop fix --prove <name> --promises ".." --produces <the fix\'s own output> '
        "--diagnosis <the repro> --before <verdict> --observed <verdict>",
        "→ before a NUMBER backs anything (it is a test whose subject is reality — control it first):",
        '   game_loop instrument --register <name> --measures ".." --connects ".." '
        "--null <b,a> --positive <b,a>",
        "   game_loop measure --instrument <name> --before <n> --after <n>   (a delta, never a total)",
        "→ writes outside this repo are blocked by .game_loop/bin/guard-writes.sh (PreToolUse)",
        "knowledge: .game_loop/LEDGER.md (reference, NOT a gate) · log: .game_loop/log.jsonl")
    out(*pinned_report())  # which code is running, and on whose home — silent unless they differ
    out(*pins_report(s))   # load-bearing env facts, re-shown every session: this is what survives
    out(*effectors_report(s))   # which verbs are proved to actually act — findings lean only on these
    out(*instruments_report(s))   # the declared harm must outlive the context that declared it
    out(*fixes_report(s))   # which fixes were exercised through their OWN output — not their repro
    out(*coverage_report(s))   # what the rails are NOT looking at — silence from a rail is not safety
    out(*worktree_report(s))   # …and whether the rails in THIS tree are the project's at all (#30)
    # A CONFIG THAT DID NOT PARSE IS NOT A CONFIG WITH NOTHING IN IT. Reported before anything that
    # reads config, because every line below is computed from defaults when this fires — and for a
    # DENYLIST rail (deploy_verbs) defaults mean ALLOW. A tracked file two branches both edited
    # conflicts as a matter of course, so this is an ordinary merge away, not an exotic state.
    _unread = config_unreadable()
    if _unread:
        out("⚠ CONFIG DID NOT PARSE — every setting below is a DEFAULT, not this project's policy:",
            *[f"    {p}" for p in _unread],
            "  This is what a git conflict in a tracked config looks like. While it lasts,",
            "  `deploy_verbs` blocks NOTHING (a denylist read as empty allows everything), and any",
            "  mcp_* or allow_write_roots grant this project set is not in force either.",
            "  Fix the file; nothing here can tell an unparseable config from an absent one on your",
            "  behalf, which is exactly why it says so rather than carrying on quietly.",
            "")
    out(*config_paths_report())   # a TRACKED config handing every cloner a write root on ONE machine
    if (ro := ruled_out()):
        # The single most useful question at the start of a resumed investigation is "what has
        # already been ruled out?" — so it is answered before it is asked.
        out("", f"RULED OUT ({len(ro)}) — refuted claims. Don't re-walk these:")
        for rec in ro[:RULED_OUT_SHOWN]:
            out(f"  ✗ {rec.get('assert')}",
                "    killed by: " + (", ".join(_short(p) for p in (rec.get("evidence") or []))
                                     or "(no evidence recorded)"))
        if len(ro) > RULED_OUT_SHOWN:
            out(f"  … {len(ro) - RULED_OUT_SHOWN} older — grep '\"outcome\": \"refuted\"' "
                ".game_loop/log.jsonl")
    out(*denials_report(s))   # the referee firing, not the loop's own scoreboard
    out(*triggers_report())  # attached ≠ working: one that never fired looks just like one that does
    out(*publish_gap(s))     # marked ≠ released: the tag is local, the attachment is the outward half
    # AND A GUARD DISABLED BY THE STATE IT READS (#90) — the same equivalence one process boundary
    # out. Registered, running, returning the code that means allowed, for sixteen hours.
    out(*guards_report())
    out(*hook_integrity_report())  # the file that wires every gate is not itself guarded
    out(*wake_path_report(s))
    out(*authorizations_report(s))  # a consumable the human paid for — show the balance
    out(*working_tree_report())  # which tree is being edited vs which one this harness speaks for
    out(*waiting_report())       # what this run is blocked on — the first question a resume asks
    snap = load_limits()
    lim = limits_summary(snap) if snap else None
    if lim:
        over = binding_windows(snap, float(limits_cfg()["threshold_pct"]), time.time())
        out("limits: " + lim + ("  ⚠ HANDOFF DUE — the limitgate is closed" if over else ""))
    if (w := limits_inert_warning(snap)):   # says what is OFF, not merely that a file is missing
        out(w)
    if notify:
        _nsrc = notify.cfg_source() if hasattr(notify, "cfg_source") else None
        # WHICH file, not just "configured": a user-level config applies to every project on the
        # machine, so "where is this paging" must be answerable without guessing (#54).
        _nwhere = ""
        if _nsrc and os.path.dirname(_nsrc) != ROOT:
            _nwhere = f"  ← from {_nsrc} (user-level, shared by every project here)"
        out("notify: " + ("Slack configured — replies readable (bot token)" if notify.can_read_replies()
                          else "Slack configured — send-only (webhook)" if notify.configured()
                          else "not configured (.game_loop/notify.json or "
                               "~/.config/game_loop/notify.json; see bin/notify.py)") + _nwhere)
    if (w := hooks_live_warning()):
        out(w)
    out(*session_start_warning())
    out(*installed_confidence_report())
    # THE MACHINE-WIDE LAYER IS REPORTED FIRST, and separately from the local one, because it is the
    # layer a reader is least likely to remember. A local override is a fact about the checkout they
    # are already standing in; this one was written in a file no repo contains, possibly months ago,
    # and it reaches every project here. Silence about it is the divergence nobody can explain.
    if (_gk := config_global_keys()):
        out(f"config: {len(_gk)} key(s) set MACHINE-WIDE by {_tilde(CONFIG_GLOBAL_F)} — "
            + ", ".join(_gk),
            "  That file is under this layer, not in any repo, and applies to every project on this "
            "machine.",
            "  Both write rails refuse it (it is outside this repo — INV3), so nothing here can "
            "change it without a human.")
    if (_lk := config_local_keys()):
        out(f"config: {len(_lk)} key(s) overridden by .game_loop/config.local.json (gitignored) — "
            + ", ".join(_lk),
            "  Site wiring lives there so it never seeds into anyone else's install; a config you "
            "cannot see is a divergence nobody can explain.")
    if (w := legacy_mandate_warning()):
        out(w)
    try:
        if (w := update_notice()):   # courtesy line, never allowed to break status
            out(w)
    except Exception:  # noqa: BLE001
        pass
    assists = s.get("watchdog_rings_total", 0) + s.get("stop_gate_blocks_total", 0)
    if assists:
        out(f"🎮 GameLoop has kept the crawl going {assists} times "
            f"(watchdog {s.get('watchdog_rings_total', 0)} · gate {s.get('stop_gate_blocks_total', 0)})")
    flair_out(s)  # surface any milestone crossed since last check (e.g. uptime)


def cmd_note(s, a):
    # --recovery IS A NOTE THAT HAS TO REACH SOMEBODY WHO ALREADY FORGOT (#95). A plain note goes
    # to the log, where it is found by whoever goes looking. A recovery path has to arrive in a
    # session that has lost the context which would make it go looking — so it lives in state,
    # where the wake-up prompt can assemble it.
    if getattr(a, "woke", False):
        w = s.get("wake_landed") or {}
        s["wake_landed"] = {"at": now(), "count": int(w.get("count", 0)) + 1}
        save(s)
        logline({"kind": "wake_landed", "count": s["wake_landed"]["count"]})
        out("wake recorded as LANDED.",
            f"  {s['wake_landed']['at']} — {s['wake_landed']['count']} this session.",
            "  This is the only direction observable from in here: a wake that never arrived",
            "  cannot record its own absence.")
        return
    _rec = (getattr(a, "recovery", None) or "").strip()
    if _rec:
        s.setdefault("recovery", []).append({"text": _rec, "at": now()})
        save(s)
        logline({"kind": "recovery_path", "text": _rec})
        out("recovery path recorded — `game_loop doorbell` will carry it.",
            f"  {_rec}",
            f"  {len(s['recovery'])} recorded in this run.")
        return
    if not a.text:
        die("note needs --text, or --recovery for something a woken session must not re-derive.")
    logline({"kind": "note", "text": a.text})
    out("noted to log.jsonl.")


def recovery_paths(s):
    """The remedies THIS run learned, which is the only place they are true (#95)."""
    return [r for r in (s.get("recovery") or []) if (r or {}).get("text")]


def doorbell_lines(s, repo=""):
    """The wake-up prompt for THIS run, assembled from live state (#95, proposal 3).

    A consumer kept a long unattended run alive with an external cron and reported that the cron
    was NOT the part worth stealing: "a generic 'check your background tasks' ping is nearly
    worthless — the agent wakes, spends real tokens re-deriving where it was, and often re-runs
    completed steps. The doorbell has to carry THIS run's recovery paths."

    Which is why this is generated and not a file you fill in. The issue says it in its own words:
    the paths are per-run, "which is why they belong in the doorbell prompt and not in any static
    doc". A template shipped as prose would be the exact thing that report found insufficient.

    THREE OUTCOMES, because two of them are easy to dress up as the third:
      - no mandate bound        -> there is nothing to wake this run FOR, and saying so beats
                                   emitting a confident prompt with a hole where the goal goes
      - mandate, no paths       -> emitted, and told plainly it mostly buys re-orientation cost
      - mandate and paths       -> the thing the report says made every wake produce progress
    """
    m = s.get("mandate") or {}
    if not m.get("active"):
        return ["no mandate is bound here, so there is nothing to wake this run FOR.",
                "",
                "A doorbell exists to return a session to a goal it already had. With no goal",
                "recorded, the prompt would name nothing, and a woken agent would re-derive the",
                "run from scratch — which is the cost this command exists to avoid.",
                "",
                "    game_loop mandate --set \"<what done means>\" --wake-path \"<how a signal lands>\""]
    paths = recovery_paths(s)
    L = ["=== WAKE-UP PROMPT" + (f" — {repo}" if repo else "") + " ===",
         "",
         "You are resuming an unattended run. IF YOU ARE MID-TASK, DO NOTHING — finish what you",
         "were doing. This is a poll, not a signal: it fires on a timer whether or not anything",
         "has happened, so its arrival means nothing by itself.",
         "",
         "DONE MEANS:",
         "  " + (m.get("text") or "").strip(),
         "",
         "FIRST, record that you arrived:  game_loop note --woke",
         "Nothing else can. A wake that lands is observable from in here; one that was sent and",
         "never delivered is not, so an unrecorded arrival reads exactly like a dead wake path.",
         "",
         "WHERE YOU WERE: run `game_loop status` and read it before doing anything else. It",
         "carries the current note. Re-deriving what it already says is the waste this prompt",
         "is trying to prevent."]
    if paths:
        L += ["",
              "RECOVERY PATHS — learned in THIS run, and the reason this is worth more than a ping:"]
        L += ["  - " + p["text"].strip() for p in paths]
    L += ["", "=== end of prompt ==="]
    if not paths:
        L += ["",
              "⚠ NO RECOVERY PATHS ARE RECORDED, so the prompt above mostly buys re-orientation.",
              "  It will return a session to its goal and nothing else. The paths worth carrying",
              "  are the ones learned in the first hour and forgotten by the fourth: the known",
              "  flake and its remedy, which credential actually authenticates, the known-good",
              "  retry for the step that times out.",
              "",
              "    game_loop note --recovery \"<what you learned, and what to do about it>\"",
              "",
              "  Recorded per run, because a remedy that was true last week is a guess today."]
    if m.get("wake_path"):
        L += ["", f"delivered by (declared): {m['wake_path']}",
              "  DECLARED, never probed — nothing here has watched a wake land."]
    else:
        L += ["", "⚠ NOTHING RECORDS HOW THIS PROMPT REACHES THE SESSION.",
              "  A doorbell nobody rings is indistinguishable in here from one that never had to",
              "  ring. Say what delivers it:",
              "    game_loop mandate --wake-path \"<how a signal reaches this session>\""]
    return L


def hook_decision(rc, out):
    """What a hook actually SAID: (deny|allow|ask|silent|error, why) — #91.2.

    THERE ARE TWO PROTOCOLS AND THIS COST ME THE FIRST VERSION OF THIS VERB. A PreToolUse hook can
    refuse by exiting 2, or by printing a JSON decision and exiting 0. game_loop's own write guard
    uses the second — so a harness that asserted only the exit code read a working INV3 guard, mid
    refusal, as allowing everything. The tool built to stop a guard going quietly inert was about
    to certify one.

    `silent` is its own answer for the same reason. Exit 0 with nothing said is what a guard that
    ALLOWED looks like, and equally what a guard that is no longer running looks like, and folding
    the second into the first is the whole of #90.
    """
    if rc == 2:
        return "deny", "exit 2 — the exit-code protocol"
    # SCANNED AS JSON, NOT AS LINES. This read `out.splitlines()` and required the object to sit on
    # ONE line — so a hook that pretty-prints its decision, which is ordinary, came back `silent`.
    # Silent is treated as an allow. That is the SAME defect this function was written to fix, one
    # level down: the first cut read only exit codes and called a JSON deny an allow; the second
    # read only single-line JSON and called a pretty-printed deny an allow. Found by feeding this
    # function an indented payload rather than by reading it.
    #
    # raw_decode from each `{` handles all three shapes at once — one line, indented, or embedded
    # in a hook's other chatter — and never needs the object to be the whole of the output.
    _scan = json.JSONDecoder()
    _text = out or ""
    for _i, _ch in enumerate(_text):
        if _ch != "{":
            continue
        try:
            d, _ = _scan.raw_decode(_text, _i)
        except ValueError:
            continue
        if not isinstance(d, dict):
            continue
        hso = d.get("hookSpecificOutput")
        hso = hso if isinstance(hso, dict) else d
        dec = str(hso.get("permissionDecision") or "").lower()
        if dec in ("deny", "allow", "ask"):
            return dec, f"permissionDecision {dec!r} in its JSON output"
    # IT SAID SOMETHING AND THIS COULD NOT READ IT, which is not the same as saying nothing. A hook
    # whose decision came back truncated or malformed has JUDGED; only the reading failed. Folding
    # that into `silent` would treat a broken guard as an allowing one — the same substitution this
    # function exists to refuse, arriving by a third road.
    if "permissionDecision" in (out or ""):
        return "unreadable", ("it printed a permissionDecision this could not parse — that is a "
                              "guard whose verdict was lost, never a guard that allowed")
    if rc != 0:
        return "error", (f"exit {rc}, and it named no decision — a hook that failed rather than one "
                         "that judged")
    return "silent", ("exit 0 and said nothing — which is what an ALLOW looks like, and equally "
                      "what a guard that is no longer running looks like")


GUARDTEST_EXPECTS = ("deny", "allow", "ask")


def guardtest_bad_expects(cases):
    """Cases whose `expect` is not one this understands: [(name, value)] — #91.2.

    A MISSPELT EXPECTATION IS A DEFECT IN THE FIXTURE, and without this it is reported as a defect
    in the GUARD. Both spellings were measured against this repo's own write guard, which was
    behaving correctly throughout:

      "expect": "denied"  -> no case counted as a deny, so the run was refused with "the cases only
                             go one way … add the case that must NOT fire" — the right verdict for
                             the wrong reason, sending you to write a case you already had.
      "expect": "alow"    -> worse: the directions check passed, the case could never match, and the
                             report said the guard failed.

    Two different repairs behind one observable, which is the substitution this whole verb exists to
    refuse. So the set is CLOSED and a stranger is named.
    """
    bad = []
    for i, c in enumerate(cases):
        if "expect" not in c:
            continue                       # an expect_exit case is a different contract, not a gap
        v = str(c.get("expect") or "").lower()
        if v not in GUARDTEST_EXPECTS:
            bad.append((c.get("name") or f"case {i + 1}", c.get("expect")))
    return bad


def guardtest_directions(cases):
    """Do these cases exercise BOTH directions? (ok, why) — #91.2.

    A guard suite whose every case expects a BLOCK is passed by a script that blocks everything,
    and one whose every case expects an ALLOW is passed by a script that does nothing at all. The
    second is #90 exactly: a guard that silently stopped firing, with its own tests still green.

    So this is the denominator check the mutation sweep and the theme scan both carry, applied to a
    consumer's fixture: a run over cases that all point one way proves the script can reach that
    answer, never that it CHOOSES it.
    """
    def _denies(c):
        if "expect" in c:
            return str(c["expect"]).lower() == "deny"
        return int(c.get("expect_exit", 0)) != 0

    blocks = [c for c in cases if _denies(c)]
    allows = [c for c in cases if not _denies(c)]
    if blocks and allows:
        return True, f"{len(blocks)} blocking case(s), {len(allows)} allowing"
    if not blocks:
        return False, ("no case here expects a DENY — a script that does nothing at all passes "
                       "this file, which is the exact failure #90 was: a guard that had silently "
                       "stopped firing, with its own tests still green")
    return False, ("every case here expects a DENY — a script that blocks everything "
                   "passes this file, so it establishes the guard CAN refuse, never that it picks "
                   "its moment")


def run_guard_case(script, case, cwd, timeout=30):
    """Feed one recorded payload to a hook script. (outcome, detail, decision).

    Claude Code hands a hook its payload as JSON on STDIN, so that is what this does. "could not
    run" is its own outcome and never collapses into "did not fire": a script that is missing, not
    executable, or times out has told you nothing, and reporting that as an ALLOW is how a harness
    certifies a guard that never executed.
    """
    body = json.dumps(case.get("payload") or {})
    try:
        r = subprocess.run([script], input=body, capture_output=True, text=True,
                           cwd=cwd, timeout=timeout)
    except subprocess.TimeoutExpired:
        return "could-not-run", f"timed out after {timeout}s — nothing was established", None
    except OSError as exc:
        return "could-not-run", (f"could not execute it: {exc}. A hook script must be executable "
                                 "and carry a shebang; this is not a verdict about the guard"), None
    out_all = (r.stdout or "") + (r.stderr or "")
    dec, why = hook_decision(r.returncode, out_all)
    want_out = case.get("expect_output")
    # An explicit exit-code expectation is still honoured for guards that only speak that protocol.
    if "expect_exit" in case and "expect" not in case:
        want = int(case["expect_exit"])
        if r.returncode != want:
            return "mismatch", f"expected exit {want}, got {r.returncode} ({why})", dec
    else:
        want = str(case.get("expect", "allow")).lower()
        # SILENCE SATISFIES `allow`, BECAUSE MOST GUARDS ALLOW BY SAYING NOTHING and pricing that
        # out would make the verb unusable. It is never hidden, though: the detail names which of
        # the two it was, and the summary counts the silent ones — the both-directions rule above
        # is what actually stops a do-nothing script passing, since it must produce a real DENY.
        if not (dec == want or (want == "allow" and dec == "silent")):
            return "mismatch", f"expected {want}, got {dec} — {why}", dec
    if want_out and want_out not in out_all:
        return "mismatch", (f"the decision was right, but the output never said {want_out!r} — a "
                            "guard that refuses for the wrong reason sends you somewhere else"), dec
    return "match", why + (f", and said {want_out!r}" if want_out else ""), dec


def cmd_guardtest(s, a):
    """Run a consumer's OWN hook script against recorded payloads (#91.2).

    test/run.py proves game_loop's guarantees; a consumer's triggers and hook scripts had nothing.
    The filer wrote 340 lines of these locally "after watching a guard fire on the case it was
    built for and then discovering it had gone inert for a different input".

    FIXTURE-DRIVEN ON PURPOSE, so no consumer's logic lands in this repo: the cases are theirs, in
    their file, and this supplies only the running and the verdict.
    """
    if not a.fixture:
        die("guardtest needs --fixture <path> — a JSON file naming the script and its cases:\n\n"
            '  {"script": ".game_loop/triggers.d/mine.sh",\n'
            '   "cases": [\n'
            '     {"name": "blocks a write outside the repo", "expect_exit": 2,\n'
            '      "payload": {"tool_name": "Write", "tool_input": {"file_path": "/etc/x"}}},\n'
            '     {"name": "allows one inside it", "expect_exit": 0,\n'
            '      "payload": {"tool_name": "Write", "tool_input": {"file_path": "README.md"}}}\n'
            "   ]}\n\n"
            "The payload is handed to the script on STDIN as JSON, which is how Claude Code hands a\n"
            "hook its own.")
    fx = os.path.realpath(os.path.expanduser(a.fixture))
    try:
        with open(fx) as f:
            spec = json.load(f)
    except OSError as exc:
        die(f"--fixture is not readable: {exc}")
    except ValueError as exc:
        die(f"--fixture is not valid JSON: {exc}")
    # THE SHAPE, BEFORE ANYTHING READS A KEY OFF IT. A fixture that parsed as valid JSON but is a
    # list — or a string, or a number — reached `spec.get("cases")` and died with an AttributeError
    # traceback at exit 1. A genuine refusal here exits 3 (#91 part 3), so a user's malformed
    # fixture was arriving as a CRASH: indistinguishable from a bug in this tool, and invisible to
    # anything reading the exit code, which is the contract that issue established.
    if not isinstance(spec, dict):
        die(f"--fixture must be a JSON OBJECT, not {type(spec).__name__}.\n\n  {fx}\n\n"
            "The shape is {\"script\": \"..\", \"cases\": [ .. ]}. A bare list is the common near-miss:\n"
            "the cases go UNDER a \"cases\" key, because the object also carries the script.")
    if not isinstance(spec.get("cases", []), list):
        die(f"--fixture's \"cases\" must be a LIST, not "
            f"{type(spec.get('cases')).__name__}.\n\n  {fx}")
    _nd = [i for i, c in enumerate(spec.get("cases") or []) if not isinstance(c, dict)]
    if _nd:
        die("every case must be a JSON object; these are not: "
            + ", ".join(f"#{i + 1}" for i in _nd) + f"\n\n  {fx}\n\n"
            "Each one needs at least a payload and an expectation.")
    script = a.script or spec.get("script")
    if not script:
        die("no script to run — give --script <path>, or a \"script\" key in the fixture.")
    script = os.path.realpath(os.path.expanduser(
        script if os.path.isabs(script) else os.path.join(REPO_ROOT, script)))
    cases = spec.get("cases") or []
    if not cases:
        die(f"the fixture declares NO cases, so this run would check nothing and exit 0 — which is\n"
            f"byte-identical to a guard suite that ran and passed.\n\n  {fx}")
    _bad_exp = guardtest_bad_expects(cases)
    if _bad_exp:
        die("REFUSED — a case expects something this does not understand.\n\n  " + fx + "\n"
            + "".join(f"    {n}: {v!r}\n" for n, v in _bad_exp)
            + "\n  known: " + ", ".join(GUARDTEST_EXPECTS)
            + " (or expect_exit for a guard that only speaks exit codes)\n\n"
            "A misspelt expectation can never match, and without this it is reported as a FAILING "
            "GUARD — measured against this project's own write guard while it was refusing "
            "correctly. 'Your fixture is wrong' and 'your guard is wrong' take opposite repairs.")
    ok_dirs, why_dirs = guardtest_directions(cases)
    if not ok_dirs:
        die(f"REFUSED — the cases only go one way.\n\n  {fx}\n  {why_dirs}\n\n"
            "Both directions are the price of admission here, the same way `instrument` wants a "
            "null control beside its positive one. Add the case that must NOT fire.")
    if not os.path.exists(script):
        die(f"the script does not exist: {script}\n"
            "That is not a failing guard — it is a fixture pointing somewhere else.")
    rows, bad, unknown, silent = [], [], [], []
    for i, c in enumerate(cases):
        name = c.get("name") or f"case {i + 1}"
        outcome, detail, dec = run_guard_case(script, c, REPO_ROOT, int(a.timeout or 30))
        rows.append((outcome, name, detail))
        if dec == "silent":
            silent.append(name)
        if outcome == "mismatch":
            bad.append(name)
        elif outcome == "could-not-run":
            unknown.append(name)
    glyph = {"match": "✓", "mismatch": "✗", "could-not-run": "?"}
    lines = [f"guardtest — {os.path.basename(script)}  ({why_dirs})", ""]
    lines += [f"  {glyph[o]} {n}\n      {d}" for o, n, d in rows]
    logline({"kind": "guardtest", "script": script, "fixture": fx, "cases": len(cases),
             "mismatch": len(bad), "could_not_run": len(unknown)})
    if unknown:
        lines += ["", f"COULD NOT RUN {len(unknown)} case(s). That is not a passing guard and not a "
                      "failing one —", "nothing was established for them, and a harness that "
                      "counted them as ALLOW would", "certify a guard that never executed."]
    if bad or unknown:
        out(*lines)
        die(f"guardtest: {len(bad)} mismatch(es), {len(unknown)} that could not run.", code=REFUSED_EXIT)
    if silent:
        lines += ["", f"  {len(silent)} of these ALLOWED BY SAYING NOTHING, which is also what a "
                      "guard that has", "  stopped running says. The deny case above is what "
                      "distinguishes them here."]
    lines += ["", "WHAT THIS DOES NOT SAY: that the guard is correct, or that it fires on the case "
                  "you have", "not thought of yet. It says these recorded payloads still produce "
                  "these decisions."]
    out(*lines)


def cmd_doorbell(s, a):
    out(*doorbell_lines(s, os.path.basename(REPO_ROOT)))


HARDEN_LADDER = [
    "1 IMPOSSIBLE — change the code/design so the mistake CANNOT be made (the rule stops existing)",
    "2 LOUD       — assert/guard AT the point of misuse (fails in 1s, not 3h later, with the reason)",
    "3 CHECKED    — a build/CI/test check that fails on regression",
    "4 AUTOMATED  — the tool just does it (no step left to remember)",
    "5 VISIBLE    — the harness REPORTS the fact, so it's read, never guessed",
    "6 (doc/memo) — LAST resort only; you must say why 1-5 genuinely don't apply",
]


def cmd_harden(s, a):
    """Record a learning converted into an artifact the harness enforces.

    Same keystone as `claim --read`: the ungameable part is naming a REAL file. Prose is a promise to
    remember, and long sessions + compaction break promises. Docs are the INDEX; the artifact is the
    ENFORCEMENT.
    """
    if not a.learning or not a.artifact or not a.mechanism:
        die("harden needs --learning, --artifact <path[,path]>, and --mechanism.\n"
            "A learning you only WRITE DOWN is a promise to remember — sessions break it.\n"
            "Encode it; take the highest rung that applies:\n  " + "\n  ".join(HARDEN_LADDER))
    paths = [p.strip() for p in a.artifact.split(",") if p.strip()]
    resolved = {p: resolve_read(p) for p in paths}
    bad = [p for p, r in resolved.items() if r is None]
    if bad:
        die("these --artifact paths aren't real files: " + ", ".join(bad) + "\n"
            "Hardening means the artifact EXISTS (code / assert / check / tool), not a plan to write "
            "one. Write it first, then record it here.")
    general = (getattr(a, "general", None) or "").strip()
    s["retro_owes_harden"] = None          # CONSUME: the retro's obligation is paid by the act
    logline({"kind": "harden", "learning": a.learning, "artifact": list(resolved.values()),
             "mechanism": a.mechanism, "rung": a.rung, "general": general or None})
    s["hardened_count"] = s.get("hardened_count", 0) + 1
    s["work_since_stepback"] = s.get("work_since_stepback", 0) + 1
    save(s)
    out("✓ HARDENED — learning → artifact.",
        f"  learning : {a.learning}",
        f"  artifact : {', '.join(paths)}",
        f"  mechanism: {a.mechanism}",
        f"  rung     : {a.rung or '(unspecified — which ladder rung?)'}",
        f"→ enforced by the harness now, not by memory. (hardened so far: {s['hardened_count']})",
        # WHAT THIS VERB CHECKED IS THAT THE PATH EXISTS (INV6). It cannot read the artifact and
        # decide whether that file would CATCH the class the learning names — "this contains a check
        # for this" is not decidable from a path. So the strongest sentence in this output was the
        # one thing not verified, and the limit was stated only in the REFUSAL text, which nobody
        # reads on the success path.
        #
        # Same shape as a mutant check that passes on "anchor found AND bytes changed": the verb
        # confirmed the edit LANDED and reported that it MEANS something. Changed is a weaker
        # property than still means something.
        "  NOT CHECKED: that the artifact ENFORCES this. The path exists and the record is written;",
        "  whether that file would CATCH the thing is your claim, in --mechanism, and nothing here",
        "  can read it. A hardening whose artifact never fires is a learning with a receipt.")
    if general:
        out(f"  general  : {general}")
    elif triggers_for("harden"):
        # Only nag where somebody has actually attached a sharing step. GENERALISING is a separate
        # act of thought from hardening, and the transferable form is rarely the incident: "our tap
        # never wrote limits.json" helps nobody, while "a check whose PASS is silence cannot tell
        # satisfied from never-ran" is the part that travels. Never blocks — an unshared learning is
        # still hardened, and refusing the record to extract a sentence would be the tail wagging.
        out("  ⚠ no --general: this project has a harden trigger attached, and it has nothing to",
            "    share. The incident form rarely transfers — say the version another agent could use",
            "    without knowing anything about this codebase.")
    if (n := retro_nudge(s)):
        out("", n)
    out(*fire_triggers(s, "harden", {
        "event": "harden", "learning": a.learning, "general": general or None,
        "artifact": list(resolved.values()), "mechanism": a.mechanism, "rung": a.rung,
        "project": config().get("project_name"), "session": SESSION}))
    flair_out(s, "harden")


def retro_outcome():
    """What CAME of the last retro, counted from the shared log rather than remembered.

    A retro that produces nothing is indistinguishable, afterwards, from one that never happened —
    both leave a session where no learning got encoded. The act was never the point; the encoding
    is. So each retro opens by reporting the previous one's yield, and an empty yield is stated
    rather than passed over. Read from the log because it is the record neither optimism nor
    compaction can edit.
    """
    # PER LINE, NOT PER FILE. This was a list comprehension inside `except (OSError, ValueError)`,
    # so ONE malformed line failed the whole thing and returned [] — the retro then reported that
    # nothing had been encoded. In the function whose docstring says an empty yield must be STATED
    # rather than passed over, and which exists precisely because "produced nothing" and "never
    # happened" look the same afterwards. It could not tell either of those from "could not read
    # the log".
    #
    # A half-written last line is the ORDINARY state of an append-only file, and three programs
    # append to this one. Every other reader here already skips the bad line and keeps the rest;
    # this one discarded the record. Now it skips too, and SAYS how many it skipped, because a
    # yield counted over a log with holes in it is not the same number.
    recs, skipped = [], 0
    try:
        with open(LOG_F) as f:
            for _l in f:
                if not _l.strip():
                    continue
                try:
                    recs.append(json.loads(_l))
                except ValueError:
                    skipped += 1
    except OSError:
        return []
    last = max((i for i, r in enumerate(recs) if r.get("kind") == "stepback"), default=None)
    # NO PRIOR RETRO IS NOT NO PRIOR WORK. This returned "this is the first" and counted nothing, so
    # everything encoded before a tree's FIRST retro fell into a window no retro ever read — real
    # hardens, invisible, with the counter reading zero. Found by probing a consumer's report whose
    # stated mechanism did NOT reproduce: their symptom was real and their cause was not this, and
    # the probe written to check them surfaced this instead. The first chapter is the whole log.
    if last is None:
        after = recs
        when = "the beginning of this tree's record — no previous retro"
    else:
        after = recs[last + 1:]
    counts = collections.Counter(r.get("kind") for r in after)
    if last is not None:
        when = recs[last].get("t") or "?"
    hardened = counts.get("harden", 0)
    lines = [f"  since {when}: {hardened} hardened · "
             f"{counts.get('claim', 0)} claims · {counts.get('fix_proof', 0)} fix proofs · "
             f"{counts.get('trigger', 0)} triggers fired"]
    if not hardened:
        lines.append("  ⚠ NOTHING WAS HARDENED since the last retro. Either the chapter genuinely "
                     "taught nothing, or the")
        lines.append("    last retro ended at the writing-it-down step. Only one of those is worth "
                     "repeating.")
    if skipped:
        lines.append(f"  ⚠ {skipped} log line(s) would not parse and were SKIPPED — these counts "
                     "are over a record with holes")
        lines.append("    in it, so a low yield here may be the log rather than the chapter.")
    return lines


def cmd_stepback(s, a):
    if getattr(a, "nothing_to_harden", False):
        if not a.reason:
            die("--nothing-to-harden needs --reason: an empty retro is a DECISION, and a decision "
                "with no reason is indistinguishable from the silence this gate exists to stop.")
        s["retro_owes_harden"] = None
        save(s)
        logline({"kind": "retro_no_harden", "reason": a.reason})
        out("✓ RECORDED — this retro encoded nothing, and why.",
            f"  {a.reason}",
            "→ turn-end is open. It is in the log, so an empty chapter reads as a call somebody",
            "  made rather than a retro that quietly produced nothing.")
        return
    # READING IS NOT RETROSPECTING (#112). Everything below this point is longer than one screen,
    # and the only way to read it was to RUN it -- which logged a stepback, zeroed the counters and
    # armed a fresh `retro_owes_harden`. So paging through the output with head/sed/tail opened a new
    # retro per page and silently discarded the harden that had already paid for the last one: the
    # message then said "NOTHING WAS HARDENED since the last retro", which reads as "you did not do
    # the work" when the truth is "your receipt was thrown away by the act of reading this".
    #
    # Measured here: a harden at 18:34:48, a stepback at 18:34:57, and the next run reporting
    # 0 hardened since 18:34:57 -- the boundary being the very refusal that asked for the harden.
    # A diagnostic must not change what it diagnoses, so --show is the read and the bare verb is the
    # act. Triggers do not fire either: they deliver other agents' learnings and mark them consumed,
    # which is a side effect a reader has not asked for.
    _show = getattr(a, "show", False)
    if not a.notes and not _show:
        die("stepback needs --notes — a REAL retro: what WORKED (repeat it)? where did I DEVIATE? "
            "did I assert before reading? AND which recurring learning gets ENCODED (harden), not "
            "written down?")
    # Others' learnings arrive BEFORE the reflection, not after it — arriving afterwards would make
    # them a reading exercise rather than an input to the thinking they are supposed to inform.
    incoming = [] if _show else fire_triggers(s, "stepback", {
        "event": "stepback", "notes": a.notes, "project": config().get("project_name"),
        "session": SESSION, "trans_since": s.get("trans_since_stepback", 0),
        "work_since": s.get("work_since_stepback", 0)})
    prior = retro_outcome()          # BEFORE the new line lands, or it finds itself and reports zero
    if not _show:
        logline({"kind": "stepback", "notes": a.notes})
        s["trans_since_stepback"] = 0
        s["work_since_stepback"] = 0
    # THE RETRO NOW OWES ITS OWN ENCODING. Everything printed below is an instruction, and a
    # consumer ran this verb, produced a full reflection and hardened nothing — the failure this
    # verb exists to prevent, committed by the verb that teaches it. The Stop gate holds turn-end
    # until a harden lands or the agent declines on the record.
    if not _show:
        s["retro_owes_harden"] = now()
        save(s)
    if incoming:
        out(*incoming)
    # THE RETRO IS WHERE THIS BELONGS (#78). It already counts hardens since the last one, and it is
    # the moment an agent is looking BACK at a chapter's learnings — which is exactly when "whose
    # defect was that?" is answerable and cheap. Asked at any other moment it is an interruption.
    if (_up := upstream_review_nudge(s)):
        out("", _up, "")
    if _show:
        out("=== A READ, NOT A RETRO — nothing was recorded ===",
            "  No stepback line was logged, the counters still stand, and no harden is owed for",
            "  reading this. Run the verb WITHOUT --show, with --notes, when the retro is real.", "")
    out("=== WHAT THE LAST RETRO YIELDED ===", *prior, "")
    out("=== STEP-BACK — invariants re-injected ===")
    try:
        with open(INV_F) as f:
            out(f.read().strip())
    except OSError:
        out(inv_oneline())
    out("",
        "RETRO — ENCODE, DON'T REMEMBER. For EACH learning this chapter, ask the only question that",
        "matters: **how does the HARNESS enforce this now?** A learning that lives in prose (a note,",
        "INVARIANTS.md, CLAUDE.md, memory) is a promise to remember — and long sessions + compaction",
        "break promises. Climb to the highest rung that applies:",
        *["  " + r for r in HARDEN_LADDER],
        "Then record each with a REAL artifact path (the ungameable bit, same as `claim --read`):",
        '  game_loop harden --learning ".." --artifact <real path> --mechanism ".." --rung <1..6>',
        "Rung 6 (doc/memory) is the LAST resort — if you pick it, say why 1-5 don't apply.",
        "",
        "THIS TURN CANNOT END UNTIL ONE OF THOSE LANDS. Not a nag — the gate holds, because every",
        "line above is an instruction and instructions are what this project refuses to enforce with.",
        "If the chapter genuinely taught nothing, say so and it is a decision on the record:",
        '  game_loop stepback --nothing-to-harden --reason "<why there is nothing to encode>"')


def retro_debt_open(s):
    """Does this session owe a harden for a retro it already ran? (the obligation, not a judgement)

    Satisfied by a harden logged AFTER the stepback — read from the log rather than a flag the
    verb sets, so it cannot be cleared by anything except the act itself.
    """
    owed = s.get("retro_owes_harden")
    if not owed:
        return None
    try:
        with open(LOG_F) as f:
            for ln in f:
                if '"harden"' not in ln:
                    continue
                try:
                    r = json.loads(ln)
                except ValueError:
                    continue
                if r.get("kind") == "harden" and str(r.get("t") or "") > str(owed):
                    return None                     # encoded: the debt is paid
    except OSError:
        return None                                 # cannot read the log: never invent a debt
    return owed


# ── prose arrives unmangled, or it does not arrive (#58) ─────────────────────────────────────────
#
# A quoted shell argument is CODE to the shell before it is text to this tool. Backticks run as
# command substitution, $NAME expands to nothing, a lone quote truncates. The shell substitutes and
# hands over the result, so by the time argparse sees the value THE EVIDENCE IS GONE: a sentence
# with three words removed is just a shorter sentence, and no inspection here can tell it from one
# somebody wrote that way. This is not fixable by detection; the unsafe path has to be bounded.
#
# Observed three times in one session, by the agent that owns this file: a public comment on #55
# lost three terms; a `harden --general` lost a command name and was BROADCAST to five other agents
# with a hole in it; a generated patch had its escapes consumed one layer early. After the first I
# hardened "route prose through a file" as a thing to remember -- rung 6 -- and it failed twice more
# while I was writing about checks that cannot report their own failure.
# ENUMERATED, AND THEREFORE ALREADY ONCE INCOMPLETE. The first version of this list missed
# `mandate --set` — the single most load-bearing sentence in the tool, the one the whole autonomy
# loop is driven by — along with the arm's question and prediction and every descriptive field of
# the evidence family. I found it by trying to rewrite my own mandate through a file and being told
# the option did not exist. That is the same failure #57 removed from mcp_standing_writes, committed
# here in the fix for it: a hand-kept list of names is complete on the day it is written.
#
# THE ENTRY TEST, restated after #97 found the old one defended by a false reason. It used to read
# "does the field hold a sentence somebody composed", excluding paths, names, enums, numbers and
# refs because "they cannot carry a backtick that means anything". True of those five. NOT true of
# `mutate --with`, which was excluded on that reasoning and holds a code fragment where a backtick
# is live — and whose mangled value becomes a ✓ PROVED verdict rather than an odd-looking sentence.
#
# The question that actually sorts these is: IF THIS VALUE WERE MANGLED, HOW WOULD ANYBODY FIND OUT?
#
#   --read <path>   does not resolve -> already REFUSED by the existence check. Loud, and by a
#                   check that exists for another reason. Nothing owed here.
#   --replace       stops appearing exactly once in the file -> already refused. Loud.
#   --assert <prose>  recorded wrong; a reader may notice an odd sentence, or may not. Quiet.
#   --with <code>   inserted verbatim; if it still compiles and still reddens, the tool reports
#                   PROVED. Quiet AND it becomes evidence. The worst of the three.
#
# So membership is not "is this a sentence" but "is this field's mangling already caught somewhere
# else". A field whose corruption fails loud owes nothing; a field whose corruption fails quiet
# needs the file path, which is the only route a shell never touches.
#
# WHAT THE BOUND CANNOT DO, since it is the obvious next thought: refuse a value CONTAINING a
# backtick. Measured — the shell rewrites `..` and $(..) before argparse is reached, so a mangled
# value arrives with no metacharacter in it and an intact single-quoted one arrives with one. The
# check would fire exactly when nothing went wrong and stay silent exactly when it did.
PROSE_OPTS = ("--assert", "--learning", "--mechanism", "--general", "--reason", "--fact",
              "--notes", "--text", "--because", "--confidence", "--promises", "--doing",
              # the autonomy loop's own prose, and the most expensive to corrupt
              "--set", "--question", "--predict", "--next",
              # the evidence family's descriptive halves — what a thing MEANS, not where it lives
              "--known-state", "--measures", "--connects", "--recheck",
              # a recovery path is read by a session that has ALREADY lost the context to spot a
              # corrupted one, and it is the field most likely to carry a backtick: half of them
              # name the command to re-run.
              "--recovery",
              # `contribute --note`. Its help says "one line of judgement" and its real content ran
              # 855 and 1152 chars across four ledger entries — the gate it serves asks which of N
              # hardened learnings name a tool's behaviour, and an honest answer enumerates. So the
              # one prose field carrying 2-3x the bound was the one field with no file variant, and
              # it was reached by `--note "$(cat ..)"`: command substitution straight into an
              # argument, which is the exact shape this list exists to remove.
              # a pin's expectation and its restore command: a command carrying $ or a backtick is
              # precisely what a shell rewrites on the way past
              "--expect", "--restore", "--note",
              # #97, and they are here for the FILE TWIN rather than for the bound. A mutation
              # fragment is short, so 400 chars never fires on it — but a shell rewrites `..` and
              # $(..) before argparse sees anything, and the applied text is what a ✓ PROVED
              # verdict then attests to. The file path is the only route that no shell touches.
              "--replace", "--with",
              # and the fault spliced beside them, for the same reason: it is inserted into source
              # verbatim, and a shell that ate its quoting produces a probe that fails without the
              # marker — which reads as "something else broke it", the one outcome that looks like
              # an honest unknown rather than a mangled input.
              "--fault")

# MEASURED, not chosen for roundness. Over the 130 prose values in this repo's log: p50 157, p75
# 285, p95 632, max 1011. Both corrupted values were over 700. 400 sits above the p95 of every field
# that is naturally a one-liner (assert 203, mechanism 359, reason 95, fact 59, text 258) and bites
# only the fields that are long-form by nature -- learning (p50 352) , general (min 319), notes
# (max 1011) -- which are exactly the ones that carry code, newlines and quoting.
#
# WHAT THIS DOES NOT FIX, since a bound is not a barrier: a SHORT value with a backtick in it is
# still mangled and still accepted. The bound cuts exposure where the damage is largest and the
# record is permanent; it does not remove the class. Nor does it reach `gh`, `git` or any other CLI
# in the loop, which have the identical exposure and their own -F / --body-file answers.
PROSE_MAX = 400

# argparse cannot store `assert` or `with` under their own names, so these two carry a trailing
# underscore. Kept as a map rather than a chain of conditionals because the failure mode is silent:
# resolve_prose skips any option whose dest it cannot find, so a missing entry here means the
# --<opt>-file twin is created, accepted on the command line, and then quietly does nothing.
_PROSE_DEST = {"--assert": "assert_", "--with": "with_"}


def add_prose_file_options(sub):
    """Give every prose option a `--<name>-file` sibling, on whatever verb happens to take it.

    Done by walking the parsers rather than by listing pairs, so a verb that later reuses --notes
    gets the safe path without anyone remembering to add it -- the failure being fixed here is
    precisely a rule that depended on remembering.
    """
    for parser in sub.choices.values():
        for act in list(parser._actions):  # noqa: SLF001 — one file, one process, stable since 3.2
            for opt in act.option_strings:
                if opt in PROSE_OPTS:
                    parser.add_argument(opt + "-file", dest=act.dest + "_file", metavar="PATH",
                                        help=f"read {opt}'s text from PATH instead — no shell "
                                             "touches it, and prose over "
                                             f"{PROSE_MAX} chars must come this way")


def resolve_prose(p, a):
    """Fill each prose option from its file, and refuse an inline value past the measured bound."""
    for opt in PROSE_OPTS:
        # Two options are named after Python keywords and carry a trailing-underscore dest. The
        # inline conditional held one of them; the second was added later and would have been
        # skipped silently by the hasattr guard below — resolve_prose looking for `with` while
        # argparse stored `with_`, so --with-file would have been accepted and then ignored.
        dest = _PROSE_DEST.get(opt) or opt[2:].replace("-", "_")
        if not hasattr(a, dest):
            continue
        path, inline = getattr(a, dest + "_file", None), getattr(a, dest)
        if path and inline:
            p.error(f"{opt} and {opt}-file are both set — pick one. Two sources for one value is "
                    "the shape where nobody can say afterwards which one was recorded.")
        if path:
            try:
                with open(path) as f:
                    setattr(a, dest, f.read().strip())
            except OSError as e:
                p.error(f"{opt}-file: cannot read {path} ({e.strerror}). Refusing rather than "
                        "recording an empty field, which would read as 'they left it blank'.")
            continue
        if isinstance(inline, str) and len(inline) > PROSE_MAX:
            p.error(
                f"{opt} is {len(inline)} chars; over {PROSE_MAX} it must come from a file:\n"
                f"    {opt}-file <path>\n\n"
                "NOT a style rule. A quoted shell argument is code to the shell first: backticks\n"
                "run, $NAME expands to nothing, a lone quote truncates. The shell hands over the\n"
                "result and this tool cannot tell a mangled sentence from a short one, so the\n"
                "corruption lands in a permanent record silently. Measured on this repo's own log,\n"
                f"{PROSE_MAX} is above the p95 of every field that is naturally a one-liner. Both\n"
                "values corrupted here were over 700.\n\n"
                "A SHORT value with a backtick in it is still mangled and still accepted — this\n"
                "bounds the exposure, it does not remove it.")


def main():
    p = argparse.ArgumentParser(prog="game_loop")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("status")

    cl = sub.add_parser("claim")  # THE gate: assert external reality only with sourced evidence
    cl.add_argument("--assert", dest="assert_", help="what you're about to tell the human")
    cl.add_argument("--read", help="real path[,path] to the source that backs it")
    cl.add_argument("--confidence", help="optional: what would change your mind?")
    cl.add_argument("--outcome", help="how it landed: resolved (default) · refuted · inconclusive")
    cl.add_argument("--evidence", help="real path[,path] that DISPROVED it — required for refuted")
    cl.add_argument("--effector", help="a verb this finding depends on having ACTED; refused unless "
                                       "`effector --prove`d in this session")
    cl.add_argument("--scope", help="the CATEGORY an \"only X\" / \"X is restricted\" claim is about")
    cl.add_argument("--probe", action="append",
                    help="a member you probed — a --scope claim needs TWO, on DIFFERENT members")
    cl.add_argument("--metric", help="admitted instrument whose READING backs it (not a document)")
    cl.add_argument("--recheck", help="for a metric that MOVED: what a user would notice now")
    cl.add_argument("--aggregate", help="this effect was DERIVED by collapsing events: sum · mean · "
                                        "pct — needs the reading's per-event --events")
    cl.add_argument("--exclude", metavar="EVENT#",
                    help="drop the dominating event the refusal NAMED from the total (needs --because)")
    cl.add_argument("--because", help="for --exclude: WHY that event does not belong — recorded, so "
                                      "the artifact is not rediscovered")

    n = sub.add_parser("note")
    n.add_argument("--text")
    n.add_argument("--recovery", help="a remedy this run learned that a woken session must not "
                                      "have to re-derive; carried by `doorbell`")
    n.add_argument("--woke", action="store_true",
                   help="record that an external wake LANDED — the half of a wake path that can be "
                        "observed from inside the run")

    sub.add_parser("doorbell", help="print the wake-up prompt for THIS run, filled from live state")

    gt = sub.add_parser("guardtest", help="run a consumer's own hook script against recorded "
                                          "payloads and assert the exits")
    gt.add_argument("--fixture", help="JSON file: the script, and the cases with their payloads")
    gt.add_argument("--script", help="the hook script to run (overrides the fixture's own key)")
    gt.add_argument("--timeout", type=int, help="seconds per case (default 30)")

    hd = sub.add_parser("harden")
    mu = sub.add_parser("mutate")   # a revert-proof the TOOL performs, not one you report (#71)
    mu.add_argument("--prove", help="what this test is claimed to pin")
    mu.add_argument("--test", help="the test command; must be GREEN before, RED after")
    mu.add_argument("--file", help="the production file to break")
    mu.add_argument("--fault", help="text that ABORTS at the anchor, containing {marker} — the "
                                    "per-stack half of the liveness probe, which is built in for "
                                    "Python and needs this everywhere else")
    mu.add_argument("--replace", help="text to replace — must appear exactly once")
    mu.add_argument("--with", dest="with_", help="what to replace it with")
    mu.add_argument("--timeout", help="seconds per test run (default 900)")
    hd.add_argument("--learning", help="the one-line rule you'd otherwise have to REMEMBER")
    hd.add_argument("--artifact", help="real path[,path] to the code/assert/check/tool that enforces it")
    hd.add_argument("--mechanism", help="how it now fails loudly / becomes impossible")
    hd.add_argument("--rung", help="ladder rung 1..6 (1 IMPOSSIBLE .. 6 doc-last-resort)")
    hd.add_argument("--general", help="the TRANSFERABLE form — what another agent could use without "
                                      "knowing this codebase (fed to any `harden` trigger)")

    sub.add_parser("kinds")

    cb = sub.add_parser("contribute")
    cb.add_argument("--reviewed", action="store_true",
                    help="record that you asked, of each learning hardened since the last review, "
                         "whether it named a TOOL's behaviour or this repo's")
    cb.add_argument("--filed", help="issue URLs you opened upstream, or 'none' — which is a "
                                    "complete answer")
    cb.add_argument("--note", help="one line of judgement, for the human reading the ledger")

    sb = sub.add_parser("stepback")
    sb.add_argument("--nothing-to-harden", action="store_true",
                    help="this retro encoded nothing, deliberately. Needs --reason; recorded in the "
                         "log so an empty chapter is a decision rather than a silence.")
    sb.add_argument("--reason", help="why there is nothing to encode (with --nothing-to-harden)")
    sb.add_argument("--notes")
    sb.add_argument("--show", action="store_true",
                    help="print what a retro would show and record NOTHING — this verb's output is "
                         "longer than a screen, and re-reading it used to open a new retro each time")

    tr = sub.add_parser("trans")
    tr.add_argument("--tier", help="T0 read · T1 subagents · T2 build · T3 the human's attention")
    tr.add_argument("--milestone", help="e.g. M2")
    tr.add_argument("--doing", help="one-line what's happening now")

    az = sub.add_parser("authorize")  # human-authorized, single-use, logged bypass
    az.add_argument("--path", help="path prefix the human authorized")
    az.add_argument("--reason", help="the human's own words")
    az.add_argument("--uses", help="how many mutations (default 1)")
    az.add_argument("--expires", metavar="WHEN",
                    help="when this grant lapses: 30m / 2h / 7d / 1w / 2026-09-30 / never")
    az.add_argument("--revoke", metavar="PATH",
                    help="withdraw live grants on PATH: uses_left to 0, kept in the record")

    at = sub.add_parser("attribute")  # a commit's merges, named by REF and recomputed here (#29)
    at.add_argument("--merge", action="append",
                    help="a ref this commit lands (repeatable): a branch, tag or sha — never a "
                         "filename. game_loop recomputes the files from it")
    at.add_argument("--reason", help="why this commit carries work another session produced")

    md = sub.add_parser("mandate")  # bind an autonomy mandate; while bound, the Stop gate is live
    md.add_argument("--wake-path", dest="wake_path",
                    help="how an external signal reaches this session while it is idle — a cron, a "
                         "waker, a human. Recorded, not probed")
    md.add_argument("--wake-every", dest="wake_every", type=int,
                    help="minutes between expected wakes on that path. With it, a path that has "
                         "STOPPED delivering becomes visible from inside: one missed wake proves "
                         "nothing, a cadence gone silent proves the path is dead")
    md.add_argument("--set", help="the mandate, in the human's words")
    md.add_argument("--because", metavar="QUOTE",
                    help="the instruction that PROMPTED this mandate, verbatim. Optional, "
                         "unverified, and recorded as a quote rather than as the reason")
    md.add_argument("--clear", action="store_true", help="release it (work genuinely done)")
    md.add_argument("--notes", help="why it's satisfied")
    md.add_argument("--park", action="store_true",
                    help="a HUMAN called a break: pause WITHOUT closing (needs --reason)")
    md.add_argument("--resume", action="store_true", help="they're back — re-arm the gate")
    md.add_argument("--reason", help="for --park: the human's words, verbatim")
    md.add_argument("--next", help="for --park: the step to pick back up on resume")

    ar = sub.add_parser("arm")  # arm ONE T3 spend (one interruption of the human)
    ar.add_argument("--question", help="what you need that you cannot get yourself")
    ar.add_argument("--read", help="real path[,path] you ALREADY read that didn't answer it")
    ar.add_argument("--predict", help="what you expect them to say — if you can predict it, don't ask")

    cp = sub.add_parser("checkpoint")  # report + hand back, without asking anything
    cp.add_argument("--notes", help="what you did and what happens next")
    cp.add_argument("--release-deferred", dest="release_deferred",
                    help="why finished work is not being published yet — recorded in the log")

    pn = sub.add_parser("pin")  # carry a load-bearing environment fact (+ its reason) in resume state
    pn.add_argument("--fact", help="the environment fact the build depends on")
    pn.add_argument("--reason", help="why it is load-bearing — what breaks if it's tidied away")
    pn.add_argument("--path", help="real path the fact lives at (checkout / file / install dir)")
    pn.add_argument("--expect", help="text that must stay in that file — makes the pin a CHECK")
    pn.add_argument("--restore", help="the exact command that re-establishes it")
    pn.add_argument("--list", action="store_true", help="show this session's live pins")
    pn.add_argument("--release", help="pin id to release (requires --notes)")
    pn.add_argument("--notes", help="why a released pin is no longer load-bearing")

    ef = sub.add_parser("effector")  # prove a verb ACTUALLY ACTS before a finding leans on it
    ef.add_argument("--prove", help="the effector you are about to depend on (scroll, click, type)")
    ef.add_argument("--known-state", dest="known_state",
                    help="a state whose RESPONSE YOU ALREADY KNOW (a view you know overflows)")
    ef.add_argument("--before", help="real path to the capture taken BEFORE the act")
    ef.add_argument("--observed", help="real path to the capture taken AFTER — the change, not the "
                                       "exit code")
    ef.add_argument("--expect", help="text that must appear in --observed and NOT in --before")
    ef.add_argument("--scale", help="coordinate factor; --aim then converts so you never multiply")
    ef.add_argument("--aim", help="effector name: convert a point into ITS coordinate space")
    ef.add_argument("--at", help="for --aim: X,Y as YOU measured it")
    ef.add_argument("--list", action="store_true", help="show this session's proved effectors")
    ef.add_argument("--release", help="effector name whose proof no longer stands (needs --notes)")
    ef.add_argument("--notes", help="why a released proof no longer stands")
    # Present ONLY to be refused by name. A hurried run reaches for this first, and argparse's
    # "unrecognized argument" would teach it nothing about why a return code is not a proof.
    ef.add_argument("--exit-code", dest="exit_code", help="(refused — see cmd_effector)")
    im = sub.add_parser("instrument")  # admit a METRIC as evidence: declared harm + both controls
    im.add_argument("--register", metavar="NAME", help="name a claim will later cite with --metric")
    im.add_argument("--measures", help="the USER-VISIBLE harm this number stands for")
    im.add_argument("--connects", help="HOW the number reaches that harm (what makes it re-checkable)")
    im.add_argument("--null", help="before,after sampled while the phenomenon is ABSENT (must be Δ0)")
    im.add_argument("--positive", help="before,after across a KNOWN-REAL event (must not be Δ0)")
    im.add_argument("--list", action="store_true", help="show this session's admitted instruments")
    im.add_argument("--release", metavar="NAME", help="retire an instrument (requires --notes)")
    im.add_argument("--notes", help="why a retired instrument is no longer trusted")

    fx = sub.add_parser("fix")  # prove a FIX HOLDS by exercising what it PRODUCES (a repro is not one)
    fx.add_argument("--prove", help="the fix you are about to report as done")
    fx.add_argument("--promises", help="the OUTCOME it promises — what someone gets that they didn't")
    fx.add_argument("--produces", help="real path to the fix's OWN output, not the source you edited")
    fx.add_argument("--diagnosis", help="real path to the repro that proved the BUG — refused back "
                                        "as proof of the fix")
    fx.add_argument("--before", help="real path to the consumer's verdict on the UNFIXED output")
    fx.add_argument("--observed", help="real path to that same consumer's verdict on the FIXED one")
    fx.add_argument("--expect", help="text the fixed verdict brings into being (and the before lacks)")
    fx.add_argument("--list", action="store_true", help="show this session's proved fixes")
    fx.add_argument("--release", help="fix name whose proof no longer stands (needs --notes)")
    fx.add_argument("--notes", help="why a released fix proof no longer stands")

    ms = sub.add_parser("measure")  # ONE reading of an instrument: two endpoints, delta computed here
    ms.add_argument("--instrument", help="the admitted instrument being read")
    ms.add_argument("--before", help="the reading BEFORE the interaction")
    ms.add_argument("--after", help="the reading AFTER it")
    ms.add_argument("--events", help="the per-event values this delta is the total of — a sum is not "
                                     "a distribution, and only these show its shape")
    ms.add_argument("--notes", help="what the interaction was (this is what the delta is scoped to)")

    nf = sub.add_parser("notify")  # page the configured Slack channel by hand
    nf.add_argument("--text", help="the message the run's human should see")
    nf.add_argument("--test", action="store_true", help="send a test page to verify the channel")

    ow = sub.add_parser("owned")  # the user-owned file set, published so nobody re-lists it (#30)
    ow.add_argument("--porcelain", action="store_true", help="emit the set as JSON, for tools")

    wd = sub.add_parser("watchdog")  # is the waiting seam armed, and what did it last say? (#67)
    wd.add_argument("--porcelain", action="store_true",
                    help="emit the waiting seam as JSON: configured, which file arms it, the last "
                         "verdict and whether the probe is FAILING. READ ONLY — there is no setter, "
                         "because a wait a session can declare for itself is an off switch for the "
                         "watchdog, and this verb cannot tell a session from the layer above it. "
                         "Arm it in config.local.json, which is not byte-compared at spawn.")
    wt = sub.add_parser("worktree")  # does this tree carry the PROJECT's rules, or its own? (#30)
    wt.add_argument("--porcelain", action="store_true",
                    help="emit the verdict as JSON: `rules` (differ ⇒ the trees enforce different "
                         "things) and `harness` (every owned file), each naming its files, plus the "
                         "owned set. exit 0 ONLY for clean; 1 rules drifted; 3 notes drifted; "
                         "2 could not determine — never read a 2 as clean")

    sf = sub.add_parser("self")  # run the harness from a pinned checkout of itself
    sf.add_argument("--pin", metavar="REF",
                    help="check .game_loop out of REF into <repo>/.game_loop_self and stamp it, so "
                         "the hooks can run code that editing this repo cannot break. No --pin: "
                         "report what is pinned now and print the hook wiring.")
    sf.add_argument("--dest", metavar="PATH",
                    help="with --pin: check out to PATH instead of <repo>/.game_loop_self — for a "
                         "machine-wide central install other repos dispatch to via "
                         "`install.sh --central` (see docs/how-it-works.md), not for this repo's own "
                         "hooks.")

    sub.add_parser("stopgate")    # Stop-hook entrypoint; not for humans
    sub.add_parser("limitgate")   # PreToolUse entrypoint (usage-limit handoff gate); not for humans
    sub.add_parser("statusline")  # statusline entrypoint (limits tap + one-row render); not for humans
    sub.add_parser("sessionstart")  # SessionStart/PostCompact entrypoint; not for humans
    md = sub.add_parser("model")
    md.add_argument("--json", action="store_true",
                    help="emit the verdict as JSON — the form a PARENT reads, since the session "
                         "itself is the one party that cannot act on a model mismatch")
    lp = sub.add_parser("limitprobe")
    lp.add_argument("--interval-only", dest="interval_only", action="store_true",
                    help="print the seconds until the next probe is worth spending on, and exit")
    lp.add_argument("--force", action="store_true",
                    help="run it even though limits.probe.enabled is false — it costs ~24k input "
                         "tokens, so the default is off")
    th = sub.add_parser("threads")
    th.add_argument("--json", action="store_true",
                    help="emit the chains as JSON — the form a viewer or another harness reads")
    sc = sub.add_parser("successor")
    sc.add_argument("--handoff", help="the file the successor should read (default: this session's "
                                      "handoff)")
    sc.add_argument("--session-id", dest="session_id",
                    help="use this id instead of minting one (a prewarmed session, say)")
    sc.add_argument("--cwd", help="where the successor starts (default: this repo)")
    sc.add_argument("--task", help=f"what the successor is doing, {TASK_MAX_WORDS} words / "
                                   f"{TASK_MAX_CHARS} chars at most — names the terminal. "
                                   "`<R> | <task>` under warp-tab, where a flat row of tabs from "
                                   "every repo needs the initial; `<task>` alone under "
                                   "saggar-agent, whose project folder already says which repo "
                                   "this is")
    sc.add_argument("--title", help="terminal name, verbatim and uncapped — the override for when "
                                    "--task is too small a box. Acts under warp-tab and "
                                    "saggar-agent (which passes it as `saggar agent --title`); "
                                    "under print it is a suggestion to whoever runs the command, "
                                    "which sets no name")
    sc.add_argument("--about", help="one line saying WHAT IS BEING WORKED ON, prepended to the "
                                    "successor's prompt so a human reading that terminal can tell. "
                                    "Derived from the handoff's heading, or the mandate, when "
                                    "omitted; pass \"\" to leave it out entirely")
    sc.add_argument("--dry-run", dest="dry_run", action="store_true",
                    help="print the id, the prompt and the command, and start nothing")
    cf = sub.add_parser("confidence")
    cf.add_argument("--mark", help="beta | stable — refused unless the evidence for it exists")
    cf.add_argument("--ref", help="the commit to report on (default HEAD)")
    cf.add_argument("--notes", help="what landed, in your words")
    cf.add_argument("--recheck", action="store_true",
                    help="do not trust the tag: run the gate the level claims")

    add_prose_file_options(sub)
    a = p.parse_args()
    resolve_prose(p, a)
    if a.cmd in ("stopgate", "limitgate", "statusline", "sessionstart"):
        # The hook payload is the authoritative session source — the env is a fallback for harnesses
        # that deliver payloads without a session_id. Parsed BEFORE load(): it decides whose state.
        try:
            payload = json.load(sys.stdin)
        except (json.JSONDecodeError, ValueError):
            payload = {}
        set_session(payload.get("session_id") or env_session())
        # REMEMBER WHERE THE TRANSCRIPT IS. Hooks receive it; `status` is not a hook and never
        # does, so without this the model reading would work inside a Stop gate and nowhere a
        # human ever looks.
        if (_tp := payload.get("transcript_path")):
            _st = load()
            if _st.get("transcript_path") != _tp:
                _st["transcript_path"] = _tp
                save(_st)
            # Publish where the PARENT reads, on every hook run, so the verdict stays current
            # without the Crawler knowing or cooperating.
            write_model_verdict()
        {"stopgate": cmd_stopgate, "limitgate": cmd_limitgate,
         "statusline": cmd_statusline,
         "sessionstart": cmd_sessionstart}[a.cmd](load(), a, payload)
        return
    set_session(env_session())
    s = load()
    {"status": cmd_status, "claim": cmd_claim, "note": cmd_note, "harden": cmd_harden,
     "stepback": cmd_stepback, "trans": cmd_trans, "mandate": cmd_mandate, "arm": cmd_arm,
     "checkpoint": cmd_checkpoint, "authorize": cmd_authorize, "attribute": cmd_attribute,
     "notify": cmd_notify,
     "pin": cmd_pin, "effector": cmd_effector, "fix": cmd_fix,
     "checkpoint": cmd_checkpoint, "authorize": cmd_authorize, "notify": cmd_notify,
     "pin": cmd_pin, "effector": cmd_effector, "fix": cmd_fix, "owned": cmd_owned,
     "mutate": cmd_mutate, "worktree": cmd_worktree, "watchdog": cmd_watchdog, "self": cmd_self,
     "confidence": cmd_confidence,
     "instrument": cmd_instrument, "measure": cmd_measure,
     "limitprobe": cmd_limitprobe, "model": cmd_model,
     "successor": cmd_successor, "threads": cmd_threads, "contribute": cmd_contribute,
     "doorbell": cmd_doorbell, "guardtest": cmd_guardtest,
     "kinds": cmd_kinds}[a.cmd](s, a)


if __name__ == "__main__":
    main()
