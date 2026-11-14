#!/bin/sh
# Reads the version of github.com/SpliceFS/common that a go.mod names and says how big the
# change is that moves it to <new version>: none, revision or minor. The server and the client
# each follow the shared code; the workflow that opens their pull requests needs the size
# before it writes the description. Major is not handled: a new major version is a new
# repository (see change-scope.sh), so it counts as minor here and the pull request will fail
# its own checks if that ever happens.
set -eu

module='github.com/SpliceFS/common'

# $1 exit status, $2 message. 2 means the call was wrong, 1 means the go.mod is not as expected.
fail() {
    printf 'plan: %s\n' "$2" >&2
    exit "$1"
}

if [ "$#" -ne 2 ]; then
    echo 'usage: plan.sh <go.mod> <new version>' >&2
    exit 2
fi
gomod="$1"
new="$2"

# The case guard comes first because grep works line by line and would accept a value that has
# a valid first line and more lines after it.
case "$new" in
    *[!0-9.]*) fail 2 "\"$new\" is not X.Y.Z" ;;
    *) ;;
esac
printf '%s\n' "$new" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' ||
    fail 2 "\"$new\" is not X.Y.Z"

[ -f "$gomod" ] || fail 2 "cannot read $gomod"

# Only the require lines count. A replace or exclude block can name the same module, and a
# comment can too, and neither one is the version the code is built with. The version comment
# "// indirect" is cut off before the line is split into words.
# shellcheck disable=SC2016
found="$(awk -v module="$module" '
{
    sub(/\r$/, "")
    sub(/[ \t]*\/\/.*$/, "")
    if (NF > 0) $1 = $1
    if (block != "") {
        if ($1 == ")") { block = ""; next }
        if (block != "require") next
        entry = $0
    } else if (NF >= 2 && $NF == "(") {
        block = $1
        next
    } else if ($1 == "require") {
        entry = $0
        sub(/^require /, "", entry)
    } else {
        next
    }
    split(entry, word, " ")
    if (word[1] == module) print entry
}
' "$gomod")"

case "$found" in
    '') fail 1 "$gomod has no require line for $module" ;;
    *'
'*) fail 1 "$gomod has more than one require line for $module" ;;
    *) ;;
esac
printf '%s\n' "$found" | grep -Eq "^$module v[0-9]+\.[0-9]+\.[0-9]+\$" ||
    fail 1 "$gomod does not give $module a version vX.Y.Z: \"$found\""
current="${found##* v}"

cur_major="${current%%.*}"
rest="${current#*.}"
cur_minor="${rest%%.*}"
cur_revision="${rest#*.}"
new_major="${new%%.*}"
rest="${new#*.}"
new_minor="${rest%%.*}"
new_revision="${rest#*.}"

# Compared with test -gt, which reads 09 as nine, where $(( )) would read it as octal.
newer=0
if [ "$new_major" -gt "$cur_major" ]; then
    newer=1
elif [ "$new_major" -eq "$cur_major" ]; then
    if [ "$new_minor" -gt "$cur_minor" ]; then
        newer=1
    elif [ "$new_minor" -eq "$cur_minor" ] && [ "$new_revision" -gt "$cur_revision" ]; then
        newer=1
    fi
fi

if [ "$newer" -eq 0 ]; then
    scope=none
elif [ "$new_major" -ne "$cur_major" ] || [ "$new_minor" -ne "$cur_minor" ]; then
    scope=minor
else
    scope=revision
fi
printf 'from=%s\nscope=%s\n' "$current" "$scope"
