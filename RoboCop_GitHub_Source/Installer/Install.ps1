# RoboCop Installer v1.0.1 | Author: Joe "Gambit" Bradford
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Core.ps1')
$package = Split-Path -Parent $PSScriptRoot
$stamp = (Get-Date -Format 'yyyyMMdd_HHmmss_fff')
$log = Join-RcpPath ([IO.Path]::GetTempPath()) ("RoboCop_Install_$stamp.log")
$discoveryLog = Join-RcpPath ([IO.Path]::GetTempPath()) ("RoboCop_Detection_$stamp.log")
$script:RcpDiscoveryLog = $discoveryLog
$logging = $false
try {
    Start-Transcript -LiteralPath $log | Out-Null
    $logging = $true
    Write-Host 'RoboCop for Police Chief Simulator - Installer 1.0.1'
    Write-Host 'Author: Joe "Gambit" Bradford'
    Write-Host 'Finding Police Chief Simulator...'
    Write-RcpDiscovery "PowerShell $($PSVersionTable.PSVersion) | OS $([Environment]::OSVersion) | 64-bit=$([Environment]::Is64BitProcess)"
    Write-RcpDiscovery "PACKAGE | $package"
    $path = $env:RCP_SELECTED_PATH
    if (-not $path) {
        $nearby = @($package, (Split-Path -Parent $package))
        $found = @(Find-RcpSteamGames -AdditionalLocations $nearby | Sort-Object -Unique)
        Write-RcpDiscovery "FOUND COUNT | $($found.Count)"
        if ($found.Count -eq 1) {
            $path = $found[0]
            Write-Host "Found game automatically: $path"
        } else {
            Add-Type -AssemblyName System.Windows.Forms
            $picker = New-Object System.Windows.Forms.OpenFileDialog
            $picker.Title = 'Select PoliceChiefSimulator.exe or PoliceChiefSimulator-Win64-Shipping.exe from your game folder'
            $picker.Filter = 'Police Chief Simulator executable|PoliceChiefSimulator.exe;PoliceChiefSimulator-Win64-Shipping.exe'
            $picker.CheckFileExists = $true
            $picker.Multiselect = $false
            $picker.RestoreDirectory = $true
            if ($found.Count -gt 1) {
                Write-Host 'Multiple copies of the game were found. Select the copy you play.'
                $picker.InitialDirectory = $found[0]
            } else {
                Write-Host 'Automatic detection found no game. Select its executable in the file window.'
                Write-Host 'Steam > Manage > Browse local files shows the game folder.'
            }
            try {
                if ($picker.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { throw 'Installation cancelled. No game files changed.' }
                $path = $picker.FileName
            } finally { $picker.Dispose() }
        }
    }
    Write-Host "Game location: $path"
    $game = Resolve-RcpGame $path
    Write-Host "Game executable: $($game.Exe)"
    Write-Host "Game assets: $($game.Paks)"
    $manifest = Get-Content -LiteralPath (Join-RcpPath $PSScriptRoot 'manifest.json') -Raw | ConvertFrom-Json
    Write-Host 'Checking gameplay compatibility and installer files...'
    $result = Invoke-RcpInstall $package $game $manifest
    Write-Host ''
    Write-Host 'SUCCESS - RoboCop model, portrait, and gameplay mod installed and verified.' -ForegroundColor Green
    Write-Host "UE4SS experimental: $($result.UE4SSVersion)"
    Write-Host "Gameplay: $($result.Mods)\RoboCopGameplay"
    Write-Host "Assets: $($game.Paks)\~mods"
    Write-Host "Backups: $($result.Backup)"
    Write-Host 'Launch the game normally. No mods.txt edits or hotkeys are needed.'
    Write-Host "Installer log: $log"
    Stop-Transcript | Out-Null
    exit 0
} catch {
    Write-Host ''
    Write-Host ('INSTALLATION STOPPED: ' + $_.Exception.Message) -ForegroundColor Red
    Write-RcpDiscovery "ERROR | $($_.Exception.ToString())"
    Write-RcpDiscovery "STACK | $($_.ScriptStackTrace)"
    if ($_.Exception.Message -match '(?i)access.*denied|unauthorized') {
        Write-Host 'Close the game. If your game folder requires administrator access, right-click Install_RoboCop.bat and choose Run as administrator.'
    }
    Write-Host "Installer log: $log"
    Write-Host "Detection log: $discoveryLog"
    if ($logging) { Stop-Transcript | Out-Null }
    exit 1
}
