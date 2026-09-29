#!/usr/bin/env bash
# PreToolUse: name the mechanism for what this call reached for. ADVICE ONLY — never denies.
#
# THE REPORTED FAILURE. An agent several compactions deep had lost which campaign it was on and
# what verbs existed, and "wasn't even using it" — doing the work by hand in the main checkout of
# a repo carrying a live campaign. An agent that cannot remember a tool does not stop working; it
# reaches for what it already knows, and every one of those reaches produces a plausible result,
# which is why nothing ever objected.
#
# SessionStart and PostCompact announce the tool once, into a window that then fills with other
# things. The moment somebody types `git worktree add` is the moment they have a specific intent
# that a specific verb serves — the only moment at which naming it costs nothing to act on.
#
# ALWAYS EXITS 0. It protects nothing by blocking, so there is no case in which refusing is
# right, and a PreToolUse hook that exits non-zero blocks every Write/Edit/Bash including the one
# that would repair it.
#
# AND IT MUST PARSE. Measured on this repo: an unclosed `if` in a sibling hook made bash fail to
# parse the file, which refuses Bash, Edit AND Write alike — so no tool could repair the file
# doing the refusing, and a human ran `git checkout` by hand. Every fail-open path below is
# downstream of parsing and none of them would run. `bash -n` on a COPY before installing is the
# only guard against that; test_every_REGISTERED_hook_parses stops it reaching a commit.
set -u

# SILENT WHEN IT CANNOT RESOLVE, and that is right HERE and wrong for a guard. A guard that could
# not check must say so, because something went unprotected. This one protects nothing: its whole
# product is advice, and announcing that no advice was available spends the reader's attention to
# report a non-event — which is how a channel gets skimmed, including on the turns it matters.
anchor="$PWD"
common="$(git rev-parse --git-common-dir 2>/dev/null)" || common=""
if [ -z "$common" ] && [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
  common="$(git -C "$CLAUDE_PROJECT_DIR" rev-parse --git-common-dir 2>/dev/null)" || common=""
  [ -n "$common" ] && anchor="$CLAUDE_PROJECT_DIR"
fi

root=""
if [ -n "$common" ]; then
  case "$common" in
    /*) ;;
     *) common="$anchor/$common" ;;
  esac
  root="$(cd "$(dirname "$common")" 2>/dev/null && pwd)" || root=""
else
  # #74: the hook lives in the project, so it can find a binary to ask even when cwd and the
  # harness both answer nothing. It locates a binary; WHICH repo that binary reads stays inside
  # util._root_anchors, the one resolver every entrypoint shares.
  root="$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)" || root=""
fi
[ -n "$root" ] || exit 0

for candidate in "$root/.showrunner_self/bin/showrunner" \
                 "$root/.showrunner/bin/showrunner" \
                 "$root/bin/showrunner"; do
  if [ -x "$candidate" ]; then
    # NOT `exec`, for the reason worktree-guard.sh gives: a binary that is FOUND and BROKEN
    # exits non-zero with empty stdout, and passing that through would turn a half-edited
    # showrunner into a hook error on every call.
    # FALL THROUGH TO THE NEXT CANDIDATE, never exit on the first one found. The pinned copy is
    # tried first on purpose (code a mid-edit cannot break) and is therefore the one most likely
    # to PREDATE a verb — measured here: .showrunner_self was pinned before `reach` existed, so
    # the first version of this loop found it, got exit 2, and went silent for every call. An
    # advisory channel that disappears wholesale when a pin is stale is worse than one that is
    # absent, because nothing distinguishes it from having no advice to give.
    out="$((cd "$root" && "$candidate" reach) 2>/dev/null)" || out=""
    if [ -n "$out" ]; then
      printf '%s\n' "$out"
      exit 0
    fi
  fi
done
exit 0
