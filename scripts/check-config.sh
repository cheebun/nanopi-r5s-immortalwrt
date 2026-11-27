#!/usr/bin/env bash
#
# Enforce the firmware spec on the resolved build config and on build outputs.
#
# Usage:
#   bash scripts/check-config.sh --config <.config> [--tree <dir>]
#        [--kernel-config <linux .config>] [--manifest <file>]... [--rootfs <dir>]
#
#   --config         The top-level .config after `make defconfig` (required).
#   --tree           The ImmortalWrt tree: checks which feed each package is
#                    installed from (package/feeds/<feed>/<package>), that no
#                    daeuniverse feed exists and that no honk apk was built.
#   --kernel-config  The kernel .config from build_dir/.../linux-*/.config.
#   --manifest       An image manifest ("name - version" per line).
#   --rootfs         The staged root filesystem (build_dir/.../root-rockchip).
#
# `make defconfig` silently drops or flips symbols whose dependencies are not
# met, so the seed config proves nothing; this checks what was actually
# resolved and built. Every failure is reported before exiting non-zero.
#
# Keep the lists below in sync with r5s.config. scripts/test-check-config.sh
# runs this script against fake inputs.

set -Eeuo pipefail

config=""
tree=""
kernel_config=""
rootfs=""
manifests=()

while [[ $# -gt 0 ]]; do
	case "$1" in
	--config) config="${2:?}"; shift 2 ;;
	--tree) tree="${2:?}"; shift 2 ;;
	--kernel-config) kernel_config="${2:?}"; shift 2 ;;
	--manifest) manifests+=("${2:?}"); shift 2 ;;
	--rootfs) rootfs="${2:?}"; shift 2 ;;
	-h | --help) sed -n '2,23p' "$0"; exit 0 ;;
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
	# ImmortalWrt release "tweak" set (not default on master)
	luci
	autocore
	default-settings-chn
	luci-app-cpufreq
	# time sync
	chrony
	luci-app-chrony
	luci-i18n-chrony-zh-cn
	# DNS
	dnsmasq-full
	mosdns
	luci-app-mosdns
	luci-i18n-mosdns-zh-cn
	geo2txt
	# v2ray-geoip, v2ray-geosite: in HONK_RUNTIME_REQUIRED
	# LuCI theme: Vantage (vantage feed), Bootstrap as the fallback
	luci-theme-vantage
	luci-i18n-vantage-theme-zh-cn
	luci-app-vantage
	luci-i18n-vantage-zh-cn
	luci-app-vantage-traffic
	luci-i18n-vantage-traffic-zh-cn
	luci-theme-bootstrap
	mount-utils
	# kmod-veth, kmod-nft-queue, kmod-nfnetlink-queue: in HONK_RUNTIME_REQUIRED
	kmod-xdp-sockets-diag
	kmod-cryptodev
	libopenssl-conf
)

# honk is NOT built here: it is installed separately on the router, from
# daeuniverse's official releases. Everything it needs at runtime must be
# built into the image (=y and in the manifest), because official kmods do
# not match this kernel. Package deps of honk and luci-app-honk
# (luci-lib-daeuniverse needs flock and coreutils-timeout).
HONK_RUNTIME_REQUIRED=(
	libstdcpp
	kmod-veth
	kmod-sched-core
	kmod-sched-bpf
	kmod-nft-core
	kmod-nft-queue
	kmod-nfnetlink-queue
	kmod-nf-conntrack
	v2ray-geoip
	v2ray-geosite
	flock
	coreutils-timeout
)
# Kernel options honk needs (=y in the final kernel .config); vmlinux must
# also carry a .BTF section (checked by the workflow with readelf).
HONK_RUNTIME_KERNEL_Y=(
	CONFIG_DEBUG_INFO_BTF
	CONFIG_BPF_SYSCALL
	CONFIG_BPF_JIT
	CONFIG_NETKIT
	CONFIG_CGROUP_BPF
	CONFIG_SYSFS
)

# Symbols that must not be =y.
forbidden_y=(
	CONFIG_KERNEL_DEBUG_INFO_REDUCED
	CONFIG_BUSYBOX_CONFIG_NTPD
	CONFIG_BUSYBOX_CONFIG_FEATURE_NTPD_SERVER
	CONFIG_PACKAGE_dnsmasq
)

# honk and its daeuniverse packages: installed separately, so neither in the
# image nor built here (=y or =m), nor in a manifest. Extended regex, matched
# against the whole package name.
not_in_image_re='(honk|luci-app-honk|luci-lib-daeuniverse|luci-i18n-daeuniverse-.*|luci-i18n-honk-.*|vmlinux-btf|vmlinux-btf-builtin)'

# Removed packages: neither in the image (=y) nor built as a package (=m).
# Extended regex, matched against the whole package name. vmlinux-btf (the
# prebuilt-blob package) cannot build here, so it must not even be =m.
# Vantage replaces Argon (luci-app-argon-config is the name Argon provides,
# its translations are luci-i18n-argon-config-*); the Vantage access-point
# pairing add-on is not wanted either.
forbidden_pkg_re='(ddns-scripts(-.*)?|ddns-go|luci-app-ddns|luci-app-ddns-go|lucky|luci-app-lucky|zerotier|luci-app-zerotier|wechatpush|luci-app-wechatpush|pushbot|luci-app-pushbot|vlmcsd|luci-app-vlmcsd|luci-i18n-(ddns|ddns-go|lucky|zerotier|wechatpush|pushbot|vlmcsd)-.*|chrony-nts|vmlinux-btf|luci-theme-argon|luci-app-argon-config|luci-i18n-argon-config-.*|luci-app-vantage-aps|luci-i18n-vantage-aps-.*)'

# The NTP servers 100-cn-ntp-servers.patch puts in /etc/config/chrony.
chrony_servers=(ntp.tencent.com ntp1.aliyun.com ntp.ntsc.ac.cn cn.ntp.org.cn)

need_file "$config"

has_line() { grep -qxF -- "$1" "$2"; }

for sym in "${required_y[@]}"; do
	has_line "$sym=y" "$config" || err "$config: $sym=y is missing"
done
for pkg in "${required_pkgs[@]}"; do
	has_line "CONFIG_PACKAGE_$pkg=y" "$config" || err "$config: CONFIG_PACKAGE_$pkg=y is missing (must be built into the image)"
done
for pkg in "${HONK_RUNTIME_REQUIRED[@]}"; do
	has_line "CONFIG_PACKAGE_$pkg=y" "$config" || err "$config: CONFIG_PACKAGE_$pkg=y is missing (honk runtime dependency)"
done
for sym in "${forbidden_y[@]}"; do
	if has_line "$sym=y" "$config"; then err "$config: $sym=y must not be set"; fi
done
while IFS= read -r line; do
	err "$config: removed package is selected: $line"
done < <(grep -E "^CONFIG_PACKAGE_${forbidden_pkg_re}=[ym]$" "$config" || true)
while IFS= read -r line; do
	err "$config: honk is installed separately, must not be built: $line"
done < <(grep -E "^CONFIG_PACKAGE_${not_in_image_re}=[ym]$" "$config" || true)

# --- Feed sources -----------------------------------------------------------

if [[ -n "$tree" ]]; then
	[[ -d "$tree/package/feeds" ]] || { echo "check-config: no package/feeds in $tree" >&2; exit 2; }
	# package:feed it must be installed from, and from no other feed.
	for spec in mosdns:mosdns luci-app-mosdns:mosdns geo2txt:mosdns \
		luci-theme-vantage:vantage luci-app-vantage:vantage luci-app-vantage-traffic:vantage; do
		pkg="${spec%%:*}"
		feed="${spec#*:}"
		[[ -f "$tree/package/feeds/$feed/$pkg/Makefile" ]] ||
			err "tree: $pkg is not installed from feed '$feed'"
		for other in "$tree"/package/feeds/*/"$pkg"; do
			if [[ -e "$other" && "$other" != "$tree/package/feeds/$feed/$pkg" ]]; then
				err "tree: $pkg is also installed from ${other#"$tree"/}"
			fi
		done
	done
	# honk is installed separately; nothing of daeuniverse is built here.
	for path in feeds/daeuniverse package/feeds/daeuniverse; do
		if [[ -e "$tree/$path" || -L "$tree/$path" ]]; then err "tree: $path exists (honk is not built here)"; fi
	done
	if [[ -d "$tree/bin/packages" ]]; then
		while IFS= read -r apk; do
			err "tree: ${apk#"$tree"/} was built (honk is not built here)"
		done < <(find "$tree/bin/packages" -name 'honk*.apk' 2>/dev/null)
	fi
fi

# --- Kernel .config ---------------------------------------------------------

if [[ -n "$kernel_config" ]]; then
	need_file "$kernel_config"
	kernel_y=(
		# plus HONK_RUNTIME_KERNEL_Y
		"${HONK_RUNTIME_KERNEL_Y[@]}"
		CONFIG_BPF CONFIG_BPF_EVENTS
		CONFIG_DEBUG_INFO CONFIG_DEBUG_INFO_BTF_MODULES
		CONFIG_XDP_SOCKETS
		CONFIG_CGROUPS CONFIG_NET_NS
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
	for pkg in "${required_pkgs[@]}" "${HONK_RUNTIME_REQUIRED[@]}"; do
		# apk package names carry the ABI version (libstdcpp -> libstdcpp6).
		grep -qxE -- "${pkg}[0-9.]*" <<<"$names" || err "$manifest: required package $pkg is not in the image"
	done
	while IFS= read -r pkg; do
		err "$manifest: removed package is in the image: $pkg"
	done < <(grep -xE -- "$forbidden_pkg_re" <<<"$names" || true)
	while IFS= read -r pkg; do
		err "$manifest: $pkg must not be in the image (honk is installed separately)"
	done < <(grep -xE -- "$not_in_image_re" <<<"$names" || true)
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

	# chrony: the Chinese servers of 100-cn-ntp-servers.patch, no default
	# pool, no NTS.
	chrony_conf="$rootfs/etc/config/chrony"
	if [[ -f "$chrony_conf" ]]; then
		for server in "${chrony_servers[@]}"; do
			grep -qF -- "option hostname '$server'" "$chrony_conf" ||
				err "rootfs: /etc/config/chrony lacks server $server (chrony feed patch not applied?)"
		done
		if grep -qE '^config pool' "$chrony_conf"; then
			err "rootfs: /etc/config/chrony still has the default pool"
		fi
		if grep -qE "^[[:space:]]*option nts '1'" "$chrony_conf"; then
			err "rootfs: /etc/config/chrony enables NTS"
		fi
	else
		err "rootfs: /etc/config/chrony is missing"
	fi

	# mosdns: sbwml's luci-app-mosdns owns the UCI config and the init script;
	# the packages feed's mosdns ships a different, non-UCI init script.
	[[ -x "$rootfs/usr/bin/mosdns" ]] || err "rootfs: /usr/bin/mosdns is missing"
	[[ -f "$rootfs/etc/config/mosdns" ]] || err "rootfs: /etc/config/mosdns is missing (sbwml mosdns)"
	if [[ -x "$rootfs/etc/init.d/mosdns" ]]; then
		grep -qF 'mosdns.config.configfile' "$rootfs/etc/init.d/mosdns" ||
			err "rootfs: /etc/init.d/mosdns is not sbwml's (packages feed mosdns?)"
	else
		err "rootfs: /etc/init.d/mosdns is missing (sbwml mosdns)"
	fi

	# honk must not be in the image.
	for path in usr/bin/honk-core etc/init.d/honk etc/config/honk; do
		if [[ -e "$rootfs/$path" ]]; then err "rootfs: /$path is present (honk must not be in the image)"; fi
	done

	# GPU row: files/ overlay plus the luci-mod-status feed patch.
	[[ -x "$rootfs/sbin/gpuinfo" ]] || err "rootfs: /sbin/gpuinfo is missing or not executable (files/ overlay)"
	[[ -f "$rootfs/usr/share/rpcd/ucode/gpuinfo" ]] || err "rootfs: /usr/share/rpcd/ucode/gpuinfo is missing (files/ overlay)"
	[[ -f "$rootfs/usr/share/rpcd/acl.d/luci-mod-status-gpuinfo.json" ]] ||
		err "rootfs: /usr/share/rpcd/acl.d/luci-mod-status-gpuinfo.json is missing (files/ overlay)"
	sys_js="$rootfs/www/luci-static/resources/view/status/include/10_system.js"
	if [[ -f "$sys_js" ]]; then
		grep -qF 'luci.gpuinfo' "$sys_js" || err "rootfs: 10_system.js has no GPU row (luci feed patch not applied?)"
	else
		err "rootfs: /www/luci-static/resources/view/status/include/10_system.js is missing (luci-mod-status)"
	fi
	[[ -x "$rootfs/sbin/cpuinfo" ]] || err "rootfs: /sbin/cpuinfo is missing (autocore)"

	# LuCI theme: Vantage from its package plus files/ (99-vantage selects it,
	# the menu override moves Status back in front of the dashboard); no Argon.
	for path in www/luci-static/vantage/vantage.css \
		usr/share/ucode/luci/template/themes/vantage/header.ut \
		etc/uci-defaults/30_luci-theme-vantage \
		www/luci-static/bootstrap/cascade.css; do
		[[ -f "$rootfs/$path" ]] || err "rootfs: /$path is missing (luci-theme-vantage / luci-theme-bootstrap)"
	done
	vantage_defaults="$rootfs/etc/uci-defaults/99-vantage"
	if [[ -x "$vantage_defaults" ]]; then
		grep -qF '/luci-static/vantage' "$vantage_defaults" ||
			err "rootfs: /etc/uci-defaults/99-vantage does not select /luci-static/vantage"
	else
		err "rootfs: /etc/uci-defaults/99-vantage is missing or not executable (files/ overlay)"
	fi
	landing="$rootfs/usr/share/luci/menu.d/zz-landing-override.json"
	if [[ -f "$landing" ]]; then
		python3 -c 'import json, sys; json.load(open(sys.argv[1]))' "$landing" 2>/dev/null ||
			err "rootfs: /usr/share/luci/menu.d/zz-landing-override.json is not valid JSON"
	else
		err "rootfs: /usr/share/luci/menu.d/zz-landing-override.json is missing (files/ overlay)"
	fi
	for path in etc/uci-defaults/30_luci-theme-argon www/luci-static/argon etc/config/argon; do
		if [[ -e "$rootfs/$path" ]]; then err "rootfs: /$path is present (Argon must not be in the image)"; fi
	done
fi

if ((errors)); then
	echo "check-config: $errors problem(s) found." >&2
	exit 1
fi
n_manifests=${#manifests[@]}
echo "check-config: OK (${config}${tree:+, tree}${kernel_config:+, kernel}, ${n_manifests} manifest(s)${rootfs:+, rootfs})"
