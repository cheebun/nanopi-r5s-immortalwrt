#!/usr/bin/env bash
#
# Install this repository's overlay into a pristine ImmortalWrt checkout.
#
# Usage: bash scripts/install-overlay.sh <immortalwrt-tree>
#
# This repository is not a fork of ImmortalWrt. It carries only what differs
# from upstream: the device config (r5s.config), the extra feeds
# (feeds.conf.extra), the feed patches under patches/feeds/, the rootfs files
# under files/, and the hook that applies the patches. This script copies them
# into the build tree so that, inside the tree, everything works exactly as in
# a fork (see include/feed-patches.mk):
#
#   <repo>/scripts/apply-feed-patches.sh -> <tree>/scripts/apply-feed-patches.sh
#   <repo>/include/feed-patches.mk       -> <tree>/include/feed-patches.mk
#   <repo>/patches/                      -> <tree>/patches/  (replaced wholesale)
#   <repo>/files/                        -> <tree>/files/    (replaced wholesale)
#   <tree>/feeds.conf.default + <repo>/feeds.conf.extra -> <tree>/feeds.conf
#
# and adds `-include $(TOPDIR)/include/feed-patches.mk` right after the
# toplevel.mk include of the tree's top-level Makefile.
#
# <tree>/files/ is the buildroot's own rootfs overlay: package/Makefile and
# include/image.mk copy it over the staged root filesystem, after the
# packages, so these files end up in every image.
#
# Idempotent: re-running refreshes the copied files, rewrites feeds.conf and
# never adds the include line twice. It refuses to touch a tree whose Makefile
# layout it does not recognise, rather than guessing where the hook belongs.
# To rebuild with the exact feed commits of an earlier build, copy that build's
# feeds.lock.txt over <tree>/feeds.conf after running this script.

set -Eeuo pipefail

die() {
	echo "install-overlay: $*" >&2
	exit 1
}

[[ $# -eq 1 ]] || die "usage: $0 <immortalwrt-tree>"

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
tree="$1"

[[ -d "$tree" ]] || die "not a directory: $tree"
tree="$(cd "$tree" && pwd)"

[[ "$tree" != "$repo_root" ]] || die "the build tree must not be the overlay repository itself"
[[ -f "$tree/Makefile" && -f "$tree/include/toplevel.mk" && -x "$tree/scripts/feeds" ]] ||
	die "$tree does not look like an ImmortalWrt/OpenWrt source tree"

install -m 0644 "$repo_root/scripts/apply-feed-patches.sh" "$tree/scripts/apply-feed-patches.sh"
install -m 0644 "$repo_root/include/feed-patches.mk" "$tree/include/feed-patches.mk"

# Replace patches/ wholesale so a patch deleted from the overlay does not
# linger in the build tree from an earlier run.
rm -rf -- "$tree/patches"
mkdir -p -- "$tree/patches"
if [[ -d "$repo_root/patches" ]]; then
	cp -R -- "$repo_root/patches/." "$tree/patches/"
fi

# Same for files/: a file removed from the overlay must leave the image too.
rm -rf -- "$tree/files"
if [[ -d "$repo_root/files" ]]; then
	mkdir -p -- "$tree/files"
	cp -R -- "$repo_root/files/." "$tree/files/"
fi

# feeds.conf takes precedence over feeds.conf.default in scripts/feeds.
[[ -f "$tree/feeds.conf.default" ]] || die "$tree/feeds.conf.default is missing"
if [[ -f "$repo_root/feeds.conf.extra" ]]; then
	feeds_tmp="$(mktemp "$tree/feeds.conf.overlay.XXXXXX")"
	{
		cat -- "$tree/feeds.conf.default"
		echo
		echo "# --- added by nanopi-r5s-immortalwrt (feeds.conf.extra) ---"
		cat -- "$repo_root/feeds.conf.extra"
	} > "$feeds_tmp"
	# scripts/feeds strips comments with s/#.+$//, so a bare "#" line is a
	# syntax error there; catch it here with a clearer message.
	if grep -qE '^[[:space:]]*#[[:space:]]*$' "$feeds_tmp"; then
		rm -f -- "$feeds_tmp"
		die "feeds.conf would contain a bare '#' line, which scripts/feeds rejects"
	fi
	# A feed name defined twice would silently shadow one of the two.
	dup="$(awk '$1 ~ /^src-/ { print $2 }' "$feeds_tmp" | sort | uniq -d)"
	if [[ -n "$dup" ]]; then
		rm -f -- "$feeds_tmp"
		die "feed name(s) defined twice in feeds.conf: $dup"
	fi
	mv -- "$feeds_tmp" "$tree/feeds.conf"
	echo "install-overlay: wrote $tree/feeds.conf (feeds.conf.default + feeds.conf.extra)"
else
	cp -- "$tree/feeds.conf.default" "$tree/feeds.conf"
fi

# Literal make syntax, not shell expansions.
# shellcheck disable=SC2016
hook_line='  -include $(TOPDIR)/include/feed-patches.mk'
# shellcheck disable=SC2016
anchor='include $(TOPDIR)/include/toplevel.mk'

if grep -qF -- 'include/feed-patches.mk' "$tree/Makefile"; then
	echo "install-overlay: feed-patches hook already present in $tree/Makefile"
else
	anchors="$(grep -cF -- "$anchor" "$tree/Makefile" || true)"
	[[ "$anchors" == "1" ]] ||
		die "expected exactly one '$anchor' line in $tree/Makefile, found ${anchors:-0}; update this script"
	tmp="$(mktemp "$tree/Makefile.overlay.XXXXXX")"
	trap 'rm -f -- "$tmp"' EXIT
	awk -v anchor="$anchor" -v hook="$hook_line" '
		{ print }
		index($0, anchor) { print hook }
	' "$tree/Makefile" > "$tmp"
	grep -qF -- 'include/feed-patches.mk' "$tmp" || die "failed to insert the hook into $tree/Makefile"
	mv -- "$tmp" "$tree/Makefile"
	trap - EXIT
	echo "install-overlay: added feed-patches hook to $tree/Makefile"
fi

echo "install-overlay: overlay installed into $tree"
