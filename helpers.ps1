Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    switch ($Level.ToUpper()) {
        'ERROR'   { Write-Error  "[$ts] $Message"; return }
        'WARN'    { Write-Warning "[$ts] $Message"; return }
        default   { Write-Host    "[$ts] $Message" }
    }
}

function Test-Administrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-PackageManagerAvailable {
    param([ValidateSet('Chocolatey','WinGet')][string]$PackageManager)
    if ($PackageManager -eq 'Chocolatey') { $cmd = 'choco' } else { $cmd = 'winget' }
    return $null -ne (Get-Command $cmd -ErrorAction SilentlyContinue)
}

function Ensure-Chocolatey {
    if (Test-PackageManagerAvailable -PackageManager Chocolatey) { return $true }
    Write-Log 'Installing Chocolatey (silent)...' 'INFO'
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    $tmp = Join-Path $env:TEMP 'install-choco.ps1'
    try {
        (New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1') | Set-Content -Path $tmp -Force
        & $tmp
    }
    catch {
        Write-Log "Chocolatey install failed: $_" 'WARN'
    }
    finally { if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue } }

    return Test-PackageManagerAvailable -PackageManager Chocolatey
}

function Invoke-FileDownload {
    param([Parameter(Mandatory)][string]$Uri, [Parameter(Mandatory)][string]$OutFile)
    Write-Log "Downloading $Uri -> $OutFile"
    if (Test-Path $OutFile) { Remove-Item $OutFile -Force -ErrorAction SilentlyContinue }
    Invoke-WebRequest -Uri $Uri -OutFile $OutFile
}

function Expand-ArchiveIfNeeded {
    param([string]$ArchivePath, [string]$Destination)
    if (Test-Path $Destination) { Remove-Item $Destination -Recurse -Force -ErrorAction SilentlyContinue }
    if (Get-Command Expand-Archive -ErrorAction SilentlyContinue) {
        Expand-Archive -Path $ArchivePath -DestinationPath $Destination -Force
    }
    else {
        Add-Type -AssemblyName 'System.IO.Compression.FileSystem'
        [System.IO.Compression.ZipFile]::ExtractToDirectory($ArchivePath, $Destination)
    }
}

function Backup-FileIfExists {
    param([Parameter(Mandatory)][string]$Path)
    if (Test-Path $Path) {
        $bak = "$Path.bak.$((Get-Date).ToString('yyyyMMddHHmmss'))"
        Copy-Item -Path $Path -Destination $bak -Force
        Write-Log "Backed up $Path -> $bak"
        return $bak
    }
    return $null
}

function Invoke-PackageAction {
    param(
        [ValidateSet('Install','Uninstall')][string]$Action,
        [string]$PackagesJson = (Join-Path $PSScriptRoot 'packages.json')
    )

    $data = Get-Content $PackagesJson -Raw | ConvertFrom-Json
    $packages = $data.packages
    if ($data.managers) { $preferred = $data.managers } else { $preferred = @('Chocolatey','WinGet') }

    $choco = Test-PackageManagerAvailable -PackageManager Chocolatey
    $winget = Test-PackageManagerAvailable -PackageManager WinGet

    $failed = @()
    $i = 0
    foreach ($p in $packages) {
        $i++
        $pct = [math]::Round(($i / $packages.Count) * 100)
        Write-Progress -Activity "$Action Packages" -Status "$($p.Name) ($i/$($packages.Count))" -PercentComplete $pct

        $did = $false
        foreach ($mgr in $preferred) {
            if ($mgr -eq 'Chocolatey' -and $choco -and $p.chocoId) {
                try {
                    if ($Action -eq 'Install') { choco install $p.chocoId -y --no-progress | Out-Null } else { choco uninstall $p.chocoId -y | Out-Null }
                    $did = $true; break
                } catch { Write-Log "$mgr failed for $($p.Name): $_" 'WARN' }
            }
            if ($mgr -eq 'WinGet' -and $winget -and $p.wingetId) {
                try {
                    if ($Action -eq 'Install') { winget install --id $p.wingetId --silent --accept-package-agreements --accept-source-agreements | Out-Null } else { winget uninstall --id $p.wingetId --silent | Out-Null }
                    $did = $true; break
                } catch { Write-Log "$mgr failed for $($p.Name): $_" 'WARN' }
            }
        }

        if (-not $did) { $failed += $p.Name }
    }
    Write-Progress -Activity "$Action Packages" -Completed

    if ($failed.Count) { Write-Log "$Action failed: $($failed -join ', ')" 'WARN' }
    Write-Log "$Action completed. Failed: $($failed.Count) / $($packages.Count)"
}

function Invoke-ProfileInstall {
    param([string]$Source = (Join-Path $PSScriptRoot 'profile.ps1'), [switch]$Force)
    $dest = $PROFILE
    $dir = Split-Path $dest
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    if ((-not $Force) -and (Test-Path $dest)) { Write-Log "Profile exists at $dest (use -Force to overwrite)"; return }
    Backup-FileIfExists -Path $dest | Out-Null
    Get-Content $Source -Raw | Set-Content -Path $dest -Encoding UTF8
    Write-Log "Profile written to $dest"
}
