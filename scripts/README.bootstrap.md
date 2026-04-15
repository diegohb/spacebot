# Bootstrap for Ubuntu WSL

This folder includes a convenience script to bootstrap a fresh Ubuntu WSL environment for Spacebot development.

- `bootstrap-spacebot-wsl.sh` — clones your fork into `~/dev/projects/spacebot` (by default), installs Nix (single-user), enables flakes, checks out `custom/main` when available, and configures the `upstream` remote. By default it only sets up tooling and the repo. Use `--test` to run `./scripts/preflight.sh` and `./scripts/gate-pr.sh` inside `nix develop` and exit with the result.

Usage (from WSL):

```bash
# If you have this repo available on the Windows side, run it directly from WSL:
bash /mnt/c/dev/projects/github/spacebot/scripts/bootstrap-spacebot-wsl.sh

# Or copy it into WSL and run:
cp /mnt/c/dev/projects/github/spacebot/scripts/bootstrap-spacebot-wsl.sh ~/bootstrap-spacebot-wsl.sh
chmod +x ~/bootstrap-spacebot-wsl.sh
~/bootstrap-spacebot-wsl.sh

# Run setup plus repo gate checks:
~/bootstrap-spacebot-wsl.sh --test
```

Options:

- `--repo REPO_URL` — clone a custom repository URL (default: https://github.com/diegohb/spacebot.git)
- `--dir CLONE_DIR` — clone target directory (default: `~/dev/projects/spacebot`)
- `--branch BRANCH` — preferred branch to check out after clone/fetch (default: `custom/main`)
- `--test` — run `./scripts/preflight.sh` and `./scripts/gate-pr.sh` inside `nix develop`
- `--fast` — when used with `--test`, pass `--fast` to `./scripts/gate-pr.sh` to skip slower checks during iteration

Notes:

- The script is intended to be run inside Ubuntu WSL. It will install Nix as a single-user install (`--no-daemon`).
- The script adds `upstream` as `https://github.com/spacedriveapp/spacebot.git` if that remote is missing so the fork workflow matches this repo's expected setup.
- The first run will download and build many inputs; expect it to take time and network/disk usage.
- If you prefer not to use Nix, you can instead install `rustup`, `cargo`, `protoc`, and system build deps manually inside WSL and then run the scripts directly.
