# Windows Laptop Automation

Automated setup and configuration script for Windows laptops. This project provides a lightweight bootstrap solution to download and install packages, configure PowerShell profiles, and deploy Office on fresh Windows installations.

## Quick Start

Run this one-liner to bootstrap your Windows laptop:

```powershell
iwr "https://raw.githubusercontent.com/Damianko135/bootstrap/main/bootstrap.ps1" | iex
```

Or with file output:

```powershell
iwr "https://raw.githubusercontent.com/Damianko135/bootstrap/main/bootstrap.ps1" -OutFile "$env:TEMP\bootstrap.ps1"; powershell -nop -ep Bypass -f "$env:TEMP\bootstrap.ps1"
```

## Features

- **Automatic Download** - Fetches the latest release from GitHub
- **Package Installation** - Installs configured packages via Chocolatey and Winget
- **PowerShell Profile** - Configures your PowerShell profile automatically
- **Office Deployment** - Optional Office installation with custom configuration
- **Error Handling** - Comprehensive logging and error reporting
- **Cleanup** - Removes temporary files after installation

## Requirements

- Windows 10/11
- PowerShell 5.1 or later
- Administrator privileges (for package installation)
- Internet connectivity

## Components

### Bootstrap Script (`bootstrap.ps1`)
The entry point script that downloads and executes the latest release from GitHub.

**Parameters:**
- `-SkipPackages` - Skip package installation
- `-SkipProfile` - Skip PowerShell profile configuration
- `-Force` - Force installation even if prerequisites fail
- `-DownloadPath` - Custom temporary download path (default: `$env:TEMP`)

### Setup Script (`setup.ps1`)
Main configuration script executed after bootstrap downloads the release.

**Parameters:**
- `-SkipPackages` - Skip package installation
- `-SkipProfile` - Skip PowerShell profile configuration
- `-Force` - Force installation
- `-SkipOffice` - Skip Office installation

### Configuration Files

#### `packageList.json`
Defines packages to install with their package manager IDs:
- Winget IDs for Windows Package Manager
- Chocolatey IDs for Chocolatey package manager

#### `office-configuration.xml`
Microsoft Office Deployment Tool configuration for Office installation.

#### `profile-content.ps1`
PowerShell profile content to be added to the user's profile.

## Releases

Releases are automatically packaged into `Bootstrap-Automation.zip` via GitHub Actions when a new release is created. The bootstrap script downloads and extracts the latest release, then runs the setup script.

## Development

### Local Testing

```powershell
# Run with skip flags for testing
.\setup.ps1 -SkipPackages -SkipProfile -Force

# Run full setup
.\setup.ps1 -Force
```

### Creating a Release

1. Create a new release on GitHub
2. GitHub Actions automatically:
   - Packages files into `Bootstrap-Automation.zip`
   - Uploads zip as release asset
3. Bootstrap script can now download and use the release

## File Structure

```
.
├── bootstrap.ps1              # Entry point script
├── setup.ps1                  # Main setup script
├── office.ps1                 # Office installation script
├── profile-content.ps1        # PowerShell profile content
├── packageList.json           # Package definitions
├── packageManagers.json       # Package manager configuration
├── office-configuration.xml   # Office deployment configuration
├── run-test.ps1              # Test runner
└── .github/
    └── workflows/
        └── release.yml        # GitHub Actions workflow for releases
```

## Logging

All scripts use timestamped logging output. Check the console output during execution for detailed information about what's being installed and configured.

## Troubleshooting

- **No internet connectivity**: Ensure you have internet access before running
- **Missing setup.ps1**: The bootstrap script looks for it in the extracted release
- **Office installation fails**: Check that Office isn't already installed
- **Package installation fails**: Ensure administrator privileges and valid package IDs

## Author

Damian Korver

## License

See LICENSE file for details.
