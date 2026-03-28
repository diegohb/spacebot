# Fork Mapping

This fork is intentionally split into three lanes so upstream contributions and local divergence do not get mixed.

## Remote Mapping

- `origin` -> `https://github.com/diegohb/spacebot.git`
- `upstream` -> `https://github.com/spacedriveapp/spacebot.git`

## Branch Roles

- `main`
  - Tracks `upstream/main`
  - Keep this branch upstream-clean
  - Use it as the local staging branch for upstream contribution work
- `contrib/<topic>`
  - Short-lived branches for upstream PRs
  - Branch from `upstream/main` or local `main` after syncing
  - Never include fork-only deployment files or org-specific prompts/config
- `custom/main`
  - Long-lived branch for fork-only divergence
  - Rebase this branch onto `upstream/main` as upstream evolves
- `custom/<topic>`
  - Short-lived branches for new fork-only work
  - Branch from `custom/main`

## Fork-Only Files

These files are intentionally fork-local and should stay out of upstream PRs unless the upstream project explicitly asks for them.

- `Dockerfile.custom`
- `docker-compose.yml`
- `FORK-MAPPING.md`
- `scripts/fork-sync.ps1`
- `scripts/new-upstream-pr-branch.ps1`
- `scripts/new-custom-branch.ps1`

## Contribution Routing

| Change type | Branch | PR target | Notes |
| --- | --- | --- | --- |
| Bug fix or feature that upstream should own | `contrib/<topic>` | `upstream:main` | Keep diff free of fork-only files |
| Local deployment, secret paths, vault mounts, org-specific prompts, local tooling | `custom/<topic>` or `custom/main` | Fork only | Rebase onto upstream regularly |
| Mixed request | Split into two branches | Upstream + fork | Do not carry local overlays into upstream PRs |

## Daily Workflow

### Sync upstream baseline

```powershell
./scripts/fork-sync.ps1
```

### Start an upstream PR branch

```powershell
./scripts/new-upstream-pr-branch.ps1 -Name short-topic
```

### Start a fork-only customization branch

```powershell
./scripts/new-custom-branch.ps1 -Name short-topic
```

## Guardrails

- Run `just preflight` and `just gate-pr` before pushing upstream PR updates.
- Before opening an upstream PR, verify that fork-only files are absent from the diff:

```powershell
git diff --name-only upstream/main...HEAD
```

- If a task touches both upstream-safe code and fork-only deployment overlays, split the work instead of mixing it.
- Rebase `custom/main` onto `upstream/main` regularly so the fork does not drift unnecessarily.