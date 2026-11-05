<#
.SYNOPSIS
  Captures a scenario on an older commit with the older compiled carriers, then restores the slot.

.DESCRIPTION
  For "before" screenshots: detaches the slot at -Base, swaps in the compiled carriers from -Main
  (which still hold the old baked icons), builds the client, runs the scenario, then switches back
  to the original branch and puts the slot's own carriers back, even when a step fails.

  The client binary is left built from -Base. Rebuild it before the next capture or test:
    cargo build -p cinnabar --features developer-control

.EXAMPLE
  .\before_capture.ps1 -Slot C:\work\slot -Base 7af298d16 `
      -Scenario .\scenarios\wear_helmet_third_person.json -Shots $env:TEMP\before
#>
param(
  [string]$Slot = $env:CINNABAR_SLOT,
  [Parameter(Mandatory)][string]$Base,
  [Parameter(Mandatory)][string]$Scenario,
  [Parameter(Mandatory)][string]$Shots,
  [string]$Main = (git -C $PSScriptRoot rev-parse --show-toplevel)
)
$ErrorActionPreference = 'Stop'
if (-not $Slot) { throw 'Pass -Slot or set CINNABAR_SLOT.' }
function Invoke-Git { & git.exe @args 2>&1 | ForEach-Object { "$_" }; if ($LASTEXITCODE -ne 0) { throw "git $args failed" } }

Set-Location $Slot
if (git.exe status --porcelain) { throw 'Slot has uncommitted work; commit or stash it first.' }
$branch = (git.exe branch --show-current)
if (-not $branch) { throw 'Slot is on a detached HEAD; switch to a branch first.' }
$assets = Join-Path $Slot '.local\assets'
$env:CARGO_BUILD_JOBS = if ($env:CARGO_BUILD_JOBS) { $env:CARGO_BUILD_JOBS } else { '6' }

Rename-Item (Join-Path $assets 'compiled') 'compiled-new'
robocopy (Join-Path $Main '.local\assets\compiled') (Join-Path $assets 'compiled') /E /NFL /NDL /NJH /NJS /NP | Out-Null
try {
  Invoke-Git switch --detach $Base
  $out = cargo build -p cinnabar --features developer-control 2>&1 | Out-String
  ($out -split "`n" | Select-String -Pattern '^error|Finished' | ForEach-Object { $_.Line.Trim() }) -join "`n"
  python -I (Join-Path $PSScriptRoot 'mcp_run.py') --repo $Slot --shots $Shots $Scenario
}
finally {
  Invoke-Git switch $branch
  Remove-Item (Join-Path $assets 'compiled') -Recurse -Force
  Rename-Item (Join-Path $assets 'compiled-new') 'compiled'
  "restored: $(git.exe rev-parse --short HEAD) on $branch"
}
