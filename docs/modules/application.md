# Application Module

The Application module handles **software installation**, **application launching**, and **browser management**.

## [Create-CondaEnvironments](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Create-CondaEnvironments.ps1)

- **Description:** Updates Conda and idempotently creates Conda environments from the YAML files in the WinuX `Conda/Environments` folder. Each environment is checked against the existing environment list and only created if it is missing. Requires Miniconda3 to be installed and the `Conda` environment variable to be set.
- **Usage:** `Create-CondaEnvironments`

Updates the base Conda installation (`conda update -n base -c defaults conda`), then enumerates every `*.yml` file in the configured environments folder (resolved from `BootstrapConfig.DataFiles.CondaEnvironments` in `Configuration.psd1`, relative to the WinuX root). The file name (without extension) is used as the environment name; environments that already exist are skipped, and missing ones are created via `conda env create -f`. Exits early with a clear message if the `Conda` variable is unset, the `conda.exe` executable is not found, the environments folder is missing, or no `.yml` files are present.

```powershell
# Create all missing Conda environments from Conda/Environments/*.yml
Create-CondaEnvironments
```

**See also:** [Modules: Workflow](workflow.md)

## [Get-VSCodeWorkspaceNames](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Get-VSCodeWorkspaceNames.ps1)

- **Description:** Lists the available VS Code workspace names by enumerating the `*.code-workspace` files in `Projects.Self.VSCodeWorkspaces` (`<repo>\VSCode\Workspaces`) and returning each file's base name. Returns an empty array when the folder is missing or holds no workspace files.
- **Usage:** `Get-VSCodeWorkspaceNames`

Shared discovery helper used by `Open-VSCodeWorkspace` (interactive selection) and `Open-Workspace` (the `-VSCodeWorkspace` override menu), so workspace discovery lives in one place. The folder is resolved through the machine-specific path map, so the same call works across machines.

```powershell
# List the workspace names available to -VSCodeWorkspace
Get-VSCodeWorkspaceNames
```

## [Install-ChocolateyApps](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Install-ChocolateyApps.ps1)

- **Description:** Installs Chocolatey-managed apps from the WinuX CSV, filtered by machine type. Reads the app list from `ChocolateyApps.csv`, installs entries matching the current machine type (plus any "All" entries), and skips the rest. Requires administrator privileges and is called automatically by Bootstrap.
- **Usage:** `Install-ChocolateyApps`

Reads the app list from the CSV at `BootstrapConfig.DataFiles.ChocolateyApps` in `Configuration.psd1`. Each row specifies an app ID and the machine types it applies to ("All", "PC", "Laptop", etc.), and may also carry optional `Version`, `Params`, and `Force` columns that are passed through to `choco install`. Apps for the current machine type and All-type apps are installed; others are skipped. Administrator privileges are verified up front via `Test-AdminPrivileges`.

```powershell
# Install all Chocolatey apps applicable to the current machine type
Install-ChocolateyApps
```

**See also:** [Modules: Workflow](workflow.md)

## [Install-ChocolateyPackageManager](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Install-ChocolateyPackageManager.ps1)

- **Description:** Installs the Chocolatey package manager if not already present. Checks whether the `choco` command is available and, if not, downloads and runs the official install script from chocolatey.org. Does nothing if Chocolatey is already installed. Called automatically by Bootstrap.
- **Usage:** `Install-ChocolateyPackageManager`

## [Install-DotnetEf](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Install-DotnetEf.ps1)

- **Description:** Installs or updates the EF Core CLI tool (`dotnet-ef`). Installs the `dotnet ef` global tool at the version pinned by the `DotnetEFVersion` key in `Configuration.psd1`; requires the .NET SDK and skips silently if it is not found. With `-Update`, installs the latest available version instead of the pinned one. Called automatically by Bootstrap.
- **Parameters:** -Update
- **Usage:** `Install-DotnetEf`, `Install-DotnetEf -Update`

If `dotnet-ef` is already installed, the function reports the current version and exits without reinstalling. When `DotnetEFVersion` is empty, it falls back to installing the latest available version.

| Parameter | Description                                                                                                 |
| --------- | ----------------------------------------------------------------------------------------------------------- |
| `-Update` | Installs the latest available version of `dotnet-ef` instead of the version pinned in `Configuration.psd1`. |

```powershell
# Install the pinned dotnet-ef version from Configuration.psd1
Install-DotnetEf

# Install the latest available dotnet-ef version
Install-DotnetEf -Update
```

## [Install-FromExecutable](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Install-FromExecutable.ps1)

- **Description:** Unified, reliable, self-cleaning runner for installer-style executables. Given a download `-Url` or a local `-Path`, it fetches the installer (retrying the download with exponential backoff), runs it, and always removes anything it downloaded. Runs unattended when `-Arguments` (the vendor's silent switches) are supplied - waiting for the installer and gating success on its exit code - or interactively otherwise, launching the GUI and waiting for you to confirm completion. Administrator elevation is opt-in via `-RequireAdmin`. Generalizes the download-run-cleanup pattern that individual installer functions used to duplicate.
- **Parameters:** -Name, -Url, -InstallerName, -Path, -Arguments, -ValidExitCodes, -DetectionPath, -MaxAttempts, -RequireAdmin
- **Usage:** `Install-FromExecutable -Name "7-Zip" -Url "https://www.7-zip.org/a/7z2408-x64.exe" -Arguments "/S"`, `Install-FromExecutable -Name "MyApp" -Path "D:\setup.exe"`

Downloads go to a unique, function-owned folder under the temp directory and are deleted afterwards; a caller-supplied `-Path` is run in place and never removed. Because that folder is never derived from `-Name`, cleanup can neither collide with nor destroy existing user data. The download is wrapped in `Invoke-WithOptionalRetry`, and any partial file is discarded between attempts so a flaky network never leaves a corrupt installer behind. Supply `-DetectionPath` to make re-runs idempotent - the function returns early with a warning when that path already exists. Supplying `-Arguments` (even empty) selects unattended mode; exit codes in `-ValidExitCodes` (default `0` and `3010`, reboot-required) count as success and anything else is reported as a failure instead of a false success. Omit `-Arguments` for an interactive GUI install.

| Parameter         | Description                                                                                                                                                                            |
| ----------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-Name`           | Display name; drives the log title ("Installing &lt;Name&gt;"). Mandatory.                                                                                                             |
| `-Url`            | Installer download URL (saved to a temporary folder and cleaned up). Mutually exclusive with `-Path`.                                                                                  |
| `-InstallerName`  | File name for the download; defaults to the URL's file name when it ends in a recognized installer extension (`.exe`/`.msi`/`.msix`/`.appx`/`.bat`/`.cmd`), otherwise `installer.exe`. |
| `-Path`           | Existing local installer to run in place (never deleted). Mutually exclusive with `-Url`.                                                                                              |
| `-Arguments`      | Silent switches; supplying this (even empty) runs the installer unattended with `-Wait` and exit-code gating.                                                                          |
| `-ValidExitCodes` | Exit codes treated as success in unattended mode. Defaults to `0` and `3010`.                                                                                                          |
| `-DetectionPath`  | If this path already exists, the software is considered installed and the function returns early.                                                                                      |
| `-MaxAttempts`    | Number of download attempts with exponential backoff. Defaults to `3`.                                                                                                                 |
| `-RequireAdmin`   | Require administrator privileges (runs `Test-AdminPrivileges` first, elevating or aborting).                                                                                           |

```powershell
# Silent install with a retried download; success gated on the installer's exit code
Install-FromExecutable -Name "7-Zip" -Url "https://www.7-zip.org/a/7z2408-x64.exe" -Arguments "/S"

# Interactive GUI install requiring elevation
Install-FromExecutable -Name "Visual Studio 2026" -Url "https://c2rsetup.example/vs.exe" -RequireAdmin

# Run a local installer silently, skipping if MyApp is already present
Install-FromExecutable -Name "MyApp" -Path "D:\installers\myapp-setup.exe" -Arguments "/quiet" -DetectionPath "C:\Program Files\MyApp\myapp.exe"
```

## [Install-PowerShellModules](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Install-PowerShellModules.ps1)

- **Description:** Installs the required PowerShell modules from PSGallery (Terminal-Icons, PSReadLine, z, VirtualDesktop, ps2exe, Pester). Ensures the NuGet provider and the PSGallery trusted repository are configured first, then installs each module only if it is not already present. Called automatically by Bootstrap.
- **Usage:** `Install-PowerShellModules`

Ensures the NuGet package provider (minimum 2.8.5.201) is available and that PSGallery is set as a `Trusted` installation policy, then iterates a fixed module list and installs anything missing into the `CurrentUser` scope. VirtualDesktop is pinned to `1.5.11` because it wraps undocumented COM interfaces that break between Windows builds, so only tested/verified versions are used; if a different VirtualDesktop version is present it is reinstalled at the pinned version. Pester is handled separately: Windows ships an unupdatable 3.4.0, so it is installed with `-SkipPublisherCheck` and is left alone only when v5.0.0 or newer is already present. Errors during installation are written in red and rethrown.

| Module           | Purpose                                                             |
| ---------------- | ------------------------------------------------------------------- |
| `Terminal-Icons` | File-type icons in the terminal                                     |
| `PSReadLine`     | Enhanced command-line editing and history                           |
| `z`              | Frecency-based directory jump shortcut                              |
| `VirtualDesktop` | Windows virtual desktop COM API wrapper (pinned to 1.5.11)          |
| `ps2exe`         | PowerShell-to-EXE compiler                                          |
| `Pester`         | PowerShell testing framework (installed with `-SkipPublisherCheck`) |

```powershell
# Install all required modules that are not already present
Install-PowerShellModules
```

**See also:** [Modules: Bootstrap](bootstrap.md), [Modules: Window](window.md)

## [Install-ScoopApps](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Install-ScoopApps.ps1)

- **Description:** Installs Scoop-managed apps from the WinuX CSV, filtered by the current machine type. Apps matching the current machine type (or marked `All`) are installed; others are skipped. Requires administrator privileges and is called automatically by Bootstrap.
- **Usage:** `Install-ScoopApps`

Reads the app list from the CSV at `BootstrapConfig.DataFiles.ScoopApps` in `Configuration.psd1`. Each row specifies an app name, optional bucket, version, global flag, and the machine types it applies to. The function determines the current machine type, queries `scoop export` for already-installed apps, and for each applicable row either installs the app, updates it (when already installed and not version-pinned), or skips it (when already installed with a pinned version).

```powershell
# Install all Scoop apps applicable to the current machine type
Install-ScoopApps
```

**See also:** [Modules: Workflow](workflow.md)

## [Install-ScoopPackageManager](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Install-ScoopPackageManager.ps1)

- **Description:** Installs the Scoop package manager if not already present. Checks whether the `scoop` command is available; if not, downloads and runs the official Scoop install script from get.scoop.sh with `-RunAsAdmin`. Does nothing if Scoop is already installed. Called automatically by Bootstrap.
- **Usage:** `Install-ScoopPackageManager`

```powershell
# Install Scoop, or report that it is already installed
Install-ScoopPackageManager
```

## [Install-WingetApps](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Install-WingetApps.ps1)

- **Description:** Installs WinGet-managed apps from the WinuX CSV, filtered by machine type. Reads the app list from `BootstrapConfig.DataFiles.WinGetApps` in `Configuration.psd1`; apps matching the current machine type (or marked `All`) are installed, others are skipped. Requires administrator privileges and is called automatically by Bootstrap.
- **Usage:** `Install-WingetApps`

Each CSV row specifies an app ID, version, installation scope (`d` default / `m` machine / `u` user), interactive flag, source (`w` winget / `s` msstore), and the machine types it applies to. The machine type is resolved at runtime and rows whose `Machine` column does not include the current type or `All` are skipped. For apps pinned at `Latest`, an existing WinGet pin is removed first so the latest version can install cleanly.

The function is fully unattended. Before touching any app it queries each source (`winget` and `msstore`) with `--accept-source-agreements`, which forces every source agreement to surface and records the acceptance. This matters for the `msstore` source, which shows a hard one-time agreement (including a geographic-region consent) the first time it is queried - a gate the `-s winget` installs never trigger and that `--disable-interactivity` alone does not suppress, so without this priming an unattended run (a VM, or the elevated bootstrap console) blocks the first time msstore is engaged. Every pin check and install then runs with `--disable-interactivity`; installs use `--accept-package-agreements --accept-source-agreements --disable-interactivity`, with `--disable-interactivity` dropped only for a row explicitly marked interactive (`Interactive = y`), since WinGet rejects combining it with `-i`. `--disable-interactivity` requires WinGet 1.6+ (ships with Windows 11).

Every install is verified: a nonzero winget exit code triggers a `winget list --id` ground-truth check (nonzero codes are not uniformly failures - "already installed" variants are benign), and genuinely failed installs are collected and printed as an explicit summary at the end (app id, exit code, and how to retry) instead of scrolling by invisibly in the bootstrap output.

**Data Source:** `WinGetApps.csv`

```csv
App,Version,Scope,Interactive,Source,Machine
Microsoft.VisualStudioCode,Latest,d,n,w,All
Mozilla.Firefox,Latest,d,n,w,All
Valve.Steam,Latest,d,n,w,PC
```

```powershell
# Install all WinGet apps applicable to the current machine type
Install-WingetApps
```

**See also:** [Modules: Bootstrap](bootstrap.md)

## [Invoke-Browser](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Invoke-Browser.ps1)

- **Description:** A thin wrapper around `Open-Browser`. Given a query, it joins the words with spaces and runs `Open-Browser -Search` to perform a Google search in the default browser; called with no arguments it falls through to `Open-Browser`, which shows the URL group selection menu.
- **Parameters:** -Query
- **Usage:** `Invoke-Browser "search terms"`, `Invoke-Browser`, `b "search terms"`
- **Alias:** b

`-Query` accepts one or more words via `ValueFromRemainingArguments`, so the terms can be passed unquoted (e.g. `b search terms`) and are joined into a single search string. The alias `b` is defined in the PowerShell profile (`New-Alias -Name b -Value Invoke-Browser`).

```powershell
# Search Google in the default browser
Invoke-Browser "search terms"

# Same search via the alias, words passed unquoted
b search terms

# No query: fall through to Open-Browser's group selection menu
Invoke-Browser
```

**See also:** [Open-Browser](../modules/application.md)

## [Open-Acrobat](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Open-Acrobat.ps1)

- **Description:** Opens Adobe Acrobat with one or more PDF groups defined in `AcrobatPdfGroups` in `Configuration.psd1`. When a PDF key (or keys) is given it opens the corresponding file(s) directly; called with no arguments it just launches Acrobat (or reports it is already running), and with an empty `-Pdf` it shows an interactive menu of configured groups plus up to 10 recently opened PDFs.
- **Parameters:** -Pdf
- **Usage:** `Open-Acrobat`, `Open-Acrobat -Pdf ""`, `Open-Acrobat -Pdf "MyDocs"`, `Open-Acrobat -Pdf "MyDocs","OtherDocs"`
- **PDFs:** Configured groups from `AcrobatGroups` / `AcrobatPdfGroups` (+ up to 10 recent PDFs in the interactive menu)

The interactive menu (shown when `-Pdf` is empty) lists the configured groups from `AcrobatGroups` alongside recently opened PDFs and supports selecting one or more. Recent PDFs are gathered first from the Acrobat registry history at `HKCU:\Software\Adobe\Adobe Acrobat\DC\AVGeneral\cRecentFiles`, then, if fewer than 10 are found, from Windows `Recent` (`.lnk`) shortcuts as a fallback. Group paths are resolved through `$global:MachineSpecificPaths`, so each entry validates the resolved path before launching.

| Parameter | Description                                                                                                                                                     |
| --------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-Pdf`    | One or more PDF group key names from `AcrobatPdfGroups`. Omit to launch Acrobat only; pass an empty string to open the interactive group/recent selection menu. |

```powershell
# Launch Adobe Acrobat only (no PDFs)
Open-Acrobat

# Interactive menu of configured groups + recent PDFs
Open-Acrobat -Pdf ""

# Open one configured group
Open-Acrobat -Pdf "MyDocs"

# Open multiple configured groups
Open-Acrobat -Pdf "MyDocs","OtherDocs"
```

## [Open-Browser](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Open-Browser.ps1)

- **Description:** The primary browser launcher for the entire system. Opens configured URL groups from `BrowserGroups` in `Configuration.psd1` (by name, with dot-notation for nested groups) in the configured browser, performs a Google search with `-Search`, or opens the browser bare / a target number of instances with `-NoMenu`. Before opening a group it matches open browser window titles against the group's URLs and skips groups that already appear open (idempotent) unless `-Override` is set. With no group specified it shows an interactive selection menu.
- **Parameters:** -Groups, -Private, -NoMenu, -Search, -Browser, -Override, -Instances
- **Usage:** `Open-Browser`, `Open-Browser GroupName`, `Open-Browser Parent.ChildGroup`, `Open-Browser GroupA,GroupB`, `Open-Browser -Search "search terms"`, `Open-Browser -Private GroupName`, `Open-Browser GroupName -Override`, `Open-Browser -NoMenu -Browser PreferredBrowser -Instances 2`

The default browser is read from `Configuration.Universal.DefaultBrowser`; browser definitions (executable path, private/incognito argument, new-window argument) come from `Configuration.Universal.Browsers`, so any browser key defined there (e.g. Firefox, Chrome, Edge, Brave, Tor) can be passed to `-Browser`. Groups support unlimited hierarchical nesting and are addressed with dot-notation. Private mode cannot be combined with group opening (it falls back to normal mode for groups) but does support `-Search`. `-Instances N` is rerun-safe: it counts how many matching windows already exist and opens only the deficit.

| Parameter    | Description                                                                                                                        |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| `-Groups`    | One or more group names to open (dot-notation for nested, e.g. `Parent.ChildGroup`). Omit to show the interactive menu.            |
| `-Private`   | Opens the browser in private/incognito mode. Cannot be combined with group opening.                                                |
| `-NoMenu`    | Skips the menu and opens the browser directly with no URLs loaded.                                                                 |
| `-Search`    | Performs a Google search with the given query, opening directly without the menu.                                                  |
| `-Browser`   | Browser to use; defaults to `Configuration.Universal.DefaultBrowser`. Valid values are keys in `Configuration.Universal.Browsers`. |
| `-Override`  | Bypasses idempotency, opening groups even if they appear to already be open.                                                       |
| `-Instances` | Target number of browser windows to have open; counts existing windows and opens only the deficit. 0 means open exactly one.       |

```powershell
# Interactive group selection menu
Open-Browser

# Open a configured group, or a nested group via dot-notation
Open-Browser GroupName
Open-Browser Parent.ChildGroup

# Web search in the default browser
Open-Browser -Search "search terms"

# Ensure exactly N windows of a group are open (only opens the deficit on rerun)
Open-Browser GroupName -Instances 3

# Force-open a group even if it looks already open
Open-Browser GroupName -Override
```

**See also:** [Add Browser Group](../configuration/guides/add-browser-group.md)

## [Open-ClaudeDesktop](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Open-ClaudeDesktop.ps1)

- **Description:** Opens Claude Desktop via `Start-Application` using its local electron launcher under `%LOCALAPPDATA%\AnthropicClaude`. Does nothing if Claude Desktop is already running. The running check is scoped to the Claude Desktop install directory so it is not tripped by the Claude Code CLI, which also runs as a process named `claude`.
- **Usage:** `Open-ClaudeDesktop`

Launches `claude.exe` from `%LOCALAPPDATA%\AnthropicClaude` via `Start-Application -StartMethod DirectPath`, passing `--processStart claude.exe`. The `-ProcessPathFilter` restricts the "already running" detection to processes under the Claude Desktop install path, so the desktop app is distinguished from the `claude` CLI.

```powershell
# Open Claude Desktop (no-op if already running)
Open-ClaudeDesktop
```

## [Open-DBeaver](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Open-DBeaver.ps1)

- **Description:** Opens the DBeaver database client via the shared `Start-Application` helper. Does nothing if DBeaver is already running. The executable path is read from the `DbeaverExe` key in the Universal configuration section.
- **Usage:** `Open-DBeaver`

## [Open-Discord](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Open-Discord.ps1)

- **Description:** Opens Discord. Starts Discord via `Start-Application` using its `Update.exe` launcher; does nothing if Discord is already running.
- **Usage:** `Open-Discord`

## [Open-Docker](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Open-Docker.ps1)

- **Description:** Starts Docker Desktop minimized to the system tray. Launches it with the `--minimized` flag so it appears in the tray without opening the main window, and suppresses Electron/Bugsnag console output via `-SuppressOutput`. Does nothing if Docker Desktop is already running.
- **Usage:** `Open-Docker`

The executable path is read from the `DockerExe` key in the `Universal` section of `Configuration.psd1`. Console noise (Electron, Bugsnag, GPU process messages) is silenced automatically so the launch is quiet.

```powershell
# Start Docker Desktop minimized to the tray (no-op if already running)
Open-Docker
```

## [Open-FoundryVTT](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Open-FoundryVTT.ps1)

- **Description:** Opens the FoundryVTT virtual tabletop server by starting the FoundryVTT desktop application via `Start-Application`. Does nothing if FoundryVTT is already running. The executable path is read from the `FoundryVTTExe` key in the `Universal` section of `Configuration.psd1`.
- **Usage:** `Open-FoundryVTT`

## [Open-LeagueOfLegends](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Open-LeagueOfLegends.ps1)

- **Description:** Opens the League of Legends client via `Start-Application`. Does nothing if the client is already running. The executable path is read from `Configuration.Universal.LeagueOfLegendsExe`.
- **Usage:** `Open-LeagueOfLegends`

## [Open-NotepadPlusPlus](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Open-NotepadPlusPlus.ps1)

- **Description:** Opens Notepad++, optionally with a specific file. When given a file path it opens that file, but if the file is already open in an existing Notepad++ window it focuses that window instead of opening a duplicate. Called without arguments, it opens Notepad++ without any file.
- **Parameters:** -File
- **Usage:** `Open-NotepadPlusPlus`, `Open-NotepadPlusPlus .\MyFile.txt`, `Open-NotepadPlusPlus -File "C:\Users\<User>\config.json"`

The Notepad++ executable is resolved from the `Universal.NotepadPlusPlusExe` key in `Configuration.psd1`. When a file is supplied its path is resolved, then existing Notepad++ window titles are checked for the file name; a match focuses the running window rather than launching a second copy. With no file argument it falls back to `Start-Application` to launch (or focus) Notepad++.

| Parameter | Description                                                      |
| --------- | ---------------------------------------------------------------- |
| `-File`   | Path to the file to open. Omit to open Notepad++ without a file. |

```powershell
# Open Notepad++ with no file
Open-NotepadPlusPlus

# Open a specific file (focuses the window if already open)
Open-NotepadPlusPlus -File "C:\Users\<User>\config.json"
```

## [Open-Obsidian](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Open-Obsidian.ps1)

- **Description:** Opens Obsidian by launching the vault startup Python script (`ObsidianStartupScript.pyw` via `pythonw`), with the script path resolved from `$MachineSpecificPaths.ObsidianStartupScript`. Does nothing if Obsidian is already running.
- **Usage:** `Open-Obsidian`

## [Open-Outlook](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Open-Outlook.ps1)

- **Description:** Opens the new Outlook (Microsoft Store app) through the shared `Start-Application` launcher, using configuration-driven values from `Configuration.psd1` (`OutlookLauncherExe` plus the Outlook AppsFolder argument). Does nothing if Outlook is already running.
- **Usage:** `Open-Outlook`

If Outlook is already running (the `olk` process), no new instance is launched.

## [Open-RiseupVPN](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Open-RiseupVPN.ps1)

- **Description:** Opens RiseupVPN via `Start-Application`. Does nothing if RiseupVPN is already running. The executable path is read from the `RiseupVpnExe` key in the `Universal` configuration section.
- **Usage:** `Open-RiseupVPN`

## [Open-SecureBrowser](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Open-SecureBrowser.ps1)

- **Description:** Establishes a VPN-protected Tor Browser session with IP verification. Retrieves and displays the current ISP IP before connecting, starts RiseupVPN and waits for manual connection confirmation, hides the RiseupVPN window to the system tray via the Win32 ShowWindow API (SW_HIDE), opens Tor Browser, then runs `Test-PrivacyStatus` in Tor mode to verify the IP has changed.
- **Usage:** `Open-SecureBrowser`

Runs a multi-step privacy workflow:

1. Retrieves the current ISP IP address before connecting the VPN.
2. Starts RiseupVPN.
3. Waits for manual confirmation that the VPN is connected.
4. Hides the RiseupVPN window to the system tray (Win32 `ShowWindow` SW_HIDE).
5. Opens Tor Browser.
6. Waits 5 seconds for Tor Browser to initialize.
7. Calls `Test-PrivacyStatus` in Tor mode to verify the IP has changed.

Requires the Window module to be loaded (for Win32 `ShowWindow` access).

> **Requires Tor Browser** - the base bootstrap does not install it. Enable the commented
> `TorProject.TorBrowser` row in `WinGetApps.csv` (WinGet installs the portable build onto the
> Desktop; move the "Tor Browser" folder to `{User}\Tor Browser`, where the default
> `Universal.Browsers.Tor` entry points), install it manually, or provision it in a fork via
> `BootstrapConfig.PersonalSteps`.

```powershell
# Start the full VPN + Tor Browser privacy session
Open-SecureBrowser
```

## [Open-Slack](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Open-Slack.ps1)

- **Description:** Opens Slack. Starts Slack via `Start-Application` using its local Electron launcher, and does nothing if Slack is already running.
- **Usage:** `Open-Slack`

## [Open-Steam](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Open-Steam.ps1)

- **Description:** Opens Steam via `Start-Application`. Does nothing if Steam is already running. The executable path is read from `Configuration.Universal.SteamExe`.
- **Usage:** `Open-Steam`

## [Open-TeamViewer](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Open-TeamViewer.ps1)

- **Description:** Opens TeamViewer via `Start-Application`. Does nothing if TeamViewer is already running. The executable path is read from the `TeamViewerExe` key in the Universal configuration section.
- **Usage:** `Open-TeamViewer`

## [Open-Terminal](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Open-Terminal.ps1)

- **Description:** Opens Windows Terminal in a new window or in the current shell, optionally running one or more commands in separate tabs with custom tab titles. Each command runs in its own tab (base64-encoded internally for reliable execution) and titles persist even after running commands that would normally change the window title. Supports administrator privileges and an explicit `-WindowId` for grouping tabs from different calls into the same window.
- **Parameters:** -Command, -Administrator, -InSameShell, -WindowId, -TabTitles
- **Usage:** `Open-Terminal`, `Open-Terminal -Administrator`, `Open-Terminal -Command "git status", "npm run dev"`, `Open-Terminal -Command "Set-Location <DevRoot>\MyProject", "Set-Location <DevRoot>\OtherProject" -TabTitles "MyProject", "OtherProject" -InSameShell`, `Open-Terminal -Command "echo hello" -WindowId "my-window-id"`
- **Alias:** t

Opens a fresh Windows Terminal window by default. When `-Command` is supplied, each command opens in its own new tab; tab titles are set via an env var marker and wrapped in a `try/finally` so the title is restored after `Ctrl+C` or long-running commands. Use `-InSameShell` to target the current window (window ID 0), or pass an explicit `-WindowId` (which takes precedence over `-InSameShell`) to group tabs from separate calls into one window. Spawned tabs run `pwsh` with `-NoProfileLoadTime`, so the "Loading personal and system profiles took NNNms" banner never appears in them regardless of machine speed.

| Parameter        | Description                                                                                            |
| ---------------- | ------------------------------------------------------------------------------------------------------ |
| `-Command`       | Array of commands to execute, each in its own tab (base64-encoded internally).                         |
| `-Administrator` | Opens Windows Terminal with elevated privileges.                                                       |
| `-InSameShell`   | Opens tabs in the current Windows Terminal window instead of a new window (targets `$env:WT_WINDOW_ID` when the calling shell knows its window, e.g. inside `Open-Workspace -Alongside`; otherwise ID 0 = the most recently used window). Default: new window. |
| `-WindowId`      | Explicit Windows Terminal window ID to open tabs in; overrides `-InSameShell`.                         |
| `-TabTitles`     | Array of custom tab titles; should match the number of commands.                                       |

```powershell
# Open a new Windows Terminal window
Open-Terminal

# Open elevated
Open-Terminal -Administrator

# Run commands in separate, titled tabs
Open-Terminal -Command "git status", "npm run dev" -TabTitles "Git", "Dev"

# Open project tabs in the current window
Open-Terminal -Command "Set-Location <DevRoot>\MyProject", "Set-Location <DevRoot>\OtherProject" -TabTitles "MyProject", "OtherProject" -InSameShell

# Group tabs from different calls into one window by ID
Open-Terminal -Command "echo hello" -WindowId "my-window-id"
```

## [Open-VirtualBox](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Open-VirtualBox.ps1)

- **Description:** Opens Oracle VirtualBox via `Start-Application`. Does nothing if VirtualBox is already running. The executable path is read from the `VirtualBoxExe` key in the Universal configuration section.
- **Usage:** `Open-VirtualBox`

## [Open-VisualStudio](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Open-VisualStudio.ps1)

- **Description:** Opens one or more Visual Studio solutions configured in `VisualStudioSolutions` in `Configuration.psd1`, where each entry maps a name to a `.sln` file path. Omit `-Solution` to show an interactive selection menu, or use `-Default` to open the first configured solution. With no menu selection it launches Visual Studio bare. Solutions already open (detected by matching window title) are skipped.
- **Parameters:** -Default, -Solution
- **Usage:** `Open-VisualStudio`, `Open-VisualStudio -Solution MySolution`, `Open-VisualStudio -Default`

Reads the solution list from `VisualStudioSolutions` and resolves the Visual Studio executable from `Universal.VisualStudio2026Exe`. Each solution's `.sln` path is resolved against `MachineSpecificPaths`, so configured solutions follow machine-specific dev roots. If `-Solution` is omitted you get an interactive menu (which also supports multiple selections); if you make no selection, Visual Studio is opened without a solution. With `-Default`, the first solution in the list opens immediately without a menu.

| Parameter   | Description                                                                                                    |
| ----------- | -------------------------------------------------------------------------------------------------------------- |
| `-Default`  | Opens the first solution defined in `VisualStudioSolutions` without showing a menu.                            |
| `-Solution` | One or more solution names as defined in `VisualStudioSolutions`. Omit to show the interactive selection menu. |

```powershell
# Interactive solution selection menu
Open-VisualStudio

# Open a specific configured solution by name
Open-VisualStudio -Solution MySolution

# Open the first configured solution without prompting
Open-VisualStudio -Default
```

## [Open-VSCode](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Open-VSCode.ps1)

- **Description:** Opens one or more VS Code project folders defined in `VSCodeProjects` in `Configuration.psd1`. Each entry maps a name to a directory path. Omit `-Folder` to show an interactive selection menu, or use `-Default` to open the first configured project. Folders already open (detected by matching window title) are skipped.
- **Parameters:** -Default, -Folder
- **Usage:** `Open-VSCode`, `Open-VSCode MyProject`, `Open-VSCode MyProject OtherProject`, `Open-VSCode -Folder MyProject`, `Open-VSCode -Default`

Reads the `VSCodeProjects` array from `Configuration.psd1`, building a name-to-path lookup. Each path is resolved through the machine-specific path map, so the same project name works across machines. When `-Folder` is omitted and `-Default` is not set, an interactive menu lists the available folders and supports multiple selections. With no projects selected, VS Code is launched bare (skipped if `Code` is already running). For each selected folder the path is validated with `Test-Path`, the folder is opened in a new window with `code -n`, and `Test-ProjectAlreadyOpen` prevents reopening a folder that already has a window.

| Parameter  | Description                                                                                            |
| ---------- | ------------------------------------------------------------------------------------------------------ |
| `-Default` | Opens the first project defined in `VSCodeProjects` without showing a menu.                            |
| `-Folder`  | One or more project names as defined in `VSCodeProjects`. Omit to show the interactive selection menu. |

```powershell
# Interactive folder selection menu (or bare VS Code if nothing selected)
Open-VSCode

# Open a single configured project folder
Open-VSCode MyProject

# Open multiple configured project folders at once
Open-VSCode MyProject OtherProject

# Open the first project in VSCodeProjects without prompting
Open-VSCode -Default
```

## [Open-VSCodeWorkspace](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Open-VSCodeWorkspace.ps1)

- **Description:** Opens a VS Code multi-root workspace (`*.code-workspace`) from `Projects.Self.VSCodeWorkspaces` (`<repo>\VSCode\Workspaces`). A workspace is addressed by its file base name (e.g. `Consolidation` => `Consolidation.code-workspace`). Omit `-VSCodeWorkspace` to show an interactive selection menu. A workspace already open (detected by its `<name> (Workspace)` window title) is skipped.
- **Parameters:** -VSCodeWorkspace
- **Usage:** `Open-VSCodeWorkspace`, `Open-VSCodeWorkspace Consolidation`

The workspace counterpart to `Open-VSCode`: where `Open-VSCode` opens a project FOLDER, this opens a `.code-workspace` FILE. `Open-Workspace` reroutes its `Open-VSCode` action here when a `-VSCodeWorkspace` override is active, so the workspace opens in place of the project folder and the window layout can target it. Names come from `Get-VSCodeWorkspaceNames`, selection uses `Resolve-Selection`, each file is opened with `code -n`, and `Test-ProjectAlreadyOpen` prevents reopening one that already has a window.

| Parameter          | Description                                                                                                            |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------- |
| `-VSCodeWorkspace` | One or more workspace names (file base names) from the Workspaces folder. Omit to show the interactive selection menu. |

```powershell
# Interactive workspace selection menu
Open-VSCodeWorkspace

# Open a specific workspace file (VSCode/Workspaces/Consolidation.code-workspace)
Open-VSCodeWorkspace Consolidation
```

## [Open-WhatsApp](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Open-WhatsApp.ps1)

- **Description:** Opens the WhatsApp Microsoft Store app via its AppxPackage using `Start-Application`. Does nothing if WhatsApp is already running.
- **Usage:** `Open-WhatsApp`

## [Open-WSLTab](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Open-WSLTab.ps1)

- **Description:** Opens a new WSL tab in the currently focused Windows Terminal window using `wt.exe -w 0 new-tab`. The WSL distribution is read from the `DefaultWSLDistribution` key in `Configuration.psd1`.
- **Usage:** `Open-WSLTab`

## [Start-Application](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Start-Application.ps1)

- **Description:** Common (DRY) helper to start applications with standardized error handling, process checking, and user feedback. Supports four start methods: ConfigPath (resolves `$Configuration.Universal.[ConfigKey]`), AppxPackage (UWP/Store apps via `Get-AppxPackage`), DirectPath (a direct executable path), and Custom (a scriptblock for complex scenarios). Applications are non-blocking by default since `Start-Process` is inherently async; use `-Sync` to wait for the process to exit before continuing.
- **Parameters:** -AppName, -ProcessName, -StartMethod, -ConfigKey, -PackageName, -ExecutableName, -ExecutablePath, -Arguments, -NoNewWindow, -SkipProcessCheck, -ProcessPathFilter, -SkipPathValidation, -Sync, -SuppressOutput, -CustomStartLogic
- **Usage:** `Start-Application -AppName "VirtualBox" -ProcessName "VirtualBox" -StartMethod ConfigPath -ConfigKey "VirtualBoxExe" -NoNewWindow`, `Start-Application -AppName "Outlook" -ProcessName "olk" -StartMethod AppxPackage -PackageName "Microsoft.Outlook" -ExecutableName "olk.exe"`, `Start-Application -AppName "Docker" -ProcessName "Docker Desktop" -StartMethod DirectPath -ExecutablePath $dockerExe -Sync`, `Start-Application -AppName "Docker Desktop" -ProcessName "Docker Desktop" -StartMethod ConfigPath -ConfigKey "DockerExe" -Arguments "--minimized" -SuppressOutput`

A generic application launcher that consolidates the common patterns of checking whether a process is already running, starting it via one of four methods, and reporting success or failure. Before launching it checks for an existing process (unless `-SkipProcessCheck`) and short-circuits with a notice if the app is already running. When two apps share a process name (e.g. Claude Desktop and the Claude Code CLI both run as `claude`), pass `-ProcessPathFilter` to scope that check to a specific install location so one app is not mistaken for the other. All four methods share consistent handling of `-Arguments`, `-Sync` (maps to `-Wait`), `-NoNewWindow`, and `-SuppressOutput` (redirects stdout/stderr to temp files, silencing console noise from chatty apps such as Electron-based Docker Desktop).

| Method        | Description                                                                                                                                        |
| ------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ConfigPath`  | Resolves the executable from `$Configuration.Universal.[ConfigKey]`. Requires `-ConfigKey`.                                                        |
| `AppxPackage` | Locates a UWP/Store app via `Get-AppxPackage` and runs `-ExecutableName` from its install location. Requires `-PackageName` and `-ExecutableName`. |
| `DirectPath`  | Launches `-ExecutablePath` directly (validated unless `-SkipPathValidation`).                                                                      |
| `Custom`      | Invokes the `-CustomStartLogic` scriptblock for complex scenarios.                                                                                 |

| Parameter             | Description                                                                                                                               |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `-AppName`            | Display name of the application (used in messages). Mandatory.                                                                            |
| `-ProcessName`        | Process name used to check whether the app is already running. Mandatory.                                                                 |
| `-StartMethod`        | One of `ConfigPath`, `AppxPackage`, `DirectPath`, `Custom`. Mandatory.                                                                    |
| `-ConfigKey`          | Configuration key under `Universal` for the ConfigPath method (e.g. `VirtualBoxExe`).                                                     |
| `-PackageName`        | Package name pattern for the AppxPackage method (e.g. `Microsoft.Outlook`).                                                               |
| `-ExecutableName`     | Executable within the package for the AppxPackage method (e.g. `olk.exe`).                                                                |
| `-ExecutablePath`     | Direct path to the executable for the DirectPath method.                                                                                  |
| `-Arguments`          | Optional arguments passed to `Start-Process`.                                                                                             |
| `-NoNewWindow`        | Passes `-NoNewWindow` to `Start-Process`.                                                                                                 |
| `-SkipProcessCheck`   | Skips the "already running" process check.                                                                                                |
| `-ProcessPathFilter`  | Wildcard pattern scoping the "already running" check to processes launched from a specific location (for apps that share a process name). |
| `-SkipPathValidation` | Skips the executable path existence check (DirectPath method).                                                                            |
| `-Sync`               | Waits for the process to exit before returning (uses `-Wait`).                                                                            |
| `-SuppressOutput`     | Redirects stdout/stderr to temp files, silencing console output from the launched process.                                                |
| `-CustomStartLogic`   | Scriptblock executed for the Custom start method.                                                                                         |

```powershell
# Config-driven launch, non-blocking (returns immediately)
Start-Application -AppName "DBeaver" -ProcessName "dbeaver" `
    -StartMethod ConfigPath -ConfigKey "DbeaverExe"

# UWP/Store app via AppxPackage
Start-Application -AppName "Outlook" -ProcessName "olk" `
    -StartMethod AppxPackage -PackageName "Microsoft.Outlook" `
    -ExecutableName "olk.exe"

# Direct path launch
Start-Application -AppName "Discord" -ProcessName "Discord" `
    -StartMethod DirectPath -ExecutablePath "$env:LOCALAPPDATA\Discord\Update.exe"

# Synchronous launch - wait for the process to exit
Start-Application -AppName "Docker" -ProcessName "Docker Desktop" `
    -StartMethod DirectPath -ExecutablePath $dockerExe -Sync

# Suppress stdout/stderr from a noisy (e.g. Electron) app
Start-Application -AppName "Docker Desktop" -ProcessName "Docker Desktop" `
    -StartMethod ConfigPath -ConfigKey "DockerExe" `
    -Arguments "--minimized" -SuppressOutput

# Scope the "already running" check to a specific install location so a
# same-named process (e.g. the Claude Code CLI) does not block the launch
Start-Application -AppName "Claude" -ProcessName "claude" `
    -ProcessPathFilter "$env:LOCALAPPDATA\AnthropicClaude\*" `
    -StartMethod DirectPath -ExecutablePath "$env:LOCALAPPDATA\AnthropicClaude\claude.exe"
```

## [Start-FancyZones](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Start-FancyZones.ps1)

- **Description:** Ensures PowerToys FancyZones is running and actually ready before returning success, with RPC health verification. Checks for the `PowerToys.FancyZones` process and, if it is missing or unhealthy, launches PowerToys and waits for FancyZones to initialize. Readiness requires a stable PID across multiple polls, healthy RPC services (RpcSs, DcomLaunch, RpcEptMapper), an existing FancyZones configuration directory, and parseable JSON state files when present. It also fixes the problematic state where PowerToys is running without FancyZones by performing a full shutdown through `Stop-PowerToysCompletely` before relaunch, and closes unwanted `PowerToys.Settings` windows to keep startup headless.
- **Parameters:** -MaxWaitSeconds, -ForceRestart
- **Usage:** `Start-FancyZones`, `Start-FancyZones -MaxWaitSeconds 15`, `Start-FancyZones -ForceRestart`, `Start-FancyZones -ForceRestart -MaxWaitSeconds 20`
- **Notes:** Returns `$true` if FancyZones is running and ready, `$false` if it could not be started. A loading spinner stays visible until FancyZones is ready or startup fails, then stops before the function returns; under `Set-LogLevel Verbose` the spinner is suppressed and detailed diagnostics are shown instead.

When `-ForceRestart` is given (or readiness checks fail for an existing process), the function calls `Stop-PowerToysCompletely -PreferGracefulExit` to fully shut down PowerToys, then relaunches from a common install location and re-verifies readiness. This guarantees reliability when applying zones rapidly or in close succession, where FancyZones may otherwise not respond correctly.

| Parameter         | Description                                                                          |
| ----------------- | ------------------------------------------------------------------------------------ |
| `-MaxWaitSeconds` | Maximum time to wait for FancyZones to start (default: 10 seconds).                  |
| `-ForceRestart`   | Forces a full PowerToys shutdown and relaunch even if FancyZones is already running. |

```powershell
# Ensure FancyZones is running with the default wait time
Start-FancyZones

# Wait up to 15 seconds for FancyZones to become ready
Start-FancyZones -MaxWaitSeconds 15

# Force a full restart and wait longer for a cold start
Start-FancyZones -ForceRestart -MaxWaitSeconds 20

# Verbose diagnostic output
Set-LogLevel Verbose { Start-FancyZones }
```

## [Start-MicrosoftActivationScripts](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Start-MicrosoftActivationScripts.ps1)

- **Description:** Runs the Microsoft Activation Scripts (MAS) to activate Windows and Office. Downloads and runs the official online activation method via `irm https://get.activated.win | iex`. With no arguments and `-Override` not set, it checks whether Windows is already activated (and whether Office is installed) and skips if so; use `-Override` to force re-activation.
- **Parameters:** -Selection, -Override
- **Usage:** `Start-MicrosoftActivationScripts`, `Start-MicrosoftActivationScripts -Override`, `Start-MicrosoftActivationScripts -Selection Yes`

This function is only called automatically during `Bootstrap -WithInitialSetup` (first-time provisioning). It detects current Windows activation state via `slmgr.vbs /xpr` and detects installed Office by inspecting the registered applications under `HKLM:\Software\RegisteredApplications`. When both Windows is already activated and Office is installed, it returns early unless `-Override` is supplied. Otherwise it presents an interactive Yes/No prompt (defaulting to No) before downloading and running MAS. The underlying activation tooling is the [Microsoft-Activation-Scripts](https://github.com/massgravel/Microsoft-Activation-Scripts) project by massgravel.

| Parameter    | Description                                                                                  |
| ------------ | -------------------------------------------------------------------------------------------- |
| `-Selection` | Pre-selects the activation method by name (e.g. `Yes`/`No`), bypassing the interactive menu. |
| `-Override`  | Forces the activation script to run even if Windows appears to already be activated.         |

```powershell
# Check activation status and run MAS only if Windows is not activated
Start-MicrosoftActivationScripts

# Run MAS regardless of current activation status
Start-MicrosoftActivationScripts -Override

# Pre-select the prompt response and skip the interactive menu
Start-MicrosoftActivationScripts -Selection Yes
```

## [Start-Win11Debloat](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Start-Win11Debloat.ps1)

- **Description:** Runs the vendored Win11Debloat script from the local repository to remove bloatware, disable telemetry, and apply system tweaks. Validates administrator privileges first, then runs with saved settings if available or shows the interactive Win11Debloat menu. Called automatically during `Bootstrap -WithInitialSetup` (first-time provisioning).
- **Notes:** Saved settings stored in `Windows\Win11Debloat` are symlinked into the vendored script's `Config` folder before execution, and `-RunSavedSettings` is passed to apply them. Missing settings files are created automatically so new machines always persist changes back into tracked dotfiles.
- **Parameters:** -Selection (pre-selects a menu option: "Use saved settings", "Debloat", or "Don't debloat")
- **Usage:** `Start-Win11Debloat`, `Start-Win11Debloat -Selection "Debloat"`

The vendored script path comes from `BootstrapConfig.LocalScripts.Win11Debloat` (falling back to `Windows\Win11Debloat\vendor\Win11Debloat.ps1`). If the script is missing, the function reports the expected path and prompts you to download a release into `Windows\Win11Debloat\vendor` first. Elevation is verified with `Test-AdminPrivileges` before invoking, which prevents the upstream self-elevation prompt. The available menu options depend on whether saved settings (`CustomAppsList` and `LastUsedSettings`) are present. The vendored upstream source is the [Win11Debloat](https://github.com/Raphire/Win11Debloat) project by Raphire.

| Parameter    | Description                                                                                                                                                                      |
| ------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-Selection` | Pre-selects a Win11Debloat menu option by name, bypassing the interactive menu. Valid values: `Use saved settings` (only when saved settings exist), `Debloat`, `Don't debloat`. |

```powershell
# Run with saved settings if available, otherwise show the interactive menu
Start-Win11Debloat

# Skip the menu and run a full debloat directly
Start-Win11Debloat -Selection "Debloat"
```

**See also:** [Update-Win11DebloatVendor](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Update-Win11DebloatVendor.ps1)

## [Stop-PowerToysCompletely](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Stop-PowerToysCompletely.ps1)

- **Description:** Performs a complete PowerToys shutdown sequence that mirrors manual tray exit behavior, used by FancyZones recovery and restart flows. It optionally requests a tray-like graceful exit via the main PowerToys window, waits briefly for clean shutdown, then force-stops any remaining PowerToys processes and escalates to `taskkill` process tree termination as a final fallback. Returns `$true` only when no `PowerToys*` process remains.
- **Parameters:** -PreferGracefulExit, -MaxGracefulWaitMs
- **Usage:** `Stop-PowerToysCompletely`, `Stop-PowerToysCompletely -PreferGracefulExit`, `Stop-PowerToysCompletely -PreferGracefulExit -MaxGracefulWaitMs 5000`

The shutdown proceeds in escalating stages. When `-PreferGracefulExit` is set it first calls `CloseMainWindow()` on the main PowerToys window (tray-like exit) and polls for up to `-MaxGracefulWaitMs` milliseconds for a clean exit. Any surviving processes are then force-stopped with `Stop-Process -Force`, falling back to `taskkill /F /PID`. If processes still remain it escalates to a tree kill (`taskkill /F /T /IM PowerToys.exe`) and finally per-PID `taskkill` as a best-effort fallback.

| Parameter             | Description                                                                               |
| --------------------- | ----------------------------------------------------------------------------------------- |
| `-PreferGracefulExit` | Attempts a tray-like graceful PowerToys shutdown before force termination.                |
| `-MaxGracefulWaitMs`  | Maximum milliseconds to wait for graceful exit before force termination (default `3000`). |

```powershell
# Force-stop all PowerToys processes (no graceful attempt)
Stop-PowerToysCompletely

# Verbose diagnostic output
Set-LogLevel Verbose { Stop-PowerToysCompletely -PreferGracefulExit }

# Allow a longer graceful window before forcing termination
Stop-PowerToysCompletely -PreferGracefulExit -MaxGracefulWaitMs 5000
```

**See also:** [Start-FancyZones](application.md#start-fancyzones)

## [Test-BrowserGroupAlreadyOpen](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Test-BrowserGroupAlreadyOpen.ps1)

- **Description:** Internal idempotency helper for `Open-Browser`. Checks whether a browser URL group is already open by extracting keywords from the group's URLs and matching them against the window titles of running browser processes. With `-ReturnCount` it returns the number of matching windows instead of a boolean (used by `Open-Browser`'s `-Instances`).
- **Parameters:** -Urls, -Browser, -GroupDisplayName, -CachedBrowserWindows, -ReturnCount
- **Usage:** `Test-BrowserGroupAlreadyOpen -Urls @("https://github.com") -Browser PreferredBrowser -GroupDisplayName GroupName`, `Test-BrowserGroupAlreadyOpen -Urls $urls -Browser PreferredBrowser -GroupDisplayName GroupName -ReturnCount`

Inspects the window titles of running browser processes and matches them against keywords extracted from the supplied URLs (domain, subdomain, path segments, SPA fragments, and localhost ports). Keyword-extraction and matching rules, including localhost patterns, generic-word filtering, domain simplification, exact-title matching for service homepages, and negative matching to exclude sibling services, are read from the `BrowserGroupMatching` section of `Configuration.psd1`. Returns `$true`/`$false` by default, or an integer count with `-ReturnCount`.

| Parameter               | Description                                                                                                                    |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `-Urls`                 | Array of URL strings to check. Keywords are extracted from these for title matching. (Mandatory)                               |
| `-Browser`              | Browser name used to resolve which process names to inspect. (Mandatory)                                                       |
| `-GroupDisplayName`     | Human-readable group name; also used for exact-title matching of service homepages and shown in debug output. (Mandatory)      |
| `-CachedBrowserWindows` | Pre-fetched window handle list. When provided, skips re-enumerating windows (Open-Browser caches windows once for all groups). |
| `-ReturnCount`          | Returns an integer count of matching windows instead of a boolean.                                                             |

```powershell
# Returns $true if a browser window for the group is already open
Test-BrowserGroupAlreadyOpen -Urls @("https://github.com") -Browser PreferredBrowser -GroupDisplayName GroupName

# Verbose diagnostic output
Set-LogLevel Verbose { Test-BrowserGroupAlreadyOpen -Urls @("https://example.com/page1", "https://example.com/page2") -Browser PreferredBrowser -GroupDisplayName GroupName }

# Count how many windows already match this group (used by Open-Browser -Instances)
Test-BrowserGroupAlreadyOpen -Urls $urls -Browser PreferredBrowser -GroupDisplayName GroupName -ReturnCount
```

**See also:** [Open-Browser](#open-browser), [Add Browser Group](../configuration/guides/add-browser-group.md)

## [Test-ProjectAlreadyOpen](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Test-ProjectAlreadyOpen.ps1)

- **Description:** Checks whether a project is already open in a given application by matching the project name against the application's window titles. Returns `$true` and prints a yellow warning if a match is found, otherwise returns `$false`.
- **Parameters:** -ProjectName, -ProcessName, -ApplicationName
- **Usage:** `Test-ProjectAlreadyOpen -ProjectName MyProject -ProcessName "devenv" -ApplicationName "Visual Studio"`, `Test-ProjectAlreadyOpen -ProjectName MyProject -ProcessName "Code" -ApplicationName "VS Code"`

Gets all window handles for the specified process via `Get-WindowHandle`, then performs a case-insensitive match of the project name against each window title. A match prints a warning and returns `$true`; no match (or no windows for the process) returns `$false`. Typically used as an idempotency guard before launching a project so it is not opened twice.

| Parameter          | Description                                                                                                    |
| ------------------ | -------------------------------------------------------------------------------------------------------------- |
| `-ProjectName`     | The project name to search for within window titles. Mandatory.                                                |
| `-ProcessName`     | The process name of the application to check (e.g. `devenv` for Visual Studio, `Code` for VS Code). Mandatory. |
| `-ApplicationName` | Human-readable application name used in the warning message. Mandatory.                                        |

```powershell
# Guard against opening a project that is already open in VS Code
if (-not (Test-ProjectAlreadyOpen -ProjectName MyProject -ProcessName "Code" -ApplicationName "VS Code")) {
    Open-VSCode MyProject
}
```

**See also:** [Add New Project](../configuration/guides/add-new-project.md)

## [Update-Win11DebloatVendor](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Application/Functions/Update-Win11DebloatVendor.ps1)

- **Description:** Updates the vendored Win11Debloat files in this repository. Invokes the repository-local updater script at `Windows\Win11Debloat\Update-Win11DebloatVendor.ps1` from the terminal, refreshing the vendored release in `Windows\Win11Debloat\vendor` and its metadata so `Start-Win11Debloat` stays pinned to a known local version.
- **Parameters:** -ReleaseTag, -Repository
- **Usage:** `Update-Win11DebloatVendor`, `Update-Win11DebloatVendor -ReleaseTag "2026.05.11"`

Locates the WinuX root (from `MachineSpecificPaths.Projects.Self.Root`, falling back to walking up from the script location), then forwards all bound parameters to the local updater script. If the updater script is not found it reports an error and returns without making changes.

| Parameter     | Description                                                                                                   |
| ------------- | ------------------------------------------------------------------------------------------------------------- |
| `-ReleaseTag` | Release tag to vendor (example: `2026.05.11`). Defaults to `latest`, which fetches the newest GitHub release. |
| `-Repository` | GitHub repository in `owner/name` format. Defaults to `Raphire/Win11Debloat`.                                 |

```powershell
# Vendor the latest Win11Debloat release
Update-Win11DebloatVendor

# Pin and vendor a specific release tag
Update-Win11DebloatVendor -ReleaseTag "2026.05.11"
```

## Configuration Reference

Application launchers read their executable paths and browser definitions from the `Universal`
section of `Configuration.psd1`:

```powershell
Universal = @{
    # Executable paths consumed by the Open-* launchers
    DbeaverExe     = "{User}\AppData\Local\DBeaver\dbeaver.exe"
    VirtualBoxExe  = "C:\Program Files\Oracle\VirtualBox\VirtualBox.exe"
    # ... one *Exe key per launcher - see the Configuration Reference for the full list

    # Browser definitions consumed by Open-Browser / Open-SecureBrowser
    Browsers       = @{
        Firefox = @{ Exe = "C:\Program Files\Mozilla Firefox\firefox.exe"; PrivateArg = "-private-window"; NewWindowArg = "-new-window" }
        Tor     = @{ Exe = "{User}\Tor Browser\Browser\firefox.exe" }
    }
    DefaultBrowser = "Firefox"
}
```

See the [Configuration Reference](../configuration/configuration-reference.md) for every key.

## Common Patterns

### Open Project Workflow

```powershell
# Open project in VS Code if not already open
if (-not (Test-ProjectAlreadyOpen -ProjectName "MyProject" -ProcessName "Code" -ApplicationName "VS Code")) {
    Open-VSCode MyProject
}

# Open related browser group
Open-Browser MyProject
```

### Installation Pattern

```powershell
# Full software installation
Install-WingetApps
Install-ScoopApps
Install-ChocolateyApps
Install-PowerShellModules
Create-CondaEnvironments
```
