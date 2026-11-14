#!/bin/sh
# Test of set-version.sh in throwaway git repositories: first version, revision and minor,
# unchanged, correcting a wrong committed value, the change log section, and every refusal. Part
# of make check.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/set-version.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failed=0

pass() { printf 'ok   %s\n' "$1"; }
fail() {
    printf 'FAIL %s\n' "$1"
    failed=$((failed + 1))
}
# $1 label, $2 wanted, $3 got.
eq() {
    if [ "$2" = "$3" ]; then pass "$1"; else fail "$1: want \"$2\" got \"$3\""; fi
}

# Explicit identity so the test never depends on the machine's git configuration.
tg() { git -c user.name=Dev -c user.email=dev@example.com -c commit.gpgsign=false "$@"; }

# $1 repository name, $2 VERSION on the base branch (empty for no file), $3 optional file that
# becomes CHANGELOG.md on the base branch. Leaves the shell inside the new repository on branch pr,
# one commit after origin/main.
newrepo() {
    rm -rf "${work:?}/$1"
    mkdir "$work/$1"
    cd "$work/$1"
    git init -q 2>/dev/null
    git symbolic-ref HEAD refs/heads/main
    echo hello >README
    if [ -n "$2" ]; then echo "$2" >VERSION; fi
    if [ -n "${3:-}" ]; then cp "$3" CHANGELOG.md; fi
    git add -A
    tg commit -q -m Base
    git update-ref refs/remotes/origin/main HEAD
    git checkout -q -b pr
    echo work >feature.txt
    git add feature.txt
    tg commit -q -m Feature
}

# $1 label, $2 wanted message; judges the rc and out of the last run, which must be a refusal.
refused() {
    if [ "$rc" -ne 0 ]; then eq "$1" "$2" "$out"; else fail "$1: accepted: $out"; fi
}

# Runs the script with the bot identity; sets rc and out.
sv() {
    rc=0
    out="$(BOT_NAME=Bot BOT_EMAIL=bot@example.com sh "$script" "$@" 2>&1)" || rc=$?
}

# $1 label, $2 wanted output, then the arguments.
expect_ok() {
    label="$1"
    want="$2"
    shift 2
    sv "$@"
    if [ "$rc" -eq 0 ]; then eq "$label" "$want" "$out"; else fail "$label: refused: $out"; fi
}

# $1 label, $2 wanted message, then the arguments.
expect_refused() {
    label="$1"
    want="$2"
    shift 2
    sv "$@"
    if [ "$rc" -ne 0 ]; then eq "$label" "$want" "$out"; else fail "$label: accepted: $out"; fi
}

# Runs the script with the bot identity, the entry file $entry and the fixed date; sets rc and out.
svc() {
    rc=0
    out="$(CHANGELOG_ENTRY_FILE="$entry" CHANGELOG_DATE=2026-11-13 \
        BOT_NAME=Bot BOT_EMAIL=bot@example.com sh "$script" "$@" 2>&1)" || rc=$?
}

# $1 label, $2 wanted output, then the arguments; like expect_ok, with the change log inputs.
expect_ok_log() {
    label="$1"
    want="$2"
    shift 2
    svc "$@"
    if [ "$rc" -eq 0 ]; then eq "$label" "$want" "$out"; else fail "$label: refused: $out"; fi
}

# $1 label, $2 wanted message, then the arguments; like expect_refused, with the change log inputs.
expect_refused_log() {
    label="$1"
    want="$2"
    shift 2
    svc "$@"
    if [ "$rc" -ne 0 ]; then eq "$label" "$want" "$out"; else fail "$label: accepted: $out"; fi
}

# $1 label. Compares CHANGELOG.md byte for byte with the intro of the base file, the new section
# in $work/section.md, and the older sections of the base file.
log_is() {
    cat "$work/head.md" "$work/section.md" "$work/tail.md" >"$work/want.md"
    if cmp -s "$work/want.md" CHANGELOG.md; then
        pass "$1"
    else
        fail "$1: $(diff "$work/want.md" CHANGELOG.md | head -8)"
    fi
}

# $1 label. Compares CHANGELOG.md byte for byte with the base file.
log_is_base() {
    if cmp -s "$work/base.md" CHANGELOG.md; then
        pass "$1"
    else
        fail "$1: $(diff "$work/base.md" CHANGELOG.md | head -8)"
    fi
}

# The change log of the base branch: an intro and two sections, one of them wrapped.
printf '%s\n' '# Changelog' '' 'Intro text.' '' >"$work/head.md"
printf '%s\n' \
    '## [0.3.2] - 2026-11-12' \
    '' \
    '- An older entry that was wrapped at one hundred columns by the bot in an earlier' \
    '  release.' \
    '' \
    '## [0.3.1] - 2026-11-11' \
    '' \
    '- The oldest entry.' >"$work/tail.md"
cat "$work/head.md" "$work/tail.md" >"$work/base.md"
entry="$work/entry.txt"

newrepo first ''
expect_ok 'no VERSION on base, minor' 'version: 0.1.0 (committed)' minor
eq 'file holds the version' 0.1.0 "$(cat VERSION)"
eq 'commit subject' 'Set version to 0.1.0' "$(git log -1 --format=%s)"
eq 'trailer present' 'Version-Commit: true' \
    "$(git log -1 --format=%B | git interpret-trailers --only-trailers)"
eq 'commit author is the bot' 'Bot <bot@example.com>' "$(git log -1 --format='%an <%ae>')"
eq 'commit committer is the bot' 'Bot <bot@example.com>' "$(git log -1 --format='%cn <%ce>')"
eq 'only VERSION is in the commit' VERSION "$(git show --name-only --format= HEAD)"
expect_ok 'second run is unchanged' 'version: 0.1.0 (unchanged)' minor
eq 'unchanged adds no commit' 2 "$(git rev-list --count origin/main..HEAD)"

newrepo first-revision ''
expect_ok 'no VERSION on base, revision' 'version: 0.0.1 (committed)' revision

newrepo revision 1.2.3
expect_ok 'revision from 1.2.3' 'version: 1.2.4 (committed)' revision
newrepo minor 1.2.3
expect_ok 'minor from 1.2.3' 'version: 1.3.0 (committed)' minor
newrepo carry 1.9.9
expect_ok 'minor from 1.9.9' 'version: 1.10.0 (committed)' minor

newrepo wrong 1.2.3
echo 9.9.9 >VERSION
git add VERSION
tg commit -q -m 'Wrong version'
expect_ok 'wrong committed value is corrected' 'version: 1.2.4 (committed)' revision
eq 'corrected file' 1.2.4 "$(cat VERSION)"
eq 'working tree clean after correction' '' "$(git status --porcelain)"
expect_ok 'unchanged after correction' 'version: 1.2.4 (unchanged)' revision

newrepo scope-changed 1.2.3
expect_ok 'first scope' 'version: 1.2.4 (committed)' revision
expect_ok 'changed scope is corrected' 'version: 1.3.0 (committed)' minor

newrepo uncommitted 1.2.3
echo 1.2.4 >VERSION
expect_ok 'wanted but uncommitted value is committed' 'version: 1.2.4 (committed)' revision
eq 'that commit holds VERSION' VERSION "$(git show --name-only --format= HEAD)"
eq 'nothing left uncommitted' '' "$(git status --porcelain)"

newrepo staged-version 1.2.3
echo 1.2.4 >VERSION
git add VERSION
expect_ok 'staged wanted value is committed' 'version: 1.2.4 (committed)' revision
eq 'staged commit made' 'Set version to 1.2.4' "$(git log -1 --format=%s)"

newrepo untracked 1.2.3
echo scratch >scratch.txt
expect_ok 'untracked file does not block' 'version: 1.2.4 (committed)' revision
eq 'untracked file stays out of the commit' VERSION "$(git show --name-only --format= HEAD)"
eq 'untracked file is still there' '?? scratch.txt' "$(git status --porcelain)"

newrepo dirty 1.2.3
echo changed >feature.txt
before="$(git rev-parse HEAD)"
expect_refused 'dirty tree is refused' \
    'set-version: the working tree has uncommitted changes besides VERSION' revision
eq 'dirty tree: no commit' "$before" "$(git rev-parse HEAD)"
eq 'dirty tree: VERSION untouched' 1.2.3 "$(cat VERSION)"
eq 'dirty tree: change kept' changed "$(cat feature.txt)"

newrepo staged 1.2.3
echo changed >feature.txt
git add feature.txt
expect_refused 'staged change is refused' \
    'set-version: the working tree has uncommitted changes besides VERSION' revision

newrepo ident 1.2.3
before="$(git rev-parse HEAD)"
rc=0
out="$(BOT_EMAIL=bot@example.com sh "$script" revision 2>&1)" || rc=$?
refused 'missing BOT_NAME is refused' 'set-version: BOT_NAME is required'
rc=0
out="$(BOT_NAME=Bot sh "$script" revision 2>&1)" || rc=$?
refused 'missing BOT_EMAIL is refused' 'set-version: BOT_EMAIL is required'
rc=0
out="$(BOT_NAME='' BOT_EMAIL='' sh "$script" revision 2>&1)" || rc=$?
refused 'empty identity is refused' 'set-version: BOT_NAME is required'
eq 'identity refusal: no commit' "$before" "$(git rev-parse HEAD)"

newrepo override 1.2.3
git update-ref refs/remotes/origin/release HEAD
git checkout -q -b release-base
echo 5.0.0 >VERSION
tg commit -q -a -m 'Release base'
git update-ref refs/remotes/origin/release HEAD
git checkout -q pr
rc=0
out="$(BASE_REF=origin/release BOT_NAME=Bot BOT_EMAIL=bot@example.com sh "$script" minor 2>&1)" ||
    rc=$?
eq 'BASE_REF is honored' 'version: 5.1.0 (committed)' "$out"

newrepo no-base 1.2.3
rc=0
out="$(BASE_REF=origin/nope BOT_NAME=Bot BOT_EMAIL=bot@example.com sh "$script" revision 2>&1)" ||
    rc=$?
eq 'unknown BASE_REF is refused' 'set-version: base ref "origin/nope" does not exist' "$out"

newrepo bad-base 'v1.2'
expect_ok 'invalid base VERSION is ignored' 'version: 0.0.1 (committed)' revision

newrepo tag-only ''
git tag v2.3.4 origin/main
expect_ok 'release tag without a VERSION file is the base' 'version: 2.3.5 (committed)' revision

newrepo tag-higher 1.2.3
git tag v1.4.0 origin/main
expect_ok 'release tag higher than VERSION is the base' 'version: 1.5.0 (committed)' minor

newrepo file-higher 1.5.0
git tag v1.4.0 origin/main
expect_ok 'VERSION higher than the release tag is the base' 'version: 1.5.1 (committed)' revision

newrepo tag-suffix 1.2.3
git tag v1.9.0-rc.1 origin/main
expect_ok 'tag with a suffix is ignored' 'version: 1.2.4 (committed)' revision

newrepo bad-scope 1.2.3
expect_refused 'bad scope is refused' \
    'next-version: scope "major" cannot be released from this repository' major

newrepo subdir 1.2.3
mkdir deep
cd deep
expect_ok 'works from a subdirectory' 'version: 1.2.4 (committed)' revision
eq 'subdirectory run writes the top VERSION' 1.2.4 "$(cat ../VERSION)"
cd "$work/subdir"
eq 'no stray VERSION in the subdirectory' no "$([ -e deep/VERSION ] && echo yes || echo no)"

newrepo usage 1.2.3
rc=0
out="$(sh "$script" 2>&1)" || rc=$?
refused 'no arguments print usage' 'usage: set-version.sh <scope>'

printf '%s\n' '- The server tells clients its version.' >"$entry"
newrepo log 0.3.2 "$work/base.md"
expect_ok_log 'change log: committed' 'version: 0.3.3 (committed)' revision
printf '%s\n' '## [0.3.3] - 2026-11-13' '' '- The server tells clients its version.' '' \
    >"$work/section.md"
log_is 'change log: section before the newest one, date from CHANGELOG_DATE'
eq 'change log: VERSION and CHANGELOG.md are in one commit' 'CHANGELOG.md
VERSION' "$(git show --name-only --format= HEAD)"
eq 'change log: commit subject' 'Set version to 0.3.3' "$(git log -1 --format=%s)"
eq 'change log: trailer present' 'Version-Commit: true' \
    "$(git log -1 --format=%B | git interpret-trailers --only-trailers)"
eq 'change log: commit author is the bot' 'Bot <bot@example.com>' \
    "$(git log -1 --format='%an <%ae>')"
eq 'change log: working tree clean' '' "$(git status --porcelain)"
expect_ok_log 'change log: second run is unchanged' 'version: 0.3.3 (unchanged)' revision
eq 'change log: unchanged adds no commit' 2 "$(git rev-list --count origin/main..HEAD)"
log_is 'change log: unchanged leaves the file as it was'

# Boundaries: a line may hold 100 columns, a longer word stays whole, and a bullet starts a line.
word49="$(printf '%049d' 0 | tr 0 a)"
word48="$(printf '%048d' 0 | tr 0 b)"
word120="$(printf '%0120d' 0 | tr 0 c)"
printf '%s\n' "- $word49 $word48 short $word120 end" '- Second bullet.' >"$entry"
newrepo wrap 0.3.2 "$work/base.md"
expect_ok_log 'wrap: committed' 'version: 0.3.3 (committed)' revision
printf '%s\n' '## [0.3.3] - 2026-11-13' '' "- $word49 $word48" '  short' "  $word120" '  end' \
    '- Second bullet.' '' >"$work/section.md"
log_is 'wrap: 100 columns fit, longer word whole, continuation with two spaces'

printf '%s\n' '- A path C:\new\table and a * star stay as written.' >"$entry"
newrepo backslash 0.3.2 "$work/base.md"
expect_ok_log 'backslash: committed' 'version: 0.3.3 (committed)' revision
printf '%s\n' '## [0.3.3] - 2026-11-13' '' '- A path C:\new\table and a * star stay as written.' \
    '' \
    >"$work/section.md"
log_is 'backslash: entry is written as it is'

# A stale section of this branch and a heading the author typed are replaced. The base sections
# stay.
printf '%s\n' '- The entry of the description.' >"$entry"
newrepo stale 0.3.2 "$work/base.md"
{
    cat "$work/head.md"
    printf '%s\n' '## [1.0.0] - 2026-01-01' '' '- Typed by the author.' ''
    printf '%s\n' '## [0.3.3] - 2026-11-12' '' '- Entry of an earlier version commit.' ''
    cat "$work/tail.md"
} >CHANGELOG.md
tg commit -q -a -m 'Stale sections'
expect_ok_log 'stale: committed' 'version: 0.3.3 (committed)' revision
printf '%s\n' '## [0.3.3] - 2026-11-13' '' '- The entry of the description.' '' >"$work/section.md"
log_is 'stale: other versions removed, new section made, base sections byte for byte'

newrepo stale-last 0.3.2 "$work/base.md"
{
    cat "$work/base.md"
    printf '%s\n' '' '## [0.1.0] - 2020-01-01' '' '- Not in the base.' ''
} >CHANGELOG.md
tg commit -q -a -m 'Stale last section'
expect_ok_log 'stale last section: committed' 'version: 0.3.3 (committed)' revision
log_is 'stale last section: removed, file ends with one newline'

# An uncommitted edit of CHANGELOG.md is fine: it is rewritten and committed with VERSION.
newrepo uncommitted-log 0.3.2 "$work/base.md"
printf '%s\n' '' '## [0.3.3] - 2026-11-01' '' '- Typed, not committed.' >>CHANGELOG.md
expect_ok_log 'uncommitted change log does not block' 'version: 0.3.3 (committed)' revision
log_is 'uncommitted change log: replaced by the new section'
eq 'uncommitted change log: nothing left over' '' "$(git status --porcelain)"

# A changed entry replaces the section of the same version, in a commit of its own.
newrepo changed 0.3.2 "$work/base.md"
expect_ok_log 'changed: first entry' 'version: 0.3.3 (committed)' revision
printf '%s\n' '- The changed entry.' >"$entry"
expect_ok_log 'changed: new entry is committed' 'version: 0.3.3 (committed)' revision
printf '%s\n' '## [0.3.3] - 2026-11-13' '' '- The changed entry.' '' >"$work/section.md"
log_is 'changed: section replaced, not added'
eq 'changed: a new commit' 3 "$(git rev-list --count origin/main..HEAD)"
eq 'changed: the section exists once' 1 "$(grep -c '^## \[0.3.3\]' CHANGELOG.md)"
expect_ok_log 'changed: then unchanged' 'version: 0.3.3 (unchanged)' revision

newrepo changed-scope 0.3.2 "$work/base.md"
expect_ok_log 'changed scope: revision' 'version: 0.3.3 (committed)' revision
expect_ok_log 'changed scope: minor' 'version: 0.4.0 (committed)' minor
printf '%s\n' '## [0.4.0] - 2026-11-13' '' '- The changed entry.' '' >"$work/section.md"
log_is 'changed scope: the section of the new version only'

# No version heading: the section is appended after one blank line, whatever the file ended with.
printf '%s\n' '# Changelog' '' 'Intro text.' >"$work/plain.md"
printf '%s\n' '- First entry.' >"$entry"
newrepo no-heading '' "$work/plain.md"
expect_ok_log 'no heading: committed' 'version: 0.0.1 (committed)' revision
printf '%s\n' '# Changelog' '' 'Intro text.' '' '## [0.0.1] - 2026-11-13' '' '- First entry.' \
    >"$work/want.md"
if cmp -s "$work/want.md" CHANGELOG.md; then
    pass 'no heading: section appended'
else
    fail "no heading: $(diff "$work/want.md" CHANGELOG.md | head -8)"
fi
printf '%s\n' '# Changelog' '' 'Intro text.' '' '' >"$work/blank-end.md"
newrepo blank-end '' "$work/blank-end.md"
expect_ok_log 'blank lines at the end: committed' 'version: 0.0.1 (committed)' revision
if cmp -s "$work/want.md" CHANGELOG.md; then
    pass 'blank lines at the end: one blank line before the section'
else
    fail "blank lines at the end: $(diff "$work/want.md" CHANGELOG.md | head -8)"
fi

# Nothing to do with the change log without the file, or without the variable.
newrepo no-log 1.2.3
expect_ok_log 'no CHANGELOG.md: as before' 'version: 1.2.4 (committed)' revision
eq 'no CHANGELOG.md: only VERSION is committed' VERSION "$(git show --name-only --format= HEAD)"
eq 'no CHANGELOG.md: none is made' no "$([ -e CHANGELOG.md ] && echo yes || echo no)"

newrepo no-variable 0.3.2 "$work/base.md"
expect_ok 'no variable: as before' 'version: 0.3.3 (committed)' revision
eq 'no variable: only VERSION is committed' VERSION "$(git show --name-only --format= HEAD)"
log_is_base 'no variable: CHANGELOG.md is left alone'
echo changed >>CHANGELOG.md
expect_refused 'no variable: a changed CHANGELOG.md blocks' \
    'set-version: the working tree has uncommitted changes besides VERSION' revision

# Refusals of the entry.
newrepo empty-entry 0.3.2 "$work/base.md"
: >"$entry"
before="$(git rev-parse HEAD)"
expect_refused_log 'empty entry file is refused' \
    'set-version: CHANGELOG_ENTRY_FILE has no entry' revision
eq 'empty entry: no commit' "$before" "$(git rev-parse HEAD)"
eq 'empty entry: VERSION untouched' 0.3.2 "$(cat VERSION)"
log_is_base 'empty entry: CHANGELOG.md untouched'
printf '%s\n' 'Text without a bullet.' '' >"$entry"
expect_refused_log 'entry file without a bullet is refused' \
    'set-version: CHANGELOG_ENTRY_FILE has no entry' revision
printf '%s\n' '- ' >"$entry"
expect_refused_log 'bullet without text is refused' \
    'set-version: CHANGELOG_ENTRY_FILE has no entry' revision
entry="$work/no-such-entry.txt"
expect_refused_log 'missing entry file is refused' \
    'set-version: CHANGELOG_ENTRY_FILE has no entry' revision
entry="$work"
expect_refused_log 'a folder as entry file is refused' \
    'set-version: CHANGELOG_ENTRY_FILE has no entry' revision
entry="$work/entry.txt"

# The refusal about the working tree names both files.
printf '%s\n' '- An entry.' >"$entry"
newrepo dirty-log 0.3.2 "$work/base.md"
echo changed >feature.txt
expect_refused_log 'dirty tree with a change log is refused' \
    'set-version: the working tree has uncommitted changes besides VERSION and CHANGELOG.md' \
    revision
log_is_base 'dirty tree with a change log: CHANGELOG.md untouched'

# A relative path of the entry file is read from where the script was started.
newrepo relative 0.3.2 "$work/base.md"
mkdir deep
printf '%s\n' '- Relative entry.' >deep/entry.txt
cd deep
rc=0
out="$(CHANGELOG_ENTRY_FILE=entry.txt CHANGELOG_DATE=2026-11-13 \
    BOT_NAME=Bot BOT_EMAIL=bot@example.com sh "$script" revision 2>&1)" || rc=$?
eq 'relative entry file path' 'version: 0.3.3 (committed)' "$out"
cd "$work/relative"
printf '%s\n' '## [0.3.3] - 2026-11-13' '' '- Relative entry.' '' >"$work/section.md"
log_is 'relative entry file: section written'

cd "$here"
[ "$failed" -eq 0 ] || { echo "$failed failed"; exit 1; }
echo "set version: all checks as expected"
