param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure([string]$Message) {
    $failures.Add($Message)
}

$required = @(
    'PLAY WEB DEV.cmd',
    'project.godot',
    'Bootstrap.tscn',
    'Main.tscn',
    'StratLayer.tscn',
    'scripts\ActionRouter.gd',
    'scripts\ActionEconomy.gd',
    'scripts\MovementContext.gd',
    'scripts\PayloadContract.gd',
    'data\payload.schema.json',
    'data\deploy.example.json',
    'web\index.html',
    'web\bridge.js',
    'web\atlas\index.html',
    'web\atlas\atlas.generated.css',
    'web\atlas\galaxy-io.js',
    'web\atlas\vendor\three.r128.min.js',
    'web\atlas\vendor\OrbitControls.r128.js',
    'web\atlas\vendor\fonts\material-icons.css',
    'web\atlas\vendor\fonts\material-icons-outlined.otf',
    'web\atlas\vendor\textures\earth-blue-marble.jpg',
    'web\atlas\vendor\textures\earth-water.png',
    'web\atlas\vendor\textures\earth-night.jpg',
    'web\atlas\vendor\textures\earth-topology.png',
    'web\battlestar.html',
    'web\tactical\index.html',
    'tools\launch-web.ps1'
)
foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $relative))) {
        Add-Failure "Missing required file: $relative"
    }
}

Get-ChildItem -LiteralPath (Join-Path $projectRoot 'data') -Filter '*.json' -File | ForEach-Object {
    try {
        Get-Content -Raw -LiteralPath $_.FullName | ConvertFrom-Json | Out-Null
    } catch {
        Add-Failure "Invalid JSON: $($_.Name) - $($_.Exception.Message)"
    }
}

$resourceFiles = Get-ChildItem -LiteralPath $projectRoot -Recurse -File |
    Where-Object {
        $_.Extension -in @('.gd', '.tscn', '.cfg') -and
        $_.FullName -notmatch '[\\/]\.godot(?:-test)?[\\/]'
    }
foreach ($file in $resourceFiles) {
    $text = Get-Content -Raw -LiteralPath $file.FullName
    if ($null -eq $text) { continue }
    foreach ($match in [regex]::Matches($text, 'res://[A-Za-z0-9_./-]+')) {
        $reference = $match.Value
        if ($reference.Contains('%') -or $reference.EndsWith('/')) { continue }
        $relative = $reference.Substring(6).Replace('/', '\')
        if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $relative))) {
            Add-Failure "Broken resource reference in $($file.Name): $reference"
        }
    }
}

$activeScripts = Get-ChildItem -LiteralPath (Join-Path $projectRoot 'scripts') -Filter '*.gd' -File
foreach ($file in $activeScripts) {
    $text = Get-Content -Raw -LiteralPath $file.FullName
    if ($text -match '\bNetwork\.|NetworkActions') {
        Add-Failure "Legacy ENet coupling remains in $($file.Name)"
    }
}

foreach ($name in @('WorldBuilder.gd', 'AIBehavior.gd', 'CombatSystem.gd', 'Main.gd')) {
    $path = Join-Path $projectRoot "scripts\$name"
    $text = Get-Content -Raw -LiteralPath $path
    if ($text -match '(?<!\.)\b(randf|randi|randf_range|randi_range|randomize)\s*\(') {
        Add-Failure "Global RNG remains in authoritative script: $name"
    }
}

$webIndex = Get-Content -Raw -LiteralPath (Join-Path $projectRoot 'web\index.html')
if ($webIndex -match '\.\./\.\./atlas-actual') {
    Add-Failure 'Web package still points outside itself for A.T.L.A.S.'
}

$atlasIndex = Get-Content -Raw -LiteralPath (Join-Path $projectRoot 'web\atlas\index.html')
if ($atlasIndex -notmatch 'activateProceduralTextureFallback' -or
    $atlasIndex -notmatch 'LIMITED FILE MODE' -or
    $atlasIndex -notmatch 'textureProfilesAvailable') {
    Add-Failure 'A.T.L.A.S. direct-file texture fallback contract is incomplete.'
}
if ($atlasIndex -match 'tailwindcss\.js') {
    Add-Failure 'A.T.L.A.S. restored the browser Tailwind compiler.'
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host 'PASS: static project verification'
