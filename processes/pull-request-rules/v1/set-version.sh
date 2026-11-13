#!/bin/sh
# Makes VERSION on a pull request branch hold the version that follows the base version of the
# target branch (see base-version.sh) for the given scope, as a commit of its own. It commits
# locally and never pushes, so the caller decides when and how the result is published.
set -eu

fail() {
    printf 'set-version: %s\n' "$1" >&2
    exit 1
}

if [ "$#" -ne 1 ]; then
    echo 'usage: set-version.sh <scope>' >&2
    exit 1
fi
scope="$1"

# Checked before any git work so a missing identity is reported even when nothing needs committing.
[ -n "${BOT_NAME:-}" ] || fail 'BOT_NAME is required'
[ -n "${BOT_EMAIL:-}" ] || fail 'BOT_EMAIL is required'
base_ref="${BASE_REF:-origin/main}"

# The sibling scripts are found by this script's own directory so any working directory works.
here="$(cd "$(dirname "$0")" && pwd)"
top="$(git rev-parse --show-toplevel)" || fail 'not inside a git repository'
cd "$top"

git rev-parse --verify --quiet "$base_ref^{commit}" >/dev/null ||
    fail "base ref \"$base_ref\" does not exist"
base="$(sh "$here/base-version.sh" "$base_ref")"
if ! wanted="$(sh "$here/next-version.sh" "$base" "$scope" 2>&1)"; then
    printf '%s\n' "$wanted" >&2
    exit 1
fi

# Untracked files are ignored: the commit below names VERSION only, so they cannot leak into it.
# VERSION itself is excluded because it is rewritten anyway.
if [ -n "$(git status --porcelain --untracked-files=no -- . ':(exclude)VERSION')" ]; then
    fail 'the working tree has uncommitted changes besides VERSION'
fi

# Writing first and comparing the index with HEAD makes "unchanged" a byte for byte statement
# about what is committed, whatever the file held before.
printf '%s\n' "$wanted" >VERSION
git add VERSION
if git cat-file -e HEAD:VERSION 2>/dev/null && git diff --cached --quiet -- VERSION; then
    echo "version: $wanted (unchanged)"
    exit 0
fi

# Two -m options make the trailer its own paragraph, which is where git looks for trailers.
git -c user.name="$BOT_NAME" -c user.email="$BOT_EMAIL" -c commit.gpgsign=false \
    commit -q --no-verify -m "Set version to $wanted" -m 'Version-Commit: true' -- VERSION
echo "version: $wanted (committed)"
