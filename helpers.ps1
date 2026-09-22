Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Invoke-FileDownload, Expand-ArchiveIfNeeded and Invoke-FetchLatestRelease live in bootstrap.ps1 -
# they're needed before helpers.ps1 can be dot-sourced there (e.g. the standalone iwr|iex flow).
# Write-LogEntry is defined in both files: bootstrap.ps1 needs it before helpers.ps1 loads, and
# office.ps1 dot-sources this file directly (not bootstrap.ps1), so it needs its own copy too.
# When both files are loaded together the two definitions are identical and the second just
# harmlessly replaces the first.
function Write-LogEntry {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    switch ($Level.ToUpper()) {
        'ERROR'   { Write-Error  "[$ts] $Message"; return }
        'WARN'    { Write-Warning "[$ts] $Message"; return }
        default   { Write-Information "[$ts] $Message" -InformationAction Continue }
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

function Install-Chocolatey {
    if (Test-PackageManagerAvailable -PackageManager Chocolatey) { return $true }
    Write-LogEntry 'Installing Chocolatey (silent)...' 'INFO'
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    $tmp = Join-Path $env:TEMP 'install-choco.ps1'
    try {
        (New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1') | Set-Content -Path $tmp -Force
        & $tmp
    }
    catch {
        Write-LogEntry "Chocolatey install failed: $_" 'WARN'
    }
    finally { if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue } }

    return Test-PackageManagerAvailable -PackageManager Chocolatey
}

function Invoke-PackageAction {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$PackagesJson = (Join-Path $PSScriptRoot 'packages.json')
    )

    $data = Get-Content $PackagesJson -Raw | ConvertFrom-Json
    $packages = $data.packages
    if ($data.managers) { $preferred = $data.managers } else { $preferred = @('Chocolatey','WinGet') }

    $choco = Test-PackageManagerAvailable -PackageManager Chocolatey
    $winget = Test-PackageManagerAvailable -PackageManager WinGet

    $failed = @()
    $attempted = 0
    $i = 0
    foreach ($p in $packages) {
        $i++
        $pct = [math]::Round(($i / $packages.Count) * 100)
        Write-Progress -Activity 'Install Packages' -Status "$($p.Name) ($i/$($packages.Count))" -PercentComplete $pct

        if (-not $PSCmdlet.ShouldProcess($p.Name, 'Install package')) { continue }
        $attempted++

        $did = $false
        foreach ($mgr in $preferred) {
            if ($mgr -eq 'Chocolatey' -and $choco -and $p.chocoId) {
                try {
                    choco install $p.chocoId -y --no-progress | Out-Null
                    $did = $true; break
                } catch { Write-LogEntry "$mgr failed for $($p.Name): $_" 'WARN' }
            }
            if ($mgr -eq 'WinGet' -and $winget -and $p.wingetId) {
                try {
                    # --exact + --source pin the match to one specific package id on the official
                    # winget source. Without --exact, --id does a case-insensitive substring match
                    # (e.g. "Discord.Discord" also matches "Discord.Discord.Canary",
                    # "Discord.Discord.PTB", etc.) - winget currently prefers an exact hit among
                    # fuzzy matches when one exists, but that's ranking behavior, not a contract,
                    # and it silently stops protecting you the moment an id has no exact match
                    # (renamed package, or another source added later with an overlapping id).
                    # --accept-*-agreements only covers those two specific agreement prompts;
                    # --disable-interactivity is the broader "don't ask me anything" flag that
                    # also covers other interactive prompts winget can show per-package.
                    winget install --id $p.wingetId --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Null
                    $did = $true; break
                } catch { Write-LogEntry "$mgr failed for $($p.Name): $_" 'WARN' }
            }
        }

        if (-not $did) { $failed += $p.Name }
    }
    Write-Progress -Activity 'Install Packages' -Completed

    if ($failed.Count) { Write-LogEntry "Install failed: $($failed -join ', ')" 'WARN' }
    Write-LogEntry "Install completed. Failed: $($failed.Count) / $attempted attempted ($($packages.Count) total)"
}

function Invoke-Debloat {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$UninstallListJson = (Join-Path $PSScriptRoot 'uninstallList.json'))

    # Get-AppxPackage/Remove-AppxPackage are backed by a binary module that's historically been
    # Windows-PowerShell-only; on some Windows/PowerShell 7 combinations only a limited
    # compatibility-proxy version loads (returning deserialized objects that don't bind the same
    # way), which fails unpredictably mid-removal instead of cleanly. Detect that up front rather
    # than logging a wall of per-app failures.
    $appxCmd = Get-Command Get-AppxPackage -ErrorAction SilentlyContinue
    if (-not $appxCmd -or $appxCmd.CommandType -ne 'Cmdlet') {
        Write-LogEntry 'Get-AppxPackage is not available as a native cmdlet in this PowerShell session (seen on some Windows versions under PowerShell 7) - skipping debloat. Re-run under Windows PowerShell (powershell.exe) if you need this step.' 'WARN'
        return
    }

    if (-not (Test-Path $UninstallListJson)) { Write-LogEntry 'uninstallList.json not found, skipping debloat' 'WARN'; return }
    $entries = Get-Content $UninstallListJson -Raw | ConvertFrom-Json
    $processed = 0
    $i = 0
    foreach ($entry in $entries) {
        $i++
        $pct = [math]::Round(($i / $entries.Count) * 100)
        Write-Progress -Activity 'Removing bloatware' -Status $entry.Name -PercentComplete $pct

        if (-not $PSCmdlet.ShouldProcess($entry.Name, 'Remove bloatware app')) { continue }
        $processed++

        try {
            $pkg = Get-AppxPackage -Name $entry.AppxPackage -AllUsers -ErrorAction SilentlyContinue
            if ($pkg) {
                $pkg | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
                Write-LogEntry "Removed $($entry.Name)"
            }
            $prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -eq $entry.AppxPackage }
            if ($prov) { Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction SilentlyContinue | Out-Null }
        }
        catch { Write-LogEntry "Failed to remove $($entry.Name): $_" 'WARN' }
    }
    Write-Progress -Activity 'Removing bloatware' -Completed
    Write-LogEntry "Debloat completed ($processed / $($entries.Count) entries processed)"
}

function Backup-ExistingItem {
    param([Parameter(Mandatory)][string]$Path)
    if (Test-Path $Path) {
        $bak = "$Path.bak.$((Get-Date).ToString('yyyyMMddHHmmss'))"
        Copy-Item -Path $Path -Destination $bak -Force
        Write-LogEntry "Backed up $Path -> $bak"
        return $bak
    }
    return $null
}

function Invoke-ProfileInstall {
    param([string]$Source = (Join-Path $PSScriptRoot 'profile.ps1'), [switch]$Force)
    $dest = $PROFILE
    $dir = Split-Path $dest
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    if ((-not $Force) -and (Test-Path $dest)) { Write-LogEntry "Profile exists at $dest (use -Force to overwrite)"; return }
    Backup-ExistingItem -Path $dest | Out-Null
    Get-Content $Source -Raw | Set-Content -Path $dest -Encoding UTF8
    Write-LogEntry "Profile written to $dest"
}
