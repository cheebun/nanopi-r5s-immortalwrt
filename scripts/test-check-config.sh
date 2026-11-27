#!/usr/bin/env bash
#
# Offline tests for scripts/check-config.sh, focused on honk: honk is not
# built here (it is installed from daeuniverse's releases), but everything it
# needs at runtime must be in the image.
#
# The good inputs are derived from r5s.config, so this also catches a
# required package that r5s.config does not select.
#
# Usage: bash scripts/test-check-config.sh

set -Eeuo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/test-check-config.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT

failures=0

fail() {
	echo "FAIL: $*" >&2
	failures=$((failures + 1))
}

pass() {
	echo "ok: $*"
}

# expect <0|1> <description> <output regex or ""> <check-config args>...
# Exit status 0 = pass, 1 = check failure; a failure must print the regex.
expect() {
	local want="$1" what="$2" re="$3" rc=0
	shift 3
	bash "$here/check-config.sh" "$@" > "$work/out.log" 2>&1 || rc=$?
	if [[ "$want" == 0 && "$rc" == 0 ]] ||
		{ [[ "$want" == 1 && "$rc" == 1 ]] && { [[ -z "$re" ]] || grep -qE -- "$re" "$work/out.log"; }; }; then
		pass "$what"
	else
		fail "$what (exit $rc)"
		sed 's/^/    /' "$work/out.log" >&2
	fi
}

# --- Good inputs ------------------------------------------------------------

# r5s.config plus what `make defconfig` selects on its own.
config="$work/good.config"
{
	cat "$here/../r5s.config"
	echo 'CONFIG_DWARVES=y'
	echo 'CONFIG_PACKAGE_libopenssl-conf=y'
} > "$config"

# Every =y package of the config, as an apk manifest ("name - version").
manifest="$work/good.manifest"
sed -n 's/^CONFIG_PACKAGE_\(.*\)=y$/\1 - 1.0-r1/p' "$config" |
	sed 's/^libstdcpp - /libstdcpp6 - /' > "$manifest"

kernel="$work/good.kernel-config"
for sym in CONFIG_DEBUG_INFO_BTF CONFIG_BPF_SYSCALL CONFIG_BPF_JIT CONFIG_NETKIT \
	CONFIG_CGROUP_BPF CONFIG_SYSFS CONFIG_BPF CONFIG_BPF_EVENTS CONFIG_DEBUG_INFO \
	CONFIG_DEBUG_INFO_BTF_MODULES CONFIG_XDP_SOCKETS CONFIG_CGROUPS CONFIG_NET_NS \
	CONFIG_NET_SCHED CONFIG_NET_CLS_ACT CONFIG_NET_XGRESS CONFIG_NET_INGRESS \
	CONFIG_NET_EGRESS CONFIG_KPROBES CONFIG_KPROBE_EVENTS CONFIG_FUNCTION_TRACER \
	CONFIG_DYNAMIC_FTRACE CONFIG_BPF_STREAM_PARSER CONFIG_VETH CONFIG_NET_CLS_BPF \
	CONFIG_NET_ACT_BPF CONFIG_NET_SCH_INGRESS CONFIG_NF_TABLES CONFIG_NF_TABLES_INET \
	CONFIG_NFT_CT CONFIG_NFT_QUEUE CONFIG_NETFILTER_NETLINK_QUEUE CONFIG_XDP_SOCKETS_DIAG; do
	echo "$sym=y"
done > "$kernel"

tree="$work/tree"
for spec in mosdns/mosdns mosdns/luci-app-mosdns mosdns/geo2txt \
	vantage/luci-theme-vantage vantage/luci-app-vantage vantage/luci-app-vantage-traffic; do
	mkdir -p "$tree/package/feeds/$spec"
	: > "$tree/package/feeds/$spec/Makefile"
done
mkdir -p "$tree/bin/packages/aarch64_generic/packages"
: > "$tree/bin/packages/aarch64_generic/packages/mosdns-5.3.3-r1.apk"

expect 0 "good config, tree, kernel config and manifest pass" "" \
	--config "$config" --tree "$tree" --kernel-config "$kernel" --manifest "$manifest"

# --- honk must not be built or in the image ---------------------------------

cp "$manifest" "$work/honk.manifest"
echo 'honk - 1.0.0-r1' >> "$work/honk.manifest"
expect 1 "manifest containing honk fails" 'honk must not be in the image' \
	--config "$config" --manifest "$work/honk.manifest"

for pkg in honk luci-app-honk luci-lib-daeuniverse vmlinux-btf vmlinux-btf-builtin; do
	for val in y m; do
		cp "$config" "$work/honk.config"
		echo "CONFIG_PACKAGE_$pkg=$val" >> "$work/honk.config"
		expect 1 "CONFIG_PACKAGE_$pkg=$val fails" "CONFIG_PACKAGE_$pkg=$val" --config "$work/honk.config"
	done
done

cp -R "$tree" "$work/tree-feed"
mkdir -p "$work/tree-feed/feeds/daeuniverse"
expect 1 "tree with feeds/daeuniverse fails" 'feeds/daeuniverse exists' \
	--config "$config" --tree "$work/tree-feed"

cp -R "$tree" "$work/tree-apk"
: > "$work/tree-apk/bin/packages/aarch64_generic/packages/honk-1.0.0-r1.apk"
expect 1 "tree with a built honk apk fails" 'honk-1\.0\.0-r1\.apk was built' \
	--config "$config" --tree "$work/tree-apk"

# --- honk runtime must be in the image --------------------------------------

grep -vx 'kmod-veth - .*' "$manifest" > "$work/no-veth.manifest"
expect 1 "manifest missing kmod-veth fails" 'required package kmod-veth is not in the image' \
	--config "$config" --manifest "$work/no-veth.manifest"

for pkg in flock coreutils-timeout kmod-nf-conntrack; do
	grep -vx "$pkg - .*" "$manifest" > "$work/no-$pkg.manifest"
	expect 1 "manifest missing $pkg fails" "required package $pkg is not in the image" \
		--config "$config" --manifest "$work/no-$pkg.manifest"
	grep -vx "CONFIG_PACKAGE_$pkg=y" "$config" > "$work/no-$pkg.config"
	expect 1 "config missing CONFIG_PACKAGE_$pkg=y fails" "CONFIG_PACKAGE_$pkg=y is missing" \
		--config "$work/no-$pkg.config"
done

for sym in CONFIG_DEBUG_INFO_BTF CONFIG_BPF_SYSCALL CONFIG_BPF_JIT CONFIG_NETKIT \
	CONFIG_CGROUP_BPF CONFIG_SYSFS; do
	grep -vx "$sym=y" "$kernel" > "$work/no-$sym.kernel-config"
	expect 1 "kernel config missing $sym=y fails" "kernel: $sym=y is missing" \
		--config "$config" --kernel-config "$work/no-$sym.kernel-config"
done

if (( failures > 0 )); then
	echo "$failures test(s) failed" >&2
	exit 1
fi
echo "All check-config tests passed"
