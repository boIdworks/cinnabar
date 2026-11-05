<#
.SYNOPSIS
  Points one persistent worktree at a new branch cut from origin/dev, keeping its warm Cargo cache.

.DESCRIPTION
  Every worktree has its own Cargo build-dir (see .cargo/config.toml), so a new worktree costs a
  cold build. Reusing one "slot" keeps edit-and-rerun builds fast. This script fetches, refuses to
  run over uncommitted work, switches to a new branch from origin/dev, and links what a headless
  client needs: the downloaded game files, a private copy of the compiled carriers (rebaking icons
  or world data writes there, so it must not point into another checkout) and the local server.

  Never rename or move the slot: its build-dir is keyed on its path.

.EXAMPLE
  $env:CINNABAR_SLOT = 'C:\work\cinnabar-slot'
  .\tools\capture-workflow\slot.ps1 fix/some-bug
#>
param(
  [Parameter(Mandatory)][string]$Branch,
  [string]$Slot = $env:CINNABAR_SLOT,
  # The checkout that owns .local/assets and target/release (default: the one holding this script).
  [string]$Main = (git -C $PSScriptRoot rev-parse --show-toplevel)
)
$ErrorActionPreference = 'Stop'
if (-not $Slot) { throw 'Pass -Slot or set CINNABAR_SLOT to the worktree to reuse.' }

# A function named Git would shadow git itself (PowerShell names are case-insensitive).
function Invoke-Git { & git.exe @args 2>&1 | ForEach-Object { "$_" }; if ($LASTEXITCODE -ne 0) { throw "git $args failed" } }

Invoke-Git -C $Slot fetch origin dev
if (git.exe -C $Slot status --porcelain) { throw 'Slot has uncommitted work; commit or stash it first.' }
Invoke-Git -C $Slot switch -c $Branch origin/dev

$assets = Join-Path $Slot '.local\assets'
New-Item -ItemType Directory -Force $assets | Out-Null
foreach ($name in 'bedrock-samples', 'downloads') {
  $target = Join-Path $Main ".local\assets\$name"
  if (-not (Test-Path (Join-Path $assets $name)) -and (Test-Path $target)) {
    New-Item -ItemType Junction (Join-Path $assets $name) -Target $target | Out-Null
  }
}
$compiled = Join-Path $assets 'compiled'
if (-not (Test-Path $compiled) -and (Test-Path (Join-Path $Main '.local\assets\compiled'))) {
  robocopy (Join-Path $Main '.local\assets\compiled') $compiled /E /NFL /NDL /NJH /NJS /NP | Out-Null
}
$server = Join-Path $Slot 'target\release\bedrock-local-server.exe'
$mainServer = Join-Path $Main 'target\release\bedrock-local-server.exe'
if (-not (Test-Path $server) -and (Test-Path $mainServer)) {
  New-Item -ItemType Directory -Force (Split-Path $server) | Out-Null
  Copy-Item $mainServer $server
}
Invoke-Git -C $Slot log -1 --oneline
