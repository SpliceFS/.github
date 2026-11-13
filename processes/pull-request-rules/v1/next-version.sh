#!/bin/sh
# Prints the version that follows <current> for a pull request of the given scope. Major is not
# handled on purpose: a new major version is a new repository (see change-scope.sh), so this
# repository never produces one.
set -eu

fail() {
    printf 'next-version: %s\n' "$1" >&2
    exit 1
}

if [ "$#" -ne 2 ]; then
    echo 'usage: next-version.sh <current> <scope>' >&2
    exit 1
fi
current="$1"
scope="$2"

# The case guard comes first because grep works line by line and would accept a value that has
# a valid first line and more lines after it.
case "$current" in
    *[!0-9.]*) fail "\"$current\" is not X.Y.Z" ;;
esac
printf '%s\n' "$current" | grep -Eq '^(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*)){2}$' ||
    fail "\"$current\" is not X.Y.Z"

major="${current%%.*}"
rest="${current#*.}"
minor="${rest%%.*}"
revision="${rest#*.}"

case "$scope" in
    revision)
        revision=$((revision + 1))
        ;;
    minor)
        minor=$((minor + 1))
        revision=0
        ;;
    *)
        fail "scope \"$scope\" cannot be released from this repository"
        ;;
esac
printf '%s.%s.%s\n' "$major" "$minor" "$revision"
