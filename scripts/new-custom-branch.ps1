param(
    [Parameter(Mandatory = $true)]
    [string]$Name
)

$ErrorActionPreference = 'Stop'

git fetch upstream --prune
git checkout custom/main
git rebase upstream/main
git checkout -b "custom/$Name"

Write-Host "Created custom/$Name from custom/main"
Write-Host "Use this branch for fork-only deployment, runtime, prompt, and org-specific changes."