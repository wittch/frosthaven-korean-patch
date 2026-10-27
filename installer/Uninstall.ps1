# SPDX-License-Identifier: MIT
# Copyright (c) 2026 wittch
param([string]$GamePath)
. (Join-Path $PSScriptRoot 'Shared.ps1')
Assert-Closed
$GamePath = Find-Game $GamePath
$statePath = Safe-Path $GamePath '.gkfont-frosthaven\installation.json'
$state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([IO.Path]::GetFullPath($state.gamePath).TrimEnd('\') -ne [IO.Path]::GetFullPath($GamePath).TrimEnd('\')) { throw 'Installation record belongs to another folder.' }
$targets = @()
foreach ($entry in $state.files) {
    $target = Safe-Path $GamePath $entry.path
    if (Test-Path -LiteralPath $target) {
        if ((Hash-File $target) -ne $entry.sha256) {
            if ($state.status -ne 'incomplete' -and $state.status -ne 'installing') { throw "Patch file was changed: $($entry.path). Preserve it manually before uninstalling. Nothing removed." }
            throw "Interrupted or changed patch file: $($entry.path). Preserve or remove this specific file manually, then retry."
        }
        $targets += $target
    }
}
foreach ($target in $targets) { Remove-Item -LiteralPath $target }
Remove-Item -LiteralPath $statePath
$stateRoot = Split-Path $statePath -Parent
if (@(Get-ChildItem -LiteralPath $stateRoot -Force).Count -eq 0) { Remove-Item -LiteralPath $stateRoot }
Write-Output 'Removed the recorded patch files. Game data, saves and unowned files were preserved. No game launched.'
