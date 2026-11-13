#!/bin/sh
# Fails, naming the files, when a shell script under processes/ is not stored in git as mode
# 100755. A script stored without the executable bit fails in a workflow with "Permission
# denied", and a checkout on a Mac does not show it, so this reads the index.
set -eu

top="$(git rev-parse --show-toplevel)" || {
    echo 'check-modes: not inside a git repository' >&2
    exit 1
}
cd "$top"

bad="$(git ls-files -s -- processes |
    awk -F'\t' '$2 ~ /\.sh$/ && substr($1, 1, 6) != "100755" { print $2 }')"
if [ -n "$bad" ]; then
    printf 'check-modes: not mode 100755 in git (run git update-index --chmod=+x on them):\n%s\n' \
        "$bad" >&2
    exit 1
fi
echo 'check-modes: every script under processes is 100755'
