#!/usr/bin/env bash
#
# Tests for scripts/clean-dl.sh.
#
# Builds a fake dl/ directory with a truncated top-level archive, a good
# top-level archive and a small Go module source file under go-mod-cache, then
# checks that only the truncated archive is removed. Needs no network.
#
# Usage: bash scripts/test-dl-cleanup.sh

set -Eeuo pipefail

script="$(cd "$(dirname "$0")" && pwd)/clean-dl.sh"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

failures=0

fail() {
	echo "FAIL: $*" >&2
	failures=$((failures + 1))
}

pass() {
	echo "ok: $*"
}

dl="$work/dl"
mkdir -p "$dl/go-mod-cache/example.com/m@v1"
head -c 100 /dev/zero > "$dl/bad.tar.xz"
head -c 4096 /dev/zero > "$dl/good.tar.xz"
printf 'package m\n' > "$dl/go-mod-cache/example.com/m@v1/x.go"

if bash "$script" "$dl" > "$work/out.log" 2>&1; then
	pass "clean-dl: exits 0 on a populated dl dir"
else
	fail "clean-dl: exited non-zero on a populated dl dir"
	sed 's/^/    /' "$work/out.log" >&2
fi

if [[ ! -e "$dl/bad.tar.xz" ]]; then
	pass "clean-dl: truncated top-level file removed"
else
	fail "clean-dl: truncated top-level file kept"
fi

if [[ -f "$dl/good.tar.xz" ]]; then
	pass "clean-dl: good top-level file kept"
else
	fail "clean-dl: good top-level file removed"
fi

if [[ -f "$dl/go-mod-cache/example.com/m@v1/x.go" ]]; then
	pass "clean-dl: small file under go-mod-cache kept"
else
	fail "clean-dl: small file under go-mod-cache removed"
fi

if grep -qF "$dl/bad.tar.xz" "$work/out.log"; then
	pass "clean-dl: removed file is logged"
else
	fail "clean-dl: removed file not logged"
fi

mkdir -p "$work/empty"
if bash "$script" "$work/empty" > /dev/null 2>&1; then
	pass "clean-dl: empty dl dir passes"
else
	fail "clean-dl: empty dl dir fails"
fi

if bash "$script" "$work/missing" > /dev/null 2>&1; then
	pass "clean-dl: missing dl dir passes"
else
	fail "clean-dl: missing dl dir fails"
fi

if bash "$script" > /dev/null 2>&1; then
	fail "clean-dl: accepted a missing argument"
else
	pass "clean-dl: missing argument rejected"
fi

if (( failures > 0 )); then
	echo "$failures test(s) failed" >&2
	exit 1
fi
echo "All dl cleanup tests passed"
