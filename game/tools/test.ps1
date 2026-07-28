param(
    [string]$GodotPath = '',
    [switch]$StaticOnly
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot

& (Join-Path $PSScriptRoot 'verify.ps1')
if (-not $?) {
    exit 1
}

if ($StaticOnly) {
    exit 0
}

if ($GodotPath -eq '') {
    $godot = Get-Command godot4 -ErrorAction SilentlyContinue
    if ($null -eq $godot) {
        $godot = Get-Command godot -ErrorAction SilentlyContinue
    }
    if ($null -ne $godot) {
        $GodotPath = $godot.Source
    }
}

if ($GodotPath -eq '' -or -not (Test-Path -LiteralPath $GodotPath)) {
    throw 'Godot was not found. Pass -GodotPath C:\path\to\Godot.exe, or use -StaticOnly.'
}

$profileRoot = if ($env:BSS_GODOT_PROFILE) {
    $env:BSS_GODOT_PROFILE
} else {
    Join-Path $projectRoot 'godot-profile'
}
$profileRoaming = Join-Path $profileRoot 'Roaming'
$profileLocal = Join-Path $profileRoot 'Local'
$profileTemp = Join-Path $profileRoot 'Temp'
if (-not (Test-Path -LiteralPath $profileRoaming)) {
    New-Item -ItemType Directory -Path $profileRoaming -Force | Out-Null
}
if (-not (Test-Path -LiteralPath $profileLocal)) {
    New-Item -ItemType Directory -Path $profileLocal -Force | Out-Null
}
if (-not (Test-Path -LiteralPath $profileTemp)) {
    New-Item -ItemType Directory -Path $profileTemp -Force | Out-Null
}
$env:APPDATA = $profileRoaming
$env:LOCALAPPDATA = $profileLocal
$env:TEMP = $profileTemp
$env:TMP = $profileTemp

# A clean clone has no global script-class cache. Import the project once so
# class_name dependencies are registered before the headless script runners.
& $GodotPath --headless --editor --path $projectRoot --quit-after 2
if ($LASTEXITCODE -ne 0) {
    throw "Godot project import failed with exit code $LASTEXITCODE."
}
& $GodotPath --headless --path $projectRoot --script 'res://tests/TestRunner.gd'
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
& $GodotPath --headless --path $projectRoot --script 'res://tests/PlaytestRunner.gd'
exit $LASTEXITCODE
