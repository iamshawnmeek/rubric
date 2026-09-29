"""notify — optional Slack paging for the moments a run genuinely needs its human.

A game_loop run is autonomous enough that nobody should babysit it. But some moments need the human —
usually their PHYSICAL presence, not just an answer: a T3 arm, the watchdog standing down with the run
stuck, the mandate completing, a usage limit about to kill the session. This module pages a Slack
channel at exactly those moments, and (bot-token setups only) reads thread replies back so an answer
typed on a phone can resume the run.

THE CONTRACT (same as flair.py): decoration and notification must NEVER take down enforcement.
Every public function swallows every error and returns a harmless value; a Slack outage, a bad token,
or a malformed notify.json must never break a gate, a verb, or the watchdog. Failures are logged to
log.jsonl (kind: notify_error) so a silent channel is at least readable — silence from a notifier is
otherwise indistinguishable from "nothing needed you".

CONFIGURATION — .game_loop/notify.json (gitignored; credentials never land in git):

    {
      "slack": {
        "bot_token": "xoxb-...",          # SEND: chat:write. READ replies: the history scope for the
        "channel": "C0123456789",          #   channel TYPE (see below) — the bot must be a MEMBER.
        "webhook_url": "https://hooks.slack.com/services/...",  # send-only alternative
        "api_base": "https://slack.com/api",   # override for tests only
        "reply_poll_sec": 20               # watchdog's poll cadence
      },
      "events": { "checkpoint": true }     # per-event overrides of DEFAULT_EVENTS
    }

BOT-TOKEN SCOPES: chat:write to send. To READ replies (so a phone answer resumes the run), add the
history scope that MATCHES the channel's type, then reinstall the app so the token picks it up:
    public channel  -> channels:history        private channel -> groups:history
    direct message  -> im:history              group DM (mpim) -> mpim:history
A channel id beginning with `C` is NOT necessarily public — Slack issues `C` ids to private channels
too, so match the scope to the actual channel type, not the id prefix. `game_loop notify --test`
actively probes the read path and names the missing scope if reads fail. Reads use the universal
`conversations.history` / `conversations.replies` methods for every type (no per-type endpoint).

Provide bot_token+channel OR webhook_url. The webhook path cannot read replies (Slack webhooks are
write-only), so `arm` questions become one-way pages — still useful, just no phone-answer resume.

WHAT THIS DOES NOT DO: it cannot verify the human saw the page, and a reply read from the thread is
trusted as the human's words — anyone in the channel can answer. Scope the channel accordingly.
Python 3 stdlib only, by the same rule as the rest of .game_loop/bin/.
"""
import datetime
import json
import os
import urllib.error
import urllib.parse
import urllib.request

def _home():
    """The .game_loop/ holding notify.json, honouring GAME_LOOP_HOME so a pinned harness pages using
    the PROJECT's credentials and logs to the PROJECT's log. Permissive where the gates refuse, for
    the same reason as bin/flair.py: paging is optional and must never break a real command, and a
    bad value has already been refused by every entrypoint that gates anything."""
    raw = (os.environ.get("GAME_LOOP_HOME") or "").strip()
    if raw:
        home = os.path.abspath(os.path.expanduser(raw))
        if os.path.isfile(os.path.join(home, "config.json")):
            return home
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


ROOT = _home()  # .game_loop/
NOTIFY_F = os.path.join(ROOT, "notify.json")
CONFIG_F = os.path.join(ROOT, "config.json")
LOG_F = os.path.join(ROOT, "log.jsonl")

TIMEOUT_SEC = 6  # a page is worthless if it stalls the gate that sends it

# Which moments page by default. Overridable per-event via notify.json -> events.
# checkpoint defaults OFF: progress reports are the normal hum of a run, not a reason to buzz a phone.
DEFAULT_EVENTS = {
    "arm": True,                 # T3 — the human is genuinely needed
    "mandate_clear": True,       # the run finished
    "watchdog_exhausted": True,  # the run is stuck and the watchdog gave up
    "limit_handoff": True,       # a usage limit is nearly exhausted; handoff written/demanded
    "limit_park": True,          # the run parked to wait out an exhausted usage limit
    "limit_resume": True,        # the limit reset and the run was rung awake
    "checkpoint": False,         # routine progress report
    "manual": True,              # `game_loop notify --text ..`
}


def _log(rec):
    try:
        with open(LOG_F, "a") as f:
            f.write(json.dumps({"t": datetime.datetime.now().isoformat(timespec="seconds"),
                                **rec}) + "\n")
    except OSError:
        pass


def user_notify_path():
    """The one-per-machine config: $XDG_CONFIG_HOME/game_loop/notify.json, else ~/.config/…"""
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")
    return os.path.join(base, "game_loop", "notify.json")


def _cfg():
    """The project's notify.json, else the user's one-per-machine file (#54).

    Anyone running game_loop across several checkouts -- worktrees of one project, or unrelated
    projects -- had to hand-copy the same bot token and channel into a gitignored notify.json in
    every .game_loop/. One Slack app, N copies of a credential, and N places to rotate it.

    THE PROJECT'S FILE STILL WINS, whole. Not merged key-by-key: a half-inherited credential is the
    worst outcome available here -- a project that deliberately points at its own channel would
    silently borrow the user's token, and a paging path that works for the wrong reason is harder to
    notice than one that does not work at all.

    WHAT THIS WIDENS, stated rather than left to be discovered (INV6): a user-level file applies to
    EVERY project on this machine, including ones installed later that never asked for it. That is
    the point, and it is also the whole of the risk -- `game_loop status` names which file is in
    use, so "where is this paging" is answerable without guessing.
    """
    for p in (NOTIFY_F, user_notify_path()):
        try:
            with open(p) as f:
                d = json.load(f)
            if isinstance(d, dict) and d:
                return d
        except (OSError, ValueError):
            continue
    return {}


def cfg_source():
    """Which file _cfg() would use, or None. For reporting -- never a decision."""
    for p in (NOTIFY_F, user_notify_path()):
        try:
            with open(p) as f:
                d = json.load(f)
            if isinstance(d, dict) and d:
                return p
        except (OSError, ValueError):
            continue
    return None


def _slack():
    return (_cfg().get("slack") or {})


def _merged_config(config_f):
    """config.json, then config.local.json on top. The local file is GITIGNORED site wiring, and it
    has to reach every component that reads config -- a setting only some of them honour is worse
    than one nobody has, because it works in the place you test it and not in the place it matters.
    (Shipped that way once: the waiting probe lived here and the watchdog could not see it.)"""
    import json as _json
    import os as _os
    cfg = {}
    for _p in (config_f, _os.path.join(_os.path.dirname(config_f), "config.local.json")):
        try:
            with open(_p) as _f:
                _d = _json.load(_f)
            if isinstance(_d, dict):
                cfg.update(_d)
        except (OSError, ValueError):
            continue
    return cfg


def _project():
    return (_merged_config(CONFIG_F).get("project_name")
            or os.path.basename(os.path.dirname(ROOT)))


def configured():
    """True when at least a send path exists (bot token+channel, or webhook)."""
    sl = _slack()
    return bool((sl.get("bot_token") and sl.get("channel")) or sl.get("webhook_url"))


def can_read_replies():
    """Reading a thread needs the bot-token path; webhooks are write-only."""
    sl = _slack()
    return bool(sl.get("bot_token") and sl.get("channel"))


def enabled(event):
    events = dict(DEFAULT_EVENTS)
    ev = _cfg().get("events")
    if isinstance(ev, dict):
        events.update(ev)
    return bool(events.get(event, True))


def reply_poll_sec():
    try:
        return max(5, int(_slack().get("reply_poll_sec") or 20))
    except (TypeError, ValueError):
        return 20


def _post_json(url, body, headers=None):
    req = urllib.request.Request(url, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json",
                                          **(headers or {})})
    with urllib.request.urlopen(req, timeout=TIMEOUT_SEC) as resp:
        return json.loads(resp.read().decode() or "{}")


def send(event, text, thread_ts=None):
    """Page the channel. Never raises.

    Returns the message ts (str, bot-token path — threadable), True (webhook path — sent but
    write-only, no thread), or None (disabled / unconfigured / failed; the log line tells which).
    """
    sl = _slack()
    if not configured() or not enabled(event):
        return None
    msg = f"🎮 [{_project()}] {text}"
    try:
        if sl.get("bot_token") and sl.get("channel"):
            body = {"channel": sl["channel"], "text": msg}
            if thread_ts:
                body["thread_ts"] = thread_ts
            api = (sl.get("api_base") or "https://slack.com/api").rstrip("/")
            r = _post_json(api + "/chat.postMessage", body,
                           {"Authorization": "Bearer " + sl["bot_token"]})
            if not r.get("ok"):
                _log({"kind": "notify_error", "event": event, "error": r.get("error", "not ok")})
                return None
            _log({"kind": "notify_sent", "event": event, "ts": r.get("ts")})
            return r.get("ts")
        _post_json(sl["webhook_url"], {"text": msg})
        _log({"kind": "notify_sent", "event": event, "via": "webhook"})
        return True
    except Exception as e:  # noqa: BLE001 — a page must never take down the thing that paged
        _log({"kind": "notify_error", "event": event, "error": str(e)[:200]})
        return None


def replies(thread_ts, oldest=None):
    """Human answers to a paged arm, oldest first: [{"ts","user","text"}, ...].

    Reads BOTH the thread (conversations.replies) AND the channel's top-level messages
    (conversations.history) posted after `oldest`, then unions them. A human who answers in the CHANNEL
    — the natural thing to do from a phone — is caught as well as one who replies in-thread. Both use
    the same `channels:history` scope (groups:history for a private channel), so this needs nothing new.

    Trust scope, as elsewhere: any human message in the channel after the page is taken as the answer —
    anyone in the channel can answer. Scope the channel to the human you're paging. Never raises; [] on
    any failure — the log line is where "no reply yet" vs "Slack is down" lives, not the return value."""
    sl = _slack()
    if not can_read_replies() or not thread_ts:
        return []
    api = (sl.get("api_base") or "https://slack.com/api").rstrip("/")
    hdr = {"Authorization": "Bearer " + sl["bot_token"]}
    seen, out = set(), []

    def collect(path, params):
        req = urllib.request.Request(api + path + "?" + urllib.parse.urlencode(params), headers=hdr)
        with urllib.request.urlopen(req, timeout=TIMEOUT_SEC) as resp:
            r = json.loads(resp.read().decode() or "{}")
        if not r.get("ok"):
            _log({"kind": "notify_error", "op": "replies", "error": r.get("error", "not ok")})
            return
        for m in r.get("messages", []):
            ts = m.get("ts")
            if not ts or ts == thread_ts or ts in seen:  # skip the parent (our question) and dups
                continue
            if m.get("bot_id") or m.get("subtype"):       # skip our own posts and channel noise
                continue
            if oldest and float(ts) <= float(oldest):
                continue
            if m.get("text"):
                seen.add(ts)
                out.append({"ts": ts, "user": m.get("user", "?"), "text": m["text"]})

    try:
        collect("/conversations.replies", {"channel": sl["channel"], "ts": thread_ts, "limit": 50})
        collect("/conversations.history", {"channel": sl["channel"], "oldest": oldest or thread_ts,
                                           "limit": 50})
    except Exception as e:  # noqa: BLE001
        _log({"kind": "notify_error", "op": "replies", "error": str(e)[:200]})
        return []
    out.sort(key=lambda m: float(m["ts"]))
    return out


def read_probe():
    """Actively verify the bot can READ this channel — distinct from can_read_replies(), which only
    checks config shape. Returns (ok: bool, detail: str). `notify --test` uses it so a wrong history
    scope surfaces LOUDLY instead of as a silently-empty reply list: a PRIVATE channel needs
    groups:history (channels:history returns missing_scope), and a C-prefixed id can still be private."""
    sl = _slack()
    if not can_read_replies():
        return (False, "send-only path (webhook, or no bot_token+channel) — replies cannot be read")
    api = (sl.get("api_base") or "https://slack.com/api").rstrip("/")
    q = urllib.parse.urlencode({"channel": sl["channel"], "limit": 1})
    req = urllib.request.Request(api + "/conversations.history?" + q,
                                 headers={"Authorization": "Bearer " + sl["bot_token"]})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT_SEC) as resp:
            r = json.loads(resp.read().decode() or "{}")
        return (True, "reads OK") if r.get("ok") else (False, r.get("error", "not ok"))
    except Exception as e:  # noqa: BLE001
        return (False, str(e)[:120])
