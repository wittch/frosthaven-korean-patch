# SPDX-License-Identifier: MIT
# Copyright (c) 2026 wittch
param([string]$GamePath, [switch]$VerifyOnly)
. (Join-Path $PSScriptRoot 'Shared.ps1')
Assert-Closed
$GamePath = Find-Game $GamePath
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($entry in $manifest.gameFiles) {
    $target = Safe-Path $GamePath $entry.path
    if (-not (Test-Path -LiteralPath $target) -or (Hash-File $target) -ne $entry.sha256) { throw "Unsupported or modified game file: $($entry.path). Nothing changed." }
}
$mono = Safe-Path $GamePath 'MonoBleedingEdge\EmbedRuntime\mono-2.0-bdwgc.dll'
if (-not (Test-Path -LiteralPath $mono)) { throw 'This patch requires the Windows x64 Mono version.' }
$exe = [IO.File]::ReadAllBytes((Safe-Path $GamePath 'Frosthaven.exe'))
$pe = [BitConverter]::ToInt32($exe,60)
if ([BitConverter]::ToUInt16($exe,$pe+4) -ne 0x8664) { throw 'This patch requires a 64-bit game.' }
$statePath = Safe-Path $GamePath '.gkfont-frosthaven\installation.json'
if (Test-Path -LiteralPath (Split-Path $statePath -Parent)) { throw 'A patch installation record exists. Uninstall that version first.' }
foreach ($conflict in @('winhttp.dll','version.dll','doorstop_config.ini','ReiPatcher')) {
    if (Test-Path -LiteralPath (Safe-Path $GamePath $conflict)) { throw "Existing mod or loader: $conflict. Nothing changed." }
}
$loaderFolder = Safe-Path $GamePath 'BepInEx'
if (Test-Path -LiteralPath $loaderFolder) {
    $activeFiles = @(Get-ChildItem -LiteralPath $loaderFolder -Recurse -File | Where-Object { $_.Extension -in @('.dll','.exe') })
    if ($activeFiles.Count -gt 0) { throw 'Existing BepInEx binaries or plugins found. Nothing changed.' }
}
$payload = Join-Path $PSScriptRoot 'payload'
foreach ($entry in $manifest.files) {
    $source = Safe-Path $payload $entry.path
    if ((Hash-File $source) -ne $entry.sha256) { throw "Damaged package: $($entry.path). Nothing changed." }
    $target = Safe-Path $GamePath $entry.path
    if (Test-Path -LiteralPath $target) { throw "Target file already exists: $($entry.path). Nothing changed." }
}
if ($VerifyOnly) { Write-Output 'Compatible game and intact package. No files changed; no game launched.'; return }
$owned = New-Object 'System.Collections.Generic.List[object]'
function Save-State([string]$Status) {
    [pscustomobject]@{version=$manifest.version; gamePath=$GamePath; status=$Status; files=@($owned.ToArray())} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statePath -Encoding UTF8
}
try {
    New-Item -ItemType Directory -Path (Split-Path $statePath -Parent) | Out-Null
    Save-State 'installing'
    foreach ($entry in $manifest.files) {
        $target = Safe-Path $GamePath $entry.path
        New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
        $owned.Add([pscustomobject]@{path=$entry.path; sha256=$entry.sha256})
        Save-State 'installing'
        Copy-Item -LiteralPath (Safe-Path $payload $entry.path) -Destination $target
    }
    Save-State 'installed'
    Write-Output 'Installed. Select Korean in the game language settings. No game launched.'
} catch {
    # Leave an accurate journal for Uninstall.ps1, including interrupted copies.
    if (Test-Path -LiteralPath (Split-Path $statePath -Parent)) { Save-State 'incomplete' }
    throw
}
