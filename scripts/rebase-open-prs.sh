#!/bin/sh
# Rebuilds every open pull request of a repository on the tip of its target branch and
# pushes the result, so that each one always looks as if it had been started from the tip.
# Run inside a full clone whose origin can be pushed to, with GH_TOKEN set for gh.
#
#   rebase-open-prs.sh <owner/repo> <target branch>
#
# The git work is done by rebase-branch.sh, which is tested on its own. This script only
# lists the pull requests, pushes, and tells the author when a branch needs their hands.
set -eu

[ $# -eq 2 ] || { echo "usage: rebase-open-prs.sh <owner/repo> <target branch>" >&2; exit 1; }
repo="$1"
base="$2"
here="$(cd "$(dirname "$0")" && pwd)"
failed=0

git fetch --quiet origin "+refs/heads/$base:refs/remotes/origin/$base"

# One line per pull request: number, head branch, head repository. A pull request from a
# fork is skipped: the bot cannot push there, and its version check asks the author instead.
gh pr list --repo "$repo" --base "$base" --state open --limit 200 \
    --json number,headRefName,headRepository,headRepositoryOwner \
    --jq '.[] | "\(.number) \(.headRefName) \(.headRepositoryOwner.login)/\(.headRepository.name)"' |
while read -r number branch head_repo; do
    if [ "$head_repo" != "$repo" ]; then
        echo "#$number: from a fork ($head_repo), skipped"
        continue
    fi
    git fetch --quiet origin "+refs/heads/$branch:refs/heads/$branch"
    before="$(git rev-parse "refs/heads/$branch")"
    status=0
    out="$("$here/rebase-branch.sh" "$branch" "origin/$base" 2>&1)" || status=$?
    echo "#$number ($branch): $out"
    case "$status" in
        0)
            after="$(git rev-parse "refs/heads/$branch")"
            if [ "$after" != "$before" ]; then
                # The lease makes the push fail, and not overwrite, if the author pushed
                # in the meantime. Their push starts the checks, which sets things right.
                git push --quiet --force-with-lease="refs/heads/$branch:$before" origin \
                    "refs/heads/$branch:refs/heads/$branch" ||
                    echo "#$number ($branch): changed while it was rebuilt; left as it is"
            fi
            ;;
        2 | 3)
            gh pr comment "$number" --repo "$repo" --body \
                "\`$base\` moved and this branch could not be rebuilt on it automatically: $out. Rebase it on \`$base\` by hand and push; the checks then set the version again." \
                >/dev/null || true
            ;;
        *)
            # An unexpected failure must be seen, but must not stop the other pull requests.
            echo "::error::#$number ($branch): $out"
            echo "$number" >> "${TMPDIR:-/tmp}/rebase-open-prs.failed"
            ;;
    esac
done

if [ -s "${TMPDIR:-/tmp}/rebase-open-prs.failed" ]; then
    failed=1
    rm -f "${TMPDIR:-/tmp}/rebase-open-prs.failed"
fi
exit "$failed"
