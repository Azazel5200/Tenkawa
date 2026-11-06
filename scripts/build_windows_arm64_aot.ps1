# Recompile an owner's locally installed EBOOT.ELF to native C++ on Windows.
# The game executable and generated source never leave the owner's machine.
param(
    [string]$BuildDirectory = 'out-media',
    [string]$EbootPath = '',
    [switch]$GenerateOnly,
    [switch]$VerifyToolsOnly
)

$ErrorActionPreference = 'Stop'
$project = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$build = if ([IO.Path]::IsPathRooted($BuildDirectory)) {
    [IO.Path]::GetFullPath($BuildDirectory)
} else {
    [IO.Path]::GetFullPath((Join-Path $project $BuildDirectory))
}

if (-not (Test-Path -LiteralPath (Join-Path $build 'CMakeCache.txt') -PathType Leaf)) {
    throw "The ARM64 build directory is not configured: $build"
}

$analyze = Join-Path $build 'portablekit\Release\psp_analyze.exe'
$recompile = Join-Path $build 'portablekit\Release\psp_recomp.exe'
foreach ($tool in @($analyze, $recompile)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
        throw "Missing recompiler tool: $tool. Build targets psp_analyze and psp_recomp first."
    }
}
Write-Host 'Native Windows ARM64 recompiler tools found.'
if ($VerifyToolsOnly) { return }

if ([string]::IsNullOrWhiteSpace($EbootPath)) {
    $candidates = @()
    if ($env:TENKAWA_EBOOT) { $candidates += $env:TENKAWA_EBOOT }
    if ($env:TENKAWA_DATA_DIR) { $candidates += (Join-Path $env:TENKAWA_DATA_DIR 'EBOOT.ELF') }
    if ($env:APPDATA) { $candidates += (Join-Path $env:APPDATA 'Tenkawa\DBZTTT\EBOOT.ELF') }
    if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA 'Tenkawa\DBZTTT\EBOOT.ELF') }
    $EbootPath = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}
if (-not $EbootPath -or -not (Test-Path -LiteralPath $EbootPath -PathType Leaf)) {
    throw 'No local EBOOT.ELF was found. Use -EbootPath with the prepared executable from your own disc.'
}

$analysis = Join-Path $project 'analysis'
$generated = Join-Path $project 'generated'
New-Item -ItemType Directory -Path $analysis, $generated -Force | Out-Null
Write-Host 'Analyzing the locally installed PSP executable...'
& $analyze $EbootPath (Join-Path $analysis 'report.json')
if ($LASTEXITCODE -ne 0) { throw "psp_analyze exited with $LASTEXITCODE" }
Write-Host 'Generating the native C++ corpus locally (this may take minutes)...'
& $recompile $EbootPath '--auto' $generated
if ($LASTEXITCODE -ne 0) { throw "psp_recomp exited with $LASTEXITCODE" }
if ($GenerateOnly) { return }

# Regenerate CMake after its source list changes. Existing ARM64 compiler,
# renderer and FFmpeg settings are retained from the checked build cache.
& cmake -S $project -B $build
if ($LASTEXITCODE -ne 0) { throw 'CMake reconfiguration failed' }
Write-Host 'Compiling AOT for the configured ARM64 target; expect a long build.'
& cmake --build $build --target TenkawaNative --config Release --parallel 1
if ($LASTEXITCODE -ne 0) { throw 'Native AOT compilation failed' }
Write-Host 'AOT compilation finished. Gameplay and GE display lists still require a hardware test.'
