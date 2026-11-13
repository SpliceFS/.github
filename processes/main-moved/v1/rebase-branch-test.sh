#!/bin/sh
# Test of rebase-branch.sh in throwaway git repositories: up to date, rebuilt after the
# base moved, version commits dropped, conflicts, merge commits and commits the base already has.
# Part of make check.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/rebase-branch.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failed=0
# The script's own scratch folder goes here so a leftover can be seen.
mkdir "$work/tmp"

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

# $1 file, $2 content, $3 subject, $4 author "Name <email>" (default Dev): one commit.
commit_file() {
    printf '%s\n' "$2" >"$1"
    git add "$1"
    tg commit -q -m "$3" --author="${4:-Dev <dev@example.com>}"
}

# Version commit as the bot makes them.
version_commit() {
    echo "$1" >VERSION
    git add VERSION
    git -c user.name=Bot -c user.email=bot@example.com commit -q -m "Set version to $1" \
        -m 'Version-Commit: true'
}

# $1 repository name. Leaves the shell inside a repository with main at one commit.
newrepo() {
    rm -rf "${work:?}/$1"
    mkdir "$work/$1"
    cd "$work/$1"
    git init -q 2>/dev/null
    git symbolic-ref HEAD refs/heads/main
    commit_file a.txt one Base
}

# Runs the script with the bot identity; sets rc and out.
rb() {
    rc=0
    out="$(TMPDIR="$work/tmp" BOT_NAME=Bot BOT_EMAIL=bot@example.com sh "$script" "$@" 2>&1)" ||
        rc=$?
}

# After every run: no worktree registered besides the main one, no scratch folder, clean status.
tidy() {
    eq "$1: no leftover worktree" 1 "$(git worktree list | wc -l | tr -d ' ')"
    eq "$1: no leftover scratch folder" '' "$(ls -A "$work/tmp")"
    eq "$1: git status clean" '' "$(git status --porcelain)"
}

# A branch pr with two real commits around a version commit, forked from main; the caller stands
# on branch other.
fork() {
    newrepo "$1"
    git checkout -q -b pr
    commit_file b.txt bee 'Add b' 'Alice <alice@example.com>'
    version_commit 0.1.0
    printf 'Add c\n\nBody of c.\n' >msg
    echo cee >c.txt
    git add c.txt
    tg commit -q -F msg --author='Bob <bob@example.com>'
    rm msg
    git checkout -q main
    git checkout -q -b other
}

fork behind
git checkout -q main
commit_file d.txt dee 'Move main'
git checkout -q other
echo scratch >scratch.txt
other_tip="$(git rev-parse other)"
old_pr="$(git rev-parse pr)"
rb pr main
short="$(git rev-parse --short main)"
eq 'rebuilt after the base moved' "rebase: rebuilt on $short, 2 commits" "$out"
eq 'status 0' 0 "$rc"
eq 'commits in order, authors kept' 'Add b|Alice|Add c|Bob|' \
    "$(git log --reverse --format='%s|%an|' main..pr | tr -d '\n')"
eq 'main is the parent chain base' "$(git rev-parse main)" "$(git merge-base main pr)"
eq 'version commit dropped' '' "$(git log --grep='Version-Commit' --format=%H main..pr)"
eq 'message body kept' 'Body of c.' "$(git log -1 --format=%b pr | sed '/^$/d')"
eq 'committer is the bot' 'Bot <bot@example.com>' "$(git log -1 --format='%cn <%ce>' pr)"
eq 'all files present' 'a.txt b.txt c.txt d.txt' "$(git ls-tree --name-only pr | tr '\n' ' ' |
    sed 's/ $//')"
eq 'VERSION is gone from the branch' no "$(git cat-file -e pr:VERSION 2>/dev/null &&
    echo yes || echo no)"
eq 'old tip is not the new tip' no "$([ "$old_pr" = "$(git rev-parse pr)" ] && echo yes || echo no)"
eq 'caller branch untouched' "$other_tip" "$(git rev-parse other)"
eq 'caller still on its branch' other "$(git branch --show-current)"
eq 'caller files untouched' '?? scratch.txt' "$(git status --porcelain)"
rm scratch.txt
tidy 'rebuilt'

rb pr main
eq 'second run is up to date' 'rebase: up to date' "$out"
eq 'up to date status 0' 0 "$rc"
before="$(git rev-parse pr)"
eq 'up to date leaves the branch' "$(git rev-parse pr)" "$before"
tidy 'up to date'

newrepo same-tip
git branch pr
rb pr main
eq 'branch equal to onto is up to date' 'rebase: up to date' "$out"

fork ahead
git checkout -q other
rb pr main
eq 'version commit with a current base is rebuilt' \
    "rebase: rebuilt on $(git rev-parse --short main), 2 commits" "$out"
eq 'version commit gone' '' "$(git log --grep='Version-Commit' --format=%H main..pr)"
tidy 'version only'

newrepo only-version
git checkout -q -b pr
version_commit 0.0.1
git checkout -q main
git checkout -q -b other
rb pr main
eq 'only a version commit leaves 0 commits' \
    "rebase: rebuilt on $(git rev-parse --short main), 0 commits" "$out"
eq 'branch equals onto' "$(git rev-parse main)" "$(git rev-parse pr)"

newrepo conflict
git checkout -q -b pr
commit_file a.txt 'pr side' 'Change a in pr'
commit_file e.txt eee 'After the conflict'
git checkout -q main
commit_file a.txt 'main side' 'Change a in main'
git checkout -q -b other
before="$(git rev-parse pr)"
rb pr main
eq 'conflict message' 'rebase: conflict in Change a in pr' "$out"
eq 'conflict status' 3 "$rc"
eq 'conflict leaves the branch' "$before" "$(git rev-parse pr)"
tidy 'conflict'
eq 'conflict leaves the caller branch' other "$(git branch --show-current)"

newrepo merge
git checkout -q -b pr
commit_file b.txt bee 'Add b'
git checkout -q -b side main
commit_file s.txt ess 'Side work'
git checkout -q pr
tg merge -q --no-ff side -m 'Merge side' >/dev/null
git checkout -q main
commit_file d.txt dee 'Move main'
git checkout -q -b other
before="$(git rev-parse pr)"
rb pr main
eq 'merge commit message' 'rebase: pr has merge commits; rebase it by hand' "$out"
eq 'merge commit status' 2 "$rc"
eq 'merge commit leaves the branch' "$before" "$(git rev-parse pr)"
tidy 'merge commit'

newrepo already
git checkout -q -b pr
commit_file b.txt bee 'Add b'
git checkout -q main
commit_file d.txt dee 'Move main'
tg cherry-pick pr >/dev/null
git checkout -q -b other
rb pr main
eq 'commits already in onto vanish' \
    "rebase: rebuilt on $(git rev-parse --short main), 0 commits" "$out"
eq 'branch equals onto after vanishing' "$(git rev-parse main)" "$(git rev-parse pr)"
tidy 'already in onto'

newrepo partial
git checkout -q -b pr
commit_file b.txt bee 'Add b'
commit_file c.txt cee 'Add c'
git checkout -q main
commit_file d.txt dee 'Move main'
tg cherry-pick pr~1 >/dev/null
git checkout -q -b other
rb pr main
eq 'only the missing commit is kept' \
    "rebase: rebuilt on $(git rev-parse --short main), 1 commits" "$out"
eq 'kept commit' 'Add c' "$(git log -1 --format=%s pr)"
eq 'one commit above onto' 1 "$(git rev-list --count main..pr)"

newrepo checked-out
git checkout -q -b pr
commit_file b.txt bee 'Add b'
git checkout -q main
commit_file d.txt dee 'Move main'
git checkout -q pr
before="$(git rev-parse pr)"
rb pr main
eq 'checked out branch is refused' \
    'rebase: pr is checked out in a worktree; check out another branch first' "$out"
eq 'checked out status' 4 "$rc"
eq 'checked out branch is untouched' "$before" "$(git rev-parse pr)"
tidy 'checked out'

newrepo identity
git checkout -q -b pr
commit_file b.txt bee 'Add b'
git checkout -q main
commit_file d.txt dee 'Move main'
git checkout -q -b other
rc=0
out="$(BOT_EMAIL=bot@example.com sh "$script" pr main 2>&1)" || rc=$?
eq 'missing BOT_NAME is refused' 'rebase: BOT_NAME is required' "$out"
rc=0
out="$(BOT_NAME=Bot sh "$script" pr main 2>&1)" || rc=$?
eq 'missing BOT_EMAIL is refused' 'rebase: BOT_EMAIL is required' "$out"
eq 'identity refusal leaves the branch' 1 "$(git rev-list --count main..pr)"
eq 'identity refusal leaves the base unmerged' no \
    "$(git merge-base --is-ancestor main pr && echo yes || echo no)"

rb nope main
eq 'unknown branch is refused' 'rebase: branch "nope" does not exist' "$out"
rb pr nope
eq 'unknown onto is refused' 'rebase: "nope" does not exist' "$out"
rb pr
eq 'one argument prints usage' 'usage: rebase-branch.sh <branch> <onto>' "$out"
rb
eq 'no arguments print usage' 'usage: rebase-branch.sh <branch> <onto>' "$out"

cd "$here"
[ "$failed" -eq 0 ] || { echo "$failed failed"; exit 1; }
echo "rebase branch: all checks as expected"
