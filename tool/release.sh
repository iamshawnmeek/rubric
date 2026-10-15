#!/usr/bin/env bash
# Releases Rubric to both stores: tags main and starts Codemagic's
# production-deploy workflow for that tag.
#
#   tool/release.sh 2.0.3
#
# Why this starts the build itself: codemagic.yaml declares a tag trigger,
# but pushing a tag has never started a build for this app (it was created
# in Codemagic's workflow-editor flow). Every release from 2.0.0 on was
# started through Codemagic's API, by hand, so this script does that one
# way. If tag pushes ever start firing, `cancel_previous_builds` in the yaml
# keeps the duplicate from shipping twice.
#
# The API token is read from .contrib/codemagic/token (gitignored) and is
# passed to curl through a 0600 header file, so it never shows in `ps`.
# The version is the name users see; codemagic.yaml picks the build number
# from the stores. See docs/RELEASE.md.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
api="${CODEMAGIC_API:-https://api.codemagic.io}"
token_file="${CODEMAGIC_TOKEN_FILE:-$repo/.contrib/codemagic/token}"
remote="${RELEASE_REMOTE:-origin}"
app_id="6ac468dff0be487e13eb3bb4"
workflow="production-deploy"

die() { echo "release: $*" >&2; exit 1; }

version="${1:-}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "usage: tool/release.sh <major.minor.patch>, got '${version}'"
[ -s "$token_file" ] || die "no Codemagic token at $token_file"

cd "$repo"
[ "$(git symbolic-ref --short HEAD 2>/dev/null)" = main ] || die "release from main only"
[ -z "$(git status --porcelain)" ] || die "the working tree has changes; commit or stash them first"
git fetch -q "$remote" main
[ "$(git rev-parse HEAD)" = "$(git rev-parse "$remote/main")" ] \
  || die "main is not the same commit as $remote/main; push or pull first"
if git rev-parse -q --verify "refs/tags/$version" >/dev/null \
  || [ -n "$(git ls-remote --tags "$remote" "refs/tags/$version")" ]; then
  die "tag $version already exists"
fi

git tag "$version"
git push -q "$remote" "refs/tags/$version"
echo "release: tagged $version at $(git rev-parse --short HEAD) and pushed it"

headers="$(mktemp)"
trap 'rm -f "$headers"' EXIT
chmod 600 "$headers"
printf 'x-auth-token: %s\ncontent-type: application/json\n' "$(tr -d '\n' < "$token_file")" > "$headers"
body="{\"appId\":\"$app_id\",\"workflowId\":\"$workflow\",\"tag\":\"$version\"}"
if ! response="$(curl -sS --fail-with-body -X POST -H @"$headers" -d "$body" "$api/builds")"; then
  die "the tag is pushed, but Codemagic refused the build: $response
  rerun the build for tag $version from Codemagic, or fix the cause and POST $api/builds again"
fi
build_id="$(printf '%s' "$response" | sed -nE 's/.*"buildId" *: *"([^"]+)".*/\1/p')"
[ -n "$build_id" ] || die "the tag is pushed, but Codemagic's answer had no buildId: $response"
echo "release: Codemagic build $build_id started"
echo "  https://codemagic.io/app/$app_id/build/$build_id"
