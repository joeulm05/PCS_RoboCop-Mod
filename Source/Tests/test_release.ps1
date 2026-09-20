# RoboCop Release Installation Test | Author: Joe "Gambit" Bradford
param([Parameter(Mandatory=$true)][string]$GameExe)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$package = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
. (Join-Path $package 'Installer/Core.ps1')
$root = Join-RcpPath ([IO.Path]::GetTempPath()) ('RcpRelease_' + [guid]::NewGuid().ToString('N'))
$project = Join-RcpPath $root "SteamLibrary/steamapps/common/Police Chief Simulator/PoliceChiefSimulator"
$bin = Join-RcpPath $project 'Binaries/Win64'
$paks = Join-RcpPath $project 'Content/Paks'
$manifest = Get-Content -LiteralPath (Join-RcpPath $package 'Installer/manifest.json') -Raw | ConvertFrom-Json
try {
    [IO.Directory]::CreateDirectory($bin) | Out-Null
    [IO.Directory]::CreateDirectory($paks) | Out-Null
    Copy-Item -LiteralPath $GameExe -Destination (Join-RcpPath $bin 'PoliceChiefSimulator-Win64-Shipping.exe')
    [IO.File]::WriteAllText((Join-RcpPath $paks 'PoliceChiefSimulator-Windows.pak'),'base-game-fixture')
    $found = @(Find-RcpLibraryGames @((Join-RcpPath $root 'SteamLibrary')))
    if ($found.Count -ne 1) { throw 'Full release fixture was not auto-detected.' }
    $game = Resolve-RcpGame $found[0]
    $first = Invoke-RcpInstall $package $game $manifest
    if (-not $first.FreshUE4SS) { throw 'Fresh runtime was not installed.' }
    $runtimeRoot = Split-Path -Parent $first.Mods
    $dll = Join-RcpPath $runtimeRoot 'UE4SS.dll'
    $ini = Join-RcpPath $runtimeRoot 'UE4SS-settings.ini'
    $proxy = Join-RcpPath $bin 'dwmapi.dll'
    $before = @((Get-RcpHash $dll),(Get-RcpHash $ini),(Get-RcpHash $proxy))
    $other = Join-RcpPath $first.Mods 'OtherMod/Scripts/main.lua'
    [IO.Directory]::CreateDirectory((Split-Path -Parent $other)) | Out-Null
    [IO.File]::WriteAllText($other,'preserve-other-mod')
    $loadList = Join-RcpPath $first.Mods 'mods.txt'
    [IO.File]::WriteAllText($loadList,'OtherMod : 1')
    Remove-Item -LiteralPath (Join-RcpPath $first.Mods 'RoboCopGameplay') -Recurse
    foreach ($asset in @($manifest.files | Where-Object {$_.path.StartsWith('Payload/Paks/')})) {
        Remove-Item -LiteralPath (Join-RcpPath $paks ('~mods/' + [IO.Path]::GetFileName($asset.path)))
    }
    $second = Invoke-RcpInstall $package (Resolve-RcpGame (Join-RcpPath $runtimeRoot 'Mods')) $manifest
    if ($second.FreshUE4SS) { throw 'Existing runtime was replaced.' }
    $after = @((Get-RcpHash $dll),(Get-RcpHash $ini),(Get-RcpHash $proxy))
    if (($before -join ',') -cne ($after -join ',')) { throw 'Existing UE4SS files changed.' }
    if ([IO.File]::ReadAllText($other) -cne 'preserve-other-mod') { throw 'Other mod changed.' }
    if ([IO.File]::ReadAllText($loadList) -cne 'OtherMod : 1') { throw 'Load list changed.' }
    if ([IO.File]::ReadAllText((Join-RcpPath $paks 'PoliceChiefSimulator-Windows.pak')) -cne 'base-game-fixture') { throw 'Base game asset changed.' }
    [IO.File]::WriteAllText($dll,'outdated-runtime-fixture')
    [IO.File]::WriteAllText($proxy,'outdated-loader-fixture')
    $third = Invoke-RcpInstall $package $game $manifest
    if (-not $third.UpdatedUE4SS) { throw 'Older runtime was not updated.' }
    $updated = @((Get-RcpHash $dll),(Get-RcpHash $ini),(Get-RcpHash $proxy))
    if (($before -join ',') -cne ($updated -join ',')) { throw 'Runtime update did not produce expected binaries while preserving settings.' }
    if ([IO.File]::ReadAllText($other) -cne 'preserve-other-mod' -or [IO.File]::ReadAllText($loadList) -cne 'OtherMod : 1') { throw 'Runtime update changed other mods or load list.' }
    Write-Host 'PASS: actual release payload; fresh runtime; RoboCop reinstall with matching runtime retained; outdated runtime and loader updated; settings, other mod and load list preserved.'
} finally { if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force } }
