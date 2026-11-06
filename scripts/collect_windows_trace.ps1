# Collect a bounded, local diagnostic log for the installed Tenkawa host.
# The game image, decrypted executable and generated guest code remain local.
[CmdletBinding()]
param(
    [switch]$Help,
    [ValidateRange(-1, 100000000)]
    [int]$GeListStart = -1,
    [ValidateRange(1, 20)]
    [int]$GeListCount = 3
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Output 'Usage: .\collect_windows_trace.ps1 [-GeListStart N [-GeListCount M]]'
    Write-Output 'Place this script beside TenkawaNative.exe. It enables performance and I/O tracing.'
    Write-Output 'Close the game window after reproducing the issue to finish the log.'
    Write-Output 'Optional GE tracing captures only display-list runs N through N+M-1.'
    Write-Output 'Logs are stored locally in the temporary Tenkawa-Traces folder.'
    return
}

$hostDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$exe = Join-Path $hostDir 'TenkawaNative.exe'
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
    throw 'TenkawaNative.exe was not found beside this script.'
}

$logDir = Join-Path ([System.IO.Path]::GetTempPath()) 'Tenkawa-Traces'
New-Item -Path $logDir -ItemType Directory -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$logFile = Join-Path $logDir "tenkawa-diagnostics-$stamp.txt"

$names = @('TENKAWA_PERF', 'TENKAWA_TRACE_IO', 'TENKAWA_TRACE_GE_LIST')
$previous = @{}
foreach ($name in $names) {
    $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

try {
    $env:TENKAWA_PERF = 'log'
    $env:TENKAWA_TRACE_IO = '1'
    if ($GeListStart -ge 0) {
        $env:TENKAWA_TRACE_GE_LIST = '{0}:{1}' -f $GeListStart, $GeListCount
    } else {
        [Environment]::SetEnvironmentVariable('TENKAWA_TRACE_GE_LIST', $null, 'Process')
    }

    Write-Host "Writing diagnostic output to $logFile"
    Write-Host 'Use the game normally, then close its window after reproducing the issue.'
    Write-Host 'The log contains local paths and technical data, not the game image.'

    Push-Location -LiteralPath $hostDir
    try {
        & $exe *>&1 | Tee-Object -FilePath $logFile
    } finally {
        Pop-Location
    }
} finally {
    foreach ($name in $names) {
        [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process')
    }
}

Write-Host "Diagnostic log saved: $logFile"
