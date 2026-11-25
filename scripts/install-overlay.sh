#!/usr/bin/env bash
#
# Install this repository's overlay into a pristine ImmortalWrt checkout.
#
# Usage: bash scripts/install-overlay.sh <immortalwrt-tree>
#
# This repository is not a fork of ImmortalWrt. It carries only what differs
# from upstream: the device config (r5s.config), the feed patches under
# patches/feeds/, and the hook that applies them. This script copies the hook
# into the build tree so that, inside the tree, everything works exactly as in
# a fork (see include/feed-patches.mk):
#
#   <repo>/scripts/apply-feed-patches.sh -> <tree>/scripts/apply-feed-patches.sh
#   <repo>/include/feed-patches.mk       -> <tree>/include/feed-patches.mk
#   <repo>/patches/                      -> <tree>/patches/  (replaced wholesale)
#
# and adds `-include $(TOPDIR)/include/feed-patches.mk` right after the
# toplevel.mk include of the tree's top-level Makefile.
#
# Idempotent: re-running refreshes the copied files and never adds the include
# line twice. It refuses to touch a tree whose Makefile layout it does not
# recognise, rather than guessing where the hook belongs.

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

hook_line='  -include $(TOPDIR)/include/feed-patches.mk'
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
