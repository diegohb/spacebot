param(
    [switch]$RebaseCustom,
    [switch]$PushForkMain
)

$ErrorActionPreference = 'Stop'

$currentBranch = git rev-parse --abbrev-ref HEAD

git fetch upstream --prune
git fetch origin --prune

git checkout main
git merge --ff-only upstream/main

if ($PushForkMain) {
    git push origin main
}

if ($RebaseCustom) {
    git checkout custom/main
    git rebase upstream/main
}

git checkout $currentBranch