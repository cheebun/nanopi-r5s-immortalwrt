#!/usr/bin/env bash
#
# Shallow-fetch one ImmortalWrt commit into a new directory.
#
# <repo> is a GitHub "owner/name". <ref> is either a full 40-hex commit SHA or a
# branch/tag name. Both are validated before anything touches the network.
# `git fetch <ref>` works for both kinds (GitHub serves reachable commits by
# SHA), so the tree is always a detached checkout of exactly one commit. For a
# SHA ref the resulting HEAD must equal it.
#
# Prints the resolved commit and, when GITHUB_ENV is set, exports
# IMMORTALWRT_SHA there.
#
# Usage: fetch-immortalwrt.sh [--dry-run] <repo> <ref> <dir>
#   --dry-run  validate the arguments and print the plan, no network or disk

set -Eeuo pipefail

die() {
	echo "::error::$*" >&2
	exit 1
}

dry_run=0
if [[ "${1:-}" == --dry-run ]]; then
	dry_run=1
	shift
fi
if [[ $# -ne 3 ]]; then
	echo "usage: $0 [--dry-run] <owner/repo> <sha|branch|tag> <dir>" >&2
	exit 2
fi
repo="$1"
ref="$2"
dir="$3"

# owner/name, no "..", no leading dot or dash in either part.
if [[ ! "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] ||
	[[ "$repo" == *..* || "$repo" == [.-]* || "$repo" == */[.-]* ]]; then
	die "invalid immortalwrt_repo '$repo' (expected owner/name)"
fi

is_sha=0
if [[ "$ref" =~ ^[0-9a-f]{40}$ ]]; then
	is_sha=1
elif [[ ! "$ref" =~ ^[A-Za-z0-9._/-]+$ ]] ||
	[[ "$ref" == [-./]* || "$ref" == */ || "$ref" == *//* || "$ref" == *..* ||
		"$ref" == *.lock || "$ref" == */.* || "$ref" == *. || ${#ref} -gt 200 ]]; then
	# The git-check-ref-format rules that the character class leaves open,
	# plus no leading "-" so the ref can never be read as an option.
	die "invalid immortalwrt_ref '$ref' (expected a 40-hex commit SHA or a branch/tag name)"
fi

[[ -n "$dir" ]] || die "empty target directory"
url="https://github.com/$repo.git"
kind=$([[ "$is_sha" == 1 ]] && echo commit || echo branch/tag)
echo "ImmortalWrt source: $url, $kind $ref -> $dir"
if [[ "$dry_run" == 1 ]]; then
	exit 0
fi

if [[ -e "$dir" ]] && [[ -n "$(ls -A -- "$dir" 2>/dev/null)" ]]; then
	die "$dir already exists and is not empty"
fi
mkdir -p -- "$dir"
git -C "$dir" init -q
git -C "$dir" remote add origin "$url"

ok=0
for attempt in 1 2 3; do
	if git -C "$dir" fetch --depth 1 --no-tags origin "$ref"; then
		ok=1
		break
	fi
	echo "::warning::fetch of $ref from $url failed (attempt $attempt/3)"
	if [[ "$attempt" -lt 3 ]]; then
		sleep $((attempt * 15))
	fi
done
[[ "$ok" == 1 ]] || die "could not fetch $ref from $url"

git -C "$dir" -c advice.detachedHead=false checkout -q --detach FETCH_HEAD
head=$(git -C "$dir" rev-parse HEAD)
if [[ "$is_sha" == 1 && "$head" != "$ref" ]]; then
	die "fetched $head, expected $ref"
fi
git -C "$dir" log -1 --format='ImmortalWrt %H (%cs) %s'
if [[ -n "${GITHUB_ENV:-}" ]]; then
	echo "IMMORTALWRT_SHA=$head" >> "$GITHUB_ENV"
fi
