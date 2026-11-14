#!/bin/sh
# Table test of draft-change-log.sh: which answers of the API give which entries, which are
# refused with which message, and what the request looks like. Runs on the host (part of make
# check). The program that sends the request is replaced (DRAFT_CURL) by a fake one that records
# what it gets and prints a canned answer, so no test reaches a real service.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
cd "$here"
failed=0

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM
fake="$work/fake"
in="$work/in"
mkdir "$fake" "$in" "$work/empty"
out="$work/out"
err="$work/err"
key='sk-test-key-0123456789'

# The fake records one argument per line, the standard input, the file that --data-binary names
# (the script removes its own copy when it ends), and one line per call.
cat >"$fake/curl" <<'EOF'
#!/bin/sh
echo called >>"$FAKE_DIR/calls"
: >"$FAKE_DIR/args"
output=""
previous=""
for arg in "$@"; do
    printf '%s\n' "$arg" >>"$FAKE_DIR/args"
    case "$previous" in
    --output) output="$arg" ;;
    --data-binary) cp "${arg#@}" "$FAKE_DIR/body.json" ;;
    *) ;;
    esac
    previous="$arg"
done
cat >"$FAKE_DIR/stdin"
cp "$FAKE_DIR/answer" "$output"
printf '%s' "$FAKE_STATUS"
EOF
chmod 755 "$fake/curl"

title='Add the --foo option to splicefsd'
description='Adds an option.
Line two has "quotes", a backslash \ and a tab:	end.'
printf '%s\n' "$title" >"$in/title"
printf '%s\n' "$description" >"$in/description"
printf '%s\n' 'diff --git a/main.go b/main.go' '+	fmt.Println("a\nb")' >"$in/diff"

# $1 answer (JSON text), $2 HTTP status, $3 key (default: the test key), $4 diff file. The fake
# program is called through the script as DRAFT_CURL.
run() {
    rm -f "$fake/calls" "$fake/args" "$fake/stdin" "$fake/body.json"
    printf '%s\n' "$1" >"$fake/answer"
    FAKE_DIR="$fake" FAKE_STATUS="$2" DRAFT_CURL="$fake/curl" CLAUDE_API_KEY="${3-$key}" \
        sh draft-change-log.sh "$in/title" "$in/description" "${4-$in/diff}" >"$out" 2>"$err"
}

# $1 text of the model as printf %b text. Prints the answer of a normal call.
reply() {
    text="$(printf '%b' "$1")"
    jq -n --arg text "$text" \
        '{stop_reason: "end_turn", content: [{type: "text", text: $text}]}'
}

pass() {
    printf 'ok   %-30s %s\n' "$1" "$2"
}

fail() {
    printf 'FAIL %-30s %s\n' "$1" "$2"
    failed=$((failed + 1))
}

# $1 label, $2 answer, $3 wanted output as printf %b text. $4 is the diff file, optional.
accept() {
    want="$(printf '%b' "$3")"
    if ! run "$2" 200 "$key" "${4-$in/diff}"; then
        fail "$1" "was refused: $(cat "$err")"
    elif [ "$(cat "$out")" != "$want" ]; then
        fail "$1" "want \"$want\" got \"$(cat "$out")\""
    elif [ -s "$err" ]; then
        fail "$1" "wrote to standard error: $(cat "$err")"
    else
        pass "$1" "$3"
    fi
}

# $1 label, $2 answer, $3 HTTP status, $4 the exact message, $5 key, $6 diff file (both
# optional). Nothing may reach standard output, and the key is in no output.
refuse() {
    if run "$2" "$3" "${5-$key}" "${6-$in/diff}"; then
        fail "$1" "was accepted: $(cat "$out")"
    elif [ -s "$out" ]; then
        fail "$1" "refused but printed: $(cat "$out")"
    elif [ "$(cat "$err")" != "draft-change-log: $4" ]; then
        fail "$1" "want \"draft-change-log: $4\" got \"$(cat "$err")\""
    elif grep -qF "$key" "$out" "$err"; then
        fail "$1" "printed the key"
    else
        pass "$1" "refused: $4"
    fi
}

# $1 label, $2 jq test on the request body (true is a pass).
body_is() {
    if jq -e "$2" "$fake/body.json" >/dev/null 2>&1; then
        pass "$1" "$2"
    else
        fail "$1" "the body does not satisfy: $2"
    fi
}

# $1 label, $2 whether the fake program must have been called (yes or no).
fake_called() {
    if [ -f "$fake/calls" ] && [ "$2" = yes ]; then
        pass "$1" "the request was sent"
    elif [ ! -f "$fake/calls" ] && [ "$2" = no ]; then
        pass "$1" "no request was sent"
    else
        fail "$1" "the request was sent or not sent against the wish: $2"
    fi
}

# A line of $1 characters after the marker "- ".
line() {
    printf '%s' '- '
    printf '%0*d' "$(($1 - 2))" 0 | tr 0 x
}

# Good answers.
# A backtick, kept in one place because backticks in single quotes trip shellcheck.
bt="$(printf '\140')"
two="- Adds the ${bt}--foo${bt} option to ${bt}splicefsd${bt}.\\n- Fixes a crash."
accept two-entries "$(reply "$two")" "$two"
accept one-entry "$(reply '- Fixes a crash.')" '- Fixes a crash.'
accept four-entries "$(reply '- A.\n- B.\n- C.\n- D.')" '- A.\n- B.\n- C.\n- D.'
accept text-around-list "$(reply 'Here is the entry:\n\n- A.\n- B.\n\nDo you want more?')" '- A.\n- B.'
accept star-line-dropped "$(reply '* A.\n- B.\n-C.\n-\n- \n-  ')" '- B.'
accept internal "$(reply '- Internal: Added tests for the server. Nothing changes for users.')" \
    '- Internal: Added tests for the server. Nothing changes for users.'
accept blocks-joined \
    '{"stop_reason":"end_turn","content":[{"type":"thinking","thinking":"- no"},{"type":"text","text":"- A."},{"type":"text","text":"- B."}]}' \
    '- A.\n- B.'
accept line-of-400 "$(reply "$(line 400)")" "$(line 400)"

# The request that went out in the last good call.
run "$(reply '- A.')" 200
body_is body-is-json '.'
body_is body-model '.model == "claude-opus-5-5" and .max_tokens == 16000'
body_is body-fallbacks '.fallbacks == "default" and .output_config == {effort: "medium"}'
body_is body-has-only-the-fields \
    'keys == ["fallbacks", "max_tokens", "messages", "model", "output_config", "system"]'
body_is body-one-user-message \
    '(.messages | length) == 1 and .messages[0].role == "user" and (.messages[0].content | type) == "string"'
paste -s -d ' ' - >"$work/system" <<'EOF'
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
jq -j '.system' "$fake/body.json" >"$work/got-system"
if [ "$(cat "$work/system")" = "$(cat "$work/got-system")" ]; then
    pass system-text "the instructions are sent word for word"
else
    fail system-text "the system text differs from the specification"
fi
{
    printf 'Title: %s\n\nDescription:\n%s\n\nDiff:\n' "$title" "$description"
    cat "$in/diff"
} >"$work/want-content"
jq -j '.messages[0].content' "$fake/body.json" >"$work/got-content"
if cmp -s "$work/want-content" "$work/got-content"; then
    pass user-content "title, description and diff are in the message, unchanged"
else
    fail user-content "the message differs from the title, description and diff"
fi

# The key and the call.
if grep -qxF "x-api-key: $key" "$fake/stdin" &&
    grep -qxF 'Content-Type: application/json' "$fake/stdin" &&
    grep -qxF 'anthropic-version: 2026-10-21' "$fake/stdin" &&
    grep -qxF 'anthropic-beta: server-side-fallback-2026-07-01' "$fake/stdin"; then
    pass headers-on-stdin "the four headers are on standard input"
else
    fail headers-on-stdin "a header is missing on standard input: $(cat "$fake/stdin")"
fi
if grep -qF "$key" "$fake/args" "$fake/body.json"; then
    fail key-not-in-arguments "the key is in an argument or in the body"
else
    pass key-not-in-arguments "the key is in no argument and not in the body"
fi
if grep -qxF -e '--max-time' "$fake/args" && grep -qxF 300 "$fake/args" &&
    grep -qxF -e '--retry' "$fake/args" && grep -qxF 2 "$fake/args" &&
    grep -qxF @- "$fake/args" &&
    grep -qxF https://api.anthropic.com/v1/messages "$fake/args"; then
    pass curl-arguments "url, timeout, retries and header file as specified"
else
    fail curl-arguments "arguments: $(tr '\n' ' ' <"$fake/args")"
fi

# Refusals of the API and of the answer.
refuse refusal '{"stop_reason":"refusal","content":[{"type":"text","text":"- A."}]}' 200 \
    'the model refused to draft an entry'
refuse http-500 '{"type":"error","error":{"type":"api_error","message":"Overloaded"}}' 500 \
    'the API answered with HTTP status 500: Overloaded'
refuse http-401-key '{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}' 401 \
    'the API answered with HTTP status 401: invalid x-api-key'
refuse http-502-no-json '<html>Bad gateway</html>' 502 'the API answered with HTTP status 502'
refuse http-error-no-message '{"error":"plain"}' 500 'the API answered with HTTP status 500'
refuse answer-no-json 'not json' 200 'the answer is not valid JSON'
refuse five-entries "$(reply '- A.\n- B.\n- C.\n- D.\n- E.')" 200 \
    'the answer has 5 entries, at most 4 are allowed'
refuse non-ascii "$(reply '- A.\n- Caf\0303\0251.')" 200 \
    'the answer has a character outside printable ASCII'
refuse tab-in-line "$(reply '- A.\tB.')" 200 'the answer has a character outside printable ASCII'
refuse long-line "$(reply "- A.\n$(line 401)")" 200 \
    'the answer has an entry longer than 400 characters'
refuse no-list "$(reply 'I cannot do that.')" 200 'the answer has no acceptable line'
refuse only-marker "$(reply '- ')" 200 'the answer has no acceptable line'
refuse no-content '{"stop_reason":"end_turn","content":[]}' 200 \
    'the answer has no acceptable line'
refuse only-thinking '{"stop_reason":"end_turn","content":[{"type":"thinking","thinking":"- A."}]}' 200 \
    'the answer has no acceptable line'

# Refusals before any request.
refuse empty-key "$(reply '- A.')" 200 'CLAUDE_API_KEY is not set or is empty' ''
fake_called empty-key-no-request no

head -c 1500001 /dev/zero | tr '\0' x >"$work/diff-big"
refuse diff-too-large "$(reply '- A.')" 200 \
    'the change is too large to draft an entry from; write the Change log section by hand' \
    "$key" "$work/diff-big"
fake_called diff-too-large-no-request no

head -c 1500000 /dev/zero | tr '\0' x >"$work/diff-limit"
accept diff-at-limit "$(reply '- A.')" '- A.' "$work/diff-limit"
fake_called diff-at-limit-request yes

refuse missing-file "$(reply '- A.')" 200 "missing input file: $work/no-such-file" "$key" \
    "$work/no-such-file"
fake_called missing-file-no-request no

# Called by hand, as they need another program, another path or other arguments.
if DRAFT_CURL="$work/no-such-program" CLAUDE_API_KEY="$key" \
    sh draft-change-log.sh "$in/title" "$in/description" "$in/diff" >"$out" 2>"$err"; then
    fail curl-missing "was accepted"
elif [ "$(cat "$err")" = "draft-change-log: curl is not installed" ] && [ ! -s "$out" ]; then
    pass curl-missing "refused: curl is not installed"
else
    fail curl-missing "got \"$(cat "$err")\""
fi
if PATH="$work/empty" DRAFT_CURL="$fake/curl" CLAUDE_API_KEY="$key" \
    /bin/sh draft-change-log.sh "$in/title" "$in/description" "$in/diff" >"$out" 2>"$err"; then
    fail jq-missing "was accepted"
elif [ "$(cat "$err")" = "draft-change-log: jq is not installed" ] && [ ! -s "$out" ]; then
    pass jq-missing "refused: jq is not installed"
else
    fail jq-missing "got \"$(cat "$err")\""
fi
if CLAUDE_API_KEY="$key" sh draft-change-log.sh "$in/title" >"$out" 2>"$err"; then
    fail wrong-arguments "was accepted"
elif grep -q '^draft-change-log: usage: ' "$err" && [ ! -s "$out" ]; then
    pass wrong-arguments "refused with the usage"
else
    fail wrong-arguments "got \"$(cat "$err")\""
fi

[ "$failed" -eq 0 ] || { echo "$failed failed"; exit 1; }
echo "draft change log: all answers handled as expected"
