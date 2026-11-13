#!/bin/sh
# Reads a pull request description on standard input and prints its declared change scope. The
# scope decides the next version (see next-version.sh), so every pull request must declare it.
# Plain sh, awk, sed and grep only, so it behaves the same on a GitHub runner and on a Mac.
set -eu

refuse() {
    printf 'change_scope: %s\n' "$*" >&2
    exit 1
}

# Comments and fenced code blocks are skipped so a template can explain the field, or show an
# example of it, without that text counting as the author's choice. GitHub sends CRLF, hence the
# sub on \r. The key must start the line (after comments are removed). Count and value leave
# awk on one line, because an empty value would disappear from a line based count.
# shellcheck disable=SC2016
found="$(awk '
function strip(s,    out, i, j) {
    out = ""
    while (s != "") {
        if (incomment) {
            j = index(s, "-->")
            if (j == 0) return out
            s = substr(s, j + 3)
            incomment = 0
        } else {
            i = index(s, "<!--")
            if (i == 0) return out s
            out = out substr(s, 1, i - 1)
            s = substr(s, i + 4)
            incomment = 1
        }
    }
    return out
}
{
    sub(/\r$/, "")
    if (!incomment && $0 ~ /^[ \t]*```/) { infence = !infence; next }
    if (infence) next
    text = strip($0)
    if (tolower(substr(text, 1, 13)) == "change_scope:") {
        count++
        value = substr(text, 14)
        sub(/^[ \t]+/, "", value)
        sub(/[ \t]+$/, "", value)
    }
}
END { print count + 0, value }
')"
count="${found%% *}"
value="${found#* }"

if [ "$count" -eq 0 ]; then
    # Dependency bots cannot fill the field, so the workflow passes their default. Any other
    # DEFAULT_SCOPE is ignored, which fails closed into the refusal below.
    case "${DEFAULT_SCOPE-}" in
        revision | minor)
            printf '%s\n' "$DEFAULT_SCOPE"
            exit 0
            ;;
    esac
    refuse 'missing. Add a line "change_scope: revision" or "change_scope: minor"' \
        'to the description.'
fi
[ "$count" -eq 1 ] || refuse "given $count times. Give it once."

case "$value" in
    revision | minor)
        printf '%s\n' "$value"
        ;;
    major)
        major_msg='major changes are never merged. A new major version is a new repository named'
        refuse "$major_msg <name>_v<major>."
        ;;
    *)
        refuse "\"$value\" is not valid. Use revision or minor."
        ;;
esac
