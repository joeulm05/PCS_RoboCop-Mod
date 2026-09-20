# RoboCop Runtime Updater Tests | Author: Joe "Gambit" Bradford
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$package = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
. (Join-Path $package 'Installer/Core.ps1')
Add-Type -AssemblyName System.IO.Compression.FileSystem
$root = Join-RcpPath ([IO.Path]::GetTempPath()) ('RcpRuntimeTests_' + [guid]::NewGuid().ToString('N'))
function Write-Fixture([string]$Path,[string]$Value) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    [IO.File]::WriteAllText($Path,$Value)
}
try {
    $bundle = Join-RcpPath $root 'Bundle'
    $contents = Join-RcpPath $root 'NewRuntime'
    foreach ($file in @('dwmapi.dll','ue4ss/UE4SS.dll','ue4ss/UE4SS-settings.ini','ue4ss/LICENSE')) {
        Write-Fixture (Join-RcpPath $bundle ('Runtime/' + $file)) ('bundled-' + $file)
        Write-Fixture (Join-RcpPath $contents $file) ('new-' + $file)
    }
    Write-Fixture (Join-RcpPath $contents 'ue4ss/Mods/ExampleMod/Scripts/main.lua') 'do not install optional example'
    $archive = Join-RcpPath $root 'new-runtime.zip'
    [IO.Compression.ZipFile]::CreateFromDirectory($contents,$archive)
    $script:archive = $archive
    $script:downloads = 0
    $new = [pscustomobject]@{name='UE4SS_v3.0.1-9999-gabcdef01.zip'; id=2; created_at='2026-09-20T00:00:00Z'; digest=('sha256:' + (Get-RcpHash $archive)); size=(Get-Item -LiteralPath $archive).Length; browser_download_url='https://github.com/UE4SS-RE/RE-UE4SS/releases/download/experimental/UE4SS_v3.0.1-9999-gabcdef01.zip'}
    $older = [pscustomobject]@{name='UE4SS_v3.0.1-9998-gabcdef00.zip'; id=1; created_at='2026-09-19T00:00:00Z'; digest=('sha256:' + ('b' * 64)); size=50; browser_download_url='https://github.com/UE4SS-RE/RE-UE4SS/releases/download/experimental/UE4SS_v3.0.1-9998-gabcdef00.zip'}
    $dev = [pscustomobject]@{name='zDEV-UE4SS_v3.0.1-9999-gabcdef01.zip'; id=3; created_at='2026-09-21T00:00:00Z'}
    $script:release = [pscustomobject]@{assets=@($older,$dev,$new)}
    function Get-RcpExperimentalRelease { return $script:release }
    function Get-RcpArchive([string]$Uri,[string]$Destination) { $script:downloads++; Copy-RcpBytes $script:archive $Destination }
    $manifest = [pscustomobject]@{ue4ssVersion='3.0.1-9998-gabcdef00'; ue4ssSource=$older.browser_download_url; ue4ssArchiveSha256=$older.digest.Substring(7)}
    $stage = Join-RcpPath $root 'Stage'
    [IO.Directory]::CreateDirectory($stage) | Out-Null
    $runtime = Resolve-RcpRuntime $bundle $manifest $stage
    if ($runtime.Version -cne '3.0.1-9999-gabcdef01' -or -not $runtime.OnlineChecked -or $script:downloads -ne 1) { throw 'Latest basic experimental selection/download failed.' }
    if ([IO.File]::ReadAllText((Join-RcpPath $runtime.Root 'ue4ss/UE4SS.dll')) -cne 'new-ue4ss/UE4SS.dll') { throw 'Downloaded runtime was not extracted.' }
    if (Test-Path -LiteralPath (Join-RcpPath $runtime.Root 'ue4ss/Mods')) { throw 'Optional upstream mods were extracted.' }
    $manifest.ue4ssSource=$new.browser_download_url
    $manifest.ue4ssArchiveSha256=$new.digest.Substring(7)
    $runtime = Resolve-RcpRuntime $bundle $manifest $stage
    if ($script:downloads -ne 1 -or $runtime.Root -cne (Join-RcpPath $bundle 'Runtime')) { throw 'Already-bundled release downloaded again.' }
    $manifest.ue4ssArchiveSha256='c' * 64
    $new.digest='sha256:' + ('d' * 64)
    try { Resolve-RcpRuntime $bundle $manifest $stage | Out-Null; throw 'Bad download hash accepted.' }
    catch { if ($_.Exception.Message -notmatch 'integrity check') { throw } }
    $new.digest='sha256:' + (Get-RcpHash $archive)
    $new.browser_download_url='https://example.invalid/runtime.zip'
    try { Resolve-RcpRuntime $bundle $manifest $stage | Out-Null; throw 'Nonofficial URL accepted.' }
    catch { if ($_.Exception.Message -notmatch 'Unexpected UE4SS download address') { throw } }
    function Get-RcpExperimentalRelease { throw 'SIMULATED_OFFLINE' }
    $runtime = Resolve-RcpRuntime $bundle $manifest $stage
    if ($runtime.OnlineChecked -or $runtime.Root -cne (Join-RcpPath $bundle 'Runtime')) { throw 'Offline fallback failed.' }
    Write-Host 'PASS: latest basic experimental selection; automatic download; extraction whitelist; bundled reuse; bad-hash rejection; nonofficial URL rejection; explicit offline fallback.'
} finally { if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force } }
