#!/usr/bin/env bash
#
# Custom `shell:` for the run steps of .github/workflows/build.yml.
#
# Without a build container (GitHub-hosted runner, or before "Start build
# container") the step script runs on the runner exactly like `shell: bash`.
#
# Once BUILD_CONTAINER is set (self-hosted runner), the step script runs inside
# that container with `docker exec`, as the runner's own uid. The step's
# environment is passed by name only (`-e NAME`), so values such as
# multi-line strings survive and never appear on a command line. The runner's
# work directory is mounted at the same path in the container, so
# $GITHUB_WORKSPACE, $RUNNER_TEMP, $GITHUB_ENV, $GITHUB_OUTPUT and the step
# script itself resolve to the same files on both sides.
#
# Per-step switches (set them in the step's `env:`):
#   CI_SHELL_HOST=1   run on the runner even though a container is up
#   CI_SHELL_ROOT=1   run as root inside the container (package installs)
#
# Usage (workflow): shell: bash <workspace>/scripts/ci-shell.sh {0}

set -Eeuo pipefail

if [[ $# -ne 1 || -z "$1" ]]; then
	echo "usage: $0 <step-script>" >&2
	exit 2
fi
script="$1"

if [[ -z "${BUILD_CONTAINER:-}" || "${CI_SHELL_HOST:-}" == 1 ]]; then
	exec bash --noprofile --norc -eo pipefail "$script"
fi

# Host-specific variables stay on the host; the container sets its own PATH,
# HOME and locale.
args=()
while IFS= read -r name; do
	case "$name" in
	PATH | HOME | USER | LOGNAME | SHELL | HOSTNAME | PWD | OLDPWD | SHLVL | _ | \
		TMPDIR | TEMP | TMP | TERM | MAIL | LANG | LANGUAGE | LC_* | XDG_* | DBUS_* | \
		INVOCATION_ID | JOURNAL_STREAM | SYSTEMD_EXEC_PID | MANAGERPID | NOTIFY_SOCKET | \
		CI_SHELL_HOST | CI_SHELL_ROOT) continue ;;
	esac
	args+=(-e "$name")
done < <(compgen -e)

if [[ "${CI_SHELL_ROOT:-}" == 1 ]]; then
	args+=(-u 0)
fi

exec docker exec "${args[@]}" -w "$PWD" "$BUILD_CONTAINER" \
	bash --noprofile --norc -eo pipefail "$script"
