<#
    fork-sync.ps1

    Purpose:
    - Fast-forward `main` to `upstream/main` and push the result to `origin/main` (default behavior).
    - Rebase `custom/main` onto `upstream/main` and push the rebased branch to `origin/custom/main` using
        `--force-with-lease` because rebase rewrites history.
    - Preserve and return to the originally active branch when finished.

    NOTE: This script performs a force push on `custom/main` after rebasing. This is intentional and
    required to keep fork-only branches aligned when their history is rewritten by rebase. The
    operation uses `--force-with-lease` to reduce risk of overwriting remote changes made by others.
#>

$ErrorActionPreference = 'Stop'

$currentBranch = git rev-parse --abbrev-ref HEAD

git fetch upstream --prune
git fetch origin --prune

# Fast-forward local main to upstream/main and publish to origin
git checkout main
git merge --ff-only upstream/main
git push origin main

# Rebase custom/main onto upstream/main and publish the rebased branch (force-with-lease)
git checkout custom/main
git rebase upstream/main
git push --force-with-lease origin custom/main

# Return to original branch
git checkout $currentBranch