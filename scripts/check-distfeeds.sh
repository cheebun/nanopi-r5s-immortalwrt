#!/usr/bin/env bash
#
# Check that every apk repository an image enables is actually hosted.
#
# Usage: bash scripts/check-distfeeds.sh <rootfs>...
#
# Reads <rootfs>/etc/apk/repositories.d/distfeeds.list and probes each
# repository index with an HTTP HEAD request (redirects followed):
#
#   - Enabled lines: 200 is ok; 403/404/410 is an error (`apk update` would
#     fail on the router; add the feed's CONFIG_FEED_<name>=m via
#     scripts/distfeeds-config.sh). Anything else (timeout, 5xx, ...) is only
#     a warning, so a flaky server does not fail the build.
#   - Commented-out lines ("# https://..."): a 200 is a warning (the feed is
#     hosted, consider adding it to DISTFEEDS_HOSTED). Never an error.
#
# base-files expands %U, %A, ... at build time (VERSION_SED_SCRIPT); an
# enabled line that still carries a placeholder is an error.
# Exits 1 if any check failed, 2 on usage errors.

set -Eeuo pipefail

[[ $# -ge 1 ]] || { echo "usage: $0 <rootfs>..." >&2; exit 2; }

errors=0
err() {
	echo "::error::check-distfeeds: $*"
	errors=$((errors + 1))
}
warn() {
	echo "::warning::check-distfeeds: $*"
}

probe() {
	curl -sIL -o /dev/null -w '%{http_code}' --retry 3 --retry-delay 2 --max-time 20 -- "$1" || true
}

url_re='^https?://[^[:space:]]+$'

for rootfs in "$@"; do
	list="$rootfs/etc/apk/repositories.d/distfeeds.list"
	if [[ ! -f "$list" ]]; then
		err "$list is missing"
		continue
	fi
	echo "check-distfeeds: $list"
	enabled=0
	while IFS= read -r line || [[ -n "$line" ]]; do
		line="${line%$'\r'}"
		[[ -n "${line//[[:space:]]/}" ]] || continue
		if [[ "$line" == \#* ]]; then
			url="${line#\#}"
			url="${url#"${url%%[![:space:]]*}"}"
			url="${url%"${url##*[![:space:]]}"}"
			# Plain comments (the header) are skipped.
			[[ "$url" =~ $url_re ]] || continue
			if [[ "$url" == *%[A-Za-z]* ]]; then
				warn "disabled line has an unexpanded placeholder: $url"
				continue
			fi
			code="$(probe "$url")"
			if [[ "$code" == 200 ]]; then
				warn "hosted but disabled, consider adding to DISTFEEDS_HOSTED: $url"
			else
				echo "  disabled ($code): $url"
			fi
			continue
		fi
		url="$line"
		if [[ ! "$url" =~ $url_re ]]; then
			err "$list: enabled line is not an http(s) URL: $line"
			continue
		fi
		if [[ "$url" == *%[A-Za-z]* ]]; then
			err "$list: unexpanded placeholder (base-files did not run VERSION_SED_SCRIPT?): $url"
			continue
		fi
		enabled=$((enabled + 1))
		code="$(probe "$url")"
		case "$code" in
		200) echo "  ok (200): $url" ;;
		403 | 404 | 410) err "$list: repository not hosted (HTTP $code): $url" ;;
		*) warn "$list: could not verify (HTTP ${code:-none}): $url" ;;
		esac
	done < "$list"
	(( enabled > 0 )) || err "$list: no enabled repository"
done

if (( errors > 0 )); then
	echo "check-distfeeds: $errors error(s)" >&2
	exit 1
fi
echo "check-distfeeds: ok"
