#!/bin/sh
# Drafts the change log entry of a pull request whose author left the section out. One request
# to the Claude API gets the title, the description and the diff, and the entries come back on
# standard output, 1 to 4 lines, each starting with "- ". Another script puts them into the
# description, where the author can change them (see put-change-log.sh and change-log.sh).
#
#   draft-change-log.sh <title file> <description file> <diff file>
#
# The key is in CLAUDE_API_KEY. It goes to curl as header lines on standard input, so it is in no
# argument that "ps" shows, and the body goes in from a file for the same reason and because a big
# diff does not fit into an argument. DRAFT_CURL names the program that sends the request, so the
# test can put a fake one in its place and never reach the real service.
set -eu

fail() {
    echo "draft-change-log: $1" >&2
    exit 1
}

# 1500000 bytes of diff stay well inside the context of the model. A bigger one is refused and
# not cut off, because a cut diff gives an entry about half of a change.
max_diff=1500000
curl="${DRAFT_CURL:-curl}"

[ $# -eq 3 ] || fail "usage: draft-change-log.sh <title file> <description file> <diff file>"
title_file="$1"
description_file="$2"
diff_file="$3"

command -v "$curl" >/dev/null 2>&1 || fail "curl is not installed"
command -v jq >/dev/null 2>&1 || fail "jq is not installed"
[ -n "${CLAUDE_API_KEY:-}" ] || fail "CLAUDE_API_KEY is not set or is empty"
for file in "$title_file" "$description_file" "$diff_file"; do
    [ -f "$file" ] || fail "missing input file: $file"
done
# wc pads its count with spaces on some systems.
diff_size="$(wc -c <"$diff_file" | tr -d ' ')"
if [ "$diff_size" -gt "$max_diff" ]; then
    fail "the change is too large to draft an entry from; write the Change log section by hand"
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM

# The line ends of the text are folded into spaces here, which keeps the system text one string
# and the wording in lines that are easy to read and compare.
system="$(paste -s -d ' ' - <<'EOF'
You write the change log entry for one change to SpliceFS, an open source file system
made of a server (splicefsd) and a client (splicefs). You get the title, the
description and the diff of a pull request. Reply with a list of 1 to 4 lines and
nothing else. Every line starts with "- " and is one or two full sentences of at most
260 characters. Say what a person who installs and runs the program would notice: a new
command, option, setting, package, message, supported system, or a fixed failure. Put
names a user types in backticks. Do not name functions, files of the source code, test
or build tools, and do not describe how the change was made. If nothing changes for a
user (tests, code checks, build automation), reply with exactly one line of the form
"- Internal: <what was done, in a few plain words>. Nothing changes for users." Use
only what the pull request shows; do not invent anything. Plain ASCII only.
EOF
)"

# jq builds the JSON, so quotes, backslashes and control characters in the inputs are escaped
# for certain. The trailing newlines of the title and the description are dropped, the diff is
# sent as it is.
jq -n \
    --arg system "$system" \
    --rawfile title "$title_file" \
    --rawfile description "$description_file" \
    --rawfile diff "$diff_file" \
    '{
        model: "claude-opus-5-5",
        max_tokens: 16000,
        fallbacks: "default",
        output_config: {effort: "medium"},
        system: $system,
        messages: [{
            role: "user",
            content: ("Title: " + ($title | sub("\n+$"; ""))
                + "\n\nDescription:\n" + ($description | sub("\n+$"; ""))
                + "\n\nDiff:\n" + $diff)
        }]
    }' >"$work/request.json"

answer="$work/answer.json"
# curl reads the header lines once, while it reads its options, so --retry does not lose them.
# Without --fail, the body of an error answer is kept for its message.
status="$(printf '%s\n' \
    'Content-Type: application/json' \
    "x-api-key: $CLAUDE_API_KEY" \
    'anthropic-version: 2026-10-21' \
    'anthropic-beta: server-side-fallback-2026-07-01' |
    "$curl" -sS --max-time 300 --retry 2 \
        --request POST \
        --header @- \
        --data-binary "@$work/request.json" \
        --output "$answer" \
        --write-out '%{http_code}' \
        https://api.anthropic.com/v1/messages)" || fail "the request to the API failed"

if [ "$status" != 200 ]; then
    # The answer may be no JSON at all (a proxy page), then there is no message to show.
    message="$(jq -r 'try (.error.message // empty) catch empty' "$answer" 2>/dev/null)" ||
        message=""
    message="$(printf '%s' "$message" | tr -c '[:print:]' ' ' | cut -c 1-300)"
    if [ -n "$message" ]; then
        fail "the API answered with HTTP status $status: $message"
    fi
    fail "the API answered with HTTP status $status"
fi

stop_reason="$(jq -r '.stop_reason // ""' "$answer" 2>/dev/null)" || fail "the answer is not valid JSON"
if [ "$stop_reason" = refusal ]; then
    fail "the model refused to draft an entry"
fi

# The blocks are joined with a newline, so the last line of one block and the first of the next
# never run together. Blocks of other types (thinking) are not part of the answer.
text="$(jq -r '[.content[]? | select(.type == "text") | (.text // "")] | join("\n")' "$answer")"

# The bytes are compared in the C locale, so a range of printable characters means ASCII on every
# system. grep exits 1 for no match, which here means "no acceptable line" and is judged below.
export LC_ALL=C
entries="$(printf '%s\n' "$text" | grep '^- .*[^[:space:]]')" || entries=""
[ -n "$entries" ] || fail "the answer has no acceptable line"

count="$(printf '%s\n' "$entries" | wc -l | tr -d ' ')"
if [ "$count" -gt 4 ]; then
    fail "the answer has $count entries, at most 4 are allowed"
fi
if printf '%s\n' "$entries" | grep -q '[^ -~]'; then
    fail "the answer has a character outside printable ASCII"
fi
# awk and not grep, because a repetition of 401 is more than some grep versions take.
if printf '%s\n' "$entries" | awk 'length($0) > 400 { found = 1 } END { exit !found }'; then
    fail "the answer has an entry longer than 400 characters"
fi

printf '%s\n' "$entries"
