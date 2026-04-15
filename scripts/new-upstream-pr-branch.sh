#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: scripts/new-upstream-pr-branch.sh <name>

Creates `contrib/<name>` from fast-forwarded `upstream/main`, pushes to origin,
and sets upstream tracking.
EOF
}

if (($# != 1)); then
	usage >&2
	exit 2
fi

name="$1"
if [[ -z "$name" ]]; then
	echo "[new-upstream-pr-branch] ERROR: name cannot be empty" >&2
	exit 2
fi

git fetch upstream --prune
git checkout main
git merge --ff-only upstream/main
git checkout -b "contrib/$name"

# Push the new upstream-facing branch and set upstream tracking.
git push -u origin "contrib/$name"

echo "Created contrib/$name from upstream/main and pushed to origin (tracking set)"
echo "Keep fork-only files out of this branch: Dockerfile.custom, docker-compose.yml, FORK-MAPPING.md, scripts/*.ps1"
