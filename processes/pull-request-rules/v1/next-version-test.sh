#!/bin/sh
# Table test of next-version.sh: the next version for each scope, and which inputs are
# refused with which message. Runs on the host (make next-version-test, part of make check).
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
cd "$here"
failed=0

# $1 current version, $2 scope, $3 wanted next version.
check() {
    if got="$(sh next-version.sh "$1" "$2" 2>&1)"; then
        if [ "$got" = "$3" ]; then
            printf 'ok   %-28s %-9s -> %s\n' "$1" "$2" "$3"
        else
            printf 'FAIL %-28s %-9s want "%s" got "%s"\n' "$1" "$2" "$3" "$got"
            failed=$((failed + 1))
        fi
    else
        printf 'FAIL %-28s %-9s was refused: %s\n' "$1" "$2" "$got"
        failed=$((failed + 1))
    fi
}

# $1 current version, $2 scope, $3 the exact message. Nothing may reach standard output.
refuse() {
    if out="$(sh next-version.sh "$1" "$2" 2>/dev/null)"; then
        printf 'FAIL %-28s %-9s was accepted: %s\n' "$1" "$2" "$out"
        failed=$((failed + 1))
    elif [ -n "$out" ]; then
        printf 'FAIL %-28s %-9s refused but printed: %s\n' "$1" "$2" "$out"
        failed=$((failed + 1))
    else
        got="$(sh next-version.sh "$1" "$2" 2>&1 >/dev/null)" || true
        if [ "$got" = "$3" ]; then
            printf 'ok   %-28s %-9s refused: %s\n' "$1" "$2" "$got"
        else
            printf 'FAIL %-28s %-9s want "%s" got "%s"\n' "$1" "$2" "$3" "$got"
            failed=$((failed + 1))
        fi
    fi
}

# $1 label, then the arguments to pass. The wrong number of arguments must print the usage line.
usage() {
    label="$1"
    shift
    if sh next-version.sh "$@" >/dev/null 2>&1; then
        printf 'FAIL %-28s was accepted\n' "$label"
        failed=$((failed + 1))
    else
        got="$(sh next-version.sh "$@" 2>&1 >/dev/null)" || true
        want='usage: next-version.sh <current> <scope>'
        if [ "$got" = "$want" ]; then
            printf 'ok   %-28s refused: %s\n' "$label" "$got"
        else
            printf 'FAIL %-28s want "%s" got "%s"\n' "$label" "$want" "$got"
            failed=$((failed + 1))
        fi
    fi
}

not_xyz() { printf 'next-version: "%s" is not X.Y.Z' "$1"; }
no_scope() {
    printf 'next-version: scope "%s" cannot be released from this repository' "$1"
}

check 0.0.0 minor 0.1.0
check 0.0.0 revision 0.0.1
check 0.1.9 revision 0.1.10
check 1.2.3 minor 1.3.0
check 1.2.3 revision 1.2.4
check 1.9.9 minor 1.10.0
check 9.9.9 revision 9.9.10
check 0.0.99 revision 0.0.100
check 10.20.30 minor 10.21.0
check 10.20.30 revision 10.20.31
check 2.0.0 minor 2.1.0

refuse v1.2.3 revision "$(not_xyz v1.2.3)"
refuse 1.2.3-rc.1 revision "$(not_xyz 1.2.3-rc.1)"
refuse 1.2.3+4 minor "$(not_xyz 1.2.3+4)"
refuse 1.2.3-dirty minor "$(not_xyz 1.2.3-dirty)"
refuse 1.2 revision "$(not_xyz 1.2)"
refuse 1 revision "$(not_xyz 1)"
refuse 1.2.3.4 revision "$(not_xyz 1.2.3.4)"
refuse 01.2.3 revision "$(not_xyz 01.2.3)"
refuse 1.02.3 revision "$(not_xyz 1.02.3)"
refuse 1.2.03 minor "$(not_xyz 1.2.03)"
refuse 00.0.0 minor "$(not_xyz 00.0.0)"
refuse 0.0.00 minor "$(not_xyz 0.0.00)"
refuse 1..2 revision "$(not_xyz 1..2)"
refuse .1.2.3 revision "$(not_xyz .1.2.3)"
refuse 1.2.3. revision "$(not_xyz 1.2.3.)"
refuse -1.2.3 revision "$(not_xyz -1.2.3)"
refuse 1.2.x revision "$(not_xyz 1.2.x)"
refuse a.b.c revision "$(not_xyz a.b.c)"
refuse ' 1.2.3' revision "$(not_xyz ' 1.2.3')"
refuse '1.2.3 ' revision "$(not_xyz '1.2.3 ')"
refuse '' revision "$(not_xyz '')"
refuse '1.2.3
4.5.6' revision "$(not_xyz '1.2.3
4.5.6')"
refuse 1.2.3 major "$(no_scope major)"
refuse 1.2.3 patch "$(no_scope patch)"
refuse 1.2.3 Minor "$(no_scope Minor)"
refuse 1.2.3 REVISION "$(no_scope REVISION)"
refuse 1.2.3 'minor ' "$(no_scope 'minor ')"
refuse 1.2.3 '' "$(no_scope '')"
refuse v1.2.3 major "$(not_xyz v1.2.3)"

usage no-arguments
usage one-argument 1.2.3
usage three-arguments 1.2.3 minor extra

[ "$failed" -eq 0 ] || { echo "$failed failed"; exit 1; }
echo "next version: all versions as expected"
