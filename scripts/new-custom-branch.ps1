param(
    [Parameter(Mandatory = $true)]
    [string]$Name
)

$ErrorActionPreference = 'Stop'

git fetch upstream --prune
git checkout custom/main
git rebase upstream/main
git checkout -b "custom/$Name"

# Push the new fork-only branch to origin and set upstream tracking (default behaviour)
git push -u origin "custom/$Name"

Write-Host "Created custom/$Name from custom/main and pushed to origin (tracking set)"
Write-Host "Use this branch for fork-only deployment, runtime, prompt, and org-specific changes."