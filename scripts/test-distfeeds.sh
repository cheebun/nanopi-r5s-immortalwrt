#!/usr/bin/env bash
#
# Tests for scripts/distfeeds-config.sh and scripts/check-distfeeds.sh.
#
# distfeeds-config.sh runs against a fake tree whose scripts/feeds prints a
# fixed feed list. check-distfeeds.sh runs against fake rootfs directories and
# probes the real ImmortalWrt download server, so it needs network access.
#
# Usage: bash scripts/test-distfeeds.sh

set -Eeuo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
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

# fake_tree <name> <feed>...: a tree whose scripts/feeds lists the feeds.
fake_tree() {
	local tree="$work/$1"
	shift
	mkdir -p "$tree/scripts"
	{
		echo '#!/bin/sh'
		# shellcheck disable=SC2016 # expanded by the fake scripts/feeds
		echo '[ "$1 $2" = "list -n" ] || exit 1'
		printf 'echo %s\n' "$@"
	} > "$tree/scripts/feeds"
	chmod +x "$tree/scripts/feeds"
	echo "$tree"
}

# fake_rootfs <name> <line>...: a rootfs whose distfeeds.list has the lines.
fake_rootfs() {
	local rootfs="$work/$1"
	shift
	mkdir -p "$rootfs/etc/apk/repositories.d"
	printf '%s\n' "$@" > "$rootfs/etc/apk/repositories.d/distfeeds.list"
	echo "$rootfs"
}

# --- distfeeds-config.sh ----------------------------------------------------

tree="$(fake_tree good packages luci routing telephony video mosdns daeuniverse vantage)"
if out="$(bash "$here/distfeeds-config.sh" "$tree")"; then
	expected=$'CONFIG_FEED_video=m\nCONFIG_FEED_mosdns=m\nCONFIG_FEED_daeuniverse=m\nCONFIG_FEED_vantage=m'
	if [[ "$out" == "$expected" ]]; then
		pass "distfeeds-config: 4 unhosted feeds set to =m"
	else
		fail "distfeeds-config: unexpected output:"$'\n'"$out"
	fi
else
	fail "distfeeds-config: exited non-zero on a valid tree"
fi

if out="$(DISTFEEDS_HOSTED='packages luci routing telephony video' bash "$here/distfeeds-config.sh" "$tree")" &&
	[[ "$(grep -c '=m$' <<<"$out")" == 3 ]] && ! grep -q video <<<"$out"; then
	pass "distfeeds-config: DISTFEEDS_HOSTED override"
else
	fail "distfeeds-config: DISTFEEDS_HOSTED override not honoured"
fi

tree="$(fake_tree bad packages luci bad-name)"
if bash "$here/distfeeds-config.sh" "$tree" >/dev/null 2>&1; then
	fail "distfeeds-config: accepted an invalid feed name"
else
	pass "distfeeds-config: invalid feed name rejected"
fi

if DISTFEEDS_HOSTED='packages lu.ci' bash "$here/distfeeds-config.sh" "$work/good" >/dev/null 2>&1; then
	fail "distfeeds-config: accepted an invalid DISTFEEDS_HOSTED name"
else
	pass "distfeeds-config: invalid DISTFEEDS_HOSTED name rejected"
fi

# --- check-distfeeds.sh -----------------------------------------------------

base=https://downloads.immortalwrt.org/snapshots/packages/aarch64_generic
header='# This file is auto-generated and build-specific, any changes will be intentionally lost in sysupgrade.'

expect() { # expect <0|1> <description> <rootfs>...
	local want="$1" what="$2" rc=0
	shift 2
	bash "$here/check-distfeeds.sh" "$@" > "$work/out.log" 2>&1 || rc=$?
	if [[ "$want" == 0 && "$rc" == 0 ]] || [[ "$want" == 1 && "$rc" != 0 ]]; then
		pass "check-distfeeds: $what"
	else
		fail "check-distfeeds: $what (exit $rc)"
		sed 's/^/    /' "$work/out.log" >&2
	fi
}

ok="$(fake_rootfs ok "$header" "$base/packages/packages.adb")"
expect 0 "hosted repository passes" "$ok"

not_hosted="$(fake_rootfs not-hosted "$base/packages/packages.adb" "$base/vantage/packages.adb")"
expect 1 "enabled 404 repository fails" "$not_hosted"

disabled="$(fake_rootfs disabled "$header" "$base/packages/packages.adb" "# $base/vantage/packages.adb")"
expect 0 "disabled 404 repository passes" "$disabled"

mkdir -p "$work/missing/etc"
expect 1 "missing distfeeds.list fails" "$work/missing"
expect 1 "one bad rootfs among good ones fails" "$ok" "$work/missing"

placeholder="$(fake_rootfs placeholder '%U/packages/%A/base/packages.adb')"
expect 1 "unexpanded placeholder fails" "$placeholder"

hosted_disabled="$(fake_rootfs hosted-disabled "$base/base/packages.adb" "# $base/packages/packages.adb")"
expect 0 "hosted but disabled repository passes" "$hosted_disabled"
if grep -q '::warning::.*consider adding to DISTFEEDS_HOSTED' "$work/out.log"; then
	pass "check-distfeeds: hosted but disabled repository warns"
else
	fail "check-distfeeds: no warning for a hosted but disabled repository"
fi

if (( failures > 0 )); then
	echo "$failures test(s) failed" >&2
	exit 1
fi
echo "All distfeeds tests passed"
