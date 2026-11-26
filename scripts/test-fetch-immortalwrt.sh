#!/usr/bin/env bash
#
# Offline tests for the argument validation of scripts/fetch-immortalwrt.sh
# (uses --dry-run, so nothing is fetched).
#
# Usage: bash scripts/test-fetch-immortalwrt.sh

set -Eeuo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
fetch="$here/fetch-immortalwrt.sh"
sha=d3a7aaedf7c0763584c9958d5dbee31380bc0d74

failures=0

fail() {
	echo "FAIL: $*" >&2
	failures=$((failures + 1))
}

pass() {
	echo "ok: $*"
}

accept() {
	if GITHUB_ENV='' bash "$fetch" --dry-run "$1" "$2" /nonexistent/tree >/dev/null 2>&1; then
		pass "accepts $1 @ $2"
	else
		fail "rejected $1 @ $2"
	fi
}

reject() {
	if GITHUB_ENV='' bash "$fetch" --dry-run "$1" "$2" /nonexistent/tree >/dev/null 2>&1; then
		fail "accepted $1 @ $2"
	else
		pass "rejects '$1' @ '$2'"
	fi
}

good_repo=cheebun/immortalwrt

# Good refs.
accept "$good_repo" "$sha"
accept immortalwrt/immortalwrt master
accept immortalwrt/immortalwrt openwrt-24.10
accept immortalwrt/immortalwrt v24.10.4
accept "$good_repo" base
accept "$good_repo" feature/kernel-6.18
accept my_org.x/immortal-wrt.git_mirror master

# Bad repos.
reject '' master
reject immortalwrt master
reject immortalwrt/immortalwrt/extra master
reject 'immortalwrt /immortalwrt' master
reject 'owner/name;rm -rf /' master
reject '../immortalwrt' master
reject 'owner/..' master
reject -owner/name master
reject owner/.hidden master
reject 'https://github.com/immortalwrt/immortalwrt' master
# shellcheck disable=SC2016 # literal on purpose
reject 'owner/$(id)' master

# Bad refs.
reject "$good_repo" ''
reject "$good_repo" '-b'
reject "$good_repo" '--upload-pack=x'
reject "$good_repo" 'master branch'
reject "$good_repo" 'a..b'
reject "$good_repo" '/master'
reject "$good_repo" 'master/'
reject "$good_repo" 'a//b'
reject "$good_repo" 'refs/heads/x.lock'
reject "$good_repo" 'a/.b'
reject "$good_repo" 'master.'
reject "$good_repo" 'master;id'
# shellcheck disable=SC2016 # literal on purpose
reject "$good_repo" 'master$(id)'
reject "$good_repo" 'ref~1'
reject "$good_repo" 'ref^'
reject "$good_repo" 'HEAD@{1}'
reject "$good_repo" "$(printf 'master\nx')"
reject "$good_repo" "$(printf 'a%.0s' {1..201})"

# Wrong argument count.
if bash "$fetch" --dry-run "$good_repo" master >/dev/null 2>&1; then
	fail "accepted two arguments"
else
	pass "rejects missing <dir>"
fi

if [[ "$failures" -ne 0 ]]; then
	echo "$failures test(s) failed" >&2
	exit 1
fi
echo "all fetch-immortalwrt tests passed"
