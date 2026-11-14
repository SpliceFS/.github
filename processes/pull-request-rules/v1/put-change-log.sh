#!/bin/sh
# Usage: put-change-log.sh <entries file> < description > new description
# Reads a pull request description on standard input and prints it with the section "## Change
# log" holding the entries of the file (the lines that start with "- "). A section that exists is
# replaced, otherwise the new one goes before "## Change scope", or to the end. The workflow uses
# it to put a drafted entry (draft-change-log.sh) into a description whose author left the section
# out, so that the author sees the entry and can change it. Plain sh and awk only, like
# change-log.sh.
set -eu

entries="${1-}"
if [ ! -f "$entries" ]; then
    echo 'put-change-log: no entries' >&2
    exit 1
fi
# The entries go to awk in the environment, because awk -v would process backslashes in them and
# a file name in the argument list could be taken for an assignment.
PUT_ENTRIES="$(cat "$entries")"
export PUT_ENTRIES

# Recognition of comments, code fences and headings is the same as in change-log.sh, so that a
# heading in either does not count, and what this script writes is found again by that script.
# Nothing is printed before END, so a refusal never leaves half a description on standard output.
# GitHub sends CRLF, hence the sub on \r; the output uses LF only. Trailing blank lines are
# dropped so that the output ends with one newline whatever came after the section.
# shellcheck disable=SC2016
awk '
function fail(msg) {
    print "put-change-log: " msg > "/dev/stderr"
    exit 1
}
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
function squeeze(s) {
    gsub(/[ \t]+/, " ", s)
    sub(/^ /, "", s)
    sub(/ $/, "", s)
    return s
}
# Tells whether the line is a heading (one to six # marks, then a space or the end of the line)
# and leaves its text in htext.
function is_heading(s) {
    if (!match(s, /^#+/) || RLENGTH > 6) return 0
    s = substr(s, RLENGTH + 1)
    if (s != "" && substr(s, 1, 1) != " ") return 0
    htext = squeeze(s)
    return 1
}
function is_log(i) {
    return isheading[i] && (name[i] == "change log" || name[i] == "changelog")
}
function emit(s) {
    result[++nout] = s
}
function trim_end() {
    while (nout > 0 && result[nout] ~ /^[ \t]*$/) nout--
}
function emit_section(    i) {
    emit("## Change log")
    emit("")
    for (i = 1; i <= nentries; i++) emit(entry[i])
    emit("")
}
{
    sub(/\r$/, "")
    lines[++total] = $0
    if (!incomment && $0 ~ /^[ \t]*```/) { infence = !infence; next }
    if (infence) next
    text = strip($0)
    sub(/[ \t]+$/, "", text)
    if (is_heading(text)) {
        isheading[total] = 1
        name[total] = tolower(htext)
        # A comment that the heading line opens and does not close would hide the new entries,
        # so the heading is then kept without it.
        outside[total] = incomment ? text : lines[total]
    }
}
END {
    n = split(ENVIRON["PUT_ENTRIES"], raw, "\n")
    for (i = 1; i <= n; i++) {
        line = raw[i]
        sub(/\r$/, "", line)
        sub(/[ \t]+$/, "", line)
        if (line ~ /^- .*[^ \t]/) entry[++nentries] = line
    }
    if (nentries == 0) fail("no entries")

    for (i = 1; i <= total; i++) {
        if (!isheading[i]) continue
        if (is_log(i) && first_log == 0) first_log = i
        if (name[i] == "change scope" && scope == 0) scope = i
    }

    skipping = 0
    for (i = 1; i <= total; i++) {
        if (isheading[i]) {
            skipping = 0
            if (is_log(i)) {
                skipping = 1
                if (i == first_log) {
                    emit(outside[i])
                    emit("")
                    for (j = 1; j <= nentries; j++) emit(entry[j])
                    emit("")
                }
                continue
            }
            if (first_log == 0 && i == scope) emit_section()
        }
        if (!skipping) emit(lines[i])
    }

    if (first_log == 0 && scope == 0) {
        trim_end()
        # An unclosed comment or code block would swallow the new section.
        if (incomment) emit("-->")
        else if (infence) emit("```")
        if (nout > 0) emit("")
        emit_section()
    }
    trim_end()
    for (i = 1; i <= nout; i++) print result[i]
}
'
