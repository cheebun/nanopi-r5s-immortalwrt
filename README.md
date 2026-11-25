# ImmortalWrt master for FriendlyElec NanoPi R5S

A custom [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) build from the `master`
branch (Linux 6.18 on rockchip) for the FriendlyElec NanoPi R5S (Rockchip RK3568, target
`rockchip/armv8`, profile `friendlyarm_nanopi-r5s`), built by GitHub Actions.

This repository is an **overlay**, not a fork. It holds only the device config, the extra
feeds, the feed patches, a few rootfs files and the tooling. CI checks out pristine
ImmortalWrt and installs the overlay into it. The layout and the feed-patch mechanism follow
the Brightspeed XR1710G ImmortalWrt repository.

| Item | Value |
|------|-------|
| Upstream | ImmortalWrt `master` (default workflow input) |
| Kernel | Linux 6.18 (`KERNEL_PATCHVER:=6.18`; 6.18.60 when this was written) |
| Target / profile | `rockchip/armv8` / `friendlyarm_nanopi-r5s` (device package: `kmod-r8125`) |
| Package arch | `aarch64_generic` |
| Images | `*-friendlyarm_nanopi-r5s-squashfs-sysupgrade.img.gz`, `*-ext4-sysupgrade.img.gz` |

## master branch caveats

- **Snapshot, not a release.** master moves daily. The feeds in `feeds.conf.default` are not
  pinned, and neither are the two extra feeds. Every build records the exact commits of the
  main tree, every feed and honk's sources in `feeds.lock.txt` (also copied into
  `build-info.txt`). `feeds.lock.txt` is a valid `feeds.conf`: copy it over
  `<tree>/feeds.conf` after `install-overlay.sh` to rebuild the same feeds.
- **No LuCI by default.** Release branches add `DEFAULT_PACKAGES.tweak` (LuCI, autocore,
  `default-settings-chn`, `block-mount`, `kmod-nf-nathelper`, `luci-app-cpufreq`) to every
  image; master leaves that line commented out in `include/target.mk`. `r5s.config` selects
  the same list.
- **Kmods come only from this build.** Kernel modules from the ImmortalWrt snapshot
  repository do not match this kernel (vermagic). Install extra kmods from this run's
  packages artifact (`upload_packages`), or add them to `r5s.config`.
- **Feed patches can break.** A patch that no longer applies to the feed's HEAD fails the
  build in "Apply feed patches". Rebase it then (see `patches/feeds/README.md`).

## Changes from the upstream image

**Added**

- `chrony` + `luci-app-chrony` (+ zh-cn) for time sync, with Chinese NTP servers.
- `dnsmasq-full`, sbwml's `mosdns` + `luci-app-mosdns` (+ zh-cn), `geo2txt`,
  `v2ray-geoip`, `v2ray-geosite`.
- A GPU row on Status -> Overview (see below).
- Kernel modules `kmod-veth`, `kmod-nft-queue`, `kmod-nfnetlink-queue`, `kmod-xdp-sockets-diag`.
- `mount-utils` (util-linux `mount`, `umount`, `findmnt`, ...).
- Kernel BTF debug info and netkit.
- OpenSSL with the built-in devcrypto engine (`kmod-cryptodev`).
- What honk needs at runtime: `kmod-sched-core`, `kmod-sched-bpf`, `kmod-nft-core`,
  `kmod-nf-conntrack`, `libstdcpp`, kprobes/BPF events, ftrace.
- The release "tweak" packages listed above.

**Removed**

- DDNS (`ddns-scripts*`, `luci-app-ddns`), DDNS-Go, Lucky, ZeroTier, WeChatPush, PushBot,
  vlmcsd: none of them is in the default image. They are pinned off so they cannot come
  back, and CI fails if any of them is selected (`=y` or `=m`).
- busybox `ntpd` and the `sysntpd` init script, which busybox installs only when its NTPD
  applet is enabled. `chrony-nts` is not selected.
- `luci-app-attendedsysupgrade` / `owut`: an attended sysupgrade would install a stock image.

**Built but not in the image:** honk, `luci-app-honk`, `luci-lib-daeuniverse` and
`vmlinux-btf-builtin`, as `.apk` files in a separate artifact.

## Spec to Kconfig mapping

Every symbol was checked against the master tree and its feeds (2026-11-24).

| Spec item | Symbols (`r5s.config`) | Notes |
|-----------|-------------------------|-------|
| BTF | `KERNEL_DEBUG_INFO=y`, `# KERNEL_DEBUG_INFO_REDUCED is not set`, `KERNEL_DEBUG_INFO_BTF=y` | Defaults to y only with `BUILDBOT`. It selects `DWARVES` (host pahole). `KERNEL_DEBUG_INFO_BTF_MODULES` is a def_bool. |
| netkit | `KERNEL_NETKIT=y` | Built in (`CONFIG_NETKIT`). There is no `kmod-netkit`. |
| veth / NFQUEUE / XSK diag | `PACKAGE_kmod-veth`, `kmod-nft-queue`, `kmod-nfnetlink-queue`, `kmod-xdp-sockets-diag` | xsk-diag depends on `KERNEL_XDP_SOCKETS`. |
| mount-utils | `PACKAGE_mount-utils` | From `package/utils/util-linux`. |
| OpenSSL devcrypto | `OPENSSL_ENGINE=y`, `OPENSSL_ENGINE_BUILTIN=y`, `OPENSSL_ENGINE_BUILTIN_DEVCRYPTO=y` | Pulls `kmod-cryptodev` and `libopenssl-conf` (`/etc/ssl/modules.cnf.d/devcrypto.cnf`). |
| chrony | `PACKAGE_chrony`, `luci-app-chrony`, `luci-i18n-chrony-zh-cn`, `# PACKAGE_chrony-nts is not set` | packages / luci feeds. |
| No busybox ntpd / sysntpd | `BUSYBOX_CUSTOM=y`, `# BUSYBOX_CONFIG_NTPD is not set`, `# BUSYBOX_CONFIG_FEATURE_NTPD_SERVER is not set` | Without `BUSYBOX_CUSTOM` the NTPD switch has no effect. |
| DNS | `PACKAGE_dnsmasq-full`, `# PACKAGE_dnsmasq is not set`, `mosdns`, `luci-app-mosdns`, `luci-i18n-mosdns-zh-cn`, `geo2txt`, `v2ray-geoip`, `v2ray-geosite` | mosdns, its LuCI app and geo2txt from the sbwml feed; the geodata from the packages feed. |
| honk apks | `PACKAGE_honk=m`, `luci-app-honk=m`, `vmlinux-btf-builtin=m` | daeuniverse feed. `luci-lib-daeuniverse` follows as `=m`. |
| honk: TC/TCX | `PACKAGE_kmod-sched-core` (`NET_SCHED=y`, `NET_CLS_ACT=y`, which selects `NET_XGRESS`), `kmod-sched-bpf` | |
| honk: cgroup/netns | `KERNEL_CGROUPS`, `KERNEL_CGROUP_BPF`, `KERNEL_NAMESPACES`, `KERNEL_NET_NS` | Upstream defaults, pinned here. |
| honk/dae: tracing | `KERNEL_BPF_EVENTS`, `KERNEL_KPROBES`, `KERNEL_KPROBE_EVENTS`, `KERNEL_FUNCTION_TRACER`, `KERNEL_DYNAMIC_FTRACE` | ftrace is optional for honk (native-api UDP fallback). |
| dae extras | `KERNEL_BPF_STREAM_PARSER`, `KERNEL_XDP_SOCKETS` | Default y when BTF is on. |
| Tweak set | `PACKAGE_autocore`, `block-mount`, `default-settings-chn`, `kmod-nf-nathelper`, `luci`, `luci-app-cpufreq` | Not default on master. |

`CONFIG_BPF`, `BPF_SYSCALL`, `BPF_JIT`, `NET_INGRESS` and `NET_EGRESS` are already `=y` in
the generic/rockchip kernel configs. `scripts/check-config.sh` checks the final kernel
`.config` for all of them.

## Time synchronisation

- chrony replaces busybox ntpd. `patches/feeds/packages/net/chrony/100-cn-ntp-servers.patch`
  (the same patch as the XR1710G build) replaces the default `2.openwrt.pool.ntp.org` pool in
  `/etc/config/chrony` with four servers, each `iburst`: `ntp.tencent.com`,
  `ntp1.aliyun.com`, `ntp.ntsc.ac.cn`, `cn.ntp.org.cn`. DHCP-provided servers are still used.
  NTS is off. CI checks the built rootfs for these servers.
- chrony ignores `system.ntp`, so the servers `default-settings-chn` writes there have no
  effect. Change servers in `/etc/config/chrony` or under Services -> Chrony.
- LuCI's System -> System page shows the "Time Synchronization" tab only when
  `/usr/sbin/ntpd` exists. With busybox ntpd gone, the tab and the "Sync with NTP-Server"
  button disappear. "Sync with browser" still works.

## DNS

`dnsmasq-full` stays the DHCP server and the resolver on port 53. sbwml's mosdns
(`src-git mosdns https://github.com/sbwml/luci-app-mosdns.git;v5`) is installed but not
configured or enabled: the repository carries no mosdns configuration. Set it up under
Services -> MosDNS (it listens on 5335 by default) and point dnsmasq at it if wanted.

The packages feed also has a `mosdns`, whose package installs a different, non-UCI
`/etc/init.d/mosdns`. `scripts/prepare-feeds.sh` deletes `feeds/packages/net/mosdns` after
`feeds update` and rebuilds the packages index before `feeds install`, the method sbwml's
README gives for non-OpenWrt sources. It then checks that mosdns, `luci-app-mosdns` and
`geo2txt` are installed from the mosdns feed. After the build, `check-config.sh` checks that
the image has `/etc/config/mosdns` and sbwml's `/etc/init.d/mosdns`.

## GPU row on the status page

ImmortalWrt already provides the CPU rows of Status -> Overview (autocore's `/sbin/cpuinfo`:
model, frequency, temperature; CpuMark; CPU usage). This build adds one row, "GPU", right
after "Architecture", e.g. `Mali Bifrost (400MHz, 43.8°C)`:

- `files/sbin/gpuinfo` prints the line: model from the Mali kbase `gpuinfo` file, else from
  the device-tree `compatible` (the mainline panfrost driver of this kernel gives
  "Mali Bifrost"), else "GPU"; frequency from the GPU devfreq node; temperature from the
  `gpu-thermal` zone. It prints nothing when none of these exists.
- `files/usr/share/rpcd/ucode/gpuinfo` exposes it as ubus `luci.gpuinfo` / `getGPUInfo`;
  `files/usr/share/rpcd/acl.d/luci-mod-status-gpuinfo.json` grants it to
  `luci-mod-status-index`.
- `patches/feeds/luci/.../include/100-gpu-row.patch` adds the call and the row to
  `10_system.js`. An empty result hides the row.

`scripts/install-overlay.sh` copies `files/` to `<tree>/files/`, which the buildroot copies
over the root filesystem of every image.

## honk

honk (daeuniverse) needs Linux 6.12+, raw BTF (`/sys/kernel/btf/vmlinux`), cgroup v2 +
`CGROUP_BPF`, `NET_CLS_ACT`/`NET_XGRESS`, netns, and nftables NFQUEUE. netkit is optional.

The daeuniverse feed's prebuilt honk targets the 25.12 SDK and may not install on a master
snapshot (libstdc++ / apk ABI, `vmlinux-btf`). This build therefore compiles honk itself
from the daeuniverse source feed (`src-git daeuniverse
https://github.com/daeuniverse/openwrt-packages.git;main`) against this tree:

- `honk`, `luci-app-honk` and `vmlinux-btf-builtin` are `=m`: they become `.apk` files in
  the `r5s-honk-apks-*` artifact and are **not** in the image. CI fails if any of them is
  `=y` or appears in the image manifest or rootfs.
- `prepare-feeds.sh` clones honk's sources (the tag the feed's Makefile names) into
  `feeds/daeuniverse/honk/src` and uninstalls the feed's `vmlinux-btf` (it needs a prebuilt
  blob); `vmlinux-btf-builtin` provides `vmlinux-btf` instead. CI installs the Rust
  toolchains honk pins and its pinned `bpf-linker`.
- Every kmod honk depends on (`kmod-veth kmod-sched-core kmod-sched-bpf kmod-nft-core
  kmod-nft-queue kmod-nfnetlink-queue kmod-nf-conntrack`) is built into the image, because
  official kmods do not match this kernel. `libstdcpp`, `v2ray-geoip` and `v2ray-geosite`
  are in the image too.
- The honk packages build with `IGNORE_ERRORS=m`: a honk build failure does not stop the
  firmware, but the "Verify honk packages" step then fails the run.

After flashing, copy the apks from the **same run's** artifact to the router and install
them:

```sh
apk add ./vmlinux-btf-builtin-*.apk ./honk-*.apk \
  ./luci-lib-daeuniverse-*.apk ./luci-app-honk-*.apk
# optional: ./luci-i18n-daeuniverse-zh-cn-*.apk
```

Each apk is signed with the key generated for that build (`CONFIG_SIGN_EACH_PACKAGE`), and
the image of the same run carries its public key in `/etc/apk/keys/`. Apks from another run
need `--allow-untrusted`, and their kmod dependencies only match if the kernel is identical.
Then configure `/etc/honk/config.dae` (or LuCI -> Services -> honk), set
`uci set honk.config.enabled=1 && uci commit honk` and start `/etc/init.d/honk`.

## Configuration

`r5s.config` is a diffconfig seed. `scripts/compose-config.sh` merges it with the CI-only
options (ccache, build logs). Later fragments win, one line per key. Then `make defconfig`
fills in the rest. `scripts/check-config.sh` enforces the spec twice:

1. After `make defconfig`: the required symbols and packages are `=y`, honk is exactly `=m`,
   no removed package is `=y`/`=m`, and (`--tree`) mosdns and honk are installed from the
   right feeds.
2. After the build: the kernel `.config` has every BPF/BTF/netkit/NFQUEUE option, `vmlinux`
   carries a `.BTF` section, the image manifest has the required packages and none of the
   removed or honk ones, and the rootfs has no `sysntpd` / `ntpd` / honk, has the chrony
   servers, sbwml's mosdns files and the GPU row files.

## CI

`.github/workflows/build.yml`, run manually (Actions -> Build R5S firmware -> Run workflow):

1. Frees runner disk space and builds on the larger of `/` and `/mnt`.
2. Installs the build dependencies, `dwarves`, and clang/LLVM for honk.
3. Clones ImmortalWrt at the chosen ref (default `master`) and installs the overlay.
4. Runs `scripts/prepare-feeds.sh` (feeds update/install, mosdns, vmlinux-btf, honk sources,
   `feeds.lock.txt`), installs honk's Rust toolchains, then runs the feed-patch tests and
   `apply-feed-patches.sh` (strict).
5. Configures and checks (see above), runs `make download`, then
   `make world IGNORE_ERRORS=m`. On failure it retries the failed package once with `V=s`.
6. Verifies the outputs and uploads the sysupgrade images, manifest, `*.buildinfo`,
   `sha256sums`, `profiles.json`, `diffconfig`, `feeds.lock.txt`, `build.log` and
   `build-info.txt`; the honk apks go to their own artifact. The full packages artifact is
   optional.

`dl/` and ccache are cached with `actions/cache` and saved even when the build fails.

## Local build

Linux x86_64, about 60 GB free, build dependencies as listed in the ImmortalWrt README,
plus rustup with the toolchains in `feeds/daeuniverse/honk/src/rust-toolchain.toml` and
`crates/honk-ebpf/rust-toolchain.toml` and `bpf-linker` (see the workflow) for honk.

```sh
git clone --depth 1 --branch master https://github.com/immortalwrt/immortalwrt.git immortalwrt
bash scripts/install-overlay.sh immortalwrt
bash scripts/prepare-feeds.sh immortalwrt --lock feeds.lock.txt
cd immortalwrt
FEED_PATCHES_STRICT=1 bash scripts/apply-feed-patches.sh
bash ../scripts/compose-config.sh .config ../r5s.config
make defconfig
bash ../scripts/check-config.sh --config .config --tree .
make download -j8
make -j"$(nproc)" world IGNORE_ERRORS=m
```

## Feed patches

See [`patches/feeds/README.md`](patches/feeds/README.md): the chrony servers and the GPU
row. Run `bash scripts/test-apply-feed-patches.sh` after changing the apply script.

## Sources

- ImmortalWrt master: `target/linux/rockchip/Makefile` (`KERNEL_PATCHVER:=6.18`),
  `target/linux/rockchip/image/armv8.mk`, `include/target.mk` (tweak packages),
  `config/Config-kernel.in`, `package/utils/busybox/`, `package/libs/openssl/Config.in`,
  `package/emortal/autocore`, `scripts/feeds`, `scripts/package-metadata.pl` (virtual
  provides)
- honk kernel requirements: <https://github.com/daeuniverse/honk/blob/main/doc/en/how-to-start.md>
- honk OpenWrt packages: <https://github.com/daeuniverse/openwrt-packages> (`honk/Makefile`,
  `honk/build.sh`, `vmlinux-btf-builtin/Makefile`, `.github/workflows/build-vmlinux-btf.yml`)
- mosdns feed: <https://github.com/sbwml/luci-app-mosdns/tree/v5>
- chrony patch: the XR1710G build's `patches/feeds/packages/net/chrony/100-cn-ntp-servers.patch`

## License

The overlay scripts are GPL-2.0-only, matching ImmortalWrt.
