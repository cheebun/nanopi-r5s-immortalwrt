#!/usr/bin/env bash
#
# Remove truncated downloads (files under 1 KiB) from the top level of an
# OpenWrt dl/ directory.
#
# Only the top level is scanned: subdirectories such as dl/go-mod-cache hold
# extracted Go module sources, many of them legitimately small, and Go does
# not re-download a module whose directory exists. Deleting them breaks Go
# packages (mosdns) with "build constraints exclude all Go files".
#
# A missing or empty dl directory is not an error.
#
# Usage: bash scripts/clean-dl.sh <dl-dir>

set -Eeuo pipefail

if [[ $# -ne 1 || -z "$1" ]]; then
	echo "usage: $0 <dl-dir>" >&2
	exit 2
fi
dl="$1"

if [[ ! -e "$dl" ]]; then
	echo "$dl does not exist; nothing to clean"
	exit 0
fi
if [[ ! -d "$dl" ]]; then
	echo "error: $dl is not a directory" >&2
	exit 1
fi

find "$dl" -maxdepth 1 -type f -size -1024c -print -delete
