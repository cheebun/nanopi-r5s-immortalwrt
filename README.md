# ImmortalWrt 25.12 for FriendlyElec NanoPi R5S

A custom [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) 25.12 build for the
FriendlyElec NanoPi R5S (Rockchip RK3568, target `rockchip/armv8`, profile
`friendlyarm_nanopi-r5s`), built by GitHub Actions.

This repository is an **overlay**, not a fork. It holds only the device config,
the feed patches and the tooling. CI checks out pristine ImmortalWrt at a release
tag and installs the overlay into it. The layout and the feed-patch mechanism
follow the Brightspeed XR1710G ImmortalWrt repository.

| Item | Value |
|------|-------|
| Upstream | ImmortalWrt `v25.12.2` (default; branch `openwrt-25.12` also works) |
| Kernel | Linux 6.12 (6.12.103 at `v25.12.2`) |
| Target / profile | `rockchip/armv8` / `friendlyarm_nanopi-r5s` (device package: `kmod-r8125`) |
| Package arch | `aarch64_generic` |
| Images | `*-friendlyarm_nanopi-r5s-squashfs-sysupgrade.img.gz`, `*-ext4-sysupgrade.img.gz` |

## Changes from the upstream image

**Added**

- `chrony` + `luci-app-chrony` for time sync.
- Kernel modules `kmod-veth`, `kmod-nft-queue`, `kmod-nfnetlink-queue`, `kmod-xdp-sockets-diag`.
- `mount-utils` (util-linux `mount`, `umount`, `findmnt`, ...).
- Kernel BTF debug info.
- Kernel netkit.
- OpenSSL with the built-in devcrypto engine (`kmod-cryptodev`).
- What honk needs at runtime (see below): `kmod-sched-core`, `kmod-sched-bpf`,
  `kmod-nft-core`, `kmod-nf-conntrack`, `libstdcpp`, kprobes/BPF events, ftrace.

**Removed**

- DDNS (`ddns-scripts*`, `luci-app-ddns`), DDNS-Go, Lucky, ZeroTier, WeChatPush,
  PushBot, vlmcsd: none of these is in the ImmortalWrt 25.12 default image. They
  are pinned off so they cannot come back, and CI fails if any of them is
  selected (`=y` or `=m`).
- busybox `ntpd` and the `sysntpd` init script, which busybox installs only when
  its NTPD applet is enabled.
- `luci-app-attendedsysupgrade` / `owut`: the official buildbot enables them, but
  on a custom image an attended sysupgrade would install a stock image.

**Not built in:** honk. Install it from the daeuniverse feed after flashing.

## Spec to Kconfig mapping

Every symbol was checked against the `v25.12.2` tree and its pinned feeds.

| Spec item | Symbols (`r5s.config`) | Notes |
|-----------|-------------------------|-------|
| BTF | `KERNEL_DEBUG_INFO=y`, `# KERNEL_DEBUG_INFO_REDUCED is not set`, `KERNEL_DEBUG_INFO_BTF=y` | Defaults to y only with `BUILDBOT`. It selects `DWARVES` (host pahole 1.31). `KERNEL_DEBUG_INFO_BTF_MODULES` is a def_bool. |
| netkit | `KERNEL_NETKIT=y` | Built in (`CONFIG_NETKIT`). There is no `kmod-netkit`. Needs kernel ≥ 6.7. |
| veth / NFQUEUE / XSK diag | `PACKAGE_kmod-veth`, `kmod-nft-queue`, `kmod-nfnetlink-queue`, `kmod-xdp-sockets-diag` | xsk-diag depends on `KERNEL_XDP_SOCKETS`. |
| mount-utils | `PACKAGE_mount-utils` | From `package/utils/util-linux`. |
| OpenSSL devcrypto | `OPENSSL_ENGINE=y`, `OPENSSL_ENGINE_BUILTIN=y`, `OPENSSL_ENGINE_BUILTIN_DEVCRYPTO=y` | Pulls `kmod-cryptodev` and `libopenssl-conf` (`/etc/ssl/modules.cnf.d/devcrypto.cnf`). |
| chrony | `PACKAGE_chrony`, `PACKAGE_luci-app-chrony` | chrony 4.8 (packages feed), LuCI app (luci feed). |
| No busybox ntpd / sysntpd | `BUSYBOX_CUSTOM=y`, `# BUSYBOX_CONFIG_NTPD is not set`, `# BUSYBOX_CONFIG_FEATURE_NTPD_SERVER is not set` | Without `BUSYBOX_CUSTOM` the NTPD switch has no effect (`BUSYBOX_DEFAULT_NTPD=y`). |
| honk: TC/TCX | `PACKAGE_kmod-sched-core` (`NET_SCHED=y`, `NET_CLS_ACT=y`, which selects `NET_XGRESS`), `kmod-sched-bpf` | |
| honk: cgroup/netns | `KERNEL_CGROUPS`, `KERNEL_CGROUP_BPF`, `KERNEL_NAMESPACES`, `KERNEL_NET_NS` | Upstream defaults. Pinned here. |
| honk/dae: tracing | `KERNEL_BPF_EVENTS`, `KERNEL_KPROBES`, `KERNEL_KPROBE_EVENTS`, `KERNEL_FUNCTION_TRACER`, `KERNEL_DYNAMIC_FTRACE` | ftrace is optional for honk (native-api UDP fallback). |
| dae extras | `KERNEL_BPF_STREAM_PARSER`, `KERNEL_XDP_SOCKETS` | Default y when BTF is on. |

`CONFIG_BPF`, `BPF_SYSCALL`, `BPF_JIT`, `NET_INGRESS` and `NET_EGRESS` are already `=y` in
the generic/rockchip kernel configs. `scripts/check-config.sh` checks the final kernel
`.config` for all of them.

## honk

honk (daeuniverse) needs Linux 6.12+, raw BTF (`/sys/kernel/btf/vmlinux`), cgroup v2 +
`CGROUP_BPF`, `NET_CLS_ACT`/`NET_XGRESS`, netns, and nftables NFQUEUE (`NFT_QUEUE`,
`NETFILTER_NETLINK_QUEUE`). netkit is optional; honk falls back to veth.

The feed's `honk` apk depends on `libstdcpp kmod-veth kmod-sched-core kmod-sched-bpf
kmod-nft-core kmod-nft-queue kmod-nfnetlink-queue kmod-nf-conntrack vmlinux-btf
v2ray-geoip v2ray-geosite`. The kmods for this custom kernel cannot come from the official
ImmortalWrt repository: the kernel vermagic differs. That is why every one of them is built
into this image. On a kernel with built-in BTF, the feed's `vmlinux-btf-builtin` package
satisfies `vmlinux-btf`. `v2ray-geoip` / `v2ray-geosite` install from the ImmortalWrt package
repository.

After flashing (ImmortalWrt instructions from <https://daeuniverse.org/openwrt/>; use the
packages line only, not the `kmods` line):

```sh
wget -O /etc/apk/keys/daeuniverse.pem https://openwrt.daeuniverse.org/public-key.pem
. /etc/openwrt_release
FEED=https://openwrt.daeuniverse.org/$(echo "$DISTRIB_RELEASE" | cut -d. -f1-2)
echo "@daeuniverse $FEED/packages/$DISTRIB_ARCH/packages.adb" > /etc/apk/repositories.d/daeuniverse.list
apk update
apk add honk@daeuniverse luci-app-honk@daeuniverse
```

## Time synchronisation

- chrony reads `/etc/config/chrony` (default pool `2.openwrt.pool.ntp.org` plus DHCP-provided
  servers). It ignores `system.ntp`, so the Chinese NTP servers that `default-settings-chn`
  writes there have no effect. To change servers, patch chrony's default config under
  `patches/feeds/packages/net/chrony/`, as xr1710g does.
- LuCI's System -> System page shows the "Time Synchronization" tab only when
  `/usr/sbin/ntpd` exists (`hasSystemFeature('sysntpd')`). With busybox ntpd gone, the tab and
  the "Sync with NTP-Server" button disappear. "Sync with browser" still works. chrony is
  managed under Services -> Chrony (`luci-app-chrony`, Simplified Chinese strings included).

## Configuration

`r5s.config` is a diffconfig seed. `scripts/compose-config.sh` merges it with the CI-only
options (ccache, build logs). Later fragments win, one line per key. Then `make defconfig`
fills in the rest. `scripts/check-config.sh` enforces the spec twice:

1. After `make defconfig`: the required symbols and packages are `=y`, and no removed
   package is `=y`/`=m`.
2. After the build: the kernel `.config` has every BPF/BTF/netkit/NFQUEUE option, `vmlinux`
   carries a `.BTF` section, the image manifest has the required packages and none of the
   removed ones, and the rootfs has no `sysntpd` / `ntpd`.

## CI

`.github/workflows/build.yml`, run manually (Actions -> Build R5S firmware -> Run workflow):

1. Frees runner disk space and builds on the larger of `/` and `/mnt`.
2. Installs the build dependencies and `dwarves`.
3. Clones ImmortalWrt at the chosen ref (release tags pin all feeds) and installs the
   overlay.
4. Runs `feeds update/install`, then the feed-patch tests and `apply-feed-patches.sh`
   (strict).
5. Configures and checks (see above), runs `make download`, then `make world`. On failure it
   retries the failed package once with `V=s`.
6. Verifies the outputs and uploads the sysupgrade images, manifest, `*.buildinfo`,
   `sha256sums`, `profiles.json`, `diffconfig`, `build.log` and `build-info.txt`.
   The kmods/packages artifact is optional.

`dl/` and ccache are cached with `actions/cache` and saved even when the build fails.

## Local build

Linux x86_64, about 50 GB free, build dependencies as listed in the ImmortalWrt README.

```sh
git clone --depth 1 --branch v25.12.2 https://github.com/immortalwrt/immortalwrt.git immortalwrt
bash scripts/install-overlay.sh immortalwrt
cd immortalwrt
./scripts/feeds update -a && ./scripts/feeds install -a
FEED_PATCHES_STRICT=1 bash scripts/apply-feed-patches.sh
bash ../scripts/compose-config.sh .config ../r5s.config
make defconfig
bash ../scripts/check-config.sh --config .config
make download -j8
make -j"$(nproc)" world
```

## Feed patches

See [`patches/feeds/README.md`](patches/feeds/README.md). There are no patches yet; a GPU
status row for LuCI is planned. Run `bash scripts/test-apply-feed-patches.sh` after
changing the apply script.

## Sources

- ImmortalWrt `v25.12.2`: `target/linux/rockchip/Makefile`, `target/linux/rockchip/image/armv8.mk`,
  `include/target.mk`, `config/Config-kernel.in`, `package/utils/busybox/`, `package/libs/openssl/`,
  `package/kernel/linux/modules/netsupport.mk`, `netfilter.mk`
- Official build: <https://downloads.immortalwrt.org/releases/25.12.2/targets/rockchip/armv8/>
  (`config.buildinfo`, `profiles.json`, manifest)
- honk kernel requirements: <https://github.com/daeuniverse/honk/blob/main/doc/en/how-to-start.md>
- dae kernel requirements: <https://github.com/daeuniverse/dae/blob/main/docs/en/README.md>
- honk OpenWrt package: <https://github.com/daeuniverse/openwrt-packages> (`honk/Makefile`,
  `vmlinux-btf-builtin/Makefile`), feed index `https://openwrt.daeuniverse.org/25.12/packages/aarch64_generic/`

## License

The overlay scripts are GPL-2.0-only, matching ImmortalWrt.
