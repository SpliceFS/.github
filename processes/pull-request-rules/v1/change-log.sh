#!/bin/sh
# Reads a pull request description on standard input and prints the entries of its change log
# section, one bullet per line, each starting with "- ". The author writes the entry in the
# description and the bot copies it into CHANGELOG.md (see set-version.sh), so the author never has
# to guess the version. Plain sh, awk, sed and grep only, so it behaves the same on a GitHub runner
# and on a Mac.
set -eu

# Comments and fenced code blocks are skipped as in change-scope.sh, so a template can explain the
# section, or show an example of it, without that text counting as the author's entry. GitHub
# sends CRLF, hence the sub on \r. Everything is decided in END and nothing is printed before, so
# a refusal never leaves half an entry on standard output. The heading marks are matched with + and
# a length check, because older awk versions have no {1,6}. The default entry comes from the
# environment, because awk -v would process backslashes in it.
# shellcheck disable=SC2016
awk '
function fail(msg) {
    print "change_log: " msg > "/dev/stderr"
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
{
    sub(/\r$/, "")
    if (!incomment && $0 ~ /^[ \t]*```/) { infence = !infence; next }
    if (infence) next
    text = strip($0)
    sub(/[ \t]+$/, "", text)
    if (is_heading(text)) {
        insection = 0
        if (tolower(htext) == "change log" || tolower(htext) == "changelog") {
            sections++
            insection = 1
        }
        next
    }
    if (!insection || text == "") next
    if (text ~ /^[-*]( |$)/) {
        entries[++n] = squeeze(substr(text, 2))
    } else if (text ~ /^(  |\t)/ && n > 0) {
        extra = squeeze(text)
        entries[n] = (entries[n] == "" ? extra : entries[n] " " extra)
    } else if (stray == "") {
        stray = squeeze(text)
    }
}
END {
    if (sections == 0) {
        # Dependency bots cannot fill the section, so the workflow passes their default.
        if (ENVIRON["DEFAULT_ENTRY"] != "") {
            print "- " ENVIRON["DEFAULT_ENTRY"]
            exit 0
        }
        fail("missing. Add a section \"## Change log\" to the description, with a line" \
            " \"- <what changed>\" for each change.")
    }
    if (sections > 1) fail("given " sections " times. Write one \"## Change log\" section.")
    if (stray != "") {
        fail("the Change log section has a line that is not an entry: \"" stray "\"." \
            " Start every entry with \"- \", and indent a line that continues an entry by" \
            " two spaces.")
    }
    if (n == 0) {
        fail("the Change log section has no entry. Add a line \"- <what changed>\" below" \
            " the heading.")
    }
    for (i = 1; i <= n; i++) {
        if (entries[i] == "") {
            fail("an entry has no text. Write what changed after the \"- \".")
        }
    }
    for (i = 1; i <= n; i++) print "- " entries[i]
}
'
