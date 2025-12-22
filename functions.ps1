# ====================================================
# Shared Functions Module
# ====================================================

# ============================
# Logging
# ============================
function Write-LogEntry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $Message,

        [ValidateSet('Info', 'Warning', 'Error')]
        [string]
        $Level = 'Info'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $prefix = "[$timestamp]"

    switch ($Level) {
        'Info'    { Write-Information "$prefix $Message" -InformationAction Continue }
        'Warning' { Write-Warning "$prefix $Message" }
        'Error'   { Write-Error "$prefix $Message" }
    }
}

# ============================
# Helper Functions
# ============================
function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-PackageManagerAvailable {
    param (
        [Parameter(Mandatory)]
        [ValidateSet('Chocolatey', 'WinGet')]
        [string]
        $PackageManager
    )

    $command = if ($PackageManager -eq 'Chocolatey') { 'choco' } else { 'winget' }
    return $null -ne (Get-Command $command -ErrorAction SilentlyContinue)
}
