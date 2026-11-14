#!/bin/sh
# Table test of body.sh: which change log and versions give which pull request description, and
# which inputs are refused with which message. Runs on the host (part of make check). Change
# logs and wanted entries are given as printf %b text so the table can show newlines.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
cd "$here"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM
log="$work/CHANGELOG.md"
failed=0

# The wanted description for $1 from, $2 to, $3 scope and $4 entries (printf %b text). Written out
# here again, apart from body.sh, so that a change to the shape of the description shows in this
# test.
description() {
    printf '## What changes\n\n'
    printf "Moves the shared code (\`github.com/SpliceFS/common\`) from version %s to %s. This\n" \
        "$1" "$2"
    printf 'pull request was opened automatically when that version was released.\n\n'
    printf '## Change log\n\n'
    printf '%b\n\n' "$4"
    printf '## Change scope\n\nchange_scope: %s\n' "$3"
}

# $1 label, $2 change log as printf %b text, $3 from, $4 to, $5 scope, $6 wanted entries as
# printf %b text. The whole output is compared byte for byte, so a trailing space or a missing
# final newline fails.
check() {
    printf '%b' "$2" >"$log"
    description "$3" "$4" "$5" "$6" >"$work/want"
    if sh body.sh "$log" "$3" "$4" "$5" >"$work/got" 2>&1; then
        if cmp -s "$work/want" "$work/got"; then
            printf 'ok   %-32s %s to %s, %s\n' "$1" "$3" "$4" "$5"
        else
            printf 'FAIL %-32s want:\n%s\ngot:\n%s\n' "$1" "$(cat "$work/want")" "$(cat "$work/got")"
            failed=$((failed + 1))
        fi
    else
        printf 'FAIL %-32s was refused: %s\n' "$1" "$(cat "$work/got")"
        failed=$((failed + 1))
    fi
}

# $1 label, $2 the exact message, then the arguments to pass. Every refusal is status 2 and
# nothing may reach standard output.
refuse_args() {
    label="$1"
    want_message="$2"
    shift 2
    status=0
    out="$(sh body.sh "$@" 2>/dev/null)" || status=$?
    if [ "$status" -eq 0 ]; then
        printf 'FAIL %-32s was accepted: %s\n' "$label" "$out"
        failed=$((failed + 1))
        return 0
    fi
    got="$(sh body.sh "$@" 2>&1 >/dev/null)" || true
    if [ -n "$out" ]; then
        printf 'FAIL %-32s refused but printed: %s\n' "$label" "$out"
        failed=$((failed + 1))
    elif [ "$status" -ne 2 ]; then
        printf 'FAIL %-32s want status 2 got %s\n' "$label" "$status"
        failed=$((failed + 1))
    elif [ "$got" = "$want_message" ]; then
        printf 'ok   %-32s refused: %s\n' "$label" "$got"
    else
        printf 'FAIL %-32s want "%s" got "%s"\n' "$label" "$want_message" "$got"
        failed=$((failed + 1))
    fi
}

usage='usage: body.sh <CHANGELOG.md> <from> <to> <scope>'
not_xyz() { printf 'body: "%s" is not X.Y.Z' "$1"; }
bad_scope() { printf 'body: scope "%s" is not revision or minor' "$1"; }

# The shared code's change log: the newest section first, an unreleased section, and a summary
# heading between releases. Their entries must never be taken.
shared='# Change log\n\nAll changes are listed here.\n\n'
shared="$shared## [Unreleased]\n\n- Not released yet.\n\n"
shared="$shared## [0.4.0] - 2026-04-01\n\n- Fourth.\n\n"
shared="$shared## [0.3.1] - 2026-03-15\n\n- Third b.\n\n"
shared="$shared## [0.3.0] - 2026-03-01\n\n- Third a.\n  A second line of third a.\n- Third c.\n\n"
shared="$shared## [0.1.1 to 0.2.3]\n\n- A summary of older versions.\n\n"
shared="$shared## [0.2.0] - 2026-02-01\n\n- Second.\n\n"
shared="$shared## [0.1.0] - 2026-01-01\n\n- First.\n"

# One section.
check one-section "$shared" 0.3.0 0.3.1 revision '- Third b.'
check one-section-minor "$shared" 0.3.1 0.4.0 minor '- Fourth.'
check one-section-oldest "$shared" 0.0.9 0.1.0 minor '- First.'
check from-is-left-out "$shared" 0.2.0 0.3.0 minor '- Third a.\n  A second line of third a.\n- Third c.'
check to-is-included "$shared" 0.1.0 0.2.0 minor '- Second.'
check section-between-versions "$shared" 0.3.5 0.4.0 minor '- Fourth.'
check from-not-in-file "$shared" 0.2.9 0.3.0 minor '- Third a.\n  A second line of third a.\n- Third c.'

# Several sections: newest first, the older ones and the from version left out, the unreleased
# section and the summary heading skipped.
check several-sections "$shared" 0.2.0 0.4.0 minor \
    '- Fourth.\n- Third b.\n- Third a.\n  A second line of third a.\n- Third c.'
check all-sections "$shared" 0.0.0 0.4.0 minor \
    '- Fourth.\n- Third b.\n- Third a.\n  A second line of third a.\n- Third c.\n- Second.\n- First.'
check newer-than-to-left-out "$shared" 0.0.0 0.3.0 minor \
    '- Third a.\n  A second line of third a.\n- Third c.\n- Second.\n- First.'
check summary-heading-skipped "$shared" 0.1.0 0.2.0 minor '- Second.'
check unreleased-left-out "$shared" 0.3.1 0.9.9 minor '- Fourth.'
check file-order-kept '## [0.2.0] - 2026-02-01\n- Old.\n\n## [0.3.0] - 2026-03-01\n- New.\n' \
    0.1.0 0.3.0 minor '- Old.\n- New.'

# Numbers, not text.
numbers='## [0.10.0] - 2026-06-01\n- Ten.\n\n## [0.9.9] - 2026-05-01\n- Nine nine.\n\n'
numbers="$numbers## [0.9.10] - 2026-05-20\n- Nine ten.\n\n## [0.2.0] - 2026-02-01\n- Two.\n"
check numbers-not-text "$numbers" 0.9.9 0.10.0 minor '- Ten.\n- Nine ten.'
check numbers-all-above-two "$numbers" 0.2.0 0.10.0 minor '- Ten.\n- Nine nine.\n- Nine ten.'
check numbers-single "$numbers" 0.9.9 0.9.10 revision '- Nine ten.'
check numbers-two-is-lower "$numbers" 0.0.1 0.2.0 minor '- Two.'

# Entries are kept byte for byte: spaces, tabs, markup, percent signs, backslashes, a nested
# list and trailing spaces. Blank lines and text that is not an entry are not.
bytes='## [0.2.0] - 2026-02-01\n\n'
bytes="${bytes}- Keeps  double spaces and a \`code\` span, 100% and a\\\\b.\n"
bytes="${bytes}    - Four spaces and a nested bullet.\n"
bytes="${bytes}  Two spaces, trailing spaces.   \n"
bytes="${bytes}\n"
bytes="${bytes}- Second entry.  \n"
bytes="${bytes}  - Nested two spaces.\n"
bytes="${bytes}Plain text between entries.\n"
bytes="${bytes}  Not a continuation, the entry before it is over.\n"
bytes="${bytes}### A deeper heading\n"
bytes="${bytes}- Third entry, after a deeper heading.\n"
bytes="${bytes}\tTab is not a continuation.\n\n## [0.1.0] - 2026-01-01\n- Old.\n"
kept="- Keeps  double spaces and a \`code\` span, 100% and a\\\\b.\n"
kept="$kept    - Four spaces and a nested bullet.\n"
kept="$kept  Two spaces, trailing spaces.   \n"
kept="$kept- Second entry.  \n"
kept="$kept  - Nested two spaces.\n"
kept="$kept- Third entry, after a deeper heading."
check bytes-kept "$bytes" 0.1.0 0.2.0 minor "$kept"
check crlf '## [0.2.0] - 2026-02-01\r\n\r\n- One.\r\n  Two.\r\n\r\n## [0.1.0] - 2026-01-01\r\n- Old.\r\n' \
    0.1.0 0.2.0 minor '- One.\r\n  Two.\r'
check heading-trailing-spaces '## [0.2.0] - 2026-02-01  \n- Two.\n' 0.1.0 0.2.0 minor '- Two.'
check no-final-newline '## [0.2.0] - 2026-02-01\n- Two.' 0.1.0 0.2.0 minor '- Two.'
check entries-before-first-heading '- Stray.\n## [0.2.0] - 2026-02-01\n- Two.\n' 0.1.0 0.2.0 minor '- Two.'
check section-with-two-versions-text '## [0.2.0] - 2026-02-01\n- Mentions ## [0.3.0] - 2026-03-01 here.\n' \
    0.1.0 0.2.0 minor '- Mentions ## [0.3.0] - 2026-03-01 here.'
check title-ends-section '## [0.2.0] - 2026-02-01\n- Two.\n# Appendix\n- Not two.\n' \
    0.1.0 0.2.0 minor '- Two.'

# No matching section: the fallback entry.
fallback() { printf '%s' "- Internal: built with version $1 of the shared code."; }
check no-newer-section "$shared" 0.4.0 0.4.1 revision "$(fallback 0.4.1)"
check to-below-all "$shared" 0.0.1 0.0.2 revision "$(fallback 0.0.2)"
check gap-between-sections "$shared" 0.2.0 0.2.9 revision "$(fallback 0.2.9)"
check from-equals-to "$shared" 0.3.0 0.3.0 revision "$(fallback 0.3.0)"
check from-above-to "$shared" 0.4.0 0.3.0 revision "$(fallback 0.3.0)"
check empty-file '' 0.1.0 0.2.0 minor "$(fallback 0.2.0)"
check only-unreleased '## [Unreleased]\n- Soon.\n' 0.1.0 0.2.0 minor "$(fallback 0.2.0)"
check only-summary '## [0.1.1 to 0.2.3]\n- Sum.\n' 0.1.0 0.2.0 minor "$(fallback 0.2.0)"
check section-without-entries '## [0.2.0] - 2026-02-01\n\nText only.\n\n## [0.1.0] - 2026-01-01\n- Old.\n' \
    0.1.0 0.2.0 minor "$(fallback 0.2.0)"
check heading-without-date '## [0.2.0]\n- Two.\n' 0.1.0 0.2.0 minor "$(fallback 0.2.0)"
check heading-with-v '## [v0.2.0] - 2026-02-01\n- Two.\n' 0.1.0 0.2.0 minor "$(fallback 0.2.0)"
check heading-level-three '### [0.2.0] - 2026-02-01\n- Two.\n' 0.1.0 0.2.0 minor "$(fallback 0.2.0)"
check bad-date '## [0.2.0] - soon\n- Two.\n' 0.1.0 0.2.0 minor "$(fallback 0.2.0)"

# Both scopes, in the shape of the description.
check scope-revision "$shared" 0.3.0 0.3.1 revision '- Third b.'
check scope-minor "$shared" 0.3.0 0.3.1 minor '- Third b.'

# Wrong calls.
printf '%b' "$shared" >"$log"
refuse_args no-arguments "$usage"
refuse_args one-argument "$usage" "$log"
refuse_args three-arguments "$usage" "$log" 0.1.0 0.2.0
refuse_args five-arguments "$usage" "$log" 0.1.0 0.2.0 minor extra
for bad in v0.1.0 0.1 0.1.0.1 0.1.0-rc.1 0.1.x 0..1 .0.1.0 0.1.0. -0.1.0 ' 0.1.0' '0.1.0 ' ''; do
    refuse_args "from-$bad" "$(not_xyz "$bad")" "$log" "$bad" 0.2.0 minor
    refuse_args "to-$bad" "$(not_xyz "$bad")" "$log" 0.1.0 "$bad" minor
done
refuse_args from-two-lines "$(not_xyz '0.1.0
0.1.1')" "$log" '0.1.0
0.1.1' 0.2.0 minor
for bad in major patch none Minor REVISION 'minor ' ''; do
    refuse_args "scope-$bad" "$(bad_scope "$bad")" "$log" 0.1.0 0.2.0 "$bad"
done
# Neither a missing file, nor a folder, nor a link to nothing can be read. No file permission is
# removed, so this also fails as root.
ln -s "$work/nothing" "$work/dangling"
mkdir "$work/folder"
refuse_args missing-file "body: cannot read $work/missing" "$work/missing" 0.1.0 0.2.0 minor
refuse_args folder-as-file "body: cannot read $work/folder" "$work/folder" 0.1.0 0.2.0 minor
refuse_args dangling-link "body: cannot read $work/dangling" "$work/dangling" 0.1.0 0.2.0 minor
refuse_args version-before-file "$(not_xyz v1)" "$work/missing" v1 0.2.0 minor

[ "$failed" -eq 0 ] || { echo "$failed failed"; exit 1; }
echo "body: all change logs and versions handled as expected"
