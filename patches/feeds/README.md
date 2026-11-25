# Feed patches

Patches here are applied to the feed checkouts (`feeds/<feed>/`) of the
ImmortalWrt build tree by `scripts/apply-feed-patches.sh`, which
`scripts/install-overlay.sh` copies into the tree and `include/feed-patches.mk`
hooks onto `prepare-tmpinfo`.

Layout: `patches/feeds/<feed>/<path inside the feed>/NNN-name.patch`. The
directory only mirrors the patched file for filing; the target paths inside the
patch are relative to the feed repository root. Patches of one feed are applied
in sorted order on top of that feed's `HEAD`. A patch that no longer applies
fails the build. Rebase it then; do not skip it.

This build follows ImmortalWrt `master`, whose feeds are not pinned, so a patch
can stop applying whenever upstream touches the file. The commits a build used
are in its `feeds.lock.txt`.

This README is a file, not a feed directory, so the apply script ignores it.

## Patches

| Patch | Feed file | What it does |
|-------|-----------|--------------|
| `packages/net/chrony/100-cn-ntp-servers.patch` | `net/chrony/files/chrony.config` | Replaces the `2.openwrt.pool.ntp.org` pool with four servers, each `iburst 1`: `ntp.tencent.com`, `ntp1.aliyun.com`, `ntp.ntsc.ac.cn`, `cn.ntp.org.cn`. No NTS. Copied unchanged from the XR1710G build. |
| `luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/100-gpu-row.patch` | `modules/luci-mod-status/.../include/10_system.js` | Adds an rpc call to `luci.gpuinfo` / `getGPUInfo` and a "GPU" row right after "Architecture". An empty result hides the row. |

Both were checked against a fresh clone of the feed's `master`
(packages `7a34fbb`, luci `6839c87`, 2026-11-24): each applies with
`git apply --check`, and `apply-feed-patches.sh` (strict) applies them and is a
no-op on a second run.

The GPU row also needs files that are not in any feed: `/sbin/gpuinfo`, the
rpcd ucode plugin `/usr/share/rpcd/ucode/gpuinfo` and its ACL. They live in
the repository's `files/` overlay (see the main README), not here.
`check-config.sh` checks the built rootfs for both halves.

## Rebasing a patch

From the repository root, with the build tree in `immortalwrt/` (as in the
local build steps):

```sh
git -C immortalwrt/feeds/<feed> checkout -- <file>     # back to the feed's HEAD
# edit immortalwrt/feeds/<feed>/<file>
git -C immortalwrt/feeds/<feed> diff -- <file> > patches/feeds/<feed>/<dir>/NNN-name.patch
git -C immortalwrt/feeds/<feed> checkout -- <file>
bash scripts/install-overlay.sh immortalwrt              # copies patches/ into the tree
(cd immortalwrt && FEED_PATCHES_STRICT=1 bash scripts/apply-feed-patches.sh)
```

Keep the `a/` / `b/` paths relative to the feed root, as `git diff` writes them.
