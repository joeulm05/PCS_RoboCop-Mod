# RoboCop Windows Compatibility Bridge Tests | Author: Joe "Gambit" Bradford
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$package=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
. (Join-Path $package 'Installer/Core.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('RcpBridge_' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root) | Out-Null
$exe=Join-Path $root "Game & Officer's Test.exe"
try {
    & python -c "import runpy,sys,pathlib; m=runpy.run_path(sys.argv[1]);pathlib.Path(sys.argv[2]).write_bytes(m['fixture']()[0])" (Join-Path $PSScriptRoot 'test_compatibility.py') $exe
    if($LASTEXITCODE -ne 0){throw 'Could not generate the PE fixture.'}
    $before=Get-RcpHash $exe
    $game=[pscustomobject]@{Exe=$exe}
    $output=@(Assert-RcpCompatibility $package $game)
    if($output.Count -ne 0){throw 'Compatibility check polluted installer return values.'}
    if((Get-RcpHash $exe) -ne $before){throw 'Compatibility check modified the executable.'}
    [IO.File]::WriteAllText($exe,'invalid PE')
    try { Assert-RcpCompatibility $package $game;throw 'DID_NOT_FAIL' }
    catch { if($_.Exception.Message -notmatch 'cannot verify patrol protection'){throw} }
    Write-Host 'PASS: Windows P/Invoke bridge, matched function profiles, read-only inspection and incompatible-file rejection.'
} finally { Remove-Item -LiteralPath $root -Recurse -Force }
