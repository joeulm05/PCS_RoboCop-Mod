# RoboCop Installer Tests | Author: Joe "Gambit" Bradford
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$package = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
. (Join-Path $package 'Installer/Core.ps1')
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('RcpTests_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$env:UE4SS_MODS_PATHS = $null
$script:passed = 0
$script:testAsset = [pscustomobject]@{name='UE4SS_v3.0.1-9999-gabcdef01.zip'; id=1; created_at='2026-09-20T00:00:00Z'; digest=('sha256:' + ('a' * 64)); size=100; browser_download_url='https://github.com/UE4SS-RE/RE-UE4SS/releases/download/experimental/UE4SS_v3.0.1-9999-gabcdef01.zip'}
function Get-RcpExperimentalRelease { return [pscustomobject]@{assets=@($script:testAsset)} }
function Assert-RcpCompatibility([string]$Package, $Game) { if ([IO.File]::ReadAllText($Game.Exe) -ne 'test-executable') { throw 'Fixture gameplay functions incompatible' } }
function Assert-Equal($a,$b,[string]$label) {
    if ($a -cne $b) { throw "FAILED: $label | actual=$a expected=$b" }
}
function Write-Fixture([string]$path,[string]$value) {
    [IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
    [IO.File]::WriteAllText($path,$value)
}
function New-Fixture([string]$name,[string]$layout='fresh') {
    $base = Join-Path $testRoot $name
    $project = Join-Path $base "Game [A] & Joe's !/PoliceChiefSimulator"
    Write-Fixture (Join-Path $project 'Binaries/Win64/PoliceChiefSimulator-Win64-Shipping.exe') 'test-executable'
    Write-Fixture (Join-Path $project 'Content/Paks/PoliceChiefSimulator-Windows.pak') 'vanilla'
    $game = Resolve-RcpGame $project
    $runtimeRoot = Join-Path $game.Bin 'ue4ss'
    if ($layout -eq 'legacy') { $runtimeRoot = $game.Bin }
    if ($layout -ne 'fresh') {
        Write-Fixture (Join-Path $runtimeRoot 'UE4SS.dll') 'existing-runtime'
        Write-Fixture (Join-Path $runtimeRoot 'UE4SS-settings.ini') "[Overrides]`nModsFolderPath =`nControllingModsTxt =`n[Debug]`nConsoleEnabled = 1`n"
        Write-Fixture (Join-Path $runtimeRoot 'Mods/OtherMod/Scripts/main.lua') 'other-mod'
        Write-Fixture (Join-Path $runtimeRoot 'Mods/mods.txt') 'OtherMod : 1'
        Write-Fixture (Join-Path $runtimeRoot 'Mods/mods.json') '[{"mod_name":"OtherMod","mod_enabled":true}]'
        Write-Fixture (Join-Path $runtimeRoot 'Mods/RoboCopGameplay/Scripts/main.lua') 'old-robo'
        Write-Fixture (Join-Path $runtimeRoot 'Mods/RoboCopGameplay/old-extra.lua') 'old-extra'
        Write-Fixture (Join-Path $runtimeRoot 'Mods/RoboCopGameplay/targets.txt') "1 2 3 4`n"
        Write-Fixture (Join-Path $game.Bin 'dwmapi.dll') 'existing-proxy'
    }
    $payload = Join-Path $base 'Package'
    foreach ($path in @('Payload/RoboCopGameplay/Scripts/main.lua','Payload/RoboCopGameplay/robocop_native.dll','Payload/RoboCopGameplay/enabled.txt','Runtime/ue4ss/UE4SS.dll','Runtime/ue4ss/UE4SS-settings.ini','Runtime/ue4ss/LICENSE','Runtime/dwmapi.dll')) {
        Write-Fixture (Join-Path $payload $path) ('fixture-' + $path)
    }
    foreach ($stem in @('RoboCop_Worker02_P','zz_RoboCop_Portrait_P')) {
        foreach ($ext in @('pak','utoc','ucas')) { Write-Fixture (Join-Path $payload "Payload/Paks/$stem.$ext") "fixture-$stem.$ext" }
    }
    $files = @(Get-ChildItem -LiteralPath $payload -Recurse -File | ForEach-Object {
        [pscustomobject]@{path=$_.FullName.Substring($payload.Length+1).Replace('\','/'); sha256=(Get-RcpHash $_.FullName); size=$_.Length}
    })
    $manifest = [pscustomobject]@{gameSha256=(Get-RcpHash $game.Exe); ue4ssVersion='3.0.1-9999-gabcdef01'; ue4ssSource=$script:testAsset.browser_download_url; ue4ssArchiveSha256=('a' * 64); files=$files}
    return [pscustomobject]@{Game=$game; Package=$payload; Manifest=$manifest; Runtime=$runtimeRoot}
}
function Expect-Failure($Fixture,[string]$pattern) {
    try { Invoke-RcpInstall $Fixture.Package $Fixture.Game $Fixture.Manifest | Out-Null; throw 'DID_NOT_FAIL' }
    catch { if ($_.Exception.Message -notmatch $pattern) { throw } }
}
try {
    foreach ($layout in @('fresh','nested','legacy')) {
        $f = New-Fixture $layout $layout
        $before = $null
        if ($layout -ne 'fresh') { $before = Get-RcpHash (Join-Path $f.Runtime 'UE4SS-settings.ini') }
        $r = Invoke-RcpInstall $f.Package $f.Game $f.Manifest
        Assert-Equal $r.FreshUE4SS ($layout -eq 'fresh') "$layout runtime decision"
        Assert-Equal ([IO.File]::ReadAllText((Join-Path $r.Mods 'RoboCopGameplay/Scripts/main.lua'))) 'fixture-Payload/RoboCopGameplay/Scripts/main.lua' "$layout gameplay"
        Assert-Equal (Test-Path -LiteralPath (Join-Path $r.Mods 'RoboCopGameplay/enabled.txt')) $true "$layout automatic mod enable"
        Assert-Equal ([IO.File]::ReadAllText((Join-Path $f.Game.Paks '~mods/zz_RoboCop_Portrait_P.ucas'))) 'fixture-zz_RoboCop_Portrait_P.ucas' "$layout portrait"
        Assert-Equal ([IO.File]::ReadAllText((Join-Path $f.Game.Paks 'PoliceChiefSimulator-Windows.pak'))) 'vanilla' "$layout vanilla"
        if ($layout -ne 'fresh') {
            Assert-Equal ([IO.File]::ReadAllText((Join-Path $f.Game.Bin 'dwmapi.dll'))) 'fixture-Runtime/dwmapi.dll' "$layout loader updated"
            Assert-Equal (Get-RcpHash (Join-Path (Split-Path -Parent $r.Mods) 'UE4SS-settings.ini')) $before "$layout settings preserved"
            Assert-Equal ([IO.File]::ReadAllText((Join-Path (Split-Path -Parent $r.Mods) 'UE4SS.dll'))) 'fixture-Runtime/ue4ss/UE4SS.dll' "$layout runtime updated"
            Assert-Equal ([IO.File]::ReadAllText((Join-Path $r.Mods 'OtherMod/Scripts/main.lua'))) 'other-mod' "$layout other mod"
            Assert-Equal ([IO.File]::ReadAllText((Join-Path $r.Mods 'mods.txt'))) 'OtherMod : 1' "$layout load list"
            Assert-Equal (Test-Path -LiteralPath (Join-Path $r.Mods 'RoboCopGameplay/old-extra.lua')) $false "$layout stale scripts removed"
            Assert-Equal ([IO.File]::ReadAllText((Join-Path $r.Mods 'RoboCopGameplay/targets.txt'))) "1 2 3 4`n" "$layout target IDs preserved"
            $originalTarget = Join-Path $r.Mods 'RoboCopGameplay'
            if ($layout -eq 'legacy') {
                Assert-Equal (Test-Path -LiteralPath (Join-Path $f.Game.Bin 'UE4SS.dll')) $false 'legacy DLL retired'
                Assert-Equal ([IO.File]::ReadAllText((Join-Path $f.Runtime 'Mods/RoboCopGameplay/old-extra.lua'))) 'old-extra' 'inactive legacy files preserved'
            } else {
                $receipt = @(Get-Content -LiteralPath (Join-Path $r.Backup 'receipt.json') -Raw | ConvertFrom-Json | Where-Object {$_.Target -eq $originalTarget})
                Assert-Equal ([IO.File]::ReadAllText((Join-Path $receipt[0].Backup 'old-extra.lua'))) 'old-extra' "$layout backup"
            }
        } else {
            Assert-Equal ([IO.File]::ReadAllText((Join-Path $f.Game.Bin 'dwmapi.dll'))) 'fixture-Runtime/dwmapi.dll' 'fresh loader'
            Assert-Equal ([IO.File]::ReadAllText((Join-Path $f.Runtime 'UE4SS.dll'))) 'fixture-Runtime/ue4ss/UE4SS.dll' 'fresh UE4SS'
            Assert-Equal ([IO.File]::ReadAllText((Join-Path $f.Runtime 'UE4SS-settings.ini'))) 'fixture-Runtime/ue4ss/UE4SS-settings.ini' 'fresh settings'
        }
        $repeat = Invoke-RcpInstall $f.Package $f.Game $f.Manifest
        Assert-Equal $repeat.UpdatedUE4SS $false 'matching experimental runtime kept'
        if ($layout -eq 'legacy') {
            Write-Fixture (Join-Path $f.Game.Bin 'Mods/StaleMod/Scripts/main.lua') 'inactive-legacy-mod'
            Write-Fixture (Join-Path $f.Game.Bin 'Mods/mods.txt') 'RoboCopGameplay : 0'
            Invoke-RcpInstall $f.Package $f.Game $f.Manifest | Out-Null
            Assert-Equal (Test-Path -LiteralPath (Join-Path $r.Mods 'StaleMod')) $false 'inactive legacy mods not reimported'
        }
        $script:passed++
    }
    $f = New-Fixture 'duplicates' 'nested'
    Write-Fixture (Join-Path $f.Game.Paks 'zz_RoboCop_Portrait_P.ucas') 'old-root-portrait'
    Write-Fixture (Join-Path $f.Game.Paks '~old/RoboCop_Worker02_P.pak') 'old-duplicate'
    $r = Invoke-RcpInstall $f.Package $f.Game $f.Manifest
    Assert-Equal (Test-Path -LiteralPath (Join-Path $f.Game.Paks 'zz_RoboCop_Portrait_P.ucas')) $false 'root duplicate removed'
    Assert-Equal (@(Get-ChildItem -LiteralPath $f.Game.Paks -Recurse -File | Where-Object {$_.Name -eq 'RoboCop_Worker02_P.pak'}).Count) 1 'one model pak'
    $script:passed++
    $f = New-Fixture 'corrupt'
    Write-Fixture (Join-Path $f.Package 'Payload/Paks/RoboCop_Worker02_P.ucas') 'corrupt'
    Expect-Failure $f 'integrity check'
    Assert-Equal (Test-Path -LiteralPath $f.Runtime) $false 'corruption made no install'
    $script:passed++
    $f = New-Fixture 'wrong-build'
    Write-Fixture $f.Game.Exe 'different-game'
    Expect-Failure $f 'gameplay functions incompatible'
    $script:passed++
    $f = New-Fixture 'proxy'
    Write-Fixture (Join-Path $f.Game.Bin 'dwmapi.dll') 'another-proxy'
    $r = Invoke-RcpInstall $f.Package $f.Game $f.Manifest
    Assert-Equal ([IO.File]::ReadAllText((Join-Path $f.Game.Bin 'dwmapi.dll'))) 'fixture-Runtime/dwmapi.dll' 'loader installed automatically'
    $proxyBackup = @(Get-Content -LiteralPath (Join-Path $r.Backup 'receipt.json') -Raw | ConvertFrom-Json | Where-Object {$_.Target -eq (Join-Path $f.Game.Bin 'dwmapi.dll')})
    Assert-Equal ([IO.File]::ReadAllText($proxyBackup[0].Backup)) 'another-proxy' 'previous proxy backed up'
    $script:passed++
    $f = New-Fixture 'custom' 'nested'
    Write-Fixture (Join-Path $f.Runtime 'UE4SS-settings.ini') "[Overrides]`nModsFolderPath = D:/CustomMods"
    Expect-Failure $f 'Custom UE4SS'
    $script:passed++
    $f = New-Fixture 'disabled' 'nested'
    Write-Fixture (Join-Path $f.Runtime 'Mods/mods.txt') 'RoboCopGameplay : 0'
    Expect-Failure $f 'explicitly disables'
    $script:passed++
    $f = New-Fixture 'dual' 'nested'
    Write-Fixture (Join-Path $f.Game.Bin 'UE4SS.dll') 'duplicate'
    Invoke-RcpInstall $f.Package $f.Game $f.Manifest | Out-Null
    Assert-Equal (Test-Path -LiteralPath (Join-Path $f.Game.Bin 'UE4SS.dll')) $false 'duplicate flat DLL retired'
    $script:passed++
    $f = New-Fixture 'rollback' 'nested'
    Write-Fixture (Join-Path $f.Game.Paks '~mods/RoboCop_Worker02_P.pak') 'old-model'
    $script:failTarget = Join-Path $f.Game.Paks '~mods/zz_RoboCop_Portrait_P.ucas'
    $script:failOnce = $true
    function Copy-Item {
        param([string]$LiteralPath,[string]$Destination,[switch]$Recurse,[switch]$Force)
        if ($script:failOnce -and $Destination -eq $script:failTarget) { $script:failOnce=$false; throw 'SIMULATED_COPY_FAILURE' }
        Microsoft.PowerShell.Management\Copy-Item @PSBoundParameters
    }
    Expect-Failure $f 'SIMULATED_COPY_FAILURE'
    Remove-Item Function:Copy-Item
    Assert-Equal ([IO.File]::ReadAllText((Join-Path $f.Runtime 'Mods/RoboCopGameplay/Scripts/main.lua'))) 'old-robo' 'rollback gameplay'
    Assert-Equal ([IO.File]::ReadAllText((Join-Path $f.Runtime 'Mods/RoboCopGameplay/old-extra.lua'))) 'old-extra' 'rollback extra'
    Assert-Equal ([IO.File]::ReadAllText((Join-Path $f.Game.Paks '~mods/RoboCop_Worker02_P.pak'))) 'old-model' 'rollback model'
    Assert-Equal (Test-Path -LiteralPath (Join-Path $f.Game.Paks '~mods/zz_RoboCop_Portrait_P.pak')) $false 'rollback new file removed'
    Assert-Equal ([IO.File]::ReadAllText((Join-Path $f.Runtime 'UE4SS.dll'))) 'existing-runtime' 'rollback previous runtime restored'
    Assert-Equal ([IO.File]::ReadAllText((Join-Path $f.Game.Bin 'dwmapi.dll'))) 'existing-proxy' 'rollback previous loader restored'
    $script:passed++
    $f = New-Fixture 'fresh-rollback'
    $script:failTarget = Join-Path $f.Game.Paks '~mods/zz_RoboCop_Portrait_P.ucas'
    $script:failOnce = $true
    function Copy-Item {
        param([string]$LiteralPath,[string]$Destination,[switch]$Recurse,[switch]$Force)
        if ($script:failOnce -and $Destination -eq $script:failTarget) { $script:failOnce=$false; throw 'SIMULATED_FRESH_FAILURE' }
        Microsoft.PowerShell.Management\Copy-Item @PSBoundParameters
    }
    Expect-Failure $f 'SIMULATED_FRESH_FAILURE'
    Remove-Item Function:Copy-Item
    Assert-Equal (Test-Path -LiteralPath (Join-Path $f.Runtime 'UE4SS.dll')) $false 'fresh rollback runtime removed'
    Assert-Equal (Test-Path -LiteralPath (Join-Path $f.Game.Bin 'dwmapi.dll')) $false 'fresh rollback loader removed'
    Assert-Equal (Test-Path -LiteralPath (Join-Path $f.Game.Paks '~mods/RoboCop_Worker02_P.ucas')) $false 'fresh rollback mod assets removed'
    Assert-Equal ([IO.File]::ReadAllText((Join-Path $f.Game.Paks 'PoliceChiefSimulator-Windows.pak'))) 'vanilla' 'fresh rollback base game preserved'
    $script:passed++
    $f = New-Fixture 'entrypoint' 'nested'
    Copy-Item -LiteralPath (Join-Path $package 'Installer') -Destination (Join-Path $f.Package 'Installer') -Recurse
    $f.Manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $f.Package 'Installer/manifest.json') -Encoding UTF8
    $mock = "`nfunction Get-RcpExperimentalRelease { return [pscustomobject]@{assets=@([pscustomobject]@{name='UE4SS_v3.0.1-9999-gabcdef01.zip'; id=1; created_at='2026-09-20T00:00:00Z'; digest=('sha256:' + ('a' * 64)); size=100; browser_download_url='https://github.com/UE4SS-RE/RE-UE4SS/releases/download/experimental/UE4SS_v3.0.1-9999-gabcdef01.zip'})} }"
    Add-Content -LiteralPath (Join-Path $f.Package 'Installer/Runtime.ps1') -Value $mock
    Add-Content -LiteralPath (Join-Path $f.Package 'Installer/Compatibility.ps1') -Value ([Environment]::NewLine + 'function Assert-RcpCompatibility {' + ${function:Assert-RcpCompatibility}.ToString() + '}')
    $oldSelected = $env:RCP_SELECTED_PATH
    try {
        $env:RCP_SELECTED_PATH = $f.Game.Exe
        $engine = (Get-Process -Id $PID).Path
        $output = & $engine -NoLogo -NoProfile -File (Join-Path $f.Package 'Installer/Install.ps1') 2>&1
        Assert-Equal $LASTEXITCODE 0 ('entrypoint success: ' + ($output -join "`n"))
        if (($output -join "`n") -notmatch 'SUCCESS - RoboCop') { throw 'Entrypoint did not report success.' }
        Assert-Equal ([IO.File]::ReadAllText((Join-Path $f.Runtime 'UE4SS.dll'))) 'fixture-Runtime/ue4ss/UE4SS.dll' 'entrypoint updated UE4SS'
        Assert-Equal ([IO.File]::ReadAllText((Join-Path $f.Game.Paks '~mods/zz_RoboCop_Portrait_P.ucas'))) 'fixture-zz_RoboCop_Portrait_P.ucas' 'entrypoint installed portrait'
    } finally { $env:RCP_SELECTED_PATH = $oldSelected }
    $script:passed++
    $f = New-Fixture 'linked-desktop' 'nested'
    $desktop = Join-Path $testRoot 'OneDrive/Desktop'
    [IO.Directory]::CreateDirectory((Split-Path -Parent $desktop)) | Out-Null
    $kind = 'SymbolicLink'
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { $kind = 'Junction' }
    New-Item -ItemType $kind -Path $desktop -Target (Split-Path -Parent $f.Package) | Out-Null
    $aliasPackage = Join-Path $desktop 'Package'
    Write-Fixture (Join-Path $f.Package 'Payload/RoboCopGameplay/unlisted.lua') 'do not install'
    try {
        Assert-RcpNoLinks (Join-Path $aliasPackage 'Payload/RoboCopGameplay/Scripts/main.lua')
        throw 'The source-link fixture did not reproduce the old installer rejection.'
    } catch { if ($_.Exception.Message -notmatch 'Linked folder/file requires manual installation') { throw } }
    $r = Invoke-RcpInstall $aliasPackage $f.Game $f.Manifest
    Assert-Equal ([IO.File]::ReadAllText((Join-Path $r.Mods 'RoboCopGameplay/Scripts/main.lua'))) 'fixture-Payload/RoboCopGameplay/Scripts/main.lua' 'linked Desktop source installed'
    $links = @(Get-ChildItem -LiteralPath (Join-Path $r.Mods 'RoboCopGameplay') -Recurse -Force | Where-Object {($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0})
    Assert-Equal $links.Count 0 'source reparse attributes not copied to installed mod'
    Assert-Equal (Test-Path -LiteralPath (Join-Path $r.Mods 'RoboCopGameplay/unlisted.lua')) $false 'only verified manifest files installed'
    [IO.Directory]::Delete($desktop)
    $script:passed++
    $f = New-Fixture 'missing-loader' 'nested'
    Copy-Item -LiteralPath (Join-Path $f.Package 'Runtime/ue4ss/UE4SS.dll') -Destination (Join-Path $f.Runtime 'UE4SS.dll') -Force
    Remove-Item -LiteralPath (Join-Path $f.Game.Bin 'dwmapi.dll')
    $r = Invoke-RcpInstall $f.Package $f.Game $f.Manifest
    Assert-Equal $r.UpdatedUE4SS $true 'missing loader repaired'
    Assert-Equal ([IO.File]::ReadAllText((Join-Path $f.Game.Bin 'dwmapi.dll'))) 'fixture-Runtime/dwmapi.dll' 'loader placed in Win64'
    $script:passed++
    $f = New-Fixture 'missing-runtime' 'nested'
    Remove-Item -LiteralPath (Join-Path $f.Runtime 'UE4SS.dll')
    $r = Invoke-RcpInstall $f.Package $f.Game $f.Manifest
    Assert-Equal ([IO.File]::ReadAllText((Join-Path $f.Runtime 'UE4SS.dll'))) 'fixture-Runtime/ue4ss/UE4SS.dll' 'partial runtime repaired'
    Assert-Equal ([IO.File]::ReadAllText((Join-Path $r.Mods 'OtherMod/Scripts/main.lua'))) 'other-mod' 'partial runtime retains mods'
    $script:passed++
    Write-Host "PASS: $script:passed installer scenarios, including reruns and rollback."
} finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
