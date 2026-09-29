#!/usr/bin/env bash
# Ask the HOST what your usage windows look like, when this host cannot tell you itself.
#
# WHY THIS EXISTS. `rate_limits` rides the statusline payload and nothing else, and a statusline is
# a TUI element: an editor-embedded session renders none, so limitgate, the watchdog's park and the
# wake-on-reset are all inert there. Measured: a headless `claude -p` never invokes the statusline
# at all, so the cheap version of this cannot work. A TUI session does — driven through a pty, with
# one tiny message to force an API response, it renders a payload carrying five_hour and seven_day.
#
# WHAT IT COSTS, and the number MOVED: measured at 2.1.223 as ~24k input tokens stripped to the
# bone (~31.5k with MCP and all tools) for a four-token reply. RE-MEASURED 2026-08-24 at 2.1.241,
# from this probe's own recorded render (probe/context-window.json): 63,943 input tokens — 2 fresh,
# 3,162 cache-creation, 60,779 cache-read. Roughly double the older figure, in a spawn of the same
# shape (--settings overrides the statusline only; tools and MCP come along).
#
# WHAT THAT ONE READING CANNOT SAY: the older number decomposes as ~24k base preamble + ~6k tool
# definitions + ~1k MCP schemas. A single total cannot apportion the growth between the host's
# preamble and THIS machine's MCP surface, which has also grown. So the headline is stale and the
# breakdown is unknown — do not read 63,943 as "the host's floor doubled". It is what a spawn costs
# HERE, today, which is the number you actually pay.
#
# That is the host's floor plus your surface, not ours, and nothing amortises across spawns.
#
# WHY IT IS WORTH IT ANYWAY, which is the argument I had backwards at first: the alternative is not
# zero. Without a snapshot an unattended run hits the limit, dies mid-action, and nothing wakes it —
# so a session that stops at 1am is stopped until somebody notices. 24k tokens to convert six dead
# hours into a park-and-resume is not a cost, it is the cheapest thing in the loop. The whole limit
# family already exists and is tested; the only missing piece was ever the snapshot.
#
# CONTRACT: prints the rate_limits object as JSON on stdout and exits 0. Exit 1 means it ran and the
# host produced no rate_limits (a real answer: unsubscribed accounts have none). Exit 2 means it
# could not tell — no binary, no pty, timed out. Three outcomes, because "could not look" and
# "looked and there is nothing" must never be the same bytes (this repo has paid for that lesson
# four times).
set -uo pipefail

WORK="$(mktemp -d "${TMPDIR:-/tmp}/gl-limitprobe-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# The running binary, not whatever is on PATH. These genuinely differ: on this machine PATH held
# 2.1.145 against a running 2.1.223 when this shipped, and 2.1.231 against the same running 2.1.223
# three days later — so WHICH IS NEWER FLIPS, and the reason to prefer EXECPATH is not newness. It is
# that the running binary is the one whose account and session this probe is asking about. A probe
# that asks the wrong binary reports the wrong account, whichever version that binary happens to be.
CB="${CLAUDE_CODE_EXECPATH:-}"
[ -n "$CB" ] && [ -x "$CB" ] || CB="$(command -v claude 2>/dev/null || true)"
if [ -z "$CB" ]; then
  echo "no claude binary (CLAUDE_CODE_EXECPATH unset and none on PATH)" >&2; exit 2
fi
command -v script >/dev/null 2>&1 || { echo "no \`script\` to allocate a pty" >&2; exit 2; }

cat > "$WORK/tap.sh" <<TAP
#!/usr/bin/env bash
cat >> "$WORK/renders.jsonl"; printf '\n' >> "$WORK/renders.jsonl"
echo probing
TAP
chmod +x "$WORK/tap.sh"

# --settings, so nothing global is touched. The probe must never edit the human's configuration to
# read a number.
printf '{"statusLine":{"type":"command","command":"%s"}}\n' "$WORK/tap.sh" > "$WORK/settings.json"

# Drive it: settle, clear any trust prompt, send one token of work, wait for the response to land.
# The message matters — rate_limits appears only AFTER an API response, so a session that merely
# starts renders a payload without them and would read as "no limits data" (this is exactly how the
# first attempt at this fooled me).
SETTLE="${GAME_LOOP_PROBE_SETTLE_SEC:-8}"
WAIT="${GAME_LOOP_PROBE_WAIT_SEC:-40}"
( { sleep "$SETTLE"; printf '\r'; sleep "$SETTLE"; printf 'ok\r'; sleep "$WAIT"; } \
  | script -q /dev/null "$CB" --settings "$WORK/settings.json" >"$WORK/tui.log" 2>&1 ) &
DRIVER=$!
( sleep $(( SETTLE * 2 + WAIT + 15 )); kill "$DRIVER" 2>/dev/null ) &
REAPER=$!
wait "$DRIVER" 2>/dev/null
kill "$REAPER" 2>/dev/null
pkill -f "$WORK/settings.json" 2>/dev/null

[ -s "$WORK/renders.jsonl" ] || { echo "the statusline never rendered — nothing to read" >&2; exit 2; }

RENDERS="$WORK/renders.jsonl" python3 <<'PY'
import json, os, sys

found = None
ctx = None
for line in open(os.environ["RENDERS"]):
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
    except ValueError:
        continue                      # a partial write is not a verdict
    if d.get("rate_limits"):
        found = d["rate_limits"]      # keep the LAST, which is the freshest
    if isinstance(d.get("context_window"), dict):
        # RIDES ALONG, and is never a reason to succeed or fail. This session is FRESH, so its
        # render is the cheapest place a fresh-session token count can be observed — but the probe's
        # job is the usage windows, and a context_window that is missing, null or unexpected must
        # not change any exit code below.
        ctx = d["context_window"]

if found is None:
    # Ran, rendered, and the host carried no rate_limits. A real answer, not a failure: the field is
    # subscriber-only. Distinct exit from "could not look", because a caller that folds them together
    # would treat an unsubscribed account as a broken probe forever.
    print("rendered, but the host carried no rate_limits (subscriber-only field)", file=sys.stderr)
    sys.exit(1)
# AN ENVELOPE, so a second reading can ride the same spawn. The consumer accepts the older bare
# shape too, because a pin can pair an old probe script with new code.
print(json.dumps({"rate_limits": found, "context_window": ctx}))
PY
