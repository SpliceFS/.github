#!/bin/sh
# Tests of report-failure.sh with a gh that is a stub: it records every call and answers from
# files, so nothing reaches GitHub. Runs on the host (part of make check).
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM
failed=0
cases=0

# The stub. It writes one line per call to "calls" (the body of a call goes to "body" so the
# line stays one line), and answers as the files in its folder say:
#   open-issues  what "gh issue list" prints, one "number title" line per issue
#   labels       the labels the repository has; creating one that is listed fails as gh does
#   fail         "<word> <word>" of a call that must fail, for example "issue create"
mkdir "$work/bin"
cat >"$work/bin/gh" <<'EOF'
#!/bin/sh
line=''
prev=''
for arg in "$@"; do
    if [ "$prev" = '--body' ]; then
        printf '%s\n' "$arg" >"$STUB_DIR/body"
        arg='(body)'
    fi
    line="$line $arg"
    prev="$arg"
done
printf '%s\n' "${line# }" >>"$STUB_DIR/calls"

if [ -f "$STUB_DIR/fail" ] && [ "$(cat "$STUB_DIR/fail")" = "$1 $2" ]; then
    echo 'gh: simulated failure (HTTP 500)' >&2
    exit 1
fi

case "$1 $2" in
    'issue list')
        if [ -f "$STUB_DIR/open-issues" ]; then
            cat "$STUB_DIR/open-issues"
        fi
        ;;
    'label create')
        if grep -qxF "$3" "$STUB_DIR/labels"; then
            printf 'label with name "%s" already exists; use --force to update its color and description\n' "$3" >&2
            exit 1
        fi
        printf '%s\n' "$3" >>"$STUB_DIR/labels"
        ;;
    'issue create')
        echo 'https://github.example.com/example-org/example-repo/issues/99'
        ;;
    'issue comment')
        echo 'https://github.example.com/example-org/example-repo/issues/7#issuecomment-1'
        ;;
    *)
        echo "gh stub: unexpected call: $*" >&2
        exit 99
        ;;
esac
EOF
chmod +x "$work/bin/gh"

# A fresh stub folder and the default run. A case changes the variables it cares about.
new_case() {
    cases=$((cases + 1))
    case_dir="$work/case-$cases"
    mkdir "$case_dir"
    : >"$case_dir/calls"
    : >"$case_dir/labels"
    workflow='Main moved'
    ref='main'
    run_id='123'
    attempt='1'
    assignee='alert-owner'
}

# Sets status and out (standard output and standard error together).
run_script() {
    status=0
    out="$(
        PATH="$work/bin:$PATH" STUB_DIR="$case_dir" GH_TOKEN=test-token \
            REPO=example-org/example-repo WORKFLOW="$workflow" REF_NAME="$ref" \
            RUN_ID="$run_id" RUN_ATTEMPT="$attempt" SERVER_URL=https://github.example.com \
            ASSIGNEE="$assignee" sh "$here/report-failure.sh" 2>&1
    )" || status=$?
}

ok() { printf 'ok   %s\n' "$1"; }
bad() {
    printf 'FAIL %s\n' "$1"
    failed=$((failed + 1))
}

# $1 label, $2 wanted status: zero means success, anything else means "not zero".
expect_status() {
    if [ "$2" -eq 0 ] && [ "$status" -eq 0 ]; then
        ok "$1: succeeds"
    elif [ "$2" -ne 0 ] && [ "$status" -ne 0 ]; then
        ok "$1: fails"
    else
        bad "$1: status $status, output: $out"
    fi
}

# $1 label, $2 number of the call (from 1), $3 what the line must be, or start with.
expect_call() {
    got="$(sed -n "$2p" "$case_dir/calls")"
    case "$got" in
        "$3"*) ok "$1" ;;
        *) bad "$1: call $2 is \"$got\", wanted \"$3\"" ;;
    esac
}

# $1 label, $2 wanted number of calls.
expect_call_count() {
    count="$(awk 'END { print NR }' "$case_dir/calls")"
    if [ "$count" -eq "$2" ]; then
        ok "$1"
    else
        recorded="$(cat "$case_dir/calls")"
        bad "$1: $count calls, wanted $2: $recorded"
    fi
}

# $1 label, $2 file ("out" for what the script printed, or the name of a file of the stub), $3 text.
expect_text() {
    if [ "$2" = out ]; then
        text="$out"
    else
        text="$(cat "$case_dir/$2")"
    fi
    case "$text" in
        *"$3"*) ok "$1" ;;
        *) bad "$1: \"$3\" is not in: $text" ;;
    esac
}

# $1 label, $2 text that must not appear in any recorded call.
expect_not_in_calls() {
    if grep -qF -- "$2" "$case_dir/calls"; then
        recorded="$(cat "$case_dir/calls")"
        bad "$1: found \"$2\" in: $recorded"
    else
        ok "$1"
    fi
}

repo_flag='--repo example-org/example-repo'
list_call="issue list $repo_flag --state open --label failure"

# 1. Nothing is open: the label is made, then the issue, assigned, with the link to the run.
new_case
run_script
expect_status 'none open' 0
expect_call_count 'none open: three calls' 3
expect_call 'none open: looks for open issues with the label' 1 "$list_call"
expect_call 'none open: creates the label' 2 "label create failure $repo_flag"
expect_call 'none open: opens an assigned issue' 3 \
    "issue create $repo_flag --title Failed: Main moved (main) --label failure --assignee alert-owner --body (body)"
expect_text 'none open: body has the link to the run' body \
    'Run: https://github.example.com/example-org/example-repo/actions/runs/123/attempts/1'
expect_text 'none open: body says how to deal with it' body 'Close this issue'

# 2. An open issue with this title and the label: a comment, and no new issue. The issues with
#    another workflow or another ref in the title must not be taken for it.
new_case
attempt='2'
printf '%s\n' '9 Failed: Main moved (other)' '8 Failed: Other (main)' '7 Failed: Main moved (main)' \
    >"$case_dir/open-issues"
run_script
expect_status 'one open' 0
expect_call_count 'one open: two calls' 2
expect_call 'one open: looks for open issues with the label' 1 "$list_call"
expect_call 'one open: comments on that issue' 2 "issue comment 7 $repo_flag --body (body)"
expect_text 'one open: comment has the link to this attempt' body \
    'https://github.example.com/example-org/example-repo/actions/runs/123/attempts/2'
expect_not_in_calls 'one open: no new issue' 'issue create'
expect_not_in_calls 'one open: no label made' 'label create'

# 3. Open issues that are about something else: a new issue.
new_case
printf '%s\n' '9 Failed: Main moved (other)' '8 Failed: Other (main)' >"$case_dir/open-issues"
run_script
expect_status 'others open' 0
expect_not_in_calls 'others open: no comment' 'issue comment'
expect_call_count 'others open: three calls' 3
expect_call 'others open: opens a new issue' 3 "issue create $repo_flag --title Failed: Main moved (main)"

# 4. The label is missing: it is created and the issue is opened.
new_case
run_script
expect_status 'label missing' 0
expect_text 'label missing: the repository has it afterwards' labels 'failure'

# 5. The label is there already: the refusal of gh is not a failure of the script.
new_case
echo failure >"$case_dir/labels"
run_script
expect_status 'label exists' 0
expect_call 'label exists: the issue is opened' 3 "issue create $repo_flag --title Failed: Main moved (main)"

# 6. No assignee: the issue is opened without one, and the script warns.
new_case
assignee=''
run_script
expect_status 'no assignee' 0
expect_call 'no assignee: unassigned issue' 3 \
    "issue create $repo_flag --title Failed: Main moved (main) --label failure --body (body)"
expect_not_in_calls 'no assignee: nobody is assigned' '--assignee'
expect_text 'no assignee: warns' out '::warning::ALERT_ASSIGNEE is not set'

# 7. Every gh call that fails fails the script, and says which one.
new_case
echo 'issue list' >"$case_dir/fail"
run_script
expect_status 'list fails' 1
expect_text 'list fails: says so' out 'report-failure: cannot list the open issues'

new_case
echo 'label create' >"$case_dir/fail"
run_script
expect_status 'label fails' 1
expect_text 'label fails: says so' out 'report-failure: cannot create the label failure'
expect_not_in_calls 'label fails: no issue without its label' 'issue create'

new_case
echo 'issue create' >"$case_dir/fail"
run_script
expect_status 'create fails' 1
expect_text 'create fails: says so' out 'report-failure: cannot create the issue'

new_case
echo '7 Failed: Main moved (main)' >"$case_dir/open-issues"
echo 'issue comment' >"$case_dir/fail"
run_script
expect_status 'comment fails' 1
expect_text 'comment fails: says so' out 'report-failure: cannot comment on issue #7'

# 8. A missing input stops the script before any call.
new_case
run_id=''
run_script
expect_status 'no run id' 1
expect_text 'no run id: names it' out 'RUN_ID'
expect_call_count 'no run id: nothing was called' 0

if [ "$failed" -ne 0 ]; then
    printf '%s checks failed\n' "$failed"
    exit 1
fi
echo 'report-failure: all checks passed'
