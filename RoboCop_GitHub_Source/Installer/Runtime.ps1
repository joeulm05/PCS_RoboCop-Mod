# RoboCop Installer v1.0.1 | Author: Joe "Gambit" Bradford
Set-StrictMode -Version Latest

function Copy-RcpBytes([string]$Source,[string]$Destination) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Destination)) | Out-Null
    $reader = [IO.File]::OpenRead($Source)
    try {
        $writer = [IO.File]::Create($Destination)
        try { $reader.CopyTo($writer) } finally { $writer.Dispose() }
    } finally { $reader.Dispose() }
}

function Get-RcpExperimentalRelease {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    return Invoke-RestMethod -Uri 'https://api.github.com/repos/UE4SS-RE/RE-UE4SS/releases/tags/experimental' -Headers @{'User-Agent'='RoboCop-Installer';'Accept'='application/vnd.github+json'} -TimeoutSec 20
}

function Select-RcpExperimentalAsset($Release) {
    $assets = @($Release.assets | Where-Object {$_.name -match '^UE4SS_v[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-g[0-9a-f]+\.zip$'} | Sort-Object -Property @{Expression={[DateTimeOffset]$_.created_at};Descending=$true},@{Expression={$_.id};Descending=$true})
    if ($assets.Count -eq 0) { throw 'The official experimental release contains no supported basic runtime ZIP.' }
    $asset = $assets[0]
    $expectedUrl = 'https://github.com/UE4SS-RE/RE-UE4SS/releases/download/experimental/' + $asset.name
    if ($asset.browser_download_url -cne $expectedUrl) { throw 'Unexpected UE4SS download address in the release metadata.' }
    if (-not $asset.PSObject.Properties['digest'] -or $asset.digest -notmatch '^sha256:[a-fA-F0-9]{64}$') { throw 'The latest UE4SS archive has no verifiable SHA-256 digest.' }
    if ($asset.size -le 0 -or $asset.size -gt 209715200) { throw 'The latest UE4SS archive size is outside the supported range.' }
    return $asset
}

function Get-RcpArchive([string]$Uri,[string]$Destination) {
    $oldProgress = $ProgressPreference
    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Uri -OutFile $Destination -UseBasicParsing -Headers @{'User-Agent'='RoboCop-Installer'} -TimeoutSec 120
    } finally { $ProgressPreference = $oldProgress }
}

function Expand-RcpRuntime([string]$Archive,[string]$Destination) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        foreach ($name in @('dwmapi.dll','ue4ss/UE4SS.dll','ue4ss/UE4SS-settings.ini','ue4ss/LICENSE')) {
            $entries = @($zip.Entries | Where-Object {$_.FullName -ceq $name})
            if ($entries.Count -ne 1 -or $entries[0].Length -gt 134217728) { throw "Unsupported UE4SS archive layout: $name" }
            $dest = Join-RcpPath $Destination $name
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dest)) | Out-Null
            $reader = $entries[0].Open()
            try {
                $writer = [IO.File]::Create($dest)
                try { $reader.CopyTo($writer) } finally { $writer.Dispose() }
            } finally { $reader.Dispose() }
        }
    } finally { $zip.Dispose() }
}

function Resolve-RcpRuntime([string]$Package,$Manifest,[string]$Stage) {
    $root = Join-RcpPath $Package 'Runtime'
    $version = $Manifest.ue4ssVersion
    $source = $Manifest.ue4ssSource
    $archiveHash = $Manifest.ue4ssArchiveSha256
    $online = $false
    $release = $null
    Write-Host 'Checking the official UE4SS experimental release...'
    try { $release = Get-RcpExperimentalRelease }
    catch { Write-Warning "Online UE4SS check unavailable. Using bundled experimental $version; latest online version could not be confirmed." }
    if ($null -ne $release) {
        $asset = Select-RcpExperimentalAsset $release
        $online = $true
        $version = $asset.name.Substring(7,$asset.name.Length - 11)
        $source = $asset.browser_download_url
        $archiveHash = $asset.digest.Substring(7).ToLowerInvariant()
        if ($source -ne $Manifest.ue4ssSource -or $archiveHash -ne $Manifest.ue4ssArchiveSha256) {
            Write-Host "Downloading official UE4SS experimental $version..."
            $archive = Join-RcpPath $Stage 'UE4SS.zip'
            Get-RcpArchive $source $archive
            if ((Get-Item -LiteralPath $archive).Length -ne $asset.size -or (Get-RcpHash $archive) -ne $archiveHash) { throw 'The UE4SS download failed its integrity check. No game files were changed.' }
            $root = Join-RcpPath $Stage 'DownloadedRuntime'
            Expand-RcpRuntime $archive $root
        }
    }
    $files = @(foreach ($name in @('dwmapi.dll','ue4ss/UE4SS.dll','ue4ss/UE4SS-settings.ini','ue4ss/LICENSE')) {
        $path = Join-RcpPath $root $name
        if (-not [IO.File]::Exists($path)) { throw "Missing UE4SS runtime file: $name" }
        [pscustomobject]@{Name=$name; Source=$path; Hash=(Get-RcpHash $path)}
    })
    return [pscustomobject]@{Root=$root; Version=$version; Source=$source; ArchiveHash=$archiveHash; OnlineChecked=$online; Files=$files}
}
