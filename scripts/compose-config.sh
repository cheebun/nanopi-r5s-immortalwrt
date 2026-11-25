#!/usr/bin/env bash
#
# Merge config fragments into one seed .config; later fragments win.
#
# Usage: bash scripts/compose-config.sh <output> <fragment>...
#
# Every key may appear in at most one line of the output: for each fragment,
# the lines already collected that set one of its keys (as `CONFIG_X=...` or
# `# CONFIG_X is not set`) are dropped before the fragment is appended. This is
# the same merge the xr1710g workflow does with its options heredoc, factored
# out so CI and local builds share it. Comments and blank lines are kept.
#
# The result is a seed for `make defconfig`, not a final config.

set -Eeuo pipefail

[[ $# -ge 2 ]] || { echo "usage: $0 <output> <fragment>..." >&2; exit 1; }

out="$1"
shift

for f in "$@"; do
	[[ -f "$f" ]] || { echo "compose-config: no such fragment: $f" >&2; exit 1; }
done

tmp="$(mktemp "${TMPDIR:-/tmp}/compose-config.XXXXXX")"
next="$(mktemp "${TMPDIR:-/tmp}/compose-config.XXXXXX")"
trap 'rm -f -- "$tmp" "$next"' EXIT
: > "$tmp"

for f in "$@"; do
	awk '
		function key(line,   k) {
			if (line ~ /^CONFIG_[A-Za-z0-9_.+-]+=/) {
				k = line; sub(/=.*/, "", k); return k
			}
			if (line ~ /^# CONFIG_[A-Za-z0-9_.+-]+ is not set$/) {
				k = line; sub(/^# /, "", k); sub(/ is not set$/, "", k); return k
			}
			return ""
		}
		NR == FNR { k = key($0); if (k != "") drop[k] = 1; next }
		{ k = key($0); if (k != "" && (k in drop)) next; print }
	' "$f" "$tmp" > "$next"
	cat "$f" >> "$next"
	mv -- "$next" "$tmp"
	next="$(mktemp "${TMPDIR:-/tmp}/compose-config.XXXXXX")"
done

mv -- "$tmp" "$out"
