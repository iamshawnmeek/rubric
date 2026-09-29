#!/usr/bin/env bash
# Fail-CLOSED entrypoint for the MCP guard. The real logic lives in guard-mcp-impl.sh; this shim runs
# it, but if that file cannot even PARSE (a broken edit) it DENIES the MCP tool call.
#
# WHY THE OPPOSITE DEFAULT FROM guard-writes.sh: that shim fails OPEN, and must. It is matched on
# Write|Edit|NotebookEdit|Bash — every tool that could REPAIR it — so a parse error there blocks its
# own fix and the session can only be rescued from outside the run (INV5). This shim is matched on
# `mcp__.*` ONLY. A parse error here blocks MCP calls and nothing else: Write, Edit and Bash still
# work, so the edit that fixes this file is never blocked by this file. The INV5 hazard that forces
# guard-writes open simply does not exist here — and what is on the other side of an unguarded MCP
# call is a `DELETE FROM`, a send, a force-push. Broken guard, no gate, irreversible effect: deny.
#
# Keep THIS file trivially correct: no logic, no dependencies, one static refusal string.
impl="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/guard-mcp-impl.sh"
if ! bash -n "$impl" 2>/dev/null; then
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED: the MCP guard cannot run — its own impl (.game_loop/bin/guard-mcp-impl.sh) is missing or will not parse.\n\nThis guard fails CLOSED, unlike the write guard: an MCP call can be irreversible and an unparseable guard is not gating anything. Nothing else is blocked — Write, Edit and Bash are untouched, so fix guard-mcp-impl.sh (bash -n it) and the calls flow again."}}'
  exit 0
fi
exec bash "$impl"
