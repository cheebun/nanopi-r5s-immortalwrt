#!/usr/bin/env bash
#
# Enforce the firmware spec on the resolved build config and on build outputs.
#
# Usage:
#   bash scripts/check-config.sh --config <.config>
#        [--kernel-config <linux .config>] [--manifest <file>]... [--rootfs <dir>]
#
#   --config         The top-level .config after `make defconfig` (required).
#   --kernel-config  The kernel .config from build_dir/.../linux-*/.config.
#   --manifest       An image manifest ("name - version" per line).
#   --rootfs         The staged root filesystem (build_dir/.../root-rockchip).
#
# `make defconfig` silently drops or flips symbols whose dependencies are not
# met, so the seed config proves nothing; this checks what was actually
# resolved and built. Every failure is reported before exiting non-zero.
#
# Keep the lists below in sync with r5s.config.

set -Eeuo pipefail

config=""
kernel_config=""
rootfs=""
manifests=()

while [[ $# -gt 0 ]]; do
	case "$1" in
	--config) config="${2:?}"; shift 2 ;;
	--kernel-config) kernel_config="${2:?}"; shift 2 ;;
	--manifest) manifests+=("${2:?}"); shift 2 ;;
	--rootfs) rootfs="${2:?}"; shift 2 ;;
	-h | --help) sed -n '2,18p' "$0"; exit 0 ;;
	*) echo "check-config: unknown argument: $1" >&2; exit 2 ;;
	esac
done

[[ -n "$config" ]] || { echo "check-config: --config is required" >&2; exit 2; }

errors=0
err() {
	echo "::error::check-config: $*" >&2
	errors=$((errors + 1))
}

need_file() {
	[[ -f "$1" ]] || { echo "check-config: no such file: $1" >&2; exit 2; }
}

# --- Top-level .config ------------------------------------------------------

required_y=(
	CONFIG_TARGET_rockchip
	CONFIG_TARGET_rockchip_armv8
	CONFIG_TARGET_rockchip_armv8_DEVICE_friendlyarm_nanopi-r5s
	# BTF / netkit / BPF
	CONFIG_KERNEL_DEBUG_INFO
	CONFIG_KERNEL_DEBUG_INFO_BTF
	CONFIG_KERNEL_NETKIT
	CONFIG_KERNEL_BPF_EVENTS
	CONFIG_KERNEL_KPROBES
	CONFIG_KERNEL_XDP_SOCKETS
	CONFIG_KERNEL_CGROUPS
	CONFIG_KERNEL_CGROUP_BPF
	CONFIG_KERNEL_NET_NS
	CONFIG_KERNEL_FUNCTION_TRACER
	CONFIG_KERNEL_DYNAMIC_FTRACE
	CONFIG_DWARVES
	# OpenSSL devcrypto
	CONFIG_OPENSSL_ENGINE
	CONFIG_OPENSSL_ENGINE_BUILTIN
	CONFIG_OPENSSL_ENGINE_BUILTIN_DEVCRYPTO
	# BusyBox customisation must be on for the NTPD switch to take effect
	CONFIG_BUSYBOX_CUSTOM
)

# Packages that must be built into the image (=y, not =m).
required_pkgs=(
	chrony
	luci-app-chrony
	mount-utils
	kmod-veth
	kmod-nft-queue
	kmod-nfnetlink-queue
	kmod-xdp-sockets-diag
	kmod-sched-core
	kmod-sched-bpf
	kmod-nft-core
	kmod-nf-conntrack
	kmod-cryptodev
	libopenssl-conf
	libstdcpp
)

# Symbols that must not be =y.
forbidden_y=(
	CONFIG_KERNEL_DEBUG_INFO_REDUCED
	CONFIG_BUSYBOX_CONFIG_NTPD
	CONFIG_BUSYBOX_CONFIG_FEATURE_NTPD_SERVER
)

# Removed packages: neither in the image (=y) nor built as a package (=m).
# Extended regex, matched against the whole package name. honk is listed on
# purpose: it is installed later from the daeuniverse feed.
forbidden_pkg_re='(ddns-scripts(-.*)?|ddns-go|luci-app-ddns|luci-app-ddns-go|lucky|luci-app-lucky|zerotier|luci-app-zerotier|wechatpush|luci-app-wechatpush|pushbot|luci-app-pushbot|vlmcsd|luci-app-vlmcsd|luci-i18n-(ddns|ddns-go|lucky|zerotier|wechatpush|pushbot|vlmcsd)-.*|honk|luci-app-honk|luci-i18n-honk-.*)'

need_file "$config"

has_line() { grep -qxF -- "$1" "$2"; }

for sym in "${required_y[@]}"; do
	has_line "$sym=y" "$config" || err "$config: $sym=y is missing"
done
for pkg in "${required_pkgs[@]}"; do
	has_line "CONFIG_PACKAGE_$pkg=y" "$config" || err "$config: CONFIG_PACKAGE_$pkg=y is missing (must be built into the image)"
done
for sym in "${forbidden_y[@]}"; do
	if has_line "$sym=y" "$config"; then err "$config: $sym=y must not be set"; fi
done
while IFS= read -r line; do
	err "$config: removed package is selected: $line"
done < <(grep -E "^CONFIG_PACKAGE_${forbidden_pkg_re}=[ym]$" "$config" || true)

# --- Kernel .config ---------------------------------------------------------

if [[ -n "$kernel_config" ]]; then
	need_file "$kernel_config"
	kernel_y=(
		CONFIG_BPF CONFIG_BPF_SYSCALL CONFIG_BPF_JIT CONFIG_BPF_EVENTS
		CONFIG_DEBUG_INFO CONFIG_DEBUG_INFO_BTF CONFIG_DEBUG_INFO_BTF_MODULES
		CONFIG_NETKIT CONFIG_XDP_SOCKETS
		CONFIG_CGROUPS CONFIG_CGROUP_BPF CONFIG_NET_NS
		CONFIG_NET_SCHED CONFIG_NET_CLS_ACT CONFIG_NET_XGRESS
		CONFIG_NET_INGRESS CONFIG_NET_EGRESS
		CONFIG_KPROBES CONFIG_KPROBE_EVENTS
		CONFIG_FUNCTION_TRACER CONFIG_DYNAMIC_FTRACE
		CONFIG_BPF_STREAM_PARSER
	)
	kernel_ym=(
		CONFIG_VETH CONFIG_NET_CLS_BPF CONFIG_NET_ACT_BPF CONFIG_NET_SCH_INGRESS
		CONFIG_NF_TABLES CONFIG_NF_TABLES_INET CONFIG_NFT_CT CONFIG_NFT_QUEUE
		CONFIG_NETFILTER_NETLINK_QUEUE CONFIG_XDP_SOCKETS_DIAG
	)
	for sym in "${kernel_y[@]}"; do
		has_line "$sym=y" "$kernel_config" || err "kernel: $sym=y is missing"
	done
	for sym in "${kernel_ym[@]}"; do
		has_line "$sym=y" "$kernel_config" || has_line "$sym=m" "$kernel_config" ||
			err "kernel: $sym=y|m is missing"
	done
	if has_line "CONFIG_DEBUG_INFO_REDUCED=y" "$kernel_config"; then
		err "kernel: CONFIG_DEBUG_INFO_REDUCED=y breaks BTF"
	fi
fi

# --- Image manifests --------------------------------------------------------

for manifest in ${manifests[@]+"${manifests[@]}"}; do
	need_file "$manifest"
	names="$(sed -n 's/^\([^ ]*\) - .*/\1/p' "$manifest")"
	[[ -n "$names" ]] || { err "$manifest: no packages parsed"; continue; }
	for pkg in "${required_pkgs[@]}"; do
		# apk package names carry the ABI version (libstdcpp -> libstdcpp6).
		grep -qxE -- "${pkg}[0-9.]*" <<<"$names" || err "$manifest: required package $pkg is not in the image"
	done
	while IFS= read -r pkg; do
		err "$manifest: removed package is in the image: $pkg"
	done < <(grep -xE -- "$forbidden_pkg_re" <<<"$names" || true)
done

# --- Root filesystem --------------------------------------------------------

if [[ -n "$rootfs" ]]; then
	[[ -d "$rootfs" ]] || { echo "check-config: no such directory: $rootfs" >&2; exit 2; }
	for path in etc/init.d/sysntpd usr/sbin/ntpd usr/sbin/ntpd-hotplug; do
		if [[ -e "$rootfs/$path" || -L "$rootfs/$path" ]]; then
			err "rootfs: /$path is present (busybox ntpd/sysntpd must be gone)"
		fi
	done
	[[ -x "$rootfs/etc/init.d/chronyd" ]] || err "rootfs: /etc/init.d/chronyd is missing"
	[[ -f "$rootfs/etc/ssl/modules.cnf.d/devcrypto.cnf" ]] ||
		err "rootfs: /etc/ssl/modules.cnf.d/devcrypto.cnf is missing (OpenSSL devcrypto engine)"
fi

if ((errors)); then
	echo "check-config: $errors problem(s) found." >&2
	exit 1
fi
n_manifests=${#manifests[@]}
echo "check-config: OK (${config}${kernel_config:+, kernel}, ${n_manifests} manifest(s)${rootfs:+, rootfs})"
