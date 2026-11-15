#!/bin/sh
# Test of base-version.sh in throwaway git repositories: which of VERSION and the release tags
# wins, numeric comparison, and which tags and VERSION contents are ignored. Part of make check.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/base-version.sh"
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

# $1 repository name, $2 VERSION content on main (empty for no file). Leaves the shell inside the
# new repository on branch main, one commit, with no tags.
newrepo() {
    rm -rf "${work:?}/$1"
    mkdir "$work/$1"
    cd "$work/$1"
    git init -q 2>/dev/null
    git symbolic-ref HEAD refs/heads/main
    echo hello >README
    if [ -n "$2" ]; then printf '%s\n' "$2" >VERSION; fi
    git add -A
    tg commit -q -m Base
}

# $1 label, $2 wanted version, $3 ref (default main): the version printed for the ref.
expect() {
    rc=0
    out="$(sh "$script" "${3:-main}" 2>&1)" || rc=$?
    if [ "$rc" -eq 0 ]; then eq "$1" "$2" "$out"; else fail "$1: refused: $out"; fi
}

# $1 label, $2 wanted message, then the arguments.
expect_refused() {
    label="$1"
    want="$2"
    shift 2
    rc=0
    out="$(sh "$script" "$@" 2>&1)" || rc=$?
    if [ "$rc" -ne 0 ]; then eq "$label" "$want" "$out"; else fail "$label: accepted: $out"; fi
}

newrepo neither ''
expect 'no file and no tag' 0.0.0

newrepo file-only 1.2.3
expect 'file only' 1.2.3

newrepo tag-only ''
git tag v1.4.0
expect 'tag only' 1.4.0

newrepo tag-annotated ''
tg tag -a -m Release v1.4.0
expect 'annotated tag' 1.4.0

newrepo tag-higher 1.2.3
git tag v1.3.0
expect 'tag higher than the file' 1.3.0

newrepo file-higher 1.5.0
git tag v1.3.0
expect 'file higher than the tag' 1.5.0

newrepo equal 1.3.0
git tag v1.3.0
expect 'file equal to the tag' 1.3.0

newrepo many-tags ''
git tag v1.2.0
git tag v1.10.0
git tag v1.9.0
expect 'highest of several tags, numerically' 1.10.0

newrepo ten-file 0.10.0
git tag v0.9.0
expect '0.10.0 in the file against 0.9.0 in a tag' 0.10.0

newrepo ten-tag 0.9.0
git tag v0.10.0
expect '0.10.0 in a tag against 0.9.0 in the file' 0.10.0

newrepo ten-patch 1.0.9
git tag v1.0.10
expect 'third field is numeric too' 1.0.10

newrepo ten-major 9.9.9
git tag v10.0.0
expect 'first field is numeric too' 10.0.0

newrepo suffix 0.2.0
git tag v0.3.0-rc.1
expect 'tag with a suffix is ignored' 0.2.0
newrepo suffix-only ''
git tag v0.3.0-rc.1
expect 'tag with a suffix alone gives 0.0.0' 0.0.0

newrepo other-tags ''
git tag 1.9.0
git tag v1.8
git tag v01.2.3
git tag release-1.7.0
git tag v1.2.3.4
expect 'tags not of the form vX.Y.Z are ignored' 0.0.0

newrepo unreachable 1.0.0
git checkout -q -b side
echo more >more.txt
git add more.txt
tg commit -q -m Side
git tag v2.0.0
git checkout -q main
expect 'tag on a commit the ref does not contain is ignored' 1.0.0
expect 'the same tag counts from the branch that has it' 2.0.0 side

newrepo older 1.0.0
git tag v1.1.0
echo more >more.txt
git add more.txt
tg commit -q -m Later
expect 'tag on an older commit of the ref counts' 1.1.0

newrepo ref-file 1.0.0
git checkout -q -b pr
echo 3.0.0 >VERSION
git add VERSION
tg commit -q -m 'Raise on the branch'
git checkout -q main
echo 4.0.0 >VERSION
expect 'VERSION is read from the ref, not from the working tree' 1.0.0
expect 'VERSION of another ref' 3.0.0 pr

for bad in 'v1.2' '1.2' '1.2.3-rc.1' '1.2.3.4' '01.2.3' 'abc' ' 1.2.3' '1.2.3 ' '1.2.3
4.5.6'; do
    newrepo bad-file "$bad"
    expect "invalid VERSION is ignored: $(printf '%s' "$bad" | tr '\n' '|')" 0.0.0
    git tag v1.1.0
    expect "invalid VERSION does not hide a tag: $(printf '%s' "$bad" | tr '\n' '|')" 1.1.0
done

newrepo empty-file ''
: >VERSION
git add VERSION
tg commit -q -m 'Empty VERSION'
expect 'empty VERSION is ignored' 0.0.0

newrepo usage 1.2.3
expect_refused 'no argument prints usage' 'usage: base-version.sh <ref>'
expect_refused 'two arguments print usage' 'usage: base-version.sh <ref>' main main
expect_refused 'unknown ref is refused' 'base-version: ref "nope" does not exist' nope

cd "$here"
[ "$failed" -eq 0 ] || { echo "$failed failed"; exit 1; }
echo "base version: all versions as expected"
