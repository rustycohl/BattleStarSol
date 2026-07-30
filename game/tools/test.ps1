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
# Godot runs as a directly-driven child process. Two reasons, both learned the hard way:
# 5.1 turns a native command's stderr into a terminating error under 'Stop' (the import step's
# harmless "WARNING: Scan thread aborted" aborted this script before any suite ran), and
# `Start-Process -PassThru` leaves ExitCode unreadable so every run looked like a failure.
# A headless suite can also fail by never finishing. A GDScript runtime error inside a
# deferred entry point abandons the function before it reaches `quit()`, so the SceneTree keeps
# running and the process hangs indefinitely rather than exiting non-zero. Observed 2026-07-30
# while probing the ledger budget: a wrong method name on an autoload hung the runner until it
# was killed. The assertion floor and the error scan below both catch a suite that *finishes*
# wrongly; neither can catch one that never finishes. Hence a hard timeout.
$script:GodotTimeoutSeconds = if ($env:BSS_SUITE_TIMEOUT) { [int]$env:BSS_SUITE_TIMEOUT } else { 600 }

function Invoke-Godot {
    param([string[]]$GodotArgs)

    # System.Diagnostics.Process rather than Start-Process. Under Windows PowerShell 5.1,
    # `Start-Process -PassThru` without `-Wait` hands back an object whose ExitCode is
    # unreadable because the process handle was never cached, so every run reported an empty
    # exit code and looked like a failure. Driving the process directly gives a reliable exit
    # code, a real timeout, and both streams read as plain strings rather than through the
    # pipeline — which matters because 5.1 wraps a native command's stderr in an ErrorRecord
    # and, under $ErrorActionPreference='Stop', one harmless warning aborts the whole script.
    $proc = New-Object System.Diagnostics.Process
    try {
        $proc.StartInfo.FileName = $GodotPath
        # ArgumentList is .NET Core only; Windows PowerShell 5.1 runs on .NET Framework, where
        # only the single Arguments string exists. Quote any argument containing whitespace so a
        # path with a space cannot silently split into two arguments.
        $proc.StartInfo.Arguments = (
            $GodotArgs | ForEach-Object {
                if ($_ -match '\s') { '"' + $_ + '"' } else { $_ }
            }
        ) -join ' '
        $proc.StartInfo.UseShellExecute = $false
        $proc.StartInfo.RedirectStandardOutput = $true
        $proc.StartInfo.RedirectStandardError = $true
        $proc.StartInfo.CreateNoWindow = $true
        [void]$proc.Start()

        # Read both streams asynchronously. Reading one synchronously while the other
        # fills its pipe buffer is the classic way to deadlock a child process.
        $outTask = $proc.StandardOutput.ReadToEndAsync()
        $errTask = $proc.StandardError.ReadToEndAsync()

        $timedOut = $false
        if (-not $proc.WaitForExit($script:GodotTimeoutSeconds * 1000)) {
            $timedOut = $true
            Write-Host ("TIMEOUT: no exit after {0}s; killing the process." -f $script:GodotTimeoutSeconds) -ForegroundColor Red
            try { $proc.Kill($true) } catch { try { $proc.Kill() } catch {} }
            $proc.WaitForExit(10000) | Out-Null
        }

        $stdout = ''
        $stderr = ''
        try { $stdout = $outTask.GetAwaiter().GetResult() } catch {}
        try { $stderr = $errTask.GetAwaiter().GetResult() } catch {}

        $lines = @()
        # Single-quoted so PowerShell does not process the escapes; this is a regex.
        if ($stdout) { $lines += ($stdout -split '\r?\n') }
        if ($stderr) { $lines += ($stderr -split '\r?\n') }
        $lines = @($lines | Where-Object { $_ -ne '' })

        $code = if ($timedOut) { 124 } else { [int]$proc.ExitCode }
        if ($timedOut) {
            $lines += ("HARNESS: suite did not exit within {0}s and was killed. A runtime error before quit() leaves the SceneTree running." -f $script:GodotTimeoutSeconds)
        }
        return [pscustomobject]@{ ExitCode = $code; Lines = $lines; TimedOut = $timedOut }
    } finally {
        $proc.Dispose()
    }
}


$import = Invoke-Godot -GodotArgs @('--headless', '--editor', '--path', $projectRoot, '--quit-after', '2')
if ($import.TimedOut) {
    throw 'Godot project import did not exit within the timeout.'
}
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

    if ($run.TimedOut) {
        Write-Host ''
        Write-Host "FAIL: $Runner never exited and was killed. It did not finish, so it did not pass." -ForegroundColor Red
        return 124
    }

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
