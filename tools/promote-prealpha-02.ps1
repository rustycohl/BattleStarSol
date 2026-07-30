[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TargetPath,
    [string]$GodotPath = '',
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$sourceRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$manifestPath = Join-Path $sourceRoot 'prealpha-02-manifest.json'

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Repository,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $output = & git -C $Repository @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        $joined = $Arguments -join ' '
        throw "git -C `"$Repository`" $joined failed:`n$($output -join "`n")"
    }
    # The unary comma prevents PowerShell from unrolling a one-line result into
    # a scalar string, which would make callers' [0] index return one character.
    return ,@($output)
}

function Test-AllowedPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [object[]]$Allowed,
        [Parameter(Mandatory = $true)]
        [object[]]$Blocked
    )

    foreach ($prefix in $Blocked) {
        if ($Path -eq $prefix.TrimEnd('/') -or $Path.StartsWith($prefix)) {
            return $false
        }
    }
    foreach ($prefix in $Allowed) {
        if ($Path -eq $prefix.TrimEnd('/') -or $Path.StartsWith($prefix)) {
            return $true
        }
    }
    return $false
}

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Missing injection manifest: $manifestPath"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$targetRoot = [System.IO.Path]::GetFullPath($TargetPath)
if (-not (Test-Path -LiteralPath $targetRoot -PathType Container)) {
    throw "Target repository does not exist: $targetRoot"
}
if ($targetRoot -eq $sourceRoot) {
    throw 'Source and target repositories must be different directories.'
}

$actualSourceRoot = (Invoke-Git -Repository $sourceRoot -Arguments @(
    'rev-parse', '--show-toplevel'
))[0].Trim()
if ([System.IO.Path]::GetFullPath($actualSourceRoot) -ne $sourceRoot) {
    throw "Unexpected source Git root: $actualSourceRoot"
}

$sourceBranch = (Invoke-Git -Repository $sourceRoot -Arguments @(
    'branch', '--show-current'
))[0].Trim()
if ($sourceBranch -ne $manifest.source.branch) {
    throw "Source branch is '$sourceBranch'; expected '$($manifest.source.branch)'."
}

$sourceStatus = Invoke-Git -Repository $sourceRoot -Arguments @(
    'status', '--porcelain'
)
if ($sourceStatus.Count -gt 0) {
    throw 'Source worktree is dirty. Commit or deliberately remove changes first.'
}

$sourceHead = (Invoke-Git -Repository $sourceRoot -Arguments @(
    'rev-parse', 'HEAD'
))[0].Trim()
$baseCommit = [string]$manifest.source.base_commit
Invoke-Git -Repository $sourceRoot -Arguments @(
    'merge-base', '--is-ancestor', $baseCommit, $sourceHead
) | Out-Null

$mergeCommits = Invoke-Git -Repository $sourceRoot -Arguments @(
    'rev-list', '--merges', "$baseCommit..$sourceHead"
)
if ($mergeCommits.Count -gt 0) {
    throw 'The injection range contains merge commits; promotion requires a linear review range.'
}

$changedPaths = Invoke-Git -Repository $sourceRoot -Arguments @(
    'diff', '--name-only', "$baseCommit..$sourceHead"
)
$disallowed = @(
    $changedPaths | Where-Object {
        -not (Test-AllowedPath -Path $_ -Allowed $manifest.promotion.allowed_paths `
            -Blocked $manifest.promotion.blocked_paths)
    }
)
if ($disallowed.Count -gt 0) {
    throw "Changed paths outside the promotion allowlist:`n$($disallowed -join "`n")"
}

$actualTargetRoot = (Invoke-Git -Repository $targetRoot -Arguments @(
    'rev-parse', '--show-toplevel'
))[0].Trim()
if ([System.IO.Path]::GetFullPath($actualTargetRoot) -ne $targetRoot) {
    throw "Unexpected target Git root: $actualTargetRoot"
}

$targetStatus = Invoke-Git -Repository $targetRoot -Arguments @(
    'status', '--porcelain'
)
if ($targetStatus.Count -gt 0) {
    throw 'Target worktree is dirty. Promotion will not touch it.'
}

$targetHead = (Invoke-Git -Repository $targetRoot -Arguments @(
    'rev-parse', 'HEAD'
))[0].Trim()
if ($targetHead -ne $manifest.target.required_head) {
    throw "Target HEAD is $targetHead; expected $($manifest.target.required_head)."
}

$npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
if ($null -eq $npm) {
    throw 'npm.cmd was not found.'
}
Push-Location $sourceRoot
try {
    & $npm.Source test
    if ($LASTEXITCODE -ne 0) {
        throw "Node tests failed with exit code $LASTEXITCODE."
    }
    & $npm.Source run check
    if ($LASTEXITCODE -ne 0) {
        throw "Node syntax checks failed with exit code $LASTEXITCODE."
    }
} finally {
    Pop-Location
}

if ($GodotPath -eq '' -and $env:BSS_GODOT_PATH) {
    $GodotPath = $env:BSS_GODOT_PATH
}
if ($GodotPath -eq '') {
    $installedGodot = Get-Command godot4, godot -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -ne $installedGodot) {
        $GodotPath = $installedGodot.Source
    }
}
if ($GodotPath -eq '' -or -not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw 'Godot was not found. Pass -GodotPath or set BSS_GODOT_PATH.'
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File (Join-Path $sourceRoot 'game\tools\test.ps1') `
    -GodotPath $GodotPath
if ($LASTEXITCODE -ne 0) {
    throw "Godot gate failed with exit code $LASTEXITCODE."
}

$moduleById = @{}
foreach ($module in $manifest.modules) {
    $moduleById[[string]$module.id] = $module
}
$blockers = [System.Collections.Generic.List[string]]::new()
foreach ($requiredId in $manifest.release.required_modules) {
    if (-not $moduleById.ContainsKey([string]$requiredId)) {
        $blockers.Add("Required module $requiredId is absent from the manifest.")
        continue
    }
    if ($moduleById[[string]$requiredId].status -ne 'complete') {
        $blockers.Add(
            "Required module $requiredId is '$($moduleById[[string]$requiredId].status)'."
        )
    }
}
if ($manifest.state -ne 'release_candidate') {
    $blockers.Add("Manifest state is '$($manifest.state)', not 'release_candidate'.")
}
if ($manifest.release.allow_apply -ne $true) {
    $blockers.Add('release.allow_apply is false.')
}

$commits = Invoke-Git -Repository $sourceRoot -Arguments @(
    'rev-list', '--reverse', "$baseCommit..$sourceHead"
)

Write-Host ''
Write-Host 'Battle/Star.SOL pre-alpha .02 promotion audit' -ForegroundColor Cyan
Write-Host "  source:  $sourceRoot"
Write-Host "  head:    $sourceHead"
Write-Host "  target:  $targetRoot"
Write-Host "  commits: $($commits.Count)"
Write-Host "  paths:   $($changedPaths.Count)"

if ($blockers.Count -gt 0) {
    Write-Host 'PROMOTION BLOCKED:' -ForegroundColor Yellow
    $blockers | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    if ($Apply) {
        throw 'Apply was requested, but the release manifest is not ready.'
    }
    Write-Host 'Dry run complete; the target was not modified.' -ForegroundColor Green
    exit 0
}

if (-not $Apply) {
    Write-Host 'PROMOTION READY. Re-run with -Apply to create and populate the target branch.' `
        -ForegroundColor Green
    Write-Host 'Dry run complete; the target was not modified.' -ForegroundColor Green
    exit 0
}

if ($commits.Count -eq 0) {
    throw 'There are no commits after the pinned base to promote.'
}

$promotionBranch = [string]$manifest.target.promotion_branch
$existingBranch = Invoke-Git -Repository $targetRoot -Arguments @(
    'branch', '--list', $promotionBranch
)
if ($existingBranch.Count -gt 0) {
    throw "Target branch '$promotionBranch' already exists."
}

Invoke-Git -Repository $targetRoot -Arguments @(
    'switch', '-c', $promotionBranch
) | Out-Null
foreach ($commit in $commits) {
    Invoke-Git -Repository $targetRoot -Arguments @(
        'cherry-pick', $commit
    ) | Out-Null
}

Write-Host "Promotion applied to target branch '$promotionBranch'." -ForegroundColor Green
Write-Host 'Re-run all gates in the target, review the diff, and back up before publishing.'
