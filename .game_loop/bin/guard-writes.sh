#!/usr/bin/env bash
# Fail-open entrypoint for the write guard. The real logic lives in guard-writes-impl.sh; this shim
# runs it, but if that file cannot even PARSE (a broken edit) it ALLOWS the tool instead of exiting 2.
#
# WHY: a PreToolUse hook that exits non-zero BLOCKS the tool. If the guard's own code has a syntax
# error, every Write/Edit/Bash — including the one that would REPAIR the guard — is blocked, and the
# session can only be rescued from outside the run. A guard that cannot parse is not guarding anything
# anyway, so failing OPEN keeps the repo editable back to health. Keep THIS file trivially correct: it
# is the piece that must never itself break — put no real logic here; all of it lives in the impl.
#
# FAIL OPEN, NEVER IN SILENCE. Allowing without a word is indistinguishable from a guard that ran and
# was content: INV3 stops being enforced and nothing reports it. That is not hypothetical — a syntax
# error is exactly the edit an agent makes while working ON this guard, so the guard is most likely to
# be off precisely when someone is changing it. Nothing in INV5 asks for quiet; it asks only that the
# repair is never blocked. So this allows AND says so, the way the blast-radius check warns without
# blocking. The notice is a fixed string with no interpolation, because this file must never be the
# thing that breaks.
impl="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/guard-writes-impl.sh"
if ! bash -n "$impl" 2>/dev/null; then
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"⚠ THE WRITE GUARD IS NOT RUNNING — .game_loop/bin/guard-writes-impl.sh is missing or will not parse, so this tool call was ALLOWED WITHOUT BEING CHECKED.\n\nINV3 (everything outside this repo is READ-ONLY) is NOT enforced until that file parses again, and neither is the commit gate. Silence from this guard is not evidence of safety right now — it is evidence the guard is absent.\n\nThis fails OPEN on purpose: a PreToolUse hook that exits non-zero blocks every Write/Edit/Bash INCLUDING the one that would repair it (INV5). Repair it, do not work around it:\n    bash -n .game_loop/bin/guard-writes-impl.sh"}}'
  exit 0
fi
exec bash "$impl"
