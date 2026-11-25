#!/usr/bin/env bash
#
# Print the config fragment that comments out, in the image's apk
# repositories, every feed the ImmortalWrt download server does not host.
#
# Usage: bash scripts/distfeeds-config.sh <immortalwrt-tree> > distfeeds.config
#
# With CONFIG_PER_FEED_REPO (the default), include/feeds.mk
# (FeedSourcesAppendAPK, called by package/base-files) writes one line per
# feed to /etc/apk/repositories.d/distfeeds.list. The server hosts only some
# of them (video from feeds.conf.default and the feeds.conf.extra feeds are
# 404), and `apk update` then fails on the router. `CONFIG_FEED_<name>=m`
# makes upstream write that feed's line commented out, so no source patch is
# needed. The target ("core") and base lines are always written.
#
#   DISTFEEDS_HOSTED  Space-separated feeds that stay enabled
#                     (default: "packages luci routing telephony").
#
# Every other feed listed by `./scripts/feeds list -n` in the tree gets one
# `CONFIG_FEED_<name>=m` line. Feed names must match ^[A-Za-z0-9_]+$.

set -Eeuo pipefail

die() {
	echo "distfeeds-config: $*" >&2
	exit 1
}

[[ $# -eq 1 ]] || die "usage: $0 <immortalwrt-tree>"
tree="$1"
[[ -d "$tree" ]] || die "not a directory: $tree"
[[ -x "$tree/scripts/feeds" ]] || die "$tree/scripts/feeds is missing or not executable"

name_re='^[A-Za-z0-9_]+$'
read -r -a hosted <<<"${DISTFEEDS_HOSTED-packages luci routing telephony}"
for feed in ${hosted[@]+"${hosted[@]}"}; do
	[[ "$feed" =~ $name_re ]] || die "invalid feed name in DISTFEEDS_HOSTED: '$feed'"
done

feeds="$(cd "$tree" && ./scripts/feeds list -n)" || die "'./scripts/feeds list -n' failed in $tree"
[[ -n "$feeds" ]] || die "'./scripts/feeds list -n' listed no feeds in $tree"

while IFS= read -r feed; do
	[[ "$feed" =~ $name_re ]] || die "invalid feed name: '$feed'"
	for h in ${hosted[@]+"${hosted[@]}"}; do
		[[ "$feed" == "$h" ]] && continue 2
	done
	echo "CONFIG_FEED_${feed}=m"
done <<<"$feeds"
