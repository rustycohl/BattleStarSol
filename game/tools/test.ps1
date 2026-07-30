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
# Run Godot through Start-Process with redirect files rather than pipeline redirection.
# Under Windows PowerShell 5.1, stderr from a native executable is wrapped in an ErrorRecord,
# and with $ErrorActionPreference = 'Stop' a single harmless warning line becomes a
# terminating error. The import step emits "WARNING: Scan thread aborted", which was enough to
# abort this script before any suite ran.
function Invoke-Godot {
    param([string[]]$GodotArgs)

    $outFile = [System.IO.Path]::GetTempFileName()
    $errFile = [System.IO.Path]::GetTempFileName()
    try {
        $proc = Start-Process -FilePath $GodotPath -ArgumentList $GodotArgs -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $outFile -RedirectStandardError $errFile
        $lines = @()
        if (Test-Path -LiteralPath $outFile) { $lines += Get-Content -LiteralPath $outFile }
        if (Test-Path -LiteralPath $errFile) { $lines += Get-Content -LiteralPath $errFile }
        return [pscustomobject]@{ ExitCode = $proc.ExitCode; Lines = $lines }
    } finally {
        Remove-Item -LiteralPath $outFile, $errFile -Force -ErrorAction SilentlyContinue
    }
}

$import = Invoke-Godot -GodotArgs @('--headless', '--editor', '--path', $projectRoot, '--quit-after', '2')
if ($import.ExitCode -ne 0) {
    $import.Lines | ForEach-Object { Write-Host $_ }
    throw "Godot project import failed with exit code $($import.ExitCode)."
}
# A Godot headless script runner can exit 0 while a test died. A GDScript runtime error
# abandons the rest of the function it occurred in and returns control to the caller, so the
# runner's own bookkeeping never learns that assertions were skipped. Observed 2026-07-30: a
# wrong argument order printed
#   SCRIPT ERROR: Invalid type in function 'damage_terrain' ... Cannot convert argument 3
# skipped the remainder of that test, and the suite still reported PASS and exited 0.
#
# The exit code is therefore not sufficient evidence. The suites carry their own assertion
# floors as an in-engine tripwire; this is the outer check, and it catches errors anywhere,
# including parse errors and failures outside any test function.
function Invoke-GodotSuite {
    param([string]$Runner)

    Write-Host "Running $Runner..." -ForegroundColor Cyan
    $run = Invoke-Godot -GodotArgs @('--headless', '--path', $projectRoot, '--script', $Runner)
    $output = $run.Lines
    $output | ForEach-Object { Write-Host $_ }
    $suiteExit = $run.ExitCode

    $fatal = $output | Where-Object {
        $_ -match 'SCRIPT ERROR' -or $_ -match 'Parse Error' -or $_ -match 'Invalid type in function'
    }
    if ($fatal) {
        Write-Host ''
        Write-Host "FAIL: $Runner produced engine errors, so its result cannot be trusted even at exit 0:" -ForegroundColor Red
        $fatal | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        return 1
    }

    if ($suiteExit -ne 0) {
        return $suiteExit
    }

    if (-not ($output | Where-Object { $_ -match '^PASS:' })) {
        Write-Host "FAIL: $Runner exited 0 without printing a PASS line." -ForegroundColor Red
        return 1
    }

    return 0
}

$result = Invoke-GodotSuite -Runner 'res://tests/TestRunner.gd'
if ($result -ne 0) {
    exit $result
}
$result = Invoke-GodotSuite -Runner 'res://tests/PlaytestRunner.gd'
exit $result
