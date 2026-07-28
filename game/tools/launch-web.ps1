[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)]
    [int]$Port = 8766,

    [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'
$webRoot = [System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $PSScriptRoot) 'web'))
$entryPoint = Join-Path $webRoot 'index.html'

if (-not (Test-Path -LiteralPath $entryPoint -PathType Leaf)) {
    throw "The Web build is incomplete: $entryPoint was not found."
}

$lastPort = [Math]::Min($Port + 19, 65535)
$candidatePorts = $Port..$lastPort
$activePorts = @(
    [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().
        GetActiveTcpListeners() |
        ForEach-Object { $_.Port }
)
foreach ($candidatePort in $candidatePorts) {
    if ($candidatePort -notin $activePorts) {
        continue
    }
    $candidateUrl = "http://127.0.0.1:$candidatePort/index.html"
    try {
        $existing = Invoke-WebRequest -UseBasicParsing -Method Head -Uri $candidateUrl -TimeoutSec 1
        if ($existing.Headers['X-BattleStar-Dev-Server'] -eq '1') {
            if (-not $NoBrowser) {
                Start-Process $candidateUrl
            }
            Write-Host "Battle/Star.SOL is already running at $candidateUrl"
            exit 0
        }
    } catch {
        # The port is unused, or it belongs to a different application.
    }
}

$mimeTypes = @{
    '.css'   = 'text/css; charset=utf-8'
    '.html'  = 'text/html; charset=utf-8'
    '.ico'   = 'image/x-icon'
    '.otf'   = 'font/otf'
    '.jpeg'  = 'image/jpeg'
    '.jpg'   = 'image/jpeg'
    '.js'    = 'text/javascript; charset=utf-8'
    '.json'  = 'application/json; charset=utf-8'
    '.ogg'   = 'audio/ogg'
    '.png'   = 'image/png'
    '.pck'   = 'application/octet-stream'
    '.svg'   = 'image/svg+xml'
    '.wasm'  = 'application/wasm'
    '.webp'  = 'image/webp'
    '.woff'  = 'font/woff'
    '.woff2' = 'font/woff2'
}

function Write-Response {
    param(
        [Parameter(Mandatory)]
        [System.Net.Sockets.NetworkStream]$Stream,

        [Parameter(Mandatory)]
        [int]$StatusCode,

        [Parameter(Mandatory)]
        [string]$StatusText,

        [Parameter(Mandatory)]
        [string]$ContentType,

        [Parameter(Mandatory)]
        [long]$ContentLength,

        [string]$FilePath,

        [switch]$HeadersOnly
    )

    $header = @(
        "HTTP/1.1 $StatusCode $StatusText"
        "Content-Type: $ContentType"
        "Content-Length: $ContentLength"
        'Cache-Control: no-store'
        'Cross-Origin-Embedder-Policy: require-corp'
        'Cross-Origin-Opener-Policy: same-origin'
        'Cross-Origin-Resource-Policy: same-origin'
        'X-BattleStar-Dev-Server: 1'
        'X-Content-Type-Options: nosniff'
        'Connection: close'
        ''
        ''
    ) -join "`r`n"

    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
    $Stream.Write($headerBytes, 0, $headerBytes.Length)

    if (-not $HeadersOnly -and $FilePath) {
        $file = [System.IO.File]::OpenRead($FilePath)
        try {
            $file.CopyTo($Stream)
        } finally {
            $file.Dispose()
        }
    }
}

function Write-TextError {
    param(
        [Parameter(Mandatory)]
        [System.Net.Sockets.NetworkStream]$Stream,

        [Parameter(Mandatory)]
        [int]$StatusCode,

        [Parameter(Mandatory)]
        [string]$StatusText
    )

    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes("$StatusCode $StatusText`n")
    $header = @(
        "HTTP/1.1 $StatusCode $StatusText"
        'Content-Type: text/plain; charset=utf-8'
        "Content-Length: $($bodyBytes.Length)"
        'Cache-Control: no-store'
        'X-BattleStar-Dev-Server: 1'
        'X-Content-Type-Options: nosniff'
        'Connection: close'
        ''
        ''
    ) -join "`r`n"
    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
    $Stream.Write($headerBytes, 0, $headerBytes.Length)
    $Stream.Write($bodyBytes, 0, $bodyBytes.Length)
}

$listener = $null
$selectedPort = $Port
foreach ($candidatePort in $candidatePorts) {
    $candidate = [System.Net.Sockets.TcpListener]::new(
        [System.Net.IPAddress]::Loopback,
        $candidatePort
    )
    try {
        $candidate.Start()
        $listener = $candidate
        $selectedPort = $candidatePort
        break
    } catch [System.Net.Sockets.SocketException] {
        $candidate.Stop()
    }
}

if ($null -eq $listener) {
    throw "Could not find an available local port from $Port through $lastPort."
}

$launchUrl = "http://127.0.0.1:$selectedPort/index.html"
$host.UI.RawUI.WindowTitle = 'Battle-Star.SOL Web Dev Server'

Write-Host ''
Write-Host '  BATTLE/STAR.SOL - WEB DEVELOPMENT BUILD' -ForegroundColor Cyan
Write-Host "  $launchUrl" -ForegroundColor Green
Write-Host ''
Write-Host '  The browser build is ready. Keep this window open while testing.'
Write-Host '  Press Ctrl+C or close this window to stop the local server.'
Write-Host ''

if (-not $NoBrowser) {
    Start-Process $launchUrl
}

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $client.ReceiveTimeout = 10000
            $client.SendTimeout = 30000
            $stream = $client.GetStream()
            $reader = [System.IO.StreamReader]::new(
                $stream,
                [System.Text.Encoding]::ASCII,
                $false,
                4096,
                $true
            )

            $requestLine = $reader.ReadLine()
            if ([string]::IsNullOrWhiteSpace($requestLine)) {
                continue
            }

            while ($true) {
                $headerLine = $reader.ReadLine()
                if ([string]::IsNullOrEmpty($headerLine)) {
                    break
                }
            }

            $requestParts = $requestLine.Split(' ')
            if ($requestParts.Length -lt 2 -or $requestParts[0] -notin @('GET', 'HEAD')) {
                Write-TextError -Stream $stream -StatusCode 405 -StatusText 'Method Not Allowed'
                continue
            }

            $rawTarget = $requestParts[1].Split('?')[0]
            $relativeTarget = [System.Uri]::UnescapeDataString($rawTarget).TrimStart('/').Replace('/', '\')
            if ([string]::IsNullOrWhiteSpace($relativeTarget)) {
                $relativeTarget = 'index.html'
            }

            $candidatePath = [System.IO.Path]::GetFullPath((Join-Path $webRoot $relativeTarget))
            $safePrefix = $webRoot.TrimEnd('\') + '\'
            if (-not $candidatePath.StartsWith($safePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                Write-TextError -Stream $stream -StatusCode 403 -StatusText 'Forbidden'
                continue
            }

            if (Test-Path -LiteralPath $candidatePath -PathType Container) {
                $candidatePath = Join-Path $candidatePath 'index.html'
            }
            if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) {
                Write-TextError -Stream $stream -StatusCode 404 -StatusText 'Not Found'
                continue
            }

            $fileInfo = Get-Item -LiteralPath $candidatePath
            $extension = $fileInfo.Extension.ToLowerInvariant()
            $contentType = $mimeTypes[$extension]
            if (-not $contentType) {
                $contentType = 'application/octet-stream'
            }

            Write-Response `
                -Stream $stream `
                -StatusCode 200 `
                -StatusText 'OK' `
                -ContentType $contentType `
                -ContentLength $fileInfo.Length `
                -FilePath $candidatePath `
                -HeadersOnly:($requestParts[0] -eq 'HEAD')
        } catch {
            Write-Warning "Request failed: $($_.Exception.Message)"
        } finally {
            if ($null -ne $client) {
                $client.Dispose()
            }
        }
    }
} finally {
    $listener.Stop()
}
