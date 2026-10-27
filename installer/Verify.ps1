# SPDX-License-Identifier: MIT
# Copyright (c) 2026 wittch
param([string]$GamePath)
. (Join-Path $PSScriptRoot 'Shared.ps1')
$GamePath = Find-Game $GamePath
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($entry in @($manifest.gameFiles) + @($manifest.files)) {
    $target = Safe-Path $GamePath $entry.path
    if (-not (Test-Path -LiteralPath $target) -or (Hash-File $target) -ne $entry.sha256) { throw "Missing or changed file: $($entry.path)" }
}
Write-Output 'Installed file hashes match. This is a static check; game screens have not been tested.'
