<#
    spacebot-docker.ps1

    Helper commands for running Spacebot in two side-by-side modes:
    - deven-spacebot: custom image tag built from local source or Dockerfile.custom
    - upstream-spacebot: direct ghcr.io/spacedriveapp/spacebot:latest image

    Examples:
    - ./scripts/spacebot-docker.ps1 custom-up
    - ./scripts/spacebot-docker.ps1 custom-up -Mode remote-base
    - ./scripts/spacebot-docker.ps1 upstream-up
    - ./scripts/spacebot-docker.ps1 both-up
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('help', 'custom-up', 'custom-down', 'upstream-up', 'upstream-down', 'both-up', 'both-down', 'status')]
    [string]$Command = 'help',

    [Parameter()]
    [ValidateSet('local', 'remote-base')]
    [string]$Mode = 'local',

    [Parameter()]
    [string]$VaultPath = $(if ($env:EMAKBAI_HOST_PATH) { $env:EMAKBAI_HOST_PATH } else { 'C:/dev/projects/pscm-dscloud/EMAKBAI' })
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot

function Invoke-DockerCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Description,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    Write-Host "==> $Description" -ForegroundColor Cyan
    & docker @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed: docker $($Arguments -join ' ')"
    }
}

function Start-Custom {
    $dockerfile = if ($Mode -eq 'local') { 'Dockerfile' } else { 'Dockerfile.custom' }

    Invoke-DockerCommand -Description "Building spacebot-custom:latest from $dockerfile" -Arguments @(
        'build',
        '--pull',
        '-f', $dockerfile,
        '-t', 'spacebot-custom:latest',
        '.'
    )

    Invoke-DockerCommand -Description 'Recreating deven-spacebot on http://localhost:19898' -Arguments @(
        'compose',
        'up',
        '-d',
        '--force-recreate',
        'spacebot'
    )
}

function Stop-Custom {
    Invoke-DockerCommand -Description 'Stopping deven-spacebot' -Arguments @(
        'compose',
        'down'
    )
}

function Start-Upstream {
    Invoke-DockerCommand -Description 'Pulling latest upstream image' -Arguments @(
        'compose',
        '-f', 'docker-compose.upstream.yml',
        'pull',
        'spacebot-upstream'
    )

    Invoke-DockerCommand -Description 'Recreating upstream-spacebot on http://localhost:29898' -Arguments @(
        'compose',
        '-f', 'docker-compose.upstream.yml',
        'up',
        '-d',
        '--force-recreate',
        'spacebot-upstream'
    )
}

function Stop-Upstream {
    Invoke-DockerCommand -Description 'Stopping upstream-spacebot' -Arguments @(
        'compose',
        '-f', 'docker-compose.upstream.yml',
        'down'
    )
}

function Show-Status {
    Write-Host '==> Container status' -ForegroundColor Cyan
    Write-Host "==> EMAKBAI_HOST_PATH=$env:EMAKBAI_HOST_PATH" -ForegroundColor Cyan
    $containers = & docker ps -a --format "{{.Names}}`t{{.Image}}`t{{.Status}}`t{{.Ports}}"
    $containers | Where-Object { $_ -match '^(deven-spacebot|upstream-spacebot)\s' }
}

function Show-Usage {
    @'
Usage:
    ./scripts/spacebot-docker.ps1 custom-up [-Mode local|remote-base] [-VaultPath C:/path]
  ./scripts/spacebot-docker.ps1 custom-down
  ./scripts/spacebot-docker.ps1 upstream-up
  ./scripts/spacebot-docker.ps1 upstream-down
    ./scripts/spacebot-docker.ps1 both-up [-Mode local|remote-base] [-VaultPath C:/path]
  ./scripts/spacebot-docker.ps1 both-down
  ./scripts/spacebot-docker.ps1 status

Modes:
  local        Build deven-spacebot from ./Dockerfile using local repo source.
  remote-base  Build deven-spacebot from ./Dockerfile.custom using ghcr.io/spacedriveapp/spacebot:latest as the app base.

Ports:
  deven-spacebot    http://localhost:19898
  upstream-spacebot http://localhost:29898

Host Path:
    EMAKBAI_HOST_PATH controls host bind mounts for the EMAKBAI vault.
    Default on PowerShell: C:/dev/projects/pscm-dscloud/EMAKBAI
'@ | Write-Host
}

Push-Location $repoRoot
try {
        $env:EMAKBAI_HOST_PATH = ($VaultPath -replace '\\', '/')

    switch ($Command) {
        'custom-up' { Start-Custom }
        'custom-down' { Stop-Custom }
        'upstream-up' { Start-Upstream }
        'upstream-down' { Stop-Upstream }
        'both-up' {
            Start-Custom
            Start-Upstream
        }
        'both-down' {
            Stop-Upstream
            Stop-Custom
        }
        'status' { Show-Status }
        default { Show-Usage }
    }
}
finally {
    Pop-Location
}