[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$gameRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$repositoryRoot = (& git -C $gameRoot rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0 -or $repositoryRoot -eq '') {
    throw 'Unable to resolve the repository root.'
}
$repositoryRoot = [System.IO.Path]::GetFullPath($repositoryRoot)

$repositoryPrefix = $repositoryRoot.TrimEnd('\') + '\'
if (-not $gameRoot.StartsWith(
    $repositoryPrefix,
    [System.StringComparison]::OrdinalIgnoreCase
)) {
    throw "Game root is outside the repository: $gameRoot"
}
$gameRelative = $gameRoot.Substring($repositoryPrefix.Length).Replace('\', '/')
$manifestPath = Join-Path $gameRoot 'MANIFEST.sha256'
$tracked = @(
    & git -C $repositoryRoot ls-files -- "$gameRelative/*"
)
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to enumerate tracked game files.'
}

$lines = @(
foreach ($repositoryPath in ($tracked | Sort-Object)) {
    $relative = $repositoryPath.Substring($gameRelative.Length + 1)
    if ($relative -eq 'MANIFEST.sha256') {
        continue
    }
    $absolute = Join-Path $repositoryRoot ($repositoryPath.Replace('/', '\'))
    $digest = (Get-FileHash -LiteralPath $absolute -Algorithm SHA256).Hash.ToLowerInvariant()
    "$digest  $relative"
}
)
$lines = @($lines | Sort-Object)

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllLines($manifestPath, $lines, $utf8NoBom)
Write-Host "Updated $manifestPath with $($lines.Count) tracked-file hashes."
