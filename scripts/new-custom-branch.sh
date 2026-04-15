#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: scripts/new-custom-branch.sh <name>

Creates `custom/<name>` from a rebased `custom/main`, pushes to origin,
and sets upstream tracking.
EOF
}

if (($# != 1)); then
	usage >&2
	exit 2
fi

name="$1"
if [[ -z "$name" ]]; then
	echo "[new-custom-branch] ERROR: name cannot be empty" >&2
	exit 2
fi

git fetch upstream --prune
git checkout custom/main
git rebase upstream/main
git checkout -b "custom/$name"

# Push the new fork-only branch and set upstream tracking.
git push -u origin "custom/$name"

echo "Created custom/$name from custom/main and pushed to origin (tracking set)"
echo "Use this branch for fork-only deployment, runtime, prompt, and org-specific changes."
