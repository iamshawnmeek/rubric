#!/usr/bin/env bash
# Tests tool/release.sh against a throwaway clone with a bare "origin" and a
# fake curl on PATH, so nothing reaches GitHub or Codemagic. Run by
# tool/check.sh.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }

# A fake curl: logs its arguments and the header file's token line, then
# answers as $CURL_MODE says.
bin="$root/bin"; mkdir -p "$bin"
cat > "$bin/curl" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$root/curl.log"
for a in "\$@"; do case "\$a" in @*) grep -c '^x-auth-token: secret-token\$' "\${a#@}" >> "$root/token.log" ;; esac; done
case "\${CURL_MODE:-ok}" in
  ok) echo '{"buildId":"b123"}' ;;
  refused) echo '{"error":"nope"}'; exit 22 ;;
  empty) echo '{}' ;;
esac
EOF
chmod +x "$bin/curl"
export PATH="$bin:$PATH"

# A repo laid out like Rubric (tool/release.sh inside it), with a bare origin.
git init -q --bare "$root/origin.git"
git clone -q "$root/origin.git" "$root/repo" 2>/dev/null
repo="$root/repo"
mkdir -p "$repo/tool"
cp "$here/release.sh" "$repo/tool/release.sh"
printf 'secret-token\n' > "$root/token"
export CODEMAGIC_TOKEN_FILE="$root/token" CODEMAGIC_API="https://cm.test"
(
  cd "$repo"
  git config user.email t@t; git config user.name t
  git checkout -q -b main
  git add tool; git commit -qm init
  git push -q origin main
)
release() { (cd "$repo" && tool/release.sh "$@") > "$root/out" 2>&1; }
remote_tags() { git -C "$root/origin.git" tag; }

# Refusals: each must leave no tag behind and never call Codemagic.
refuses() {
  local name="$1"; shift
  if release "$@"; then bad "$name (it succeeded)"; return; fi
  if [ -n "$(remote_tags)" ] || [ -s "$root/curl.log" ]; then bad "$name (it tagged or called Codemagic)"; return; fi
  ok "$name"
}
refuses "a version that is not major.minor.patch is refused" 2.0
refuses "no version is refused"
echo dirty > "$repo/dirty"
refuses "a dirty working tree is refused" 2.0.3
rm "$repo/dirty"
(cd "$repo" && git checkout -q -b side)
refuses "a branch other than main is refused" 2.0.3
(cd "$repo" && git checkout -q main && git commit -q --allow-empty -m unpushed)
refuses "main ahead of origin is refused" 2.0.3
(cd "$repo" && git push -q origin main)
CODEMAGIC_TOKEN_FILE="$root/missing" refuses "a missing token is refused" 2.0.3

# The main path: the tag reaches origin and the build is started for it.
if release 2.0.3 \
  && [ "$(remote_tags)" = 2.0.3 ] \
  && grep -q 'https://cm.test/builds' "$root/curl.log" \
  && grep -q '"workflowId":"production-deploy","tag":"2.0.3"' "$root/curl.log" \
  && grep -q 'build b123 started' "$root/out"; then
  ok "a release pushes the tag and starts production-deploy for it"
else
  bad "a release pushes the tag and starts production-deploy for it"; cat "$root/out"
fi
if [ "$(cat "$root/token.log")" = 1 ] && ! grep -q secret-token "$root/curl.log"; then
  ok "the token goes in a header file, never on curl's command line"
else
  bad "the token goes in a header file, never on curl's command line"
fi

# An existing tag is refused before anything happens, whether only origin
# has it (another clone released) or only this clone does (a tag that was
# never pushed). Each case alone, so neither check can cover for the other.
tag_refused() {
  local name="$1"
  : > "$root/curl.log"
  if release 2.0.3 || [ -s "$root/curl.log" ] || ! grep -q 'tag 2.0.3 already exists' "$root/out"; then
    bad "$name"; cat "$root/out"
  else
    ok "$name"
  fi
}
(cd "$repo" && git tag -d 2.0.3 >/dev/null)
tag_refused "a tag only origin has is refused"
(cd "$repo" && git fetch -q --tags origin && git push -q origin :refs/tags/2.0.3)
tag_refused "a tag only this clone has is refused"

# Codemagic failures fail the run and say the tag is already out.
(cd "$repo" && git commit -q --allow-empty -m next && git push -q origin main)
if CURL_MODE=refused release 2.0.4; then bad "a refused build fails the run"
elif grep -q 'the tag is pushed, but Codemagic refused' "$root/out"; then ok "a refused build fails the run"
else bad "a refused build fails the run (wrong message)"; cat "$root/out"; fi
(cd "$repo" && git commit -q --allow-empty -m next2 && git push -q origin main)
if CURL_MODE=empty release 2.0.5; then bad "an answer with no buildId fails the run"
else ok "an answer with no buildId fails the run"; fi

[ "$fails" -eq 0 ] || { echo "test_release: $fails failed"; exit 1; }
echo "test_release: passed"
