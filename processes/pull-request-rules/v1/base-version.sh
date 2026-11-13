#!/bin/sh
# Prints the version a pull request is raised from, for the target branch <ref>: the higher of
# the file VERSION at <ref> and the highest release tag vX.Y.Z reachable from <ref>, or 0.0.0
# when neither exists. Run inside the repository.
#
# Both sources are read because either one can be missing or behind. A repository that has
# releases but no VERSION file yet would otherwise restart at 0.0.0 and collide with a tag, and
# a VERSION that was never released must not be lowered by an older tag. Only tags of exactly
# the form vX.Y.Z count: a tag with a suffix such as -rc.1 is not a release of this branch.
set -eu

fail() {
    printf 'base-version: %s\n' "$1" >&2
    exit 1
}

if [ "$#" -ne 1 ]; then
    echo 'usage: base-version.sh <ref>' >&2
    exit 1
fi
ref="$1"
git rev-parse --verify --quiet "$ref^{commit}" >/dev/null || fail "ref \"$ref\" does not exist"

number='(0|[1-9][0-9]*)'
pattern="$number(\\.$number){2}"

# The case guard comes first because grep works line by line and would accept a value that has
# a valid first line and more lines after it.
is_version() {
    case "$1" in
        *[!0-9.]*) return 1 ;;
    esac
    printf '%s\n' "$1" | grep -Eq "^$pattern\$"
}

# One version per line. 0.0.0 is always listed, so the result exists when nothing else does.
candidates() {
    echo 0.0.0
    if file="$(git show "$ref:VERSION" 2>/dev/null)" && is_version "$file"; then
        echo "$file"
    fi
    git tag --list 'v*' --merged "$ref" | grep -E "^v$pattern\$" | sed 's/^v//' || true
}

# Numeric per field, so 0.10.0 is higher than 0.9.0.
candidates | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1
