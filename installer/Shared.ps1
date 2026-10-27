# SPDX-License-Identifier: MIT
# Copyright (c) 2026 wittch
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
function Safe-Path([string]$Root, [string]$Relative) {
    if ([IO.Path]::IsPathRooted($Relative)) { throw 'Absolute package path is invalid.' }
    $basePath = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $result = [IO.Path]::GetFullPath((Join-Path $basePath $Relative))
    if (-not $result.StartsWith($basePath, [StringComparison]::OrdinalIgnoreCase)) { throw 'Package path leaves the game folder.' }
    $check = $result
    while ($check.Length -ge $basePath.TrimEnd('\').Length) {
        if (Test-Path -LiteralPath $check) {
            if ((Get-Item -LiteralPath $check -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked folder or file is not supported: $check" }
        }
        $parent = Split-Path $check -Parent
        if (-not $parent -or $parent -eq $check) { break }
        $check = $parent
    }
    return $result
}
function Find-SteamGames([string[]]$Libraries) {
    foreach ($library in ($Libraries | Where-Object { $_ } | Select-Object -Unique)) {
        # Steam retains entries for disconnected or removed library drives.
        if (-not (Test-Path -LiteralPath $library -PathType Container -ErrorAction SilentlyContinue)) { continue }
        $candidate = [IO.Path]::Combine($library, 'steamapps\common\Frosthaven')
        if (Test-Path -LiteralPath ([IO.Path]::Combine($candidate, 'Frosthaven.exe')) -PathType Leaf -ErrorAction SilentlyContinue) { $candidate }
    }
}
function Find-Game([string]$GamePath) {
    if ($GamePath) { return (Resolve-Path -LiteralPath $GamePath).Path }
    $info = Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue
    $steam = if ($info) { $info.SteamPath } else { $null }
    $libraries = @($steam)
    if ($steam -and (Test-Path -LiteralPath ([IO.Path]::Combine($steam, 'steamapps\libraryfolders.vdf')) -PathType Leaf -ErrorAction SilentlyContinue)) {
        foreach ($match in [regex]::Matches([IO.File]::ReadAllText([IO.Path]::Combine($steam, 'steamapps\libraryfolders.vdf')), '"path"\s+"([^"]+)"')) {
            $libraries += $match.Groups[1].Value.Replace('\\', '\')
        }
    }
    $games = @(Find-SteamGames $libraries)
    if ($games.Count -eq 1) { return $games[0] }
    return (Resolve-Path -LiteralPath (Read-Host 'Frosthaven.exe folder')).Path
}
function Assert-Closed {
    if (Get-Process Frosthaven -ErrorAction SilentlyContinue) { throw 'Close Frosthaven before changing the patch.' }
}
function Hash-File([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
