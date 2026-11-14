#!/bin/sh
# Makes VERSION on a pull request branch hold the version that follows the base version of the
# target branch (see base-version.sh) for the given scope, as a commit of its own. It commits
# locally and never pushes, so the caller decides when and how the result is published.
#
# With CHANGELOG_ENTRY_FILE (bullets, one per line, each starting with "- ") and a CHANGELOG.md at
# the top of the repository, the same commit also holds the change log section of that version.
# The section is rebuilt on every run, so an entry edited in the pull request description
# replaces the earlier one instead of piling up.
set -eu

fail() {
    printf 'set-version: %s\n' "$1" >&2
    exit 1
}

if [ "$#" -ne 1 ]; then
    echo 'usage: set-version.sh <scope>' >&2
    exit 1
fi
scope="$1"

# Checked before any git work so a missing identity is reported even when nothing needs committing.
[ -n "${BOT_NAME:-}" ] || fail 'BOT_NAME is required'
[ -n "${BOT_EMAIL:-}" ] || fail 'BOT_EMAIL is required'
base_ref="${BASE_REF:-origin/main}"

# The path is made absolute before the change of directory below, so a relative one still works.
entry_file="${CHANGELOG_ENTRY_FILE:-}"
case "$entry_file" in
    '' | /*) ;;
    *) entry_file="$PWD/$entry_file" ;;
esac

# The sibling scripts are found by this script's own directory so any working directory works.
here="$(cd "$(dirname "$0")" && pwd)"
top="$(git rev-parse --show-toplevel)" || fail 'not inside a git repository'
cd "$top"

git rev-parse --verify --quiet "$base_ref^{commit}" >/dev/null ||
    fail "base ref \"$base_ref\" does not exist"
base="$(sh "$here/base-version.sh" "$base_ref")"
if ! wanted="$(sh "$here/next-version.sh" "$base" "$scope" 2>&1)"; then
    printf '%s\n' "$wanted" >&2
    exit 1
fi

# Without the variable, or without a CHANGELOG.md, the change log is not touched at all.
use_changelog=no
if [ -n "$entry_file" ] && [ -f CHANGELOG.md ]; then
    use_changelog=yes
fi

if [ "$use_changelog" = yes ]; then
    [ -f "$entry_file" ] || fail 'CHANGELOG_ENTRY_FILE has no entry'
    # Words are filled up to 100 columns. A bullet starts with "- " and its continuation lines with
    # two spaces, which is how Markdown keeps them in the same list item. A word that is longer than
    # a line stays whole on a line of its own.
    bullets="$(awk '
        /^- / {
            count = split(substr($0, 3), words, " ")
            line = ""
            for (i = 1; i <= count; i++) {
                if (line == "") line = "- " words[i]
                else if (length(line) + 1 + length(words[i]) <= 100) line = line " " words[i]
                else {
                    print line
                    line = "  " words[i]
                }
            }
            if (line != "") print line
        }
    ' "$entry_file")"
    [ -n "$bullets" ] || fail 'CHANGELOG_ENTRY_FILE has no entry'
fi

# Untracked files are ignored: the commit below names its files only, so they cannot leak into it.
# The files this script rewrites are excluded because they are rewritten anyway.
if [ "$use_changelog" = yes ]; then
    dirty="$(git status --porcelain --untracked-files=no -- . ':(exclude)VERSION' \
        ':(exclude)CHANGELOG.md')"
    dirty_message='the working tree has uncommitted changes besides VERSION and CHANGELOG.md'
else
    dirty="$(git status --porcelain --untracked-files=no -- . ':(exclude)VERSION')"
    dirty_message='the working tree has uncommitted changes besides VERSION'
fi
[ -z "$dirty" ] || fail "$dirty_message"

# The files this script writes and commits, as the positional parameters.
set -- VERSION

if [ "$use_changelog" = yes ]; then
    set -- VERSION CHANGELOG.md
    # A version section that the base branch does not have comes from an earlier version commit of
    # this branch or from a heading the author typed. Both are replaced by the section made here,
    # and every section the base has stays as it is. A base without the file has no sections.
    base_log="$(git show "$base_ref:CHANGELOG.md" 2>/dev/null)" || base_log=''
    base_versions="$(printf '%s\n' "$base_log" | sed -n 's/^## \[\([^]]*\)\].*/\1/p')"
    changelog_date="${CHANGELOG_DATE:-}"
    [ -n "$changelog_date" ] || changelog_date="$(date -u +%Y-%m-%d)"
    # The values travel in the environment: awk -v would interpret backslashes in the bullets.
    new_log="$(CL_BASE_VERSIONS="$base_versions" CL_VERSION="$wanted" CL_DATE="$changelog_date" \
        CL_BULLETS="$bullets" awk '
        BEGIN {
            known_count = split(ENVIRON["CL_BASE_VERSIONS"], list, "\n")
            for (i = 1; i <= known_count; i++) known[list[i]] = 1
        }
        /^## / {
            skipping = 0
            if ($0 ~ /^## \[[0-9]+\.[0-9]+\.[0-9]+\]/) {
                version = substr($0, 5)
                sub(/\].*/, "", version)
                if (!(version in known)) skipping = 1
            }
        }
        !skipping { lines[++count] = $0 }
        END {
            at = count + 1
            for (i = 1; i <= count; i++) {
                if (lines[i] ~ /^## \[/) {
                    at = i
                    break
                }
            }
            last = at - 1
            while (last > 0 && lines[last] == "") last--
            for (i = 1; i <= last; i++) print lines[i]
            if (last > 0) print ""
            print "## [" ENVIRON["CL_VERSION"] "] - " ENVIRON["CL_DATE"]
            print ""
            print ENVIRON["CL_BULLETS"]
            if (at <= count) {
                print ""
                for (i = at; i <= count; i++) print lines[i]
            }
        }
    ' CHANGELOG.md)"
    # The substitution above dropped the trailing blank lines, so the file ends in one newline.
    printf '%s\n' "$new_log" >CHANGELOG.md
fi

# Writing first and comparing the index with HEAD makes "unchanged" a byte for byte statement
# about what is committed, whatever the files held before.
printf '%s\n' "$wanted" >VERSION
git add "$@"
if git cat-file -e HEAD:VERSION 2>/dev/null && git diff --cached --quiet -- "$@"; then
    echo "version: $wanted (unchanged)"
    exit 0
fi

# Two -m options make the trailer its own paragraph, which is where git looks for trailers.
# The identity goes in as environment variables: git prefers them over its configuration, so
# an identity inherited from the caller's environment cannot replace the bot.
GIT_AUTHOR_NAME="$BOT_NAME" GIT_AUTHOR_EMAIL="$BOT_EMAIL" \
    GIT_COMMITTER_NAME="$BOT_NAME" GIT_COMMITTER_EMAIL="$BOT_EMAIL" \
    git -c commit.gpgsign=false \
    commit -q --no-verify -m "Set version to $wanted" -m 'Version-Commit: true' -- "$@"
echo "version: $wanted (committed)"
