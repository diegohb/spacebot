#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bootstrap-spacebot-wsl.sh [--repo REPO_URL] [--dir CLONE_DIR] [--branch BRANCH] [--test] [--fast]

This script prepares an Ubuntu WSL environment for Spacebot development:
- installs minimal prerequisites
- installs Nix (single-user, --no-daemon)
- enables flakes
- clones the repo into the WSL filesystem (default: ~/dev/projects/spacebot)
- checks out the preferred branch when available (default: custom/main)
- configures the `upstream` remote if missing
- optionally runs the repo preflight and PR gate checks inside `nix develop`

Example:
  ./bootstrap-spacebot-wsl.sh
  ./bootstrap-spacebot-wsl.sh --test

Notes:
- Run this inside your Ubuntu WSL shell. The script is idempotent where practical.
- First runs may download/build many packages and take considerable time.
EOF
}

REPO_URL="https://github.com/diegohb/spacebot.git"
UPSTREAM_URL="https://github.com/spacedriveapp/spacebot.git"
CLONE_DIR="${HOME}/dev/projects/spacebot"
BRANCH="custom/main"
RUN_TESTS=false
FAST_MODE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO_URL="$2"; shift 2;;
    --dir)
      CLONE_DIR="$2"; shift 2;;
    --branch)
      BRANCH="$2"; shift 2;;
    --test)
      RUN_TESTS=true; shift;;
    --fast)
      FAST_MODE=true; shift;;
    -h|--help)
      usage; exit 0;;
    *)
      echo "Unknown argument: $1" >&2; usage; exit 2;;
  esac
done

log() { echo "[bootstrap] $*"; }
fail() { echo "[bootstrap] ERROR: $*" >&2; exit 1; }

if [[ "$(uname -s)" != "Linux" ]]; then
  fail "This script must be run inside WSL/Ubuntu (Linux)."
fi

log "target repo: $REPO_URL"
log "clone dir: $CLONE_DIR"
log "preferred branch: $BRANCH"
log "run tests: $RUN_TESTS"
log "fast mode: $FAST_MODE"

# 1) Minimal apt prerequisites (curl/git/xz-utils)
if ! command -v curl >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1 || ! command -v xz >/dev/null 2>&1; then
  log "installing apt prerequisites (curl git ca-certificates xz-utils)..."
  sudo apt-get update -y
  sudo apt-get install -y curl git ca-certificates xz-utils
else
  log "apt prerequisites present"
fi

# 2) Clone repo if needed
mkdir -p "$(dirname "$CLONE_DIR")"
if [[ -d "$CLONE_DIR/.git" ]]; then
  log "repo already exists at $CLONE_DIR; fetching updates"
  git -C "$CLONE_DIR" fetch --all --prune
else
  log "cloning $REPO_URL -> $CLONE_DIR"
  git clone --recurse-submodules "$REPO_URL" "$CLONE_DIR"
fi

cd "$CLONE_DIR"

# 2a) Prefer the configured branch when it exists on origin.
if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  if [[ "$(git branch --show-current)" != "$BRANCH" ]]; then
    log "checking out existing local branch: $BRANCH"
    git checkout "$BRANCH"
  else
    log "already on local branch: $BRANCH"
  fi
elif git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
  log "creating local branch from origin/$BRANCH"
  git checkout -b "$BRANCH" --track "origin/$BRANCH"
else
  log "preferred branch not found on origin: $BRANCH (leaving current branch unchanged)"
fi

# 2b) Ensure upstream remote matches the upstream Spacebot repository
if git remote get-url upstream >/dev/null 2>&1; then
  log "upstream remote already configured: $(git remote get-url upstream)"
else
  log "adding upstream remote: $UPSTREAM_URL"
  git remote add upstream "$UPSTREAM_URL"
fi

# 3) Install Nix (single-user) if not present
if ! command -v nix >/dev/null 2>&1; then
  log "installing Nix (single-user, --no-daemon)"
  # Use the official installer (single-user). This is standard for WSL.
  curl -L https://nixos.org/nix/install | sh -s -- --no-daemon

  # Source nix profile in current shell if available
  if [[ -f "$HOME/.nix-profile/etc/profile.d/nix.sh" ]]; then
    # shellcheck disable=SC1090
    . "$HOME/.nix-profile/etc/profile.d/nix.sh"
  elif [[ -f "/etc/profile.d/nix.sh" ]]; then
    # shellcheck disable=SC1091
    . /etc/profile.d/nix.sh
  fi
else
  log "nix already installed: $(nix --version 2>/dev/null || true)"
  # ensure nix profile loaded
  if [[ -f "$HOME/.nix-profile/etc/profile.d/nix.sh" ]]; then
    # shellcheck disable=SC1090
    . "$HOME/.nix-profile/etc/profile.d/nix.sh"
  fi
fi

# 4) Enable experimental features for flakes and nix-command in single-user config
mkdir -p "$HOME/.config/nix"
NIX_CONF="$HOME/.config/nix/nix.conf"
if ! grep -q 'experimental-features' "$NIX_CONF" 2>/dev/null; then
  echo 'experimental-features = nix-command flakes' >> "$NIX_CONF"
  log "enabled nix experimental features (nix-command flakes) in $NIX_CONF"
else
  log "nix experimental features already configured"
fi

# reload profile if needed
if [[ -f "$HOME/.nix-profile/etc/profile.d/nix.sh" ]]; then
  # shellcheck disable=SC1090
  . "$HOME/.nix-profile/etc/profile.d/nix.sh"
fi

log "nix available: $(command -v nix || true)"

# 5) Optionally run preflight and gate checks inside nix develop
if [[ ! -f "flake.nix" ]]; then
  fail "flake.nix not found in $CLONE_DIR — expected repository root with Nix flake"
fi

if [[ "$FAST_MODE" == "true" && "$RUN_TESTS" != "true" ]]; then
  log "ignoring --fast because --test was not requested"
fi

if [[ "$RUN_TESTS" == "true" ]]; then
  log "running preflight inside nix develop (this may take time on first run)"
  nix develop --command bash -lc './scripts/preflight.sh'

  log "running gate-pr inside nix develop"
  if [[ "$FAST_MODE" == "true" ]]; then
    nix develop --command bash -lc './scripts/gate-pr.sh --fast'
  else
    nix develop --command bash -lc './scripts/gate-pr.sh'
  fi

  log "bootstrap completed — tooling, clone, and tests finished successfully."
else
  log "bootstrap completed — tooling installed and repo cloned without running tests."
fi

log "To enter an interactive dev shell, run:"
echo
echo "  cd '$CLONE_DIR'"
echo "  nix develop"
echo
if [[ "$RUN_TESTS" == "true" ]]; then
  log "If any command above failed, capture the failing output and re-run after addressing the reported issue."
else
  log "To run repository gates later, use:"
  echo
  echo "  cd '$CLONE_DIR'"
  echo "  nix develop --command bash -lc './scripts/preflight.sh'"
  echo "  nix develop --command bash -lc './scripts/gate-pr.sh'"
  echo
fi
