# RoboCop Installer v1.0.0-RC4 | Author: Joe "Gambit" Bradford
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Discovery.ps1')
. (Join-Path $PSScriptRoot 'Runtime.ps1')

function Get-RcpHash([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-RcpNoLinks([string]$Path) {
    $p = [IO.Path]::GetFullPath($Path)
    while ($p) {
        if (Test-Path -LiteralPath $p) {
            if (((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Linked folder/file requires manual installation: $p"
            }
        }
        $parent = [IO.Directory]::GetParent($p)
        if ($null -eq $parent) { break }
        $p = $parent.FullName
    }
}

function Assert-RcpTree([string]$Path) {
    Assert-RcpNoLinks $Path
    if (Test-Path -LiteralPath $Path -PathType Container) {
        foreach ($file in Get-ChildItem -LiteralPath $Path -Force -Recurse) {
            if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Linked content requires manual installation: $($file.FullName)" }
        }
    }
}

function Get-RcpLayout($Game) {
    $root = Join-RcpPath $Game.Bin 'ue4ss'
    $nestedDll = Join-RcpPath $root 'UE4SS.dll'
    $flatDll = Join-RcpPath $Game.Bin 'UE4SS.dll'
    $hasNested = [IO.File]::Exists($nestedDll)
    $hasFlat = [IO.File]::Exists($flatDll)
    if ($env:UE4SS_MODS_PATHS) { throw 'A custom UE4SS_MODS_PATHS setting is active. Clear that override before using the standard automatic installation.' }
    $ini = Join-RcpPath $root 'UE4SS-settings.ini'
    $legacyIni = Join-RcpPath $Game.Bin 'UE4SS-settings.ini'
    $migrateLegacy = $hasFlat -or (-not $hasNested -and [IO.File]::Exists($legacyIni))
    if ($migrateLegacy -and -not [IO.File]::Exists($ini) -and [IO.File]::Exists($legacyIni)) { $ini = $legacyIni }
    if ([IO.File]::Exists($ini)) {
        $text = [IO.File]::ReadAllText($ini)
        if ($text -match '(?im)^[ \t]*(?:ModsFolderPath|[+-]?ModsFolderPaths|ControllingModsTxt)[ \t]*=[ \t]*[^\s;\r\n][^\r\n]*') { throw 'Custom UE4SS mod locations/load lists detected. Existing settings were preserved; the standard installation cannot override them.' }
    }
    $mods = Join-RcpPath $root 'Mods'
    $legacyMods = Join-RcpPath $Game.Bin 'Mods'
    $activeFolders = @($mods)
    if ($migrateLegacy) { $activeFolders += $legacyMods }
    foreach ($folder in $activeFolders) {
        $list = Join-RcpPath $folder 'mods.txt'
        if ([IO.File]::Exists($list) -and [IO.File]::ReadAllText($list) -match '(?im)^\s*RoboCopGameplay\s*:\s*0\b') { throw 'The existing mods.txt explicitly disables RoboCopGameplay. Resolve that explicit disable before installing.' }
        $list = Join-RcpPath $folder 'mods.json'
        if ([IO.File]::Exists($list)) {
            foreach ($entry in (Get-Content -LiteralPath $list -Raw | ConvertFrom-Json)) {
                if ($entry.mod_name -eq 'RoboCopGameplay' -and -not $entry.mod_enabled) { throw 'The existing mods.json explicitly disables RoboCopGameplay.' }
            }
        }
    }
    return [pscustomobject]@{Fresh=(-not $hasNested -and -not $hasFlat); Root=$root; Mods=$mods; LegacyDll=$flatDll; LegacyMods=$legacyMods; MigrateLegacy=$migrateLegacy; SettingsSource=$ini}
}

function Assert-RcpPayload([string]$Package, $Manifest) {
    $expected = @('Payload/RoboCopGameplay/Scripts/main.lua','Payload/RoboCopGameplay/robocop_native.dll','Payload/RoboCopGameplay/enabled.txt','Runtime/dwmapi.dll','Runtime/ue4ss/UE4SS.dll','Runtime/ue4ss/UE4SS-settings.ini','Runtime/ue4ss/LICENSE')
    foreach ($stem in @('RoboCop_Worker02_P','zz_RoboCop_Portrait_P')) {
        foreach ($extension in @('pak','utoc','ucas')) { $expected += "Payload/Paks/$stem.$extension" }
    }
    $paths = @($Manifest.files | ForEach-Object {$_.path})
    if ($paths.Count -ne $expected.Count -or @($paths | Sort-Object -Unique).Count -ne $expected.Count) { throw 'The installer manifest does not contain the expected payload.' }
    foreach ($f in $Manifest.files) {
        if ($expected -cnotcontains $f.path) { throw 'Invalid payload path in manifest.' }
        $p = Join-RcpPath $Package $f.path
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "Missing package file: $($f.path). Extract the entire ZIP first." }
        if ((Get-Item -LiteralPath $p).Length -ne $f.size -or (Get-RcpHash $p) -ne $f.sha256) { throw "Package integrity check failed: $($f.path). Download and extract a fresh copy." }
    }
}

function Add-RcpFileOperation($Ops,[string]$Source,[string]$Target,[string]$Stage,[string]$ExpectedHash='') {
    if (-not $ExpectedHash) { $ExpectedHash = Get-RcpHash $Source }
    if ([IO.File]::Exists($Target) -and (Get-RcpHash $Target) -eq $ExpectedHash) { return }
    $staged = Join-RcpPath $Stage ('file_' + $Ops.Count)
    Copy-RcpBytes $Source $staged
    if ((Get-RcpHash $staged) -ne $ExpectedHash) { throw "Source changed while staging: $Source" }
    $Ops.Add([pscustomobject]@{Source=$staged; Target=$Target; Hash=$ExpectedHash})
}

function Invoke-RcpInstall([string]$Package, $Game, $Manifest) {
    if (Get-Process -Name 'PoliceChiefSimulator*' -ErrorAction SilentlyContinue) { throw 'Close Police Chief Simulator completely before installing.' }
    Assert-RcpNoLinks $Game.Project
    if ((Get-RcpHash $Game.Exe) -ne $Manifest.gameSha256) { throw 'This game executable differs from the tested RoboCop build. Installation stopped before modifying the game. Ask the mod author for a compatible update.' }
    Assert-RcpPayload $Package $Manifest
    $layout = Get-RcpLayout $Game
    $backupRoot = Join-RcpPath $Game.Project 'RoboCop_Installer_Backups'
    Assert-RcpNoLinks $backupRoot
    $backup = Join-RcpPath $backupRoot ((Get-Date -Format 'yyyyMMdd_HHmmss_fff') + '_' + [guid]::NewGuid().ToString('N').Substring(0,8))
    $ops = [Collections.Generic.List[object]]::new()
    $stage = Join-RcpPath ([IO.Path]::GetTempPath()) ('RoboCopInstall_' + [guid]::NewGuid().ToString('N'))
    $done = [Collections.Generic.List[object]]::new()
    try {
        [IO.Directory]::CreateDirectory($stage) | Out-Null
        $runtime = Resolve-RcpRuntime $Package $Manifest $stage
        $runtimeChanged = $false
        foreach ($file in $runtime.Files) {
            $destination = Join-RcpPath $Game.Bin $file.Name
            if ($file.Name -eq 'ue4ss/UE4SS-settings.ini' -and [IO.File]::Exists($layout.SettingsSource)) {
                Add-RcpFileOperation $ops $layout.SettingsSource $destination $stage
            } else {
                $before = $ops.Count
                Add-RcpFileOperation $ops $file.Source $destination $stage $file.Hash
                if ($ops.Count -gt $before -and $file.Name -in @('ue4ss/UE4SS.dll','dwmapi.dll')) { $runtimeChanged = $true }
            }
        }
        if ($runtimeChanged) { Write-Host "Installing/updating UE4SS experimental $($runtime.Version) and its loader." }
        else { Write-Host "UE4SS experimental $($runtime.Version) and dwmapi.dll already match; keeping them." }
        if ($layout.MigrateLegacy -and [IO.Directory]::Exists($layout.LegacyMods)) {
            Assert-RcpTree $layout.LegacyMods
            foreach ($file in @(Get-ChildItem -LiteralPath $layout.LegacyMods -File -Recurse -Force)) {
                $rel = $file.FullName.Substring($layout.LegacyMods.Length + 1).Replace('\','/')
                if ($rel -match '^RoboCopGameplay/') { continue }
                $destination = Join-RcpPath $layout.Mods $rel
                if ([IO.File]::Exists($destination)) {
                    if ($rel -in @('mods.txt','mods.json') -and (Get-RcpHash $file.FullName) -ne (Get-RcpHash $destination)) { throw 'Legacy and nested UE4SS load lists conflict. Both originals were preserved; reconcile them before installing.' }
                    continue
                }
                Add-RcpFileOperation $ops $file.FullName $destination $stage
            }
        }
        foreach ($name in @('UE4SS_Signatures','UE4SS_Custom','UE4SS_SDK_Backends')) {
            if (-not $layout.MigrateLegacy) { break }
            $old = Join-RcpPath $Game.Bin $name
            if (-not [IO.Directory]::Exists($old)) { continue }
            Assert-RcpTree $old
            foreach ($file in @(Get-ChildItem -LiteralPath $old -File -Recurse -Force)) {
                $rel = $file.FullName.Substring($Game.Bin.Length + 1)
                $dest = Join-RcpPath $layout.Root $rel
                if (-not [IO.File]::Exists($dest)) { Add-RcpFileOperation $ops $file.FullName $dest $stage }
            }
        }
        foreach ($name in @('UE4SS-local-settings.ini','MemberVariableLayout.ini','VTableLayout.ini')) {
            if (-not $layout.MigrateLegacy) { break }
            $old = Join-RcpPath $Game.Bin $name
            $dest = Join-RcpPath $layout.Root $name
            if ([IO.File]::Exists($old) -and -not [IO.File]::Exists($dest)) { Add-RcpFileOperation $ops $old $dest $stage }
        }
        if ([IO.File]::Exists($layout.LegacyDll)) { $ops.Add([pscustomobject]@{Source=$null; Target=$layout.LegacyDll; Hash=$null}) }
        $stageMod = Join-RcpPath $stage 'RoboCopGameplay'
        foreach ($f in @($Manifest.files | Where-Object {$_.path.StartsWith('Payload/RoboCopGameplay/')})) {
            $dest = Join-RcpPath $stageMod $f.path.Substring('Payload/RoboCopGameplay/'.Length)
            Copy-RcpBytes (Join-RcpPath $Package $f.path) $dest
            if ((Get-RcpHash $dest) -ne $f.sha256) { throw "Source changed while staging: $($f.path)" }
        }
        $ops.Add([pscustomobject]@{Source=$stageMod; Target=(Join-RcpPath $layout.Mods 'RoboCopGameplay'); Hash=$null})
        foreach ($f in @($Manifest.files | Where-Object {$_.path.StartsWith('Payload/Paks/')})) {
            $name = [IO.Path]::GetFileName($f.path)
            $destination = Join-RcpPath $Game.Paks ('~mods/' + $name)
            foreach ($existing in @(Get-ChildItem -LiteralPath $Game.Paks -File -Recurse -Force | Where-Object {$_.Name -eq $name})) {
                if ([IO.Path]::GetFullPath($existing.FullName) -ne [IO.Path]::GetFullPath($destination)) {
                    $ops.Add([pscustomobject]@{Source=$null; Target=$existing.FullName; Hash=$null})
                }
            }
            Add-RcpFileOperation $ops (Join-RcpPath $Package $f.path) $destination $stage $f.sha256
        }
        foreach ($op in $ops) {
            Assert-RcpTree $op.Target
            if ($op.Source -and (Test-Path -LiteralPath $op.Target)) {
                if ((Get-Item -LiteralPath $op.Target -Force).PSIsContainer -ne (Get-Item -LiteralPath $op.Source).PSIsContainer) { throw "Unexpected file/folder type at destination: $($op.Target)" }
            }
        }
        if (Get-Process -Name 'PoliceChiefSimulator*' -ErrorAction SilentlyContinue) { throw 'Police Chief Simulator was started during installation. Close it and run the installer again; no game files have been changed.' }
        [IO.Directory]::CreateDirectory($backup) | Out-Null
        $runtime | Select-Object Version,Source,ArchiveHash,OnlineChecked | ConvertTo-Json | Set-Content -LiteralPath (Join-RcpPath $backup 'ue4ss-runtime.json') -Encoding UTF8
        $i = 0
        foreach ($op in $ops) {
            $saved = Join-RcpPath $backup ('original_' + $i)
            $had = Test-Path -LiteralPath $op.Target
            if ($had) { Copy-Item -LiteralPath $op.Target -Destination $saved -Recurse -Force }
            $record = [pscustomobject]@{Target=$op.Target; Backup=$saved; HadOriginal=$had; Installed=$null -ne $op.Source}
            $done.Add($record)
            $done.ToArray() | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-RcpPath $backup 'receipt.json') -Encoding UTF8
            if ($had) { Remove-Item -LiteralPath $op.Target -Recurse -Force }
            if ($null -ne $op.Source) {
                [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($op.Target)) | Out-Null
                Copy-Item -LiteralPath $op.Source -Destination $op.Target -Recurse -Force
            }
            $i++
        }
        foreach ($op in $ops) {
            if ($op.Hash -and (Get-RcpHash $op.Target) -ne $op.Hash) { throw "Installed-file verification failed: $($op.Target)" }
        }
        foreach ($file in $runtime.Files) {
            if ($file.Name -eq 'ue4ss/UE4SS-settings.ini') { continue }
            if ((Get-RcpHash (Join-RcpPath $Game.Bin $file.Name)) -ne $file.Hash) { throw "UE4SS verification failed: $($file.Name)" }
        }
        foreach ($f in $Manifest.files) {
            $dest = $null
            if ($f.path.StartsWith('Payload/Paks/')) { $dest = Join-RcpPath $Game.Paks ('~mods/' + [IO.Path]::GetFileName($f.path)) }
            elseif ($f.path.StartsWith('Payload/RoboCopGameplay/')) { $dest = Join-RcpPath $layout.Mods $f.path.Substring('Payload/'.Length) }
            if ($dest -and (Get-RcpHash $dest) -ne $f.sha256) { throw "Installed-file verification failed: $dest" }
        }
        'Installation completed and file hashes verified.' | Set-Content -LiteralPath (Join-RcpPath $backup 'SUCCESS.txt')
        return [pscustomobject]@{Backup=$backup; FreshUE4SS=$layout.Fresh; UpdatedUE4SS=$runtimeChanged; UE4SSVersion=$runtime.Version; OnlineChecked=$runtime.OnlineChecked; Mods=$layout.Mods}
    } catch {
        $failure = $_
        $rollbackErrors = [Collections.Generic.List[string]]::new()
        for ($j = $done.Count - 1; $j -ge 0; $j--) {
            $r = $done[$j]
            try {
                if (Test-Path -LiteralPath $r.Target) { Remove-Item -LiteralPath $r.Target -Recurse -Force }
                if ($r.HadOriginal) { Copy-Item -LiteralPath $r.Backup -Destination $r.Target -Recurse -Force }
            } catch { $rollbackErrors.Add($_.Exception.Message) }
        }
        if ($rollbackErrors.Count) { throw "Installation failed: $failure. Automatic restore was incomplete. Preserve backups at $backup. Restore errors: $($rollbackErrors -join '; ')" }
        if ($done.Count -eq 0) { throw $failure }
        throw "Installation failed; changed files were restored: $failure"
    } finally {
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
