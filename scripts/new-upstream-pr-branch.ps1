param(
    [Parameter(Mandatory = $true)]
    [string]$Name
)

$ErrorActionPreference = 'Stop'

git fetch upstream --prune
git checkout main
git merge --ff-only upstream/main
git checkout -b "contrib/$Name"
 
# Push the new upstream-facing branch to the fork and set the upstream tracking branch
git push -u origin "contrib/$Name"

Write-Host "Created contrib/$Name from upstream/main and pushed to origin (tracking set)"
Write-Host "Keep fork-only files out of this branch: Dockerfile.custom, docker-compose.yml, FORK-MAPPING.md, scripts/*.ps1"