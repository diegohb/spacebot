#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage:
	./scripts/spacebot-docker.sh custom-up [--mode local|remote-base] [--vault-path /path|C:/path]
  ./scripts/spacebot-docker.sh custom-down
  ./scripts/spacebot-docker.sh upstream-up
  ./scripts/spacebot-docker.sh upstream-down
	./scripts/spacebot-docker.sh both-up [--mode local|remote-base] [--vault-path /path|C:/path]
  ./scripts/spacebot-docker.sh both-down
  ./scripts/spacebot-docker.sh status

Modes:
  local        Build deven-spacebot from ./Dockerfile using local repo source.
  remote-base  Build deven-spacebot from ./Dockerfile.custom using ghcr.io/spacedriveapp/spacebot:latest as the app base.

Ports:
  deven-spacebot    http://localhost:19898
  upstream-spacebot http://localhost:29898

Host Path:
  EMAKBAI_HOST_PATH controls host bind mounts for the EMAKBAI vault.
  Default on Bash/WSL: /mnt/c/dev/projects/pscm-dscloud/EMAKBAI
EOF
}

command="help"
mode="local"
vault_host_path="${EMAKBAI_HOST_PATH:-/mnt/c/dev/projects/pscm-dscloud/EMAKBAI}"

resolve_vault_host_path() {
	local input_path="$1"

	# On WSL/Linux shells, normalize Windows drive paths if provided.
	if [[ "$input_path" =~ ^[A-Za-z]:[\\/] ]] && command -v wslpath >/dev/null 2>&1; then
		wslpath -u "$input_path"
		return
	fi

	echo "$input_path"
}

if (($# > 0)); then
	command="$1"
	shift
fi

while (($# > 0)); do
	case "$1" in
	--mode | -m)
		if (($# < 2)); then
			echo "[spacebot-docker] ERROR: missing value for $1" >&2
			exit 2
		fi
		mode="$2"
		shift 2
		;;
	--vault-path | -v)
		if (($# < 2)); then
			echo "[spacebot-docker] ERROR: missing value for $1" >&2
			exit 2
		fi
		vault_host_path="$2"
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "[spacebot-docker] ERROR: unknown argument: $1" >&2
		usage >&2
		exit 2
		;;
	esac
done

case "$command" in
help | custom-up | custom-down | upstream-up | upstream-down | both-up | both-down | status)
	;;
*)
	echo "[spacebot-docker] ERROR: unknown command: $command" >&2
	usage >&2
	exit 2
	;;
esac

case "$mode" in
local | remote-base)
	;;
*)
	echo "[spacebot-docker] ERROR: mode must be 'local' or 'remote-base'" >&2
	exit 2
	;;
esac

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

vault_host_path="$(resolve_vault_host_path "$vault_host_path")"
export EMAKBAI_HOST_PATH="$vault_host_path"

docker_command() {
	local description="$1"
	shift
	echo "==> $description"
	docker "$@"
}

start_custom() {
	local dockerfile="Dockerfile"
	if [[ "$mode" == "remote-base" ]]; then
		dockerfile="Dockerfile.custom"
	fi

	docker_command "Building spacebot-custom:latest from $dockerfile" \
		build --pull -f "$dockerfile" -t spacebot-custom:latest .

	docker_command "Recreating deven-spacebot on http://localhost:19898" \
		compose up -d --force-recreate spacebot
}

stop_custom() {
	docker_command "Stopping deven-spacebot" compose down
}

start_upstream() {
	docker_command "Pulling latest upstream image" \
		compose -f docker-compose.upstream.yml pull spacebot-upstream

	docker_command "Recreating upstream-spacebot on http://localhost:29898" \
		compose -f docker-compose.upstream.yml up -d --force-recreate spacebot-upstream
}

stop_upstream() {
	docker_command "Stopping upstream-spacebot" \
		compose -f docker-compose.upstream.yml down
}

show_status() {
	echo "==> Container status"
	echo "==> EMAKBAI_HOST_PATH=$EMAKBAI_HOST_PATH"
	docker ps -a --format '{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' \
		| grep -E '^(deven-spacebot|upstream-spacebot)[[:space:]]' || true
}

case "$command" in
custom-up)
	start_custom
	;;
custom-down)
	stop_custom
	;;
upstream-up)
	start_upstream
	;;
upstream-down)
	stop_upstream
	;;
both-up)
	start_custom
	start_upstream
	;;
both-down)
	stop_upstream
	stop_custom
	;;
status)
	show_status
	;;
*)
	usage
	;;
esac
