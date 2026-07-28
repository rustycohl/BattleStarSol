[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$webOutput = Join-Path $projectRoot 'web\tactical\index.html'
$packageOutput = Join-Path $projectRoot 'web\tactical\index.pck'
$webOutputDirectory = Split-Path -Parent $webOutput
if (-not (Test-Path -LiteralPath $webOutputDirectory)) {
    New-Item -ItemType Directory -Force -Path $webOutputDirectory | Out-Null
}

$sourceFiles = @(
    Get-ChildItem -LiteralPath (Join-Path $projectRoot 'scripts') -Recurse -File
    Get-ChildItem -LiteralPath (Join-Path $projectRoot 'data') -Recurse -File
    Get-ChildItem -LiteralPath $projectRoot -File |
        Where-Object { $_.Extension -in @('.godot', '.tscn', '.tres') }
)
$latestSource = $sourceFiles | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1

if (
    -not $Force -and
    (Test-Path -LiteralPath $packageOutput -PathType Leaf) -and
    $null -ne $latestSource -and
    (Get-Item -LiteralPath $packageOutput).LastWriteTimeUtc -ge $latestSource.LastWriteTimeUtc
) {
    Write-Host 'Godot Web package is current.' -ForegroundColor DarkGreen
    exit 0
}

$godotCandidates = @()
if ($env:BSS_GODOT_PATH) {
    $godotCandidates += $env:BSS_GODOT_PATH
}
$godotCandidates += @(
    (Join-Path $projectRoot '..\..\godot-exe\Godot_v4.7.1-stable_win64_console.exe'),
    (Join-Path $projectRoot '..\godot-exe\Godot_v4.7.1-stable_win64_console.exe'),
    (Join-Path $projectRoot '..\..\battle.star.sol-prealpha00\godot-exe\Godot_v4.7.1-stable_win64_console.exe')
)
$installedGodot = Get-Command godot, godot4 -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -ne $installedGodot) {
    $godotCandidates += $installedGodot.Source
}

$godotPath = $godotCandidates |
    ForEach-Object { [System.IO.Path]::GetFullPath($_) } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    Select-Object -First 1
if (-not $godotPath) {
    throw 'Godot console executable was not found. Set BSS_GODOT_PATH or restore the supplied godot-exe folder.'
}

# Prefer the supplied isolated profile when its matching Web templates exist.
$profileCandidates = @(
    (Join-Path $projectRoot 'godot-profile'),
    (Join-Path (Split-Path -Parent $projectRoot) 'godot-isolated-profile'),
    (Join-Path $projectRoot '..\..\.codex-delivery\godot-isolated-profile')
)
$isolatedProfile = $profileCandidates |
    ForEach-Object { [System.IO.Path]::GetFullPath($_) } |
    Where-Object {
        Test-Path -LiteralPath (Join-Path $_ 'Roaming\Godot\export_templates\4.7.1.stable') -PathType Container
    } |
    Select-Object -First 1
if ($isolatedProfile) {
    $env:APPDATA = Join-Path $isolatedProfile 'Roaming'
    $env:LOCALAPPDATA = Join-Path $isolatedProfile 'Local'
    $env:TEMP = Join-Path $isolatedProfile 'Temp'
    $env:TMP = $env:TEMP
    New-Item -ItemType Directory -Force -Path $env:TEMP | Out-Null
}

Write-Host 'Rebuilding the Godot Web package...' -ForegroundColor Cyan
& $godotPath --headless --path $projectRoot --export-release Web $webOutput
if ($LASTEXITCODE -ne 0) {
    throw "Godot Web export failed with exit code $LASTEXITCODE."
}
Write-Host 'Godot Web package rebuilt.' -ForegroundColor Green
