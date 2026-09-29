#!/usr/bin/env bash
# PreToolUse (Bash): when a session starts LONG work with nothing able to wake it back to a goal,
# say so once. Advice at a moment, never a refusal — every path here exits 0.
#
# A VERB NOBODY REGISTERS HAS NEVER ONCE RUN. That was true of `lock guard` for this repo's entire
# life and true of `dispatch guard` for the hours between building it and noticing. The
# registration is the feature; the verb is an implementation detail of it.
#
# THIN ON PURPOSE, exactly like dispatch-guard.sh: this locates a binary and hands it the payload
# on stdin. Every decision — what counts as long work, whether a mandate is bound, whether this
# session has already been told — lives in `showrunner wake-gate`, where the suite can reach it
# and the mutation sweep can neuter it. A rule that lives in a shell script is a rule with no
# test and no denominator.
set -u

# SILENT ON EVERY FAILURE, which is the opposite of dispatch-guard.sh's loud fail-open, and the
# difference is what each one protects. That guard is the only thing between a session and an
# unguarded dispatch, so a call it could not check must announce itself. This one offers advice
# about a wake path: an agent that does not get it is exactly as badly off as before this existed,
# whereas a paragraph printed before every Bash call because a binary moved is how the notice that
# matters stops being read at all.
anchor="$PWD"
common="$(git rev-parse --git-common-dir 2>/dev/null)" || common=""
if [ -z "$common" ] && [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
  common="$(git -C "$CLAUDE_PROJECT_DIR" rev-parse --git-common-dir 2>/dev/null)" || common=""
  [ -n "$common" ] && anchor="$CLAUDE_PROJECT_DIR"
fi
if [ -z "$common" ]; then
  root="$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)" || exit 0
else
  case "$common" in /*) ;; *) common="$anchor/$common" ;; esac
  root="$(cd "$(dirname "$common")" 2>/dev/null && pwd)" || exit 0
fi

# KEEP LOOKING WHEN A BINARY DOES NOT KNOW THE VERB. The first version stopped at the first
# candidate that EXISTED, and in showrunner's own checkout that is `.showrunner_self` -- a pinned
# copy, deliberately older than HEAD, which predates this verb. So the hook was registered, the
# shim ran, the binary exited 2 with a usage error, `|| true` swallowed it, and the result was
# indistinguishable from "nothing to say". Registered and DEAD, wearing the shape of registered
# and quiet, in the gate written to stop exactly that class of silence.
#
# The preference order is unchanged and still deliberate -- a pinned self-copy is what lets this
# repo guard itself with a known-good build. What changed is that a candidate which cannot answer
# no longer ENDS the search. Exit 0 means it answered, whether or not it printed anything; any
# other status means ask the next one.
#
# Payload is read once and replayed, because stdin is consumed by the first candidate that reads
# it and the second would otherwise be handed an empty stream -- which this tool correctly treats
# as "no payload" and, just as correctly, says nothing about.
payload="$(cat 2>/dev/null)" || payload=""

for candidate in "$root/.showrunner_self/bin/showrunner" \
                 "$root/.showrunner/bin/showrunner" \
                 "$root/bin/showrunner"; do
  [ -x "$candidate" ] || continue
  if printf '%s' "$payload" | (cd "$root" && "$candidate" wake-gate) 2>/dev/null; then
    exit 0
  fi
done
exit 0
