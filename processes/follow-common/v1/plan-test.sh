#!/bin/sh
# Table test of plan.sh: which go.mod and new version give which scope, and which inputs are
# refused with which exit status and message. Runs on the host (part of make check). The go.mod
# files are given as printf %b text so the table can show tabs, CRLF and newlines.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
cd "$here"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM
gomod="$work/go.mod"
failed=0

# $1 label, $2 go.mod as printf %b text, $3 new version, $4 wanted from, $5 wanted scope.
check() {
    printf '%b' "$2" >"$gomod"
    want="from=$4
scope=$5"
    if got="$(sh plan.sh "$gomod" "$3" 2>&1)"; then
        if [ "$got" = "$want" ]; then
            printf 'ok   %-34s %s -> %s\n' "$1" "$4" "$5"
        else
            printf 'FAIL %-34s want "%s" got "%s"\n' "$1" "$want" "$got"
            failed=$((failed + 1))
        fi
    else
        printf 'FAIL %-34s was refused: %s\n' "$1" "$got"
        failed=$((failed + 1))
    fi
}

# $1 label, $2 wanted exit status, $3 the exact message, then the arguments to pass. Nothing may
# reach standard output on a refusal.
refuse_args() {
    label="$1"
    want_status="$2"
    want_message="$3"
    shift 3
    status=0
    out="$(sh plan.sh "$@" 2>/dev/null)" || status=$?
    if [ "$status" -eq 0 ]; then
        printf 'FAIL %-34s was accepted: %s\n' "$label" "$out"
        failed=$((failed + 1))
        return 0
    fi
    got="$(sh plan.sh "$@" 2>&1 >/dev/null)" || true
    if [ -n "$out" ]; then
        printf 'FAIL %-34s refused but printed: %s\n' "$label" "$out"
        failed=$((failed + 1))
    elif [ "$status" -ne "$want_status" ]; then
        printf 'FAIL %-34s want status %s got %s\n' "$label" "$want_status" "$status"
        failed=$((failed + 1))
    elif [ "$got" = "$want_message" ]; then
        printf 'ok   %-34s refused (%s): %s\n' "$label" "$status" "$got"
    else
        printf 'FAIL %-34s want "%s" got "%s"\n' "$label" "$want_message" "$got"
        failed=$((failed + 1))
    fi
}

# $1 label, $2 go.mod as printf %b text, $3 new version, $4 wanted exit status, $5 the message.
refuse() {
    printf '%b' "$2" >"$gomod"
    refuse_args "$1" "$4" "$5" "$gomod" "$3"
}

head='module example.com/server\n\ngo 1.24\n\n'
mod=github.com/SpliceFS/common
block() { printf '%srequire (\\n\\t%s v%s%s\\n\\texample.com/other v1.0.0\\n)\\n' "$head" "$mod" "$1" "${2-}"; }
single() { printf '%srequire %s v%s%s\\n' "$head" "$mod" "$1" "${2-}"; }
usage='usage: plan.sh <go.mod> <new version>'
not_xyz() { printf 'plan: "%s" is not X.Y.Z' "$1"; }
no_line() { printf 'plan: %s has no require line for %s' "$gomod" "$mod"; }
two_lines() { printf 'plan: %s has more than one require line for %s' "$gomod" "$mod"; }
bad_version() {
    printf 'plan: %s does not give %s a version vX.Y.Z: "%s"' "$gomod" "$mod" "$1"
}

# Each scope, in the block form of require.
check revision "$(block 0.3.0)" 0.3.1 0.3.0 revision
check revision-two-digits "$(block 0.3.9)" 0.3.10 0.3.9 revision
check revision-far "$(block 0.3.0)" 0.3.40 0.3.0 revision
check minor "$(block 0.3.0)" 0.4.0 0.3.0 minor
check minor-with-revision "$(block 0.3.5)" 0.4.2 0.3.5 minor
check minor-skips-versions "$(block 0.3.0)" 0.7.0 0.3.0 minor
check minor-0.9.9-to-0.10.0 "$(block 0.9.9)" 0.10.0 0.9.9 minor
check revision-0.9.9-to-0.9.10 "$(block 0.9.9)" 0.9.10 0.9.9 revision
check major-counts-as-minor "$(block 0.3.0)" 1.0.0 0.3.0 minor
check major-with-same-minor "$(block 1.2.3)" 2.2.3 1.2.3 minor
check major-and-revision "$(block 1.2.3)" 2.2.4 1.2.3 minor
check minor-after-major "$(block 1.2.3)" 1.3.0 1.2.3 minor
check revision-after-major "$(block 1.2.3)" 1.2.4 1.2.3 revision
check equal "$(block 0.3.0)" 0.3.0 0.3.0 none
check equal-zero "$(block 0.0.0)" 0.0.0 0.0.0 none
check lower-revision "$(block 0.3.5)" 0.3.4 0.3.5 none
check lower-minor "$(block 0.3.0)" 0.2.9 0.3.0 none
check lower-minor-number "$(block 0.10.0)" 0.9.9 0.10.0 none
check lower-major "$(block 1.0.0)" 0.9.9 1.0.0 none
check lower-long-revision "$(block 0.3.10)" 0.3.9 0.3.10 none
check leading-zero-is-decimal "$(block 0.3.9)" 0.3.010 0.3.9 revision
check leading-zero-minor "$(block 0.3.0)" 0.08.0 0.3.0 minor

# The single-line form, and the comment.
check single-revision "$(single 0.3.0)" 0.3.1 0.3.0 revision
check single-minor "$(single 0.3.0)" 0.4.0 0.3.0 minor
check single-equal "$(single 0.3.0)" 0.3.0 0.3.0 none
check single-lower "$(single 0.3.0)" 0.2.0 0.3.0 none
check block-indirect "$(block 0.3.0 ' // indirect')" 0.3.1 0.3.0 revision
check single-indirect "$(single 0.3.0 ' // indirect')" 0.4.0 0.3.0 minor
check indirect-no-space "$(block 0.3.0 '//indirect')" 0.3.1 0.3.0 revision
check indirect-many-spaces "$(block 0.3.0 '   //   indirect')" 0.3.1 0.3.0 revision
check indirect-tab "$(block 0.3.0 '\t// indirect')" 0.3.1 0.3.0 revision

# Other text in the file that is not the version in use.
check spaces-for-tab "module x\n\nrequire (\n    $mod v0.3.0\n)\n" 0.3.1 0.3.0 revision
check extra-spaces "module x\nrequire (\n\t$mod    v0.3.0   \n)\n" 0.3.1 0.3.0 revision
check single-extra-spaces "module x\nrequire   $mod   v0.3.0\n" 0.3.1 0.3.0 revision
check crlf "module x\r\n\r\nrequire (\r\n\t$mod v0.3.0\r\n)\r\n" 0.3.1 0.3.0 revision
check no-final-newline "module x\nrequire $mod v0.3.0" 0.3.1 0.3.0 revision
check other-requires-first "module x\nrequire (\n\texample.com/a v1.0.0\n\texample.com/b v2.0.0\n\t$mod v0.3.0\n\texample.com/z v3.0.0\n)\n" 0.3.1 0.3.0 revision
check two-require-blocks "module x\nrequire (\n\texample.com/a v1.0.0\n)\nrequire (\n\t$mod v0.3.0 // indirect\n)\n" 0.4.0 0.3.0 minor
check block-and-single-other "module x\nrequire example.com/a v1.0.0\nrequire (\n\t$mod v0.3.0\n)\n" 0.3.1 0.3.0 revision
check longer-module-name "module x\nrequire (\n\t$mod-extra v9.9.9\n\t$mod v0.3.0\n)\n" 0.3.1 0.3.0 revision
check sub-module "module x\nrequire (\n\t$mod/v2 v2.0.0\n\t$mod v0.3.0\n)\n" 0.3.1 0.3.0 revision
check other-owner "module x\nrequire (\n\texample.com/SpliceFS/common v9.0.0\n\t$mod v0.3.0\n)\n" 0.3.1 0.3.0 revision
check comment-line "module x\n// $mod v0.1.0\nrequire (\n\t// $mod v0.2.0\n\t$mod v0.3.0\n)\n" 0.3.1 0.3.0 revision
check replace-block "module x\nrequire $mod v0.3.0\nreplace (\n\t$mod v0.3.0 => ../common\n)\n" 0.3.1 0.3.0 revision
check replace-line "module x\nrequire $mod v0.3.0\nreplace $mod => ../common\n" 0.3.1 0.3.0 revision
check exclude-block "module x\nexclude (\n\t$mod v0.3.1\n)\nrequire $mod v0.3.0\n" 0.3.1 0.3.0 revision
check retract-after-require "module x\nrequire $mod v0.3.0\nretract (\n\tv0.1.0\n)\n" 0.3.1 0.3.0 revision

# go.mod problems: exit 1, naming the file.
refuse empty-file '' 0.3.1 1 "$(no_line)"
refuse no-line "$head" 0.3.1 1 "$(no_line)"
refuse other-module-only "${head}require example.com/a v1.0.0\n" 0.3.1 1 "$(no_line)"
refuse only-in-comment "${head}// $mod v0.3.0\n" 0.3.1 1 "$(no_line)"
refuse only-in-replace "${head}replace $mod v0.3.0 => ../common\n" 0.3.1 1 "$(no_line)"
refuse only-in-replace-block "${head}replace (\n\t$mod v0.3.0 => ../common\n)\n" 0.3.1 1 "$(no_line)"
refuse sub-module-only "${head}require $mod/v2 v2.0.0\n" 0.3.1 1 "$(no_line)"
refuse block-and-single "${head}require $mod v0.3.0\nrequire (\n\t$mod v0.3.0\n)\n" 0.3.1 1 \
    "$(two_lines)"
refuse twice-in-block "${head}require (\n\t$mod v0.3.0\n\t$mod v0.3.0\n)\n" 0.3.1 1 "$(two_lines)"
refuse twice-single "${head}require $mod v0.3.0\nrequire $mod v0.4.0\n" 0.3.1 1 "$(two_lines)"
refuse twice-two-blocks "${head}require (\n\t$mod v0.3.0\n)\nrequire (\n\t$mod v0.3.0 // indirect\n)\n" \
    0.3.1 1 "$(two_lines)"
refuse no-version "${head}require $mod\n" 0.3.1 1 "$(bad_version "$mod")"
refuse no-version-in-block "${head}require (\n\t$mod\n)\n" 0.3.1 1 "$(bad_version "$mod")"
refuse no-v "${head}require $mod 0.3.0\n" 0.3.1 1 "$(bad_version "$mod 0.3.0")"
refuse two-numbers "${head}require $mod v0.3\n" 0.3.1 1 "$(bad_version "$mod v0.3")"
refuse four-numbers "${head}require $mod v0.3.0.1\n" 0.3.1 1 "$(bad_version "$mod v0.3.0.1")"
refuse pre-release "${head}require $mod v0.3.0-rc.1\n" 0.3.1 1 "$(bad_version "$mod v0.3.0-rc.1")"
refuse pseudo-version "${head}require $mod v0.0.0-20260101120000-abcdef123456\n" 0.3.1 1 \
    "$(bad_version "$mod v0.0.0-20260101120000-abcdef123456")"
refuse incompatible "${head}require $mod v2.0.0+incompatible\n" 2.0.1 1 \
    "$(bad_version "$mod v2.0.0+incompatible")"
refuse extra-word "${head}require $mod v0.3.0 extra\n" 0.3.1 1 "$(bad_version "$mod v0.3.0 extra")"
refuse bad-version-and-none-newer "${head}require $mod vX\n" 0.3.0 1 "$(bad_version "$mod vX")"

# Wrong calls: exit 2.
refuse_args no-arguments 2 "$usage"
refuse_args one-argument 2 "$usage" "$gomod"
refuse_args three-arguments 2 "$usage" "$gomod" 0.3.1 extra
printf '%b' "$(block 0.3.0)" >"$gomod"
for bad in v0.3.1 0.3 0.3.1.2 0.3.1-rc.1 0.3.1+4 0.3.x a.b.c 0..1 .0.3.1 0.3.1. -0.3.1 ' 0.3.1' \
    '0.3.1 ' '' '0.3.1
0.3.2'; do
    refuse_args "new-version-$(printf '%s' "$bad" | tr '\n ' 'N_')" 2 "$(not_xyz "$bad")" "$gomod" "$bad"
done
# Neither a missing file, nor a folder, nor a link to nothing can be read. No file permission is
# removed, so this also fails as root.
ln -s "$work/nothing" "$work/dangling"
mkdir "$work/folder"
refuse_args missing-file 2 "plan: cannot read $work/missing" "$work/missing" 0.3.1
refuse_args folder-as-file 2 "plan: cannot read $work/folder" "$work/folder" 0.3.1
refuse_args dangling-link 2 "plan: cannot read $work/dangling" "$work/dangling" 0.3.1
refuse_args new-version-before-file 2 "$(not_xyz v1)" "$work/missing" v1

[ "$failed" -eq 0 ] || { echo "$failed failed"; exit 1; }
echo "plan: all go.mod files and versions handled as expected"
