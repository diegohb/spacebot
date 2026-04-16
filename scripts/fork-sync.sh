#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: scripts/fork-sync.sh

Synchronize fork branches:
- Fast-forward `main` to `upstream/main` and push to `origin/main`
- Rebase `custom/main` onto `upstream/main` and force-push with lease
EOF
}

if (($# > 0)); then
	case "$1" in
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "[fork-sync] ERROR: unknown argument: $1" >&2
		usage >&2
		exit 2
		;;
	esac
fi

current_branch="$(git rev-parse --abbrev-ref HEAD)"
restore_branch=true

cleanup() {
	if [[ "$restore_branch" == true && "$(git rev-parse --abbrev-ref HEAD)" != "$current_branch" ]]; then
		git checkout "$current_branch" >/dev/null 2>&1 || true
	fi
}

trap cleanup EXIT

git fetch upstream --prune
git fetch origin --prune

# Fast-forward local main to upstream/main and publish to origin.
git checkout main
git merge --ff-only upstream/main
git push origin main

# Rebase custom/main onto upstream/main and publish with force-with-lease.
git checkout custom/main
git rebase upstream/main
git push --force-with-lease origin custom/main

git checkout "$current_branch"
restore_branch=false
