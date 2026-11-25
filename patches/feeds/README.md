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

There are no patches yet. This README is a file, not a feed directory, so the
apply script ignores it.

## Planned: GPU row on the status page

A future patch adds a GPU row (RK3568 Mali-G52: frequency and temperature) to
LuCI's Status -> Overview "System" block. It would go in:

```
patches/feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/NNN-gpu-row.patch
```

Things to check before writing it:

- The values come from sysfs (`/sys/class/devfreq/fde60000.gpu/cur_freq` and
  the `gpu-thermal` zone under `/sys/class/thermal/`). Confirm the node names on
  the running 25.12 kernel first.
- The browser cannot read sysfs. Expose the values through an rpcd ACL plus
  `fs.read`, or through a ucode RPC method. The CPU rows of the overview come
  from ImmortalWrt's `autocore` package, which lives in the main tree
  (`package/emortal/autocore`), not in a feed. Patches under `patches/feeds/`
  cannot touch it, so a change there needs its own mechanism (for example a
  file in a `files/` overlay).
