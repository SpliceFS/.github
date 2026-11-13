#!/bin/sh
# Test of set-version.sh in throwaway git repositories: first version, revision and minor,
# unchanged, correcting a wrong committed value, and every refusal. Part of make check.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/set-version.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failed=0

pass() { printf 'ok   %s\n' "$1"; }
fail() {
    printf 'FAIL %s\n' "$1"
    failed=$((failed + 1))
}
# $1 label, $2 wanted, $3 got.
eq() {
    if [ "$2" = "$3" ]; then pass "$1"; else fail "$1: want \"$2\" got \"$3\""; fi
}

# Explicit identity so the test never depends on the machine's git configuration.
tg() { git -c user.name=Dev -c user.email=dev@example.com -c commit.gpgsign=false "$@"; }

# $1 repository name, $2 VERSION on the base branch (empty for no file). Leaves the shell inside
# the new repository on branch pr, one commit after origin/main.
newrepo() {
    rm -rf "${work:?}/$1"
    mkdir "$work/$1"
    cd "$work/$1"
    git init -q 2>/dev/null
    git symbolic-ref HEAD refs/heads/main
    echo hello >README
    if [ -n "$2" ]; then echo "$2" >VERSION; fi
    git add -A
    tg commit -q -m Base
    git update-ref refs/remotes/origin/main HEAD
    git checkout -q -b pr
    echo work >feature.txt
    git add feature.txt
    tg commit -q -m Feature
}

# $1 label, $2 wanted message; judges the rc and out of the last run, which must be a refusal.
refused() {
    if [ "$rc" -ne 0 ]; then eq "$1" "$2" "$out"; else fail "$1: accepted: $out"; fi
}

# Runs the script with the bot identity; sets rc and out.
sv() {
    rc=0
    out="$(BOT_NAME=Bot BOT_EMAIL=bot@example.com sh "$script" "$@" 2>&1)" || rc=$?
}

# $1 label, $2 wanted output, then the arguments.
expect_ok() {
    label="$1"
    want="$2"
    shift 2
    sv "$@"
    if [ "$rc" -eq 0 ]; then eq "$label" "$want" "$out"; else fail "$label: refused: $out"; fi
}

# $1 label, $2 wanted message, then the arguments.
expect_refused() {
    label="$1"
    want="$2"
    shift 2
    sv "$@"
    if [ "$rc" -ne 0 ]; then eq "$label" "$want" "$out"; else fail "$label: accepted: $out"; fi
}

newrepo first ''
expect_ok 'no VERSION on base, minor' 'version: 0.1.0 (committed)' minor
eq 'file holds the version' 0.1.0 "$(cat VERSION)"
eq 'commit subject' 'Set version to 0.1.0' "$(git log -1 --format=%s)"
eq 'trailer present' 'Version-Commit: true' \
    "$(git log -1 --format=%B | git interpret-trailers --only-trailers)"
eq 'commit author is the bot' 'Bot <bot@example.com>' "$(git log -1 --format='%an <%ae>')"
eq 'commit committer is the bot' 'Bot <bot@example.com>' "$(git log -1 --format='%cn <%ce>')"
eq 'only VERSION is in the commit' VERSION "$(git show --name-only --format= HEAD)"
expect_ok 'second run is unchanged' 'version: 0.1.0 (unchanged)' minor
eq 'unchanged adds no commit' 2 "$(git rev-list --count origin/main..HEAD)"

newrepo first-revision ''
expect_ok 'no VERSION on base, revision' 'version: 0.0.1 (committed)' revision

newrepo revision 1.2.3
expect_ok 'revision from 1.2.3' 'version: 1.2.4 (committed)' revision
newrepo minor 1.2.3
expect_ok 'minor from 1.2.3' 'version: 1.3.0 (committed)' minor
newrepo carry 1.9.9
expect_ok 'minor from 1.9.9' 'version: 1.10.0 (committed)' minor

newrepo wrong 1.2.3
echo 9.9.9 >VERSION
git add VERSION
tg commit -q -m 'Wrong version'
expect_ok 'wrong committed value is corrected' 'version: 1.2.4 (committed)' revision
eq 'corrected file' 1.2.4 "$(cat VERSION)"
eq 'working tree clean after correction' '' "$(git status --porcelain)"
expect_ok 'unchanged after correction' 'version: 1.2.4 (unchanged)' revision

newrepo scope-changed 1.2.3
expect_ok 'first scope' 'version: 1.2.4 (committed)' revision
expect_ok 'changed scope is corrected' 'version: 1.3.0 (committed)' minor

newrepo uncommitted 1.2.3
echo 1.2.4 >VERSION
expect_ok 'wanted but uncommitted value is committed' 'version: 1.2.4 (committed)' revision
eq 'that commit holds VERSION' VERSION "$(git show --name-only --format= HEAD)"
eq 'nothing left uncommitted' '' "$(git status --porcelain)"

newrepo staged-version 1.2.3
echo 1.2.4 >VERSION
git add VERSION
expect_ok 'staged wanted value is committed' 'version: 1.2.4 (committed)' revision
eq 'staged commit made' 'Set version to 1.2.4' "$(git log -1 --format=%s)"

newrepo untracked 1.2.3
echo scratch >scratch.txt
expect_ok 'untracked file does not block' 'version: 1.2.4 (committed)' revision
eq 'untracked file stays out of the commit' VERSION "$(git show --name-only --format= HEAD)"
eq 'untracked file is still there' '?? scratch.txt' "$(git status --porcelain)"

newrepo dirty 1.2.3
echo changed >feature.txt
before="$(git rev-parse HEAD)"
expect_refused 'dirty tree is refused' \
    'set-version: the working tree has uncommitted changes besides VERSION' revision
eq 'dirty tree: no commit' "$before" "$(git rev-parse HEAD)"
eq 'dirty tree: VERSION untouched' 1.2.3 "$(cat VERSION)"
eq 'dirty tree: change kept' changed "$(cat feature.txt)"

newrepo staged 1.2.3
echo changed >feature.txt
git add feature.txt
expect_refused 'staged change is refused' \
    'set-version: the working tree has uncommitted changes besides VERSION' revision

newrepo ident 1.2.3
before="$(git rev-parse HEAD)"
rc=0
out="$(BOT_EMAIL=bot@example.com sh "$script" revision 2>&1)" || rc=$?
refused 'missing BOT_NAME is refused' 'set-version: BOT_NAME is required'
rc=0
out="$(BOT_NAME=Bot sh "$script" revision 2>&1)" || rc=$?
refused 'missing BOT_EMAIL is refused' 'set-version: BOT_EMAIL is required'
rc=0
out="$(BOT_NAME='' BOT_EMAIL='' sh "$script" revision 2>&1)" || rc=$?
refused 'empty identity is refused' 'set-version: BOT_NAME is required'
eq 'identity refusal: no commit' "$before" "$(git rev-parse HEAD)"

newrepo override 1.2.3
git update-ref refs/remotes/origin/release HEAD
git checkout -q -b release-base
echo 5.0.0 >VERSION
tg commit -q -a -m 'Release base'
git update-ref refs/remotes/origin/release HEAD
git checkout -q pr
rc=0
out="$(BASE_REF=origin/release BOT_NAME=Bot BOT_EMAIL=bot@example.com sh "$script" minor 2>&1)" ||
    rc=$?
eq 'BASE_REF is honored' 'version: 5.1.0 (committed)' "$out"

newrepo no-base 1.2.3
rc=0
out="$(BASE_REF=origin/nope BOT_NAME=Bot BOT_EMAIL=bot@example.com sh "$script" revision 2>&1)" ||
    rc=$?
eq 'unknown BASE_REF is refused' 'set-version: base ref "origin/nope" does not exist' "$out"

newrepo bad-base 'v1.2'
expect_ok 'invalid base VERSION is ignored' 'version: 0.0.1 (committed)' revision

newrepo tag-only ''
git tag v2.3.4 origin/main
expect_ok 'release tag without a VERSION file is the base' 'version: 2.3.5 (committed)' revision

newrepo tag-higher 1.2.3
git tag v1.4.0 origin/main
expect_ok 'release tag higher than VERSION is the base' 'version: 1.5.0 (committed)' minor

newrepo file-higher 1.5.0
git tag v1.4.0 origin/main
expect_ok 'VERSION higher than the release tag is the base' 'version: 1.5.1 (committed)' revision

newrepo tag-suffix 1.2.3
git tag v1.9.0-rc.1 origin/main
expect_ok 'tag with a suffix is ignored' 'version: 1.2.4 (committed)' revision

newrepo bad-scope 1.2.3
expect_refused 'bad scope is refused' \
    'next-version: scope "major" cannot be released from this repository' major

newrepo subdir 1.2.3
mkdir deep
cd deep
expect_ok 'works from a subdirectory' 'version: 1.2.4 (committed)' revision
eq 'subdirectory run writes the top VERSION' 1.2.4 "$(cat ../VERSION)"
cd "$work/subdir"
eq 'no stray VERSION in the subdirectory' no "$([ -e deep/VERSION ] && echo yes || echo no)"

newrepo usage 1.2.3
rc=0
out="$(sh "$script" 2>&1)" || rc=$?
refused 'no arguments print usage' 'usage: set-version.sh <scope>'

cd "$here"
[ "$failed" -eq 0 ] || { echo "$failed failed"; exit 1; }
echo "set version: all checks as expected"
