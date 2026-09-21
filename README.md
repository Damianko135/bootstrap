# Windows Laptop Automation (personal)

Lightweight, single-user bootstrap for a Windows laptop. The repository has been simplified to a single entrypoint and a small set of resources for clarity and maintainability.

Main files

- `bootstrap.ps1` — single entrypoint. Supported `-Action` values:
  - `install` (default): install packages, deploy Office, and write profile
  - `uninstall`: remove packages listed in `packages.json`
  - `office`: run Office deployment only
  - `fetch`: download latest release zip
  - `test`: non-destructive smoke test — extracts a local archive and validates every script/JSON file in it; installs nothing
- `helpers.ps1` — shared helper functions dot-sourced by `bootstrap.ps1`
- `packages.json` — merged package manifest and manager preference
- `profile.ps1` — PowerShell profile content (your QoL helpers)
- `office.ps1`, `office.xml` — Office deployment logic and configuration
- `uninstallList.json` — explicit uninstall list (kept for compatibility)

Requirements: Windows PowerShell 5.1, which ships with every supported version of Windows — no separate PowerShell 7 (`pwsh`) install needed. If `pwsh` is on your machine the scripts run fine under it too; just swap `powershell` for `pwsh` in the commands below.

Quick start

Run the full install (this will reinstall packages where applicable and will not skip steps):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\bootstrap.ps1
```

Or run the installer directly from GitHub. Two variants — use whichever your machine allows:

**Option A** — opens an elevated window and runs the script directly (may trigger AV on managed machines):

```powershell
Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', "iwr 'https://raw.githubusercontent.com/Damianko135/bootstrap/master/bootstrap.ps1' | iex"
```

**Option B** — downloads to a temp file first, then relaunches elevated (friendlier to AV/MDM policies):

```powershell
$f="$env:TEMP\bootstrap.ps1"; iwr 'https://raw.githubusercontent.com/Damianko135/bootstrap/master/bootstrap.ps1' -OutFile $f; Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$f`""
```

Uninstall packages listed in `packages.json`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\bootstrap.ps1 -Action uninstall
```

Fetch latest release zip (downloads to `$env:TEMP`):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\bootstrap.ps1 -Action fetch
```

Run the smoke test (safe to run anytime, no admin required, changes nothing on the system):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\bootstrap.ps1 -Action test
```

Notes

- This repo is personal and minimal by design — no module publishing or heavy frameworks.
- The new default behaviour performs installs without skipping; use flags if you want to skip steps.
- If you run the script without Administrator privileges and the selected action requires elevation (`install`, `uninstall`, or `office`), the script will attempt to relaunch itself elevated (using whichever PowerShell host you're already running) and prompt for UAC.

Troubleshooting

- If a package install fails, check console logs. Most installers run silently, but some large installers (Docker Desktop, JetBrains IDEs) may require additional steps.
- Office deployment is network-heavy and may take a while; run it alone with `-Action office` if you want to troubleshoot. It also requires Administrator, since the Office Deployment Tool's extract/configure steps need elevation.

Author: Damian Korver
