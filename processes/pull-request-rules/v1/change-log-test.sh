#!/bin/sh
# Table test of change-log.sh: which pull request descriptions give which entries, and which are
# refused with which message. Runs on the host (part of make check). Descriptions are given as
# printf %b text so the table can show CRLF, tabs and newlines.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
cd "$here"
failed=0

# $1 description, $2 DEFAULT_ENTRY (may be empty).
run() {
    printf '%b' "$1" | DEFAULT_ENTRY="$2" sh change-log.sh
}

# $1 label, $2 description, $3 wanted output as printf %b text, $4 optional DEFAULT_ENTRY.
check() {
    want="$(printf '%b' "$3")"
    if got="$(run "$2" "${4-}" 2>&1)"; then
        if [ "$got" = "$want" ]; then
            printf 'ok   %-30s %s\n' "$1" "$3"
        else
            printf 'FAIL %-30s want "%s" got "%s"\n' "$1" "$want" "$got"
            failed=$((failed + 1))
        fi
    else
        printf 'FAIL %-30s was refused: %s\n' "$1" "$got"
        failed=$((failed + 1))
    fi
}

# $1 label, $2 description, $3 the exact message, $4 optional DEFAULT_ENTRY. Nothing may reach
# standard output on a refusal.
refuse() {
    if out="$(run "$2" "${4-}" 2>/dev/null)"; then
        printf 'FAIL %-30s was accepted: %s\n' "$1" "$out"
        failed=$((failed + 1))
    elif [ -n "$out" ]; then
        printf 'FAIL %-30s refused but printed: %s\n' "$1" "$out"
        failed=$((failed + 1))
    else
        got="$(run "$2" "${4-}" 2>&1 >/dev/null)" || true
        if [ "$got" = "$3" ]; then
            printf 'ok   %-30s refused: %s\n' "$1" "$got"
        else
            printf 'FAIL %-30s want "%s" got "%s"\n' "$1" "$3" "$got"
            failed=$((failed + 1))
        fi
    fi
}

missing='change_log: missing. Add a section "## Change log" to the description, with a line'
missing="$missing \"- <what changed>\" for each change."
no_entry='change_log: the Change log section has no entry. Add a line "- <what changed>" below'
no_entry="$no_entry the heading."
no_text='change_log: an entry has no text. Write what changed after the "- ".'
stray_tail='". Start every entry with "- ", and indent a line that continues an entry by two'
stray_tail="$stray_tail spaces."
stray() {
    printf 'change_log: the Change log section has a line that is not an entry: "%s%s' \
        "$1" "$stray_tail"
}
twice='change_log: given 2 times. Write one "## Change log" section.'
# A code fence, kept in one place because backticks in single quotes trip shellcheck.
# shellcheck disable=SC2016
f='```'
one='- The server tells clients its version.'

check basic '## Change log\n\n- The server tells clients its version.\n' "$one"
check no-final-newline '## Change log\n- A' '- A'
check no-blank-line '## Change log\n- A\n- B\n' '- A\n- B'
check crlf '## Change log\r\n\r\n- A\r\n- B\r\n' '- A\n- B'
check crlf-among-text 'Fix.\r\n\r\n## Change log\r\n\r\n- A\r\n\r\n## Notes\r\n\r\nMore.\r\n' '- A'
check changelog-one-word '## Changelog\n- A\n' '- A'
check lower-case '## change log\n- A\n' '- A'
check upper-case '## CHANGE LOG\n- A\n' '- A'
check mixed-case-one-word '## ChangeLog\n- A\n' '- A'
check heading-level-1 '# Change log\n- A\n' '- A'
check heading-level-3 '### Change log\n- A\n' '- A'
check heading-level-6 '###### Change log\n- A\n' '- A'
check spaces-at-heading-end '## Change log   \n- A\n' '- A'
check tab-at-heading-end '## Change log\t\n- A\n' '- A'
check spaces-after-marks '##   Change log\n- A\n' '- A'
check star-bullets '## Change log\n* A\n* B\n' '- A\n- B'
check mixed-bullets '## Change log\n- A\n* B\n' '- A\n- B'
check continuation '## Change log\n- A long\n  entry here.\n- B\n' '- A long entry here.\n- B'
check continuation-three-lines '## Change log\n- A\n  b\n  c\n' '- A b c'
check continuation-tab '## Change log\n- A\n\tb\n' '- A b'
check continuation-crlf '## Change log\r\n- A\r\n  b\r\n' '- A b'
check continuation-after-blank '## Change log\n- A\n\n  b\n' '- A b'
check continuation-of-star '## Change log\n* A\n  b\n' '- A b'
check blank-lines-ignored '## Change log\n\n\n- A\n\n\n- B\n\n' '- A\n- B'
check spaces-squeezed '## Change log\n- A    b   c\n' '- A b c'
check tabs-squeezed '## Change log\n- A\t\tb\n' '- A b'
check spaces-in-continuation '## Change log\n- A\n      b    c\n' '- A b c'
check trailing-spaces '## Change log\n- A   \n  b   \n' '- A b'
check extra-spaces-after-marker '## Change log\n-    A\n' '- A'
check text-before-section 'Fix a bug.\n\n- not an entry\n\n## Change log\n- A\n' '- A'
check section-between-others '## Why\nText.\n\n## Change log\n- A\n\n## Tests\n- B\n' '- A'
check ends-at-next-heading '## Change log\n- A\n## Tests\n- B\n' '- A'
check ends-at-deeper-heading '## Change log\n- A\n#### Tests\n- B\n' '- A'
check ends-at-empty-heading '## Change log\n- A\n#\n- B\n' '- A'
check comment-hides-example '<!--\n## Change log\n- Example\n-->\n## Change log\n- A\n' '- A'
check comment-one-line-hides-example '<!-- ## Change log -->\n## Change log\n- A\n' '- A'
check comment-in-section '## Change log\n<!-- Write one line. -->\n- A\n' '- A'
check comment-after-entry '## Change log\n- A <!-- note -->\n' '- A'
check comment-spans-lines-in-section '## Change log\n<!--\n- Example\n-->\n- A\n' '- A'
check comment-heading-does-not-end '## Change log\n- A\n<!--\n## Tests\n-->\n- B\n' '- A\n- B'
check comment-after-heading '## Change log <!-- one line per change -->\n- A\n' '- A'
check code-block-hides-example "${f}\n## Change log\n- Example\n${f}\n## Change log\n- A\n" '- A'
check code-block-in-section "## Change log\n${f}\n- Example\n${f}\n- A\n" '- A'
check code-block-heading-does-not-end "## Change log\n- A\n${f}\n## Tests\n${f}\n- B\n" '- A\n- B'
check default-unused 'Bump.\n\n## Change log\n- A\n' '- A' 'Update a dependency.'
check default-fills 'Bump a dependency.\n' '- Update a dependency.' 'Update a dependency.'
check default-for-empty '' '- Update a dependency.' 'Update a dependency.'
check default-for-comment-only '<!--\n## Change log\n- A\n-->\n' '- X' X
check default-for-code-only "${f}\n## Change log\n- A\n${f}\n" '- X' X
check default-for-other-heading '## Notes\n- A\n' '- X' X
check default-kept-as-is 'Bump.\n' '- Bump  a\\b.' 'Bump  a\b.'

refuse empty-description '' "$missing"
refuse text-only 'Fix a bug.\n' "$missing"
refuse other-heading-only '## Notes\n- A\n' "$missing"
refuse comment-only '<!--\n## Change log\n- A\n-->\n' "$missing"
refuse unclosed-comment '<!--\n## Change log\n- A\n' "$missing"
refuse code-block-only "${f}\n## Change log\n- A\n${f}\n" "$missing"
refuse unclosed-code-block "${f}\n## Change log\n- A\n" "$missing"
refuse no-space-after-marks '##Change log\n- A\n' "$missing"
refuse seven-marks '####### Change log\n- A\n' "$missing"
refuse no-marks 'Change log\n- A\n' "$missing"
refuse key-with-colon 'change_log: - A\n' "$missing"
refuse heading-with-more-text '## Change log of this\n- A\n' "$missing"
refuse heading-is-plural '## Change logs\n- A\n' "$missing"
refuse heading-indented ' ## Change log\n- A\n' "$missing"
refuse heading-split '## Change\n- A\n## log\n' "$missing"
refuse two-sections '## Change log\n- A\n\n## Change log\n- B\n' "$twice"
refuse two-sections-spelling '## Change log\n- A\n\n### Changelog\n- B\n' "$twice"
refuse two-sections-crlf '## Change log\r\n- A\r\n## Changelog\r\n- B\r\n' "$twice"
refuse three-sections '# Change log\n- A\n# Change log\n- B\n# Change log\n- C\n' \
    'change_log: given 3 times. Write one "## Change log" section.'
refuse two-sections-one-empty '## Change log\n## Change log\n- A\n' "$twice"
refuse empty-section '## Change log\n' "$no_entry"
refuse blank-section '## Change log\n\n\n' "$no_entry"
refuse empty-section-then-heading '## Change log\n\n## Tests\n- A\n' "$no_entry"
refuse comment-only-section '## Change log\n<!-- - A -->\n' "$no_entry"
refuse code-only-section "## Change log\n${f}\n- A\n${f}\n" "$no_entry"
refuse entry-after-section-ends '## Change log\n## Tests\n- A\n' "$no_entry"
refuse plain-line '## Change log\nThe server tells.\n' "$(stray 'The server tells.')"
refuse plain-line-after-entry '## Change log\n- A\nNo marker here.\n' \
    "$(stray 'No marker here.')"
refuse plain-line-crlf '## Change log\r\nThe server tells.\r\n' "$(stray 'The server tells.')"
refuse one-space-continuation '## Change log\n- A\n b\n' "$(stray b)"
refuse seven-marks-is-no-heading '## Change log\n- A\n####### Tests\n' "$(stray '####### Tests')"
refuse mark-without-space-no-heading '## Change log\n- A\n#1 is next\n' "$(stray '#1 is next')"
refuse marker-without-space '## Change log\n-A\n' "$(stray -A)"
refuse star-without-space '## Change log\n*A\n' "$(stray '*A')"
refuse numbered-list '## Change log\n1. A\n' "$(stray '1. A')"
refuse indented-before-entry '## Change log\n  b\n- A\n' "$(stray b)"
refuse tab-before-entry '## Change log\n\tb\n- A\n' "$(stray b)"
refuse first-plain-line-named '## Change log\n- A\nfirst\nsecond\n' "$(stray first)"
refuse empty-entry '## Change log\n- \n' "$no_text"
refuse empty-entry-no-space '## Change log\n-\n' "$no_text"
refuse empty-star-entry '## Change log\n*   \n' "$no_text"
refuse empty-entry-crlf '## Change log\r\n-\r\n' "$no_text"
refuse empty-entry-after-entry '## Change log\n- A\n- \n- B\n' "$no_text"
refuse empty-entry-with-comment '## Change log\n- <!-- A -->\n' "$no_text"
refuse default-with-two-sections 'Bump.\n## Change log\n- A\n## Change log\n- B\n' "$twice" X
refuse default-with-empty-section '## Change log\n' "$no_entry" X
refuse default-with-plain-line '## Change log\nText.\n' "$(stray 'Text.')" X
refuse default-with-empty-entry '## Change log\n-\n' "$no_text" X

[ "$failed" -eq 0 ] || { echo "$failed failed"; exit 1; }
echo "change log: all descriptions handled as expected"
