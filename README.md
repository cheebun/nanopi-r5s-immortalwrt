# ImmortalWrt master for FriendlyElec NanoPi R5S

A custom [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) `master` build (Linux 6.18
on rockchip, from our fork's `base` branch, see [Source tree](#source-tree)) for the FriendlyElec NanoPi R5S (Rockchip RK3568, target
`rockchip/armv8`, profile `friendlyarm_nanopi-r5s`), built by GitHub Actions.

This repository is an **overlay**, not a fork. It holds only the device config, the extra
feeds, the feed patches, a few rootfs files and the tooling. CI checks out unmodified
ImmortalWrt and installs the overlay into it. The layout and the feed-patch mechanism follow
the Brightspeed XR1710G ImmortalWrt repository.

| Item | Value |
|------|-------|
| Source | [`cheebun/immortalwrt`](https://github.com/cheebun/immortalwrt) branch `base`, pinned to `d3a7aaedf7` |
| Kernel | Linux 6.18 (`KERNEL_PATCHVER:=6.18`; 6.18.64 at the pinned commit) |
| Target / profile | `rockchip/armv8` / `friendlyarm_nanopi-r5s` (device package: `kmod-r8125`) |
| Package arch | `aarch64_generic` |
| Images | `*-friendlyarm_nanopi-r5s-squashfs-sysupgrade.img.gz`, `*-ext4-sysupgrade.img.gz` |

## Source tree

CI builds [`cheebun/immortalwrt`](https://github.com/cheebun/immortalwrt), branch `base`:
ImmortalWrt `master` plus a merge of the newer OpenWrt 6.18 kernel (see `.github/FORK.md`
there). The workflow pins a commit, not the branch, so a build is reproducible: input
`immortalwrt_repo` defaults to `cheebun/immortalwrt` and `immortalwrt_ref` to
`d3a7aaedf7c0763584c9958d5dbee31380bc0d74`.

- **Bump:** set the `immortalwrt_ref` default in `.github/workflows/build.yml` to the new head
  of `base` (`gh api repos/cheebun/immortalwrt/commits/base --jq .sha`).
- **Upstream master instead:** run the workflow with `immortalwrt_repo: immortalwrt/immortalwrt`
  and `immortalwrt_ref: master` (any branch, tag or full 40-hex SHA works).

`scripts/fetch-immortalwrt.sh` validates both inputs, fetches exactly that one commit and, for
a SHA, checks that it got it; the commit and kernel version go to the job summary and
`build-info.txt`. Run `bash scripts/test-fetch-immortalwrt.sh` (offline) after changing it.

## master branch caveats

- **Snapshot, not a release.** master moves daily. The feeds in `feeds.conf.default` are not
  pinned, and neither is the mosdns feed (only the vantage theme feed is
  pinned, to its v1.2.0 commit). Every build records the exact commits of the
  main tree and every feed in `feeds.lock.txt` (also copied into
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
- The Vantage LuCI theme, its dashboard and its per-device traffic add-on (+ zh-cn), as the
  default theme, with Bootstrap as the fallback (see below).
- Kernel modules `kmod-veth`, `kmod-nft-queue`, `kmod-nfnetlink-queue`, `kmod-xdp-sockets-diag`.
- `mount-utils` (util-linux `mount`, `umount`, `findmnt`, ...).
- Kernel BTF debug info and netkit.
- OpenSSL with the built-in devcrypto engine (`kmod-cryptodev`).
- What honk needs at runtime (honk itself is not built, see [honk](#honk)): `kmod-sched-core`,
  `kmod-sched-bpf`, `kmod-nft-core`, `kmod-nf-conntrack`, `libstdcpp`, `flock`,
  `coreutils-timeout`, kprobes/BPF events, ftrace.
- The release "tweak" packages listed above.

**Removed**

- DDNS (`ddns-scripts*`, `luci-app-ddns`), DDNS-Go, Lucky, ZeroTier, WeChatPush, PushBot,
  vlmcsd: none of them is in the default image. They are pinned off so they cannot come
  back, and CI fails if any of them is selected (`=y` or `=m`).
- busybox `ntpd` and the `sysntpd` init script, which busybox installs only when its NTPD
  applet is enabled. `chrony-nts` is not selected.
- `luci-app-attendedsysupgrade` / `owut`: an attended sysupgrade would install a stock image.
- Argon (`luci-theme-argon`, `luci-app-argon-config`): replaced by Vantage. It is not in the
  master image anyway; CI fails if it is selected or in the image.

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
| honk: userspace deps | `PACKAGE_libstdcpp`, `flock`, `coreutils-timeout` | honk is installed separately; `flock` (util-linux) and `coreutils-timeout` are deps of `luci-lib-daeuniverse`. |
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

## LuCI theme: Vantage

[Vantage](https://github.com/anothaDev/luci-theme-vantage) (GPL-3.0-or-later) comes from its
own source feed, pinned to the v1.2.0 release commit in `feeds.conf.extra`
(`src-git vantage https://github.com/anothaDev/luci-theme-vantage.git^a7ff63b7...`).
`r5s.config` selects `luci-theme-vantage`, `luci-app-vantage` (dashboard),
`luci-app-vantage-traffic` (per-device traffic of hosts behind a shared port) and their zh-cn
translations (`luci-i18n-vantage-theme-zh-cn`, `luci-i18n-vantage-zh-cn`,
`luci-i18n-vantage-traffic-zh-cn`), plus `luci-theme-bootstrap` as the fallback.
`luci-app-vantage-aps` (access-point pairing over SSH) and Argon are not selected, and CI fails
if they are.

- `files/etc/uci-defaults/99-vantage` registers the theme (`luci.themes.Vantage`) and sets
  `luci.main.mediaurlbase=/luci-static/vantage` on the first boot of every new image, so a
  sysupgrade also switches back to Vantage. It then sets these appearance preferences in
  `/etc/config/vantage_theme`, each only when it is unset, so choices saved on the router are
  kept: `theme light`, `brand hostname`, `login grid`, `unfocused still`, `chart lanes`,
  `path full` and a `layout_wide_wired` dashboard layout.
- `files/usr/share/luci/menu.d/zz-landing-override.json` sets `admin/status` to `order 2`.
- `prepare-feeds.sh` and `check-config.sh --tree` check that the three packages are installed
  from the vantage feed. After the build `check-config.sh` checks the image for the theme's
  stylesheet, header template and `30_luci-theme-vantage`, for Bootstrap, for `99-vantage`
  and a valid menu override, and for the absence of Argon's files.

## honk

honk (daeuniverse) is **not built here**. Install it on the router from daeuniverse's
official releases: <https://github.com/daeuniverse/openwrt-packages/releases>.

The official builds target ImmortalWrt 25.12.x (kernel 6.12). This firmware is master
(kernel 6.18), so test-install honk before relying on it. Everything honk needs at runtime
is in the image, because official kmods do not match this kernel:

- Kernel: BTF built in (`/sys/kernel/btf/vmlinux`), BPF syscall/JIT, netkit, cgroup BPF,
  TCX, XDP sockets, kprobes/ftrace (see the mapping table above).
- Packages: `kmod-veth kmod-sched-core kmod-sched-bpf kmod-nft-core kmod-nft-queue
  kmod-nfnetlink-queue kmod-nf-conntrack libstdcpp v2ray-geoip v2ray-geosite`, plus `flock`
  and `coreutils-timeout` for `luci-lib-daeuniverse`, so the LuCI app installs offline.

The official honk package also depends on `vmlinux-btf`, which this image does not ship
(BTF is built into the kernel). Check how that dependency is met when test-installing.

`scripts/check-config.sh` keeps this list as `HONK_RUNTIME_REQUIRED` (and the kernel options
as `HONK_RUNTIME_KERNEL_Y`), and fails if any honk package (`honk`, `luci-app-honk`,
`luci-lib-daeuniverse`, `vmlinux-btf`, `vmlinux-btf-builtin`) is selected or in the image,
if a `honk*.apk` was built, or if a `daeuniverse` feed exists. Run
`bash scripts/test-check-config.sh` (offline; CI runs it too) after changing the script.

## Configuration

`r5s.config` is a diffconfig seed. `scripts/compose-config.sh` merges it with the CI-only
options (ccache, build logs). Later fragments win, one line per key. Then `make defconfig`
fills in the rest. `scripts/check-config.sh` enforces the spec twice:

1. After `make defconfig`: the required symbols and packages (including honk's runtime deps)
   are `=y`, no removed or honk package is `=y`/`=m`, and (`--tree`) mosdns and Vantage are
   installed from the right feeds and there is no daeuniverse feed.
2. After the build: the kernel `.config` has every BPF/BTF/netkit/NFQUEUE option, `vmlinux`
   carries a `.BTF` section, no `honk*.apk` was built, the image manifest has the required
   packages and none of the removed or honk ones, and the rootfs has no `sysntpd` / `ntpd` /
   honk / Argon, has the chrony servers, sbwml's mosdns files, the GPU row files and the
   Vantage theme files.

## apk repositories

With `CONFIG_PER_FEED_REPO` (the default), base-files writes one line per feed to
`/etc/apk/repositories.d/distfeeds.list`, but the ImmortalWrt download server hosts only
`packages`, `luci`, `routing` and `telephony` (plus the target and `base` repositories);
`video`, `mosdns` and `vantage` are 404 and would break `apk update`.
`scripts/distfeeds-config.sh` prints `CONFIG_FEED_<name>=m` for every feed not in
`DISTFEEDS_HOSTED` (default `packages luci routing telephony`), which makes upstream write
that line commented out. CI merges it before `make defconfig` and checks that it survived.
After the build `scripts/check-distfeeds.sh` probes every line of the image's file: an
enabled repository answering 403/404/410 fails the run, a timeout or 5xx only warns, and a
commented-out repository that answers 200 warns (add it to `DISTFEEDS_HOSTED`). Run
`bash scripts/test-distfeeds.sh` (needs network) after changing either script.

## CI

`.github/workflows/build.yml`, run manually (Actions -> Build R5S firmware -> Run workflow).
It builds on the self-hosted runner by default (see below); choose `runner: github` for a
GitHub-hosted runner:

1. GitHub-hosted: frees runner disk space and builds on the larger of `/` and `/mnt`.
   Self-hosted: checks free disk and starts the build container.
2. Installs the build dependencies and `dwarves`.
3. Fetches ImmortalWrt at the chosen repo and ref (default: the pinned `base` commit of our
   fork, see [Source tree](#source-tree)) and installs the overlay.
4. Runs `scripts/prepare-feeds.sh` (feeds update/install, mosdns, vantage,
   `feeds.lock.txt`), then runs the feed-patch tests and `apply-feed-patches.sh` (strict).
5. Configures and checks (see above, and the apk repositories), runs `make download`, then
   `make world`. On failure it retries the failed package once with `V=s`.
6. Verifies the outputs (including `check-distfeeds.sh`) and uploads the sysupgrade images, manifest, `*.buildinfo`,
   `sha256sums`, `profiles.json`, `diffconfig`, `feeds.lock.txt`, `build.log` and
   `build-info.txt`. The full packages artifact is optional.

On GitHub-hosted runners `dl/` and ccache are cached with `actions/cache/restore` and `actions/cache/save`. ccache is
saved even when the build fails; `dl/` (key prefix `dl-v2-`) is saved only when "Build
firmware" succeeded. After `make download`, `scripts/clean-dl.sh` deletes truncated
downloads (under 1 KiB) from the top level of `dl/` only: `dl/go-mod-cache` holds small Go
sources, and deleting them broke mosdns while Go still saw the modules as present. The
`dl-v2-` prefix keeps caches saved with that damage from being restored. Run
`bash scripts/test-dl-cleanup.sh` (offline; CI runs it too) after changing the script.

## Self-hosted runner

The build job runs on a self-hosted Linux x86_64 runner with the labels
`self-hosted, Linux, X64, r5s-builder`, unless the run is started with `runner: github`
(use that when the self-hosted machine is off; the job otherwise waits in the queue).

- Who can run it: the workflow has only the `workflow_dispatch` trigger, and the job runs
  only in this repository and only when the repository owner both started it and (for
  re-runs) re-triggered it. Do not add `pull_request` or `pull_request_target` triggers to a
  job that can land on the self-hosted runner. Permissions are `contents: read`.
- Container: the runner checks out the overlay and runs the actions (checkout, artifacts) on
  the host. Every other step runs through `scripts/ci-shell.sh`, which `docker exec`s it in
  a throwaway `ubuntu:24.04` container as the runner's own uid (packages are installed as
  root inside the container only). The container mounts the runner's work directory and the
  cache directory at their host paths, has no Docker socket, and is removed at the end of the
  job, also after a failure or a cancel.
- Caches: `dl/` and ccache live in a persistent directory on the runner machine
  (`/srv/openwrt-cache/r5s` by default, override with the repository variable
  `R5S_CACHE_DIR`), with subdirectories `dl` and `ccache` owned by the runner user. Create
  them once as root: `install -d -o <runner-user> -g <runner-user> <dir>/dl <dir>/ccache`.
  `scripts/clean-dl.sh` still runs on the persistent `dl/`. The GitHub Actions caches are not
  used on the self-hosted runner.
- Disk: each run clones ImmortalWrt fresh, needs at least 60 GB free (checked at the start)
  and deletes the tree at the end.
- Machine requirements: Docker usable by the runner user, network access to GitHub, the
  ImmortalWrt download servers and the Ubuntu archive.

## Local build

Linux x86_64, about 60 GB free, build dependencies as listed in the ImmortalWrt README.

```sh
bash scripts/fetch-immortalwrt.sh cheebun/immortalwrt d3a7aaedf7c0763584c9958d5dbee31380bc0d74 immortalwrt
bash scripts/install-overlay.sh immortalwrt
bash scripts/prepare-feeds.sh immortalwrt --lock feeds.lock.txt
cd immortalwrt
FEED_PATCHES_STRICT=1 bash scripts/apply-feed-patches.sh
bash ../scripts/distfeeds-config.sh . > distfeeds.config
bash ../scripts/compose-config.sh .config ../r5s.config distfeeds.config
make defconfig
bash ../scripts/check-config.sh --config .config --tree .
make download -j8
make -j"$(nproc)" world
```

## Feed patches

See [`patches/feeds/README.md`](patches/feeds/README.md): the chrony servers and the GPU
row. Run `bash scripts/test-apply-feed-patches.sh` after changing the apply script.

## Sources

- ImmortalWrt master (via the fork's `base` branch): `target/linux/rockchip/Makefile` (`KERNEL_PATCHVER:=6.18`),
  `target/linux/rockchip/image/armv8.mk`, `include/target.mk` (tweak packages),
  `config/Config-kernel.in`, `package/utils/busybox/`, `package/libs/openssl/Config.in`,
  `package/emortal/autocore`, `scripts/feeds`, `scripts/package-metadata.pl` (virtual
  provides)
- honk kernel requirements: <https://github.com/daeuniverse/honk/blob/main/doc/en/how-to-start.md>
- honk OpenWrt packages: <https://github.com/daeuniverse/openwrt-packages> (`honk/Makefile`,
  `luci-lib-daeuniverse/Makefile` for the package deps; releases for the install)
- mosdns feed: <https://github.com/sbwml/luci-app-mosdns/tree/v5>
- Vantage feed: <https://github.com/anothaDev/luci-theme-vantage> (v1.2.0,
  `a7ff63b715bca51effb5ab2d488dfff6cff1b16a`)
- chrony patch: the XR1710G build's `patches/feeds/packages/net/chrony/100-cn-ntp-servers.patch`

## License

The overlay scripts are GPL-2.0-only, matching ImmortalWrt.
