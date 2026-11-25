#!/usr/bin/env bash
#
# Update and install the feeds of an ImmortalWrt tree prepared by
# scripts/install-overlay.sh, resolve the package conflicts of the extra
# feeds, fetch honk's sources, and optionally write a feed lock file.
#
# Usage: bash scripts/prepare-feeds.sh <immortalwrt-tree> [--lock <file>]
#
#   --lock <file>  Write a feeds.conf with every git feed pinned to the commit
#                  that was checked out ("src-git <name> <url>^<commit>"),
#                  headed by comments with the main tree and honk commits.
#                  Copy it over <tree>/feeds.conf to rebuild the same feeds.
#
# Steps:
#
#   1. `./scripts/feeds update -a`.
#   2. mosdns: sbwml's feed (feeds.conf.extra) ships its own mosdns, which
#      luci-app-mosdns is written for (/etc/init.d/mosdns and /etc/config/mosdns
#      come from luci-app-mosdns, the bare binary from mosdns). The packages
#      feed also has net/mosdns, whose package installs a different
#      /etc/init.d/mosdns. `feeds install -a` takes the first feed that has a
#      package, and packages comes first, so feeds/packages/net/mosdns is
#      deleted and the packages index rebuilt (`update -i`) before installing.
#      This is the method sbwml's README gives for non-OpenWrt sources.
#   3. `./scripts/feeds install -a`.
#   4. daeuniverse: honk depends on vmlinux-btf, so step 3 installed the
#      feed's vmlinux-btf, which needs a prebuilt BTF blob and cannot build
#      here. It is uninstalled; with it gone, vmlinux-btf-builtin (which
#      provides vmlinux-btf) is the only provider and honk selects it. The dae
#      and luci-app-dae of this feed are shadowed by those of the packages and
#      luci feeds, which come first; none of them is selected.
#   5. honk's package Makefile builds from ./src next to it, which the feed does
#      not ship. Clone the upstream tag the Makefile names (HONK_GIT_TAG).
#   6. vantage (checked after step 4, with the mosdns and daeuniverse links):
#      the theme, the dashboard and the traffic add-on must be installed
#      from the vantage feed. No other feed ships them today;
#      should the luci feed ever add one, it would win (it comes first) and
#      this check fails instead of silently building another version.
#
# Idempotent: re-running updates the feeds again and repeats every step.

set -Eeuo pipefail

die() {
	echo "prepare-feeds: $*" >&2
	exit 1
}

tree=""
lock=""
while [[ $# -gt 0 ]]; do
	case "$1" in
	--lock) lock="${2:?--lock needs a file}"; shift 2 ;;
	-h | --help) sed -n '2,13p' "$0"; exit 0 ;;
	-*) die "unknown option: $1" ;;
	*) [[ -z "$tree" ]] || die "only one tree may be given"; tree="$1"; shift ;;
	esac
done
[[ -n "$tree" ]] || die "usage: $0 <immortalwrt-tree> [--lock <file>]"
[[ -x "$tree/scripts/feeds" ]] || die "$tree does not look like an ImmortalWrt tree"
[[ -f "$tree/feeds.conf" ]] || die "$tree/feeds.conf is missing; run scripts/install-overlay.sh first"
if [[ -n "$lock" ]]; then
	# Resolve before cd, so a relative path means relative to the caller.
	mkdir -p -- "$(dirname -- "$lock")"
	lock="$(cd "$(dirname -- "$lock")" && pwd)/$(basename -- "$lock")"
fi
cd "$tree"

# 1. Update.
./scripts/feeds update -a

# 2. mosdns from sbwml's feed only.
[[ -f feeds/mosdns/mosdns/Makefile ]] || die "feeds/mosdns/mosdns is missing (is the mosdns feed in feeds.conf?)"
[[ -f feeds/mosdns/luci-app-mosdns/Makefile ]] || die "feeds/mosdns/luci-app-mosdns is missing"
if [[ -e feeds/packages/net/mosdns ]]; then
	echo "prepare-feeds: deleting feeds/packages/net/mosdns (replaced by feeds/mosdns/mosdns)"
	rm -rf -- feeds/packages/net/mosdns
fi
./scripts/feeds update -i packages
# A link left by an earlier install from the packages feed would win.
if [[ -L package/feeds/packages/mosdns ]]; then
	rm -f -- package/feeds/packages/mosdns
fi

# 3. Install.
./scripts/feeds install -a

# 4. vmlinux-btf cannot build without a blob; vmlinux-btf-builtin replaces it.
./scripts/feeds uninstall vmlinux-btf

# Fail here, not hours later, if a package came from the wrong feed.
expect_link() {
	local link="package/feeds/$1/$2"
	[[ -L "$link" && -f "$link/Makefile" ]] || die "$2 is not installed from feed '$1' ($link)"
}
for pkg in mosdns luci-app-mosdns geo2txt; do expect_link mosdns "$pkg"; done
for pkg in honk luci-app-honk luci-lib-daeuniverse vmlinux-btf-builtin; do expect_link daeuniverse "$pkg"; done
for pkg in luci-theme-vantage luci-app-vantage luci-app-vantage-traffic; do expect_link vantage "$pkg"; done
[[ ! -e package/feeds/packages/mosdns ]] || die "mosdns from the packages feed is still installed"
for f in package/feeds/*/vmlinux-btf; do
	[[ ! -e "$f" ]] || die "vmlinux-btf is still installed ($f)"
done

# 5. honk sources, at the tag the feed's Makefile builds.
honk_dir=feeds/daeuniverse/honk
honk_tag="$(sed -n 's/^HONK_GIT_TAG:=.*,\([^,)]*\))$/\1/p' "$honk_dir/Makefile")"
[[ "$honk_tag" =~ ^v[0-9][0-9A-Za-z.+-]{0,63}$ ]] || die "cannot read HONK_GIT_TAG from $honk_dir/Makefile (got '$honk_tag')"
if [[ -d "$honk_dir/src/.git" ]] &&
	[[ "$(git -C "$honk_dir/src" describe --tags --exact-match 2>/dev/null || true)" == "$honk_tag" ]]; then
	echo "prepare-feeds: honk sources already at $honk_tag"
else
	rm -rf -- "$honk_dir/src"
	# honk's build script takes the version from GITHUB_REF (set by build.sh),
	# so a shallow clone of the tag is enough.
	git clone --quiet --depth 1 --branch "$honk_tag" https://github.com/daeuniverse/honk.git "$honk_dir/src"
fi
honk_sha="$(git -C "$honk_dir/src" rev-parse HEAD)"
echo "prepare-feeds: honk $honk_tag ($honk_sha)"

# Lock file.
if [[ -n "$lock" ]]; then
	{
		echo "# Feed lock for the NanoPi R5S build: a feeds.conf with every git feed"
		echo "# pinned to the commit used. Copy it to <tree>/feeds.conf after"
		echo "# scripts/install-overlay.sh to rebuild with the same feeds."
		# No bare "#" line: scripts/feeds rejects it as a syntax error.
		echo "# immortalwrt $(git remote get-url origin 2>/dev/null || echo unknown) $(git rev-parse HEAD) ($(git log -1 --format=%cs))"
		echo "# honk-src https://github.com/daeuniverse/honk.git $honk_tag $honk_sha"
		while read -r type name url _; do
			[[ "$type" == src-git || "$type" == src-git-full ]] || continue
			[[ -d "feeds/$name/.git" ]] || die "feed '$name' has no git checkout"
			sha="$(git -C "feeds/$name" rev-parse HEAD)"
			url="${url%%[;^]*}"
			echo "$type $name $url^$sha"
		done < <(grep -E '^[[:space:]]*src-' feeds.conf)
	} > "$lock"
	echo "prepare-feeds: wrote $lock"
	cat -- "$lock"
fi

echo "prepare-feeds: done"
