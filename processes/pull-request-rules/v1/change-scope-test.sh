#!/bin/sh
# Table test of change-scope.sh: which pull request descriptions give which scope, and
# which are refused with which message. Runs on the host (make change-scope-test, part of
# make check). Descriptions are given as printf %b text so the table can show CRLF and newlines.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
cd "$here"
failed=0

# $1 description, $2 DEFAULT_SCOPE (may be empty).
run() {
    printf '%b' "$1" | DEFAULT_SCOPE="$2" sh change-scope.sh
}

# $1 label, $2 description, $3 wanted output, $4 optional DEFAULT_SCOPE.
check() {
    if got="$(run "$2" "${4-}" 2>&1)"; then
        if [ "$got" = "$3" ]; then
            printf 'ok   %-28s %s\n' "$1" "$3"
        else
            printf 'FAIL %-28s want "%s" got "%s"\n' "$1" "$3" "$got"
            failed=$((failed + 1))
        fi
    else
        printf 'FAIL %-28s was refused: %s\n' "$1" "$got"
        failed=$((failed + 1))
    fi
}

# $1 label, $2 description, $3 the exact message, $4 optional DEFAULT_SCOPE. Nothing may reach
# standard output on a refusal.
refuse() {
    if out="$(run "$2" "${4-}" 2>/dev/null)"; then
        printf 'FAIL %-28s was accepted: %s\n' "$1" "$out"
        failed=$((failed + 1))
    elif [ -n "$out" ]; then
        printf 'FAIL %-28s refused but printed: %s\n' "$1" "$out"
        failed=$((failed + 1))
    else
        got="$(run "$2" "${4-}" 2>&1 >/dev/null)" || true
        if [ "$got" = "$3" ]; then
            printf 'ok   %-28s refused: %s\n' "$1" "$got"
        else
            printf 'FAIL %-28s want "%s" got "%s"\n' "$1" "$3" "$got"
            failed=$((failed + 1))
        fi
    fi
}

missing='change_scope: missing. Add a line "change_scope: revision" or'
missing="$missing \"change_scope: minor\" to the description."
major='change_scope: major changes are never merged. A new major version is a new repository'
major="$major named <name>_v<major>."
# A code fence, kept in one place because backticks in single quotes trip shellcheck.
# shellcheck disable=SC2016
f='```'
invalid() { printf 'change_scope: "%s" is not valid. Use revision or minor.' "$1"; }

check minor 'change_scope: minor\n' minor
check revision 'change_scope: revision\n' revision
check no-final-newline 'change_scope: minor' minor
check crlf 'change_scope: minor\r\n' minor
check crlf-among-text 'Fix a bug.\r\n\r\nchange_scope: revision\r\n\r\nMore.\r\n' revision
check spaces-around-value 'change_scope:   minor  \n' minor
check tab-around-value 'change_scope:\tminor\t\n' minor
check no-space-after-colon 'change_scope:minor\n' minor
check upper-case-key 'CHANGE_SCOPE: minor\n' minor
check mixed-case-key 'Change_Scope: revision\n' revision
check text-before-and-after 'Title\n\nSome words.\nchange_scope: minor\nMore words.\n' minor
check comment-line-then-field '<!-- change_scope: major -->\nchange_scope: minor\n' minor
check comment-spans-lines '<!--\nchange_scope: major\n-->\nchange_scope: revision\n' revision
check comment-inside-value 'change_scope: <!-- pick one --> minor\n' minor
check comment-then-key '<!-- note -->change_scope: minor\n' minor
check two-comments-then-key '<!-- a --><!-- b -->change_scope: minor\n' minor
check comment-ends-then-key '<!--\nnote -->change_scope: minor\n' minor
check code-block-then-field "${f}\nchange_scope: major\n${f}\nchange_scope: minor\n" minor
check code-block-with-lang "${f}sh\nchange_scope: major\n${f}\nchange_scope: revision\n" revision
check comment-opener-in-code "${f}\n<!--\n${f}\nchange_scope: minor\n" minor
check fence-inside-comment "<!--\n${f}\n-->\nchange_scope: minor\n" minor
check field-in-comment-is-one '<!-- change_scope: minor -->\nchange_scope: revision\n' revision
check default-unused-minor 'change_scope: minor\n' minor revision
check default-unused-revision 'change_scope: revision\n' revision minor
check default-fills-revision 'Bump a dependency.\n' revision revision
check default-fills-minor 'Bump a dependency.\n' minor minor
check default-for-empty '' revision revision
check default-for-comment-only '<!-- change_scope: minor -->\n' revision revision
check default-for-code-only "${f}\nchange_scope: minor\n${f}\n" minor minor

refuse empty-description '' "$missing"
refuse text-only 'Fix a bug.\n' "$missing"
refuse comment-only '<!-- change_scope: minor -->\n' "$missing"
refuse comment-spans-lines '<!--\nchange_scope: minor\n-->\n' "$missing"
refuse unclosed-comment '<!--\nchange_scope: minor\n' "$missing"
refuse code-block-only "${f}\nchange_scope: minor\n${f}\n" "$missing"
refuse unclosed-code-block "${f}\nchange_scope: minor\n" "$missing"
refuse key-not-at-line-start '  change_scope: minor\n' "$missing"
refuse key-inside-sentence 'Set change_scope: minor here.\n' "$missing"
refuse key-with-space 'change_scope : minor\n' "$missing"
refuse two-fields 'change_scope: minor\nchange_scope: minor\n' \
    'change_scope: given 2 times. Give it once.'
refuse two-fields-differ 'change_scope: minor\nchange_scope: revision\n' \
    'change_scope: given 2 times. Give it once.'
refuse three-fields-crlf 'change_scope: minor\r\nchange_scope: minor\r\nchange_scope: minor\r\n' \
    'change_scope: given 3 times. Give it once.'
refuse two-with-key-case 'change_scope: minor\nCHANGE_SCOPE: minor\n' \
    'change_scope: given 2 times. Give it once.'
refuse major 'change_scope: major\n' "$major"
refuse major-crlf 'change_scope: major\r\n' "$major"
refuse upper-case-value 'change_scope: MINOR\n' "$(invalid MINOR)"
refuse capitalised-value 'change_scope: Revision\n' "$(invalid Revision)"
refuse upper-case-major 'change_scope: MAJOR\n' "$(invalid MAJOR)"
refuse extra-words 'change_scope: minor please\n' "$(invalid 'minor please')"
refuse extra-word-before 'change_scope: a minor\n' "$(invalid 'a minor')"
refuse trailing-punctuation 'change_scope: minor.\n' "$(invalid 'minor.')"
refuse unknown-value 'change_scope: patch\n' "$(invalid patch)"
refuse empty-value 'change_scope:\n' "$(invalid '')"
refuse empty-value-crlf 'change_scope:   \r\n' "$(invalid '')"
refuse default-missing-value-major '' "$missing" major
refuse default-unknown-value '' "$missing" patch
refuse default-upper-case '' "$missing" MINOR
refuse default-with-bad-field 'change_scope: patch\n' "$(invalid patch)" revision
refuse default-with-major 'change_scope: major\n' "$major" revision
refuse default-with-two-fields 'change_scope: minor\nchange_scope: minor\n' \
    'change_scope: given 2 times. Give it once.' revision

[ "$failed" -eq 0 ] || { echo "$failed failed"; exit 1; }
echo "change scope: all descriptions handled as expected"
