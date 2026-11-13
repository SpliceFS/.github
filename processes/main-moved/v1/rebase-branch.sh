#!/bin/sh
# Rebuilds <branch> on top of <onto> without version commits, in a throwaway worktree. The branch
# ref moves only at the very end, so every failure leaves it exactly where it was. Never pushes.
set -eu

# $1 message, $2 exit status. Refusals go to standard error, results to standard output.
fail() {
    printf 'rebase: %s\n' "$1" >&2
    exit "$2"
}

if [ "$#" -ne 2 ]; then
    echo 'usage: rebase-branch.sh <branch> <onto>' >&2
    exit 1
fi
branch="$1"
onto="$2"
[ -n "${BOT_NAME:-}" ] || fail 'BOT_NAME is required' 1
[ -n "${BOT_EMAIL:-}" ] || fail 'BOT_EMAIL is required' 1

old="$(git rev-parse --verify --quiet "refs/heads/$branch^{commit}")" ||
    fail "branch \"$branch\" does not exist" 1
onto_commit="$(git rev-parse --verify --quiet "$onto^{commit}")" ||
    fail "\"$onto\" does not exist" 1
short="$(git rev-parse --short "$onto_commit")"
range="$onto_commit..$old"

# The trailer is read the way git reads it, so a look-alike line inside the body does not count.
is_version_commit() {
    git log -1 --format=%B "$1" | git interpret-trailers --only-trailers |
        grep -qx 'Version-Commit: true'
}

picks=""
has_version_commit=0
for c in $(git rev-list --reverse "$range"); do
    if is_version_commit "$c"; then
        has_version_commit=1
    else
        picks="$picks $c"
    fi
done

base="$(git merge-base "$onto_commit" "$old" || true)"
if [ "$has_version_commit" -eq 0 ] && [ "$base" = "$onto_commit" ]; then
    echo 'rebase: up to date'
    exit 0
fi

[ -z "$(git rev-list --merges "$range")" ] ||
    fail "$branch has merge commits; rebase it by hand" 2

# git itself refuses to move a checked-out branch under a working tree, and so do we.
if git worktree list --porcelain | grep -Fqx "branch refs/heads/$branch"; then
    fail "$branch is checked out in a worktree; check out another branch first" 4
fi

tmp="$(mktemp -d)"
cleanup() {
    git worktree remove --force "$tmp/wt" >/dev/null 2>&1 || true
    rm -rf "$tmp"
    git worktree prune
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
git worktree add -q --detach "$tmp/wt" "$onto_commit"

wt() {
    git -C "$tmp/wt" -c user.name="$BOT_NAME" -c user.email="$BOT_EMAIL" \
        -c commit.gpgsign=false "$@"
}

n=0
for c in $picks; do
    if ! wt cherry-pick -n "$c" >/dev/null 2>&1; then
        fail "conflict in $(git log -1 --format=%s "$c")" 3
    fi
    # A change that <onto> already has leaves nothing staged; committing it would only add noise.
    if wt diff --cached --quiet; then
        continue
    fi
    # -C keeps author, date and message; the committer is the bot because of the -c options.
    wt commit -q --no-verify -C "$c"
    n=$((n + 1))
done

new="$(wt rev-parse HEAD)"
# The old value is passed so a branch that moved while we worked is not overwritten.
git update-ref -m "rebase onto $onto" "refs/heads/$branch" "$new" "$old"
echo "rebase: rebuilt on $short, $n commits"
