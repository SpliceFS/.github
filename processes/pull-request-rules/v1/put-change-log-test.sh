#!/bin/sh
# Table test of put-change-log.sh: which descriptions and entries give which new description,
# and which entries files are refused. Every result is also piped into change-log.sh, which must
# give back exactly the entries, because that is what the bot reads later. Runs on the host (part
# of make check). Text is given as printf %b so the table can show CRLF and newlines.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
cd "$here"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failed=0

# $1 description, $2 entries file text. The sentinel x keeps the newlines at the end, which a
# command substitution would remove, so "exactly one newline" can be compared.
run() {
    printf '%b' "$1" >"$work/description"
    printf '%b' "$2" >"$work/entries"
    sh put-change-log.sh "$work/entries" <"$work/description"
}

# $1 label, $2 description, $3 entries file text, $4 wanted output.
check() {
    want="$(printf '%b' "$4"; printf x)"
    # A refusal shows as its message in got, so it fails the comparison.
    got="$(run "$2" "$3" 2>&1; printf x)"
    if [ "$got" != "$want" ]; then
        printf 'FAIL %-30s want "%s" got "%s"\n' "$1" "${want%x}" "${got%x}"
        failed=$((failed + 1))
        return
    fi
    printf '%s' "${got%x}" >"$work/result"
    # The entries as change-log.sh must give them back: no CR, no trailing blanks, and no bullet
    # without text.
    tr -d '\r' <"$work/entries" | sed 's/[[:space:]]*$//' >"$work/entries-lf"
    want_entries="$(grep '^- .' "$work/entries-lf")"
    if back="$(sh change-log.sh <"$work/result" 2>&1)" && [ "$back" = "$want_entries" ]; then
        printf 'ok   %s\n' "$1"
    else
        printf 'FAIL %-30s change-log.sh wants "%s" got "%s"\n' "$1" "$want_entries" "$back"
        failed=$((failed + 1))
    fi
}

# $1 label, $2 entries file text, or the word missing for a file that does not exist. Nothing may
# reach standard output on a refusal.
refuse() {
    printf '%b' "# Heading\n" >"$work/description"
    if [ "$2" = missing ]; then
        rm -f "$work/entries"
    else
        printf '%b' "$2" >"$work/entries"
    fi
    if out="$(sh put-change-log.sh "$work/entries" <"$work/description" 2>/dev/null)"; then
        printf 'FAIL %-30s was accepted: %s\n' "$1" "$out"
        failed=$((failed + 1))
    elif [ -n "$out" ]; then
        printf 'FAIL %-30s refused but printed: %s\n' "$1" "$out"
        failed=$((failed + 1))
    else
        got="$(sh put-change-log.sh "$work/entries" <"$work/description" 2>&1 >/dev/null)" || true
        if [ "$got" = 'put-change-log: no entries' ]; then
            printf 'ok   %-30s refused: %s\n' "$1" "$got"
        else
            printf 'FAIL %-30s want the refusal got "%s"\n' "$1" "$got"
            failed=$((failed + 1))
        fi
    fi
}

# A code fence, kept in one place because backticks in single quotes trip shellcheck.
# shellcheck disable=SC2016
f='```'
e='- A one.\n- B two.\n'
sect='## Change log\n\n- A one.\n- B two.\n'
scope='## Change scope\n\n- [ ] Patch\n'

# A section that exists is replaced.
check replace-in-middle '## Why\n\nText.\n\n## Change log\n\n- Old.\n\n## Tests\n\nMore.\n' "$e" \
    "## Why\n\nText.\n\n${sect}\n## Tests\n\nMore.\n"
check replace-at-end 'Text.\n\n## Change log\n- Old.\n' "$e" "Text.\n\n${sect}"
check replace-only-section '## Change log\n- Old.\n' "$e" "$sect"
check replace-before-scope '## Change log\n\n- Old.\n\n## Change scope\n\n- [ ] Patch\n' "$e" \
    "${sect}\n${scope}"
check replace-no-final-newline '## Change log\n- Old.' "$e" "$sect"
check replace-empty-section '## Change log\n\n## Tests\n' "$e" "${sect}\n## Tests\n"
check template-empty-bullet \
    "## Summary\n\nText.\n\n## Change log\n\n<!-- Write one line. -->\n- \n\n${scope}" "$e" \
    "## Summary\n\nText.\n\n${sect}\n${scope}"
check replace-drops-comments \
    '## Change log\n<!--\n- Example\n-->\n- Old. <!-- note -->\n\n## Tests\n' "$e" \
    "${sect}\n## Tests\n"
check replace-drops-code-block "## Change log\n${f}\n- Example\n${f}\n- Old.\n\n## Tests\n" "$e" \
    "${sect}\n## Tests\n"
check replace-keeps-heading-spelling '### CHANGELOG\n- Old.\n' "$e" \
    '### CHANGELOG\n\n- A one.\n- B two.\n'
check replace-keeps-heading-level '# change LOG\n- Old.\n' "$e" \
    '# change LOG\n\n- A one.\n- B two.\n'
check replace-keeps-heading-spaces '## Change log   \n- Old.\n' "$e" \
    '## Change log   \n\n- A one.\n- B two.\n'
check replace-heading-with-comment '## Change log <!-- one line -->\n- Old.\n' "$e" \
    '## Change log <!-- one line -->\n\n- A one.\n- B two.\n'
check replace-heading-opens-comment '## Change log <!-- one line\n- Old.\n-->\n' "$e" \
    "${sect}"
check replace-ends-at-deeper-heading '## Change log\n- Old.\n#### Deeper\nText.\n' "$e" \
    "${sect}\n#### Deeper\nText.\n"
check replace-heading-in-comment-does-not-end \
    '## Change log\n- Old.\n<!--\n## Tests\n-->\n- Older.\n## Tests\nMore.\n' "$e" \
    "${sect}\n## Tests\nMore.\n"
check replace-heading-in-code-does-not-end \
    "## Change log\n- Old.\n${f}\n## Tests\n${f}\n- Older.\n## Tests\nMore.\n" "$e" \
    "${sect}\n## Tests\nMore.\n"
check example-in-comment-is-skipped \
    '<!--\n## Change log\n- Example\n-->\n## Change log\n- Old.\n' "$e" \
    '<!--\n## Change log\n- Example\n-->\n## Change log\n\n- A one.\n- B two.\n'
check example-in-code-is-skipped \
    "${f}\n## Change log\n- Example\n${f}\n## Change log\n- Old.\n" "$e" \
    "${f}\n## Change log\n- Example\n${f}\n## Change log\n\n- A one.\n- B two.\n"

# Two or more sections: the first is replaced and the others removed.
check two-sections '## Change log\n- Old.\n\n## Tests\nT.\n\n## Changelog\n- Other.\n' "$e" \
    "${sect}\n## Tests\nT.\n"
check two-sections-adjacent '## Change log\n- Old.\n## Changelog\n- Other.\n## Tests\nT.\n' "$e" \
    "${sect}\n## Tests\nT.\n"
check three-sections '# Change log\n- A\n# CHANGE LOG\n- B\n### Changelog\n- C\n' "$e" \
    '# Change log\n\n- A one.\n- B two.\n'
check two-sections-with-text \
    '## Why\nW.\n## Change log\n- Old.\n## Notes\nN.\n## Change log\n- X\n## End\nE.\n' "$e" \
    "## Why\nW.\n${sect}\n## Notes\nN.\n## End\nE.\n"

# No section: before "Change scope", else at the end.
check insert-before-scope 'Text.\n\n## Change scope\n\n- [ ] Patch\n' "$e" \
    "Text.\n\n${sect}\n${scope}"
check insert-before-scope-spelling 'Text.\n\n### CHANGE scope\n- [ ] Patch\n' "$e" \
    'Text.\n\n## Change log\n\n- A one.\n- B two.\n\n### CHANGE scope\n- [ ] Patch\n'
check insert-before-scope-only "$scope" "$e" "${sect}\n${scope}"
check insert-directly-before-scope 'Text.\n## Change scope\nPatch\n' "$e" \
    'Text.\n## Change log\n\n- A one.\n- B two.\n\n## Change scope\nPatch\n'
check insert-before-first-scope 'T.\n## Change scope\nOne.\n## Change scope\nTwo.\n' "$e" \
    'T.\n## Change log\n\n- A one.\n- B two.\n\n## Change scope\nOne.\n## Change scope\nTwo.\n'
check scope-in-comment-is-skipped 'Text.\n<!--\n## Change scope\n-->\n' "$e" \
    'Text.\n<!--\n## Change scope\n-->\n\n## Change log\n\n- A one.\n- B two.\n'
check scope-in-code-is-skipped "Text.\n${f}\n## Change scope\n${f}\n" "$e" \
    "Text.\n${f}\n## Change scope\n${f}\n\n${sect}"
check scope-with-more-text-is-skipped 'Text.\n## Change scope of this\n' "$e" \
    'Text.\n## Change scope of this\n\n## Change log\n\n- A one.\n- B two.\n'
check append-neither 'Fix a bug.\n' "$e" "Fix a bug.\n\n${sect}"
check append-no-final-newline 'Fix a bug.' "$e" "Fix a bug.\n\n${sect}"
check append-after-trailing-blanks 'Fix a bug.\n\n\n\n' "$e" "Fix a bug.\n\n${sect}"
check append-after-other-heading '## Why\n\nText.\n' "$e" "## Why\n\nText.\n\n${sect}"
check append-empty-description '' "$e" "$sect"
check append-blank-description '\n\n' "$e" "$sect"
check append-plural-heading '## Change logs\n- A\n' "$e" "## Change logs\n- A\n\n${sect}"
check append-closes-comment 'Text.\n<!--\nnote\n' "$e" "Text.\n<!--\nnote\n-->\n\n${sect}"
check append-closes-code "Text.\n${f}\ncode\n" "$e" "Text.\n${f}\ncode\n${f}\n\n${sect}"

# CRLF in, LF out, the rest unchanged.
check crlf-replace \
    '## Why\r\n\r\nText.\r\n\r\n## Change log\r\n\r\n- Old.\r\n\r\n## Tests\r\n' "$e" \
    "## Why\n\nText.\n\n${sect}\n## Tests\n"
check crlf-insert 'Text.\r\n\r\n## Change scope\r\n\r\n- [ ] Patch\r\n' "$e" \
    "Text.\n\n${sect}\n## Change scope\n\n- [ ] Patch\n"
check crlf-append 'Text.\r\n' "$e" "Text.\n\n${sect}"
check crlf-empty-bullet '## Change log\r\n\r\n- \r\n' "$e" "$sect"
check crlf-entries 'Text.\r\n' '- A one.\r\n- B two.\r\n' "Text.\n\n${sect}"
check rest-unchanged \
    'Back\\slash  and   spaces\t.\n\n* [ ] item\n> quote\n\n## Change scope\n' "$e" \
    "Back\\\\slash  and   spaces\t.\n\n* [ ] item\n> quote\n\n${sect}\n## Change scope\n"

# The entries file: only lines that start with "- " count, and their text is kept as it is.
check one-entry 'Text.\n' '- Only one.\n' 'Text.\n\n## Change log\n\n- Only one.\n'
check entries-with-other-lines 'Text.\n' \
    'Intro.\n- A one.\n\n* Star.\n  - Nested.\n- B two.\nEnd.\n' \
    "Text.\n\n${sect}"
check entries-no-final-newline 'Text.\n' '- A one.\n- B two.' "Text.\n\n${sect}"
check entries-with-backslash 'Text.\n' '- Use a\\b.\n' 'Text.\n\n## Change log\n\n- Use a\\b.\n'
check entries-trailing-spaces 'Text.\n' '- A one.   \n- B two.\t\n' "Text.\n\n${sect}"
check entries-empty-bullet-skipped 'Text.\n' '- \n- A one.\n-\n- B two.\n' "Text.\n\n${sect}"

refuse entries-missing missing
refuse entries-empty ''
refuse entries-blank '\n\n'
refuse entries-no-bullet 'A one.\nB two.\n'
refuse entries-star-bullet '* A one.\n'
refuse entries-no-space '-A one.\n'
refuse entries-empty-bullet '- \n'
refuse entries-empty-bullet-crlf '- \r\n'
refuse entries-indented '  - A one.\n'

# A folder in place of the file, and no argument at all.
mkdir "$work/folder"
if out="$(printf 'Text.\n' | sh put-change-log.sh "$work/folder" 2>&1)" ||
    [ "$out" != 'put-change-log: no entries' ]; then
    printf 'FAIL %-30s got "%s"\n' entries-folder "$out"
    failed=$((failed + 1))
else
    printf 'ok   %s\n' entries-folder
fi
if out="$(printf 'Text.\n' | sh put-change-log.sh 2>&1)" ||
    [ "$out" != 'put-change-log: no entries' ]; then
    printf 'FAIL %-30s got "%s"\n' no-argument "$out"
    failed=$((failed + 1))
else
    printf 'ok   %s\n' no-argument
fi

[ "$failed" -eq 0 ] || { echo "$failed failed"; exit 1; }
echo "put change log: all descriptions handled as expected"
