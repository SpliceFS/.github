#!/bin/sh
# Tells the owner that a workflow run failed, by way of an issue in the repository that ran it.
# GitHub sends no email for a run started by the release bot or the merge bot, and it does send
# one to the person an issue is assigned to. A silent alert path is the failure this script
# exists to remove, so every gh call is checked and a failed call fails the script.
#
# Everything comes in through the environment, set by report-failure-v1.yml:
#   GH_TOKEN      token for gh, with the permission to write issues
#   REPO          owner/name of the repository whose run failed
#   WORKFLOW      name of the workflow that failed
#   REF_NAME      branch or tag the run was for
#   RUN_ID        id of the failed run
#   RUN_ATTEMPT   attempt number of the failed run
#   SERVER_URL    address of the GitHub server
#   ASSIGNEE      account to email; may be empty
set -eu

# $1 message. A missing alert is as bad as a missing mail, so the status is never 0.
fail() {
    printf 'report-failure: %s\n' "$1" >&2
    exit 1
}

: "${GH_TOKEN:?GH_TOKEN is not set}"
repo="${REPO:?REPO is not set}"
workflow="${WORKFLOW:?WORKFLOW is not set}"
ref_name="${REF_NAME:?REF_NAME is not set}"
run_id="${RUN_ID:?RUN_ID is not set}"
run_attempt="${RUN_ATTEMPT:?RUN_ATTEMPT is not set}"
server_url="${SERVER_URL:?SERVER_URL is not set}"
assignee="${ASSIGNEE:-}"

label='failure'
title="Failed: $workflow ($ref_name)"
# The address of this attempt, so that a re-run of the same run is told apart from the first.
run_url="$server_url/$repo/actions/runs/$run_id/attempts/$run_attempt"

# The label has to exist before an issue can carry it. Another run may create it between the
# two steps, so "already exists" is a fine answer.
ensure_label() {
    out="$(gh label create "$label" --repo "$repo" --color B60205 \
        --description 'A workflow run failed' 2>&1)" && return 0
    case "$out" in
        *'already exists'*) return 0 ;;
        *) ;;
    esac
    printf '%s\n' "$out" >&2
    fail "cannot create the label $label"
}

# One line per open issue that has the label: number, a space, title. The title is compared
# here and not put into a search query, so that quotes or search words in a workflow name
# cannot make it match another issue.
open_issues="$(gh issue list --repo "$repo" --state open --label "$label" --limit 200 \
    --json number,title --jq '.[] | "\(.number) \(.title)"')" ||
    fail 'cannot list the open issues'

existing=''
while read -r number name; do
    if [ "$name" = "$title" ]; then
        existing="$number"
        break
    fi
done <<EOF
$open_issues
EOF

# A workflow that keeps failing gets one issue. Every failure is still a comment, and a comment
# is a mail to the assignee.
if [ -n "$existing" ]; then
    gh issue comment "$existing" --repo "$repo" --body "Failed again: $run_url" ||
        fail "cannot comment on issue #$existing"
    exit 0
fi

ensure_label

body="$(printf 'The workflow run failed.\n\nRun: %s\n\nClose this issue to say the failure is dealt with.' \
    "$run_url")"
set -- --repo "$repo" --title "$title" --label "$label"
if [ -n "$assignee" ]; then
    set -- "$@" --assignee "$assignee"
else
    echo '::warning::ALERT_ASSIGNEE is not set. The issue is not assigned, so nobody gets an email until the repository variable holds the account to email.'
fi
gh issue create "$@" --body "$body" || fail 'cannot create the issue'
