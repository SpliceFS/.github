#!/bin/sh
# Prints the description of the pull request that moves the shared code from version <from> to
# <to>. Its change log is what the shared code's own CHANGELOG.md says for the versions in
# between, so a reader of the server or client change log sees what came in with the move.
set -eu

module='github.com/SpliceFS/common'

# $1 message. Every refusal here is a wrong call, so the status is always 2.
fail() {
    printf 'body: %s\n' "$1" >&2
    exit 2
}

# $1 value. The case guard comes first because grep works line by line and would accept a value
# that has a valid first line and more lines after it.
need_version() {
    case "$1" in
        *[!0-9.]*) fail "\"$1\" is not X.Y.Z" ;;
        *) ;;
    esac
    printf '%s\n' "$1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || fail "\"$1\" is not X.Y.Z"
}

if [ "$#" -ne 4 ]; then
    echo 'usage: body.sh <CHANGELOG.md> <from> <to> <scope>' >&2
    exit 2
fi
changelog="$1"
from="$2"
to="$3"
scope="$4"

need_version "$from"
need_version "$to"
case "$scope" in
    revision | minor) ;;
    *) fail "scope \"$scope\" is not revision or minor" ;;
esac
[ -f "$changelog" ] || fail "cannot read $changelog"

# A section is the lines after a heading "## [X.Y.Z] - YYYY-MM-DD" up to the next heading of
# level one or two. Other headings, such as "## [0.1.1 to 0.2.3]" or "## [Unreleased]", end the
# section before them and are not taken. Deeper headings and text that is not an entry are
# left out. An entry is a line that starts with "- " and the lines after it that start with two
# spaces, and those are printed as they are. The file lists the newest section first and the
# output keeps that order.
# shellcheck disable=SC2016
bullets="$(awk -v low="$from" -v high="$to" '
function newer(a, b,    x, y, i) {
    split(a, x, ".")
    split(b, y, ".")
    for (i = 1; i <= 3; i++) {
        if (x[i] + 0 > y[i] + 0) return 1
        if (x[i] + 0 < y[i] + 0) return 0
    }
    return 0
}
{
    probe = $0
    sub(/\r$/, "", probe)
    if (probe ~ /^##? /) {
        take = 0
        open = 0
        if (probe ~ /^## \[[0-9]+\.[0-9]+\.[0-9]+\] - [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][ \t]*$/) {
            version = probe
            sub(/^## \[/, "", version)
            sub(/\].*$/, "", version)
            take = newer(version, low) && !newer(version, high)
        }
        next
    }
    if (!take || probe ~ /^[ \t]*$/) next
    if ($0 ~ /^- /) {
        print
        open = 1
    } else if (open && $0 ~ /^  /) {
        print
    } else {
        open = 0
    }
}
' "$changelog")"

if [ -z "$bullets" ]; then
    bullets="- Internal: built with version $to of the shared code."
fi

printf '## What changes\n\n'
printf "Moves the shared code (\`%s\`) from version %s to %s. This\n" "$module" "$from" "$to"
printf 'pull request was opened automatically when that version was released.\n\n'
printf '## Change log\n\n%s\n\n' "$bullets"
printf '## Change scope\n\nchange_scope: %s\n' "$scope"
