# System Module

The System module handles **Windows system configuration**, **environment setup**, and **OS-level operations**.

## [Add-WindowsFormsType](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Add-WindowsFormsType.ps1)

- **Description:** Loads the `System.Windows.Forms` assembly into the current PowerShell session via `Add-Type -AssemblyName System.Windows.Forms`. Safe to call multiple times. Used as a helper by functions that open file-picker dialogs or rely on Windows Forms controls. Pass `-Quiet` to suppress the status output messages.
- **Parameters:** -Quiet
- **Usage:** `Add-WindowsFormsType`, `Add-WindowsFormsType -Quiet`

## [Clear-TaskbarPins](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Clear-TaskbarPins.ps1)

- **Description:** Clears all pinned taskbar items by removing the taskbar pin values from the `Taskband` registry key (`HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband`). Restarts Explorer to apply the change unless `-SkipExplorerRestart` is specified. Requires administrator privileges.
- **Parameters:** -SkipExplorerRestart
- **Usage:** `Clear-TaskbarPins`, `Clear-TaskbarPins -SkipExplorerRestart`

Removes the `Favorites`, `FavoritesResolve`, `FavoritesChanges`, `FavoritesVersion`, and `FavoritesRemovedChanges` values under the `Taskband` key, reporting how many were cleared. If the registry path or pin data is missing it reports that there is nothing to clear and returns without error. By default it then restarts Explorer so the empty taskbar takes effect; pass `-SkipExplorerRestart` when the caller (for example `Unpin-TaskbarApps`) will restart Explorer itself, to avoid restarting it twice.

| Parameter              | Description                                                                                                  |
| ---------------------- | ------------------------------------------------------------------------------------------------------------ |
| `-SkipExplorerRestart` | Skips the Explorer restart after clearing pins. Use when Explorer will be restarted by the calling function. |

```powershell
# Clear all taskbar pins and restart Explorer to apply
Clear-TaskbarPins

# Clear pins but leave the Explorer restart to the caller
Clear-TaskbarPins -SkipExplorerRestart
```

## [Clear-WhatsAppLocalStorage](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Clear-WhatsAppLocalStorage.ps1)

- **Description:** Clears WhatsApp Desktop local storage to resolve startup issues. Stops WhatsApp if it is running, lists the contents and total size of the storage directory, then (after confirmation) deletes everything under the path configured in `Configuration.Universal.WhatsAppLocalStoragePath`. Requires administrator privileges.
- **Usage:** `Clear-WhatsAppLocalStorage`

Runs `Test-AdminPrivileges` first, so it must be invoked from an elevated session. If WhatsApp is running it is force-stopped; if the configured storage path no longer exists the function reports that storage is already cleared and returns. Before deleting, it prints a per-directory size breakdown (MB/GB) plus a total, then prompts for confirmation (Enter defaults to Yes). Choosing Yes removes the directory recursively; any other response cancels the operation.

```powershell
# Stop WhatsApp and clear its local storage directory (run elevated)
Clear-WhatsAppLocalStorage
```

## [Close-BrowserWindows](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Close-BrowserWindows.ps1)

- **Description:** Gracefully closes previously discovered browser windows by posting `WM_CLOSE` directly to each supplied native window handle. Operates on the window objects collected by `Get-BrowserWindowsByTarget`, and is used by `Terminate-AllBrowserProcesses` after exclusion filtering has been applied.
- **Parameters:** -WindowsToClose
- **Usage:** `Close-BrowserWindows -WindowsToClose $windows`

Iterates over each supplied window object and posts `WM_CLOSE` (`0x0010`) to its native `Handle` via `[Win32BrowserHelper]::PostMessage`. Because the message is posted directly to each handle, the foreground is never touched, so windows excluded upstream are never accidentally closed by a misfired keystroke.

| Parameter         | Type       | Default | Description                                                                                                        |
| ----------------- | ---------- | ------- | ------------------------------------------------------------------------------------------------------------------ |
| `-WindowsToClose` | `object[]` | -       | Browser window objects containing a native `Handle` property (typically produced by `Get-BrowserWindowsByTarget`). |

```powershell
# Close every browser window collected for the target PIDs
$windows = Get-BrowserWindowsByTarget -TargetPids @(1234) -TitlePattern "Google Chrome"
Close-BrowserWindows -WindowsToClose $windows
```

## [Configure-NerdFont](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Configure-NerdFont.ps1)

- **Description:** Installs and configures a Nerd Font. Reads the available fonts from `NerdFonts` in `Configuration.psd1`; when given a font name it installs that font, and when called without arguments it shows an interactive menu (Enter selects the `DefaultNerdFont`). Requires administrator privileges.
- **Parameters:** -FontName
- **Usage:** `Configure-NerdFont`, `Configure-NerdFont -FontName "JetBrainsMono"`

Copies the matching `.ttf`/`.otf` files from the font's source folder under the WinuX root into the Windows fonts directory and registers them under `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts`. The operation is idempotent: if the target font is already present in both the filesystem and the registry it is skipped, and individual font files that already exist are not re-copied. The font's `SearchPattern` and `FolderName` come from its entry in `NerdFonts`.

| Parameter   | Description                                                                                                                             |
| ----------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `-FontName` | Nerd Font name as defined in `NerdFonts` in `Configuration.psd1` (e.g. `"JetBrainsMono"`). Omit to show the interactive selection menu. |

```powershell
# Show the interactive Nerd Font selection menu (Enter picks DefaultNerdFont)
Configure-NerdFont

# Install a specific Nerd Font by its configured name
Configure-NerdFont -FontName "JetBrainsMono"
```

## [Configure-NuGetConfig](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Configure-NuGetConfig.ps1)

- **Description:** Configures NuGet package source settings for the GitHub Package Registry by copying a NuGet.config template from the WinuX repository to the user's AppData NuGet folder. Source and destination paths are read from `MachineSpecificPaths.NuGetConfig`. If the destination already exists, it compares package sources against the repository template and reconfigures only on a mismatch; otherwise it skips the copy unless `-Override` is set. When a copy is performed it prompts securely for the GitHub username and personal access token (PAT), substituting them into the template.
- **Parameters:** -Override
- **Usage:** `Configure-NuGetConfig`, `Configure-NuGetConfig -Override`

Reads `MachineSpecificPaths.NuGetConfig.SourcePath` and `.DestinationPath`. When the destination exists, it parses both XML files and diffs the `packageSources` entries by key and URL: any missing, extra, or differing source triggers reconfiguration. If the sources match, it reports success and returns without changes. During reconfiguration it prompts for the GitHub username and PAT (entered as a secure string), replaces the `[Username]` and `[Token]` placeholders in the template, creates the destination directory if needed, and writes the resulting file as UTF-8.

| Parameter   | Description                                                                                              |
| ----------- | -------------------------------------------------------------------------------------------------------- |
| `-Override` | Force reconfiguration of NuGet settings even if the destination already exists and matches the template. |

```powershell
# Configure NuGet only if not already correctly set up
Configure-NuGetConfig

# Force a full reconfigure, overwriting the existing config
Configure-NuGetConfig -Override
```

## [Configure-PostgreSqlPasswords](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Configure-PostgreSqlPasswords.ps1)

- **Description:** Changes the `postgres` user password across every installed PostgreSQL version found on the machine. Prompts for the current and new passwords, or with `-Auto` reads them from `PostgreSqlPasswords` in `Configuration.psd1` and applies them without prompting. Already-configured installations are detected and skipped (idempotent); a manual-instructions file is written to the Desktop only for installations that fail.
- **Parameters:** -DefaultOrCurrentPassword, -NewPassword, -Auto
- **Usage:** `Configure-PostgreSqlPasswords`, `Configure-PostgreSqlPasswords -Auto`, `Configure-PostgreSqlPasswords -DefaultOrCurrentPassword foo -NewPassword bar`

Scans `C:\Program Files\PostgreSQL` and `C:\Program Files (x86)\PostgreSQL` for every version's `bin\psql.exe`. For each installation it tries ports 5432, 5433, 5434, and 5435: it first checks whether the new password already authenticates (skip if so), otherwise runs `ALTER USER postgres WITH PASSWORD '<new>'` via a temporary SQL file. A call with no arguments defaults to the configuration values (same as `-Auto`); explicit `-DefaultOrCurrentPassword` / `-NewPassword` override the configuration. If any version fails on all attempted ports (or an unexpected error occurs), step-by-step manual instructions are written to the Desktop via `Write-ManualInstructionsToDesktop`.

| Parameter                   | Description                                                                                                 |
| --------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `-DefaultOrCurrentPassword` | The current PostgreSQL password, used to authenticate before the change.                                    |
| `-NewPassword`              | The new password to set on the `postgres` user.                                                             |
| `-Auto`                     | Reads `DefaultOrCurrent` and `New` from `PostgreSqlPasswords` in `Configuration.psd1` instead of prompting. |

```powershell
# Use the passwords from Configuration.psd1 (PostgreSqlPasswords key)
Configure-PostgreSqlPasswords -Auto

# Equivalent: no arguments defaults to the configuration values
Configure-PostgreSqlPasswords

# Override the configuration with explicit current/new passwords
Configure-PostgreSqlPasswords -DefaultOrCurrentPassword foo -NewPassword bar
```

## [Configure-Taskbar](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Configure-Taskbar.ps1)

- **Description:** Configures the Windows taskbar pins from configuration. Clears all existing pins (via `Unpin-TaskbarApps`), builds an XML layout from `TaskbarConfiguration` in `Configuration.psd1`, then applies it with an unlock -> apply -> restart Explorer -> lock sequence optimized for Windows 11. Requires administrator privileges.
- **Parameters:** -FromBootstrap
- **Usage:** `Configure-Taskbar`, `Configure-Taskbar -FromBootstrap`

Resolves the current machine type (via `DetermineMachineType`) and states in the output which machine the pins are being configured for (or that the hostname is unmapped and the default set is used). Reads the pin list from `TaskbarConfiguration` (each entry is either an `AUMID` or a `Path`, with `{User}` tokens expanded to the current profile), keeping only rows whose `Machine` scope matches the machine type - the same `Test-MachineTypeScope` gate the app CSVs use; a row without `Machine` defaults to `All`. It writes the generated layout directly to the machine-local `TaskbarLayoutFile` (`C:\ProgramData\provisioning\taskbar_layout.xml`) - not versioned in the repo and needing no symlink - sets the `StartLayoutFile` and `LockedStartLayout` registry policies under `HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer`, restarts Explorer (`Restart-Explorer`), and rebuilds the icon cache (`Rebuild-IconCache`). With `-FromBootstrap`, it skips the 5-second Explorer-initialization wait and leaves the layout unlocked so the Bootstrap script can lock it after its own Explorer restart.

| Parameter        | Description                                                                                                                                                |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-FromBootstrap` | Skips the 5-second wait for Explorer initialization and leaves the layout unlocked for the Bootstrap sequence to lock later. Used internally during setup. |

```powershell
# Clear and reconfigure the taskbar pins (interactive use)
Configure-Taskbar

# Internal use during the bootstrap sequence (skips the init delay, leaves layout unlocked)
Configure-Taskbar -FromBootstrap
```

**See also:** [Clear-TaskbarPins](system.md#clear-taskbarpins), [Get-PinnedApps](system.md#get-pinnedapps)

## [Configure-WSL](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Configure-WSL.ps1)

- **Description:** Enables the Windows Subsystem for Linux optional feature (if not already enabled) and installs the default WSL distribution read from `DefaultWSLDistribution` in `Configuration.psd1` (if not already installed). On first installation it launches WSL so you can set up the user account. Requires administrator privileges.
- **Usage:** `Configure-WSL`

Checks `Test-WSLEnabled` and enables the `Microsoft-Windows-Subsystem-Linux` optional feature with `-NoRestart` when needed. It then checks `Test-WSLDistributionInstalled` and, if the distribution is missing, runs `wsl --install -d <distro> --no-launch` followed by a bare `wsl` launch for the initial setup. On that first launch you are prompted to create the WSL user account (username and a sudo password); use `exit` to let setup continue. Both stages are idempotent and report when WSL or the distribution is already present.

**See also:** [Configure-WSLSSH](#configure-wslssh)

## [Configure-WSLSSH](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Configure-WSLSSH.ps1)

- **Description:** Configures SSH inside WSL for proper security. Copies the Windows `.ssh` directory into WSL's home directory, sets ownership, and applies appropriate Unix permissions: directory `700` (rwx------), config file and private keys `600` (rw-------), and public keys `644` (rw-r--r--).
- **Usage:** `Configure-WSLSSH`

Removes any existing `.ssh` in the WSL home directory, recreates it, then copies the SSH files over from the Windows profile. Ownership is reset to the WSL user, after which permissions are tightened: `700` on the directory, `600` on the `config` file and all private keys (everything that is not `*.pub`, `known_hosts*`, `authorized_keys*`, or `config`), and `644` on public keys. This avoids the strict-permission errors SSH raises when keys carried over from Windows are world-readable.

## [Determine-DotnetDependencies](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Determine-DotnetDependencies.ps1)

- **Description:** Scans a directory tree for .NET projects and lists their dependencies. Recursively finds project files (`.csproj`, `.fsproj`, `.vbproj`), parses their target frameworks, compares the required modern .NET versions against the installed SDKs and runtimes, and reports which required SDKs are present or missing. For any missing SDKs it prints ready-to-use installation commands in both WinGet and `WinGetApps.csv` formats.
- **Parameters:** -SearchPath, -ExcludePaths, -ListProjects
- **Usage:** `Determine-DotnetDependencies`, `Determine-DotnetDependencies -ListProjects`, `Determine-DotnetDependencies -SearchPath C:\repos -ListProjects`

The search path defaults to `MachineSpecificPaths.DotnetProjectsSearchPath`, falling back to `$env:USERPROFILE\Development` when that key is not configured. Common build and cache folders (`node_modules`, `bin`, `obj`, `.git`, `.vs`, `packages`) are excluded by default. Only modern .NET target frameworks are evaluated against the installed SDKs; missing versions are surfaced with `Microsoft.DotNet.SDK.<major>` package commands.

| Parameter       | Description                                                                                                                                                |
| --------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-SearchPath`   | Root directory to scan for .NET projects. Defaults to `MachineSpecificPaths.DotnetProjectsSearchPath` or `$env:USERPROFILE\Development` if not configured. |
| `-ExcludePaths` | Array of directory names to exclude from scanning. Defaults to common build/cache folders.                                                                 |
| `-ListProjects` | Also outputs the list of .NET projects found, grouped per target framework.                                                                                |

```powershell
# Scan the configured .NET projects directory for dependencies
Determine-DotnetDependencies

# Scan a specific folder and list each project under its target framework
Determine-DotnetDependencies -SearchPath C:\repos -ListProjects
```

## [Display-SystemLanguageSettings](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Display-SystemLanguageSettings.ps1)

- **Description:** Displays the current system language, locale, and culture settings. Prints three sections: Display Language(s) from `Get-WinUserLanguageList`, System Locale from `Get-WinSystemLocale`, and User Culture from `Get-Culture`.
- **Usage:** `Display-SystemLanguageSettings`

## [Enable-DeveloperMode](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Enable-DeveloperMode.ps1)

- **Description:** Enables Windows Developer Mode by setting the registry value `AllowDevelopmentWithoutDevLicense` to `1` under `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock`. Developer Mode allows running unsigned scripts and unpacked UWP apps, and is required for creating symlinks without admin (used by SymbolicLinkMaker for Windows symlinks outside Bootstrap; WSL symlinks do not require it). Requires administrator privileges.
- **Usage:** `Enable-DeveloperMode`

The function first calls `Test-AdminPrivileges`, then checks whether `AllowDevelopmentWithoutDevLicense` under `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock` is already set to `1`. If not, it creates the key as needed and sets the value. The optional `Tools.DeveloperMode` capability (Device Portal / SSH for remote UWP debugging) is deliberately not installed — it needs online Windows Update servicing and can stall bootstrap for minutes on fresh machines; install it manually with `Get-WindowsCapability -Online -Name "Tools.DeveloperMode*" | Add-WindowsCapability -Online` if ever needed. The operation is idempotent: if Developer Mode is already enabled it reports so and makes no changes.

```powershell
# Enable Windows Developer Mode (run from an elevated session)
Enable-DeveloperMode
```

## [Get-BrowserWindowsByTarget](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Get-BrowserWindowsByTarget.ps1)

- **Description:** Enumerates visible top-level windows (via the native `Win32BrowserHelper` type) for the supplied browser process IDs and returns only the ones whose titles match the provided regex. Used to distinguish browser main windows from child/helper processes (GPU / renderer / utility) that do not own a top-level window.
- **Parameters:** -TargetPids, -TitlePattern
- **Usage:** `Get-BrowserWindowsByTarget -TargetPids @(1234) -TitlePattern "Google Chrome"`

Walks every top-level window with `Win32BrowserHelper::EnumWindows`, maps each handle back to its owning process ID, and keeps a window only when its PID is in `-TargetPids`, the window is visible, and its title matches `-TitlePattern`. Each kept window is returned as a `PSCustomObject` with `Handle` and `Title` properties.

| Parameter       | Type     | Description                                                      |
| --------------- | -------- | ---------------------------------------------------------------- |
| `-TargetPids`   | `int[]`  | Process IDs whose top-level windows should be enumerated.        |
| `-TitlePattern` | `string` | Regex used to keep only the intended browser brand main windows. |

```powershell
# Return visible Chrome windows owned by process 1234
Get-BrowserWindowsByTarget -TargetPids @(1234) -TitlePattern "Google Chrome"
```

**See also:** [Close-BrowserWindows](../modules/system.md)

## [Get-InstalledApps](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Get-InstalledApps.ps1)

- **Description:** Enumerates all installed Windows applications (both 64-bit and 32-bit) by scanning the registry's Uninstall keys, then exports the results to `installed_apps.txt` on the Desktop.
- **Usage:** `Get-InstalledApps`

For each application found it records `DisplayName`, `DisplayVersion`, `Publisher`, `InstallDate`, `UninstallString`, `Bits`, and the registry `Path`, writing the formatted list to `C:\Users\<User>\Desktop\installed_apps.txt`. Any existing file at that location is cleared before the export.

```powershell
# Enumerate all installed apps and export to Desktop\installed_apps.txt
Get-InstalledApps
```

## [Get-PinnedApps](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Get-PinnedApps.ps1)

- **Description:** Reads version-pinned apps from a package-manager CSV file (e.g. WinGetApps.csv, ScoopApps.csv) and returns their app names. Used to identify apps that should NOT be upgraded because they are locked to a specific version. Helper function for `Upgrade-All`.
- **Parameters:** -CsvFileName, -VersionExcludeValue
- **Usage:** `Get-PinnedApps -CsvFileName "Windows/bootstrap/WinGetApps.csv"`, `Get-PinnedApps -CsvFileName "Windows/bootstrap/ScoopApps.csv" -VersionExcludeValue "latest"`

Imports the given CSV and returns the `App` values of every row whose `Version` field is set and does not match the exclude value. The CSV path is resolved relative to `MachineSpecificPaths.Projects.Self.Root`. Apps whose version equals the exclude value (default `"Latest"`) are treated as unpinned and are omitted from the results.

| Parameter              | Description                                                                                                                            |
| ---------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `-CsvFileName`         | Relative path to the CSV file (e.g. `"Windows/bootstrap/WinGetApps.csv"`). Resolved against `MachineSpecificPaths.Projects.Self.Root`. |
| `-VersionExcludeValue` | Version value treated as "not pinned" and excluded from results. Defaults to `"Latest"`.                                               |

```powershell
# Return WinGet apps locked to a specific version (Version other than "Latest")
Get-PinnedApps -CsvFileName "Windows/bootstrap/WinGetApps.csv"

# Same for Scoop, excluding the lowercase "latest" sentinel
Get-PinnedApps -CsvFileName "Windows/bootstrap/ScoopApps.csv" -VersionExcludeValue "latest"
```

## [Initialize-OhMyPosh](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Initialize-OhMyPosh.ps1)

- **Description:** Resolves the `oh-my-posh` binary and initializes the prompt theme for the current session - the robust form of the classic profile one-liner `oh-my-posh init pwsh --config <theme> | Invoke-Expression`. Resolution order: PATH (`Get-Command`), then the known install locations (winget EXE per-user and machine scope, WinGet portable links, Store alias). When a fallback location hits, its directory is prepended to the session PATH so `oh-my-posh` also resolves as a plain command afterwards. When the binary is genuinely absent, prints a single install hint instead of erroring on every prompt. The theme file is read from `Universal.OhMyPoshThemeFile` in `Configuration.psd1`.
- **Usage:** `. Initialize-OhMyPosh` (dot-invoked)

Called by the PowerShell profile on every shell start. **Must be dot-invoked** (`. Initialize-OhMyPosh`): the theme init script defines the prompt in the caller's scope, so a normal call would discard it when the function returns. On a provisioned machine the PATH lookup succeeds immediately - Bootstrap persists the Oh My Posh install locations onto the User PATH via `AutoPathAdditions` (see [Set-EnvironmentVariables](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Set-EnvironmentVariables.ps1)) - and the function degenerates to the one-liner. The fallback resolution exists for shells opened before provisioning finished or when an installer's PATH registration did not reach the session.

```powershell
# Initialize the prompt theme (profile usage - note the leading dot)
. Initialize-OhMyPosh
```

## [Initialize-Win32BrowserHelperType](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Initialize-Win32BrowserHelperType.ps1)

- **Description:** Ensures the `Win32BrowserHelper` C# interop type is available. Adds the type used by browser window discovery and graceful window closure, enumerating visible browser windows and posting WM_CLOSE messages. The type is added only once per PowerShell session.
- **Usage:** `Initialize-Win32BrowserHelperType`

Adds the Win32 interop type only once per session, exposing the native `user32.dll` calls (`EnumWindows`, `GetWindowThreadProcessId`, `GetWindowText`, `GetWindowTextLength`, `IsWindowVisible`, and `PostMessage`) used by `Get-BrowserWindowsByTarget` and `Close-BrowserWindows`.

```powershell
# Load the Win32 browser helper type if it has not already been added
Initialize-Win32BrowserHelperType
```

## [Initialize-WSLEnvironment](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Initialize-WSLEnvironment.ps1)

- **Description:** Initializes the active WSL distribution with shell tooling. Installs the `fastfetch` system info tool via apt and adds it to `.bashrc` so it runs on shell startup, then installs `unzip` and `oh-my-posh` and wires `oh-my-posh` into `.profile` with the configured theme. Each step is idempotent, detecting existing installs and configuration before acting.
- **Usage:** `Initialize-WSLEnvironment`

Runs against the currently active WSL distribution. First it checks whether `fastfetch` is present (`command -v fastfetch`); if missing it adds the fastfetch PPA, runs `apt update`, and installs the package as root, then appends `fastfetch` to `~/.bashrc` unless already present. It then provisions a temporary setup script in `/tmp` that installs `unzip` (if not already installed) and `oh-my-posh` (via the official install script), appends the `oh-my-posh init bash` line to `~/.profile` referencing the configured theme, reloads the profile, and is removed afterward.

```powershell
# Install and configure fastfetch and oh-my-posh inside the active WSL distribution
Initialize-WSLEnvironment
```

## [Invoke-ClearAndFastfetch](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Invoke-ClearAndFastfetch.ps1)

- **Description:** Clears the terminal screen with `Clear-Host` and displays the fastfetch system info panel, shrinking the font once if the panel does not fit the window. Inside Windows Terminal it first measures the panel by capturing fastfetch's output (in pipe mode fastfetch emits one line per visual row, so the captured line count is the panel height and the longest line is its width), then sends `Ctrl+0` ("reset font size") so the panel is always judged against - and returns to - the default font; if it still overflows at the default size it sends a single `Ctrl+Minus` ("decrease font size") so it fits, then clears and renders the colored panel. Resetting first keeps the result deterministic (default font when it fits, one step smaller when it does not) and avoids oscillating on repeated calls.
- **Parameters:** -NoResize, -PromptReserve
- **Usage:** `c`, `Invoke-ClearAndFastfetch`, `Invoke-ClearAndFastfetch -NoResize`, `Invoke-ClearAndFastfetch -PromptReserve 2`
- **Alias:** c

Because measuring and displaying are separate steps, `fastfetch` runs twice when auto-fit is active; use `-NoResize` to keep the original single-run clear + fastfetch behavior. Auto-fit is Windows Terminal specific (the `Ctrl+0` / `Ctrl+Minus` bindings) and is skipped automatically outside Windows Terminal and in non-interactive hosts with no console window. Any failure while measuring or sending the keystrokes degrades gracefully to a plain clear + fastfetch.

| Parameter        | Type     | Default | Description                                                                             |
| ---------------- | -------- | ------- | --------------------------------------------------------------------------------------- |
| `-NoResize`      | `switch` | -       | Skip auto-fit; clear and run fastfetch once.                                            |
| `-PromptReserve` | `int`    | `1`     | Rows kept free below the panel for the upcoming prompt when checking vertical overflow. |

```powershell
# Clear the terminal and show the system info panel, auto-fitting to the window
c

# Clear and show the panel without ever resizing the font
Invoke-ClearAndFastfetch -NoResize

# Verbose diagnostic output
Set-LogLevel Verbose { Invoke-ClearAndFastfetch }
```

## [Invoke-TerminateWindowsTerminalTabsExit](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Invoke-TerminateWindowsTerminalTabsExit.ps1)

- **Description:** Executes the scriptable exit seam used by `Terminate-WindowsTerminalTabs` during `-IncludeCurrent` cleanup. Invokes the configured script-scoped exit action when a test seam is present, otherwise exits the current process cleanly with code `0`.
- **Usage:** `Invoke-TerminateWindowsTerminalTabsExit`

This helper centralizes the process-exit step of the `-IncludeCurrent` shutdown path so it can be overridden in tests. When `$script:TerminateWindowsTerminalTabsExitAction` is set it runs that action; otherwise it calls `[Environment]::Exit(0)`. Keeping the exit behind this seam lets the `-IncludeCurrent` path be exercised without forcing the calling test session to terminate.

**See also:** [Invoke-TerminateWindowsTerminalTabsIncludeCurrentCleanup](#invoke-terminatewindowsterminaltabsincludecurrentcleanup), [Terminate-WindowsTerminalTabs](#terminate-windowsterminaltabs)

## [Invoke-TerminateWindowsTerminalTabsIncludeCurrentCleanup](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Invoke-TerminateWindowsTerminalTabsIncludeCurrentCleanup.ps1)

- **Description:** Finalizes the `-IncludeCurrent` cleanup path for `Terminate-WindowsTerminalTabs`. Prints the final closed-tab summary, restores the original host window title, optionally waits before closing the current tab so the final status stays visible, spawns a safety-net PowerShell process to force-close the hosting Windows Terminal instance if it lingers, and then invokes the exit seam.
- **Parameters:** -ClosedTabs, -StartingTitle, -OriginalHostTitle, -CloseWaitSeconds
- **Usage:** `Invoke-TerminateWindowsTerminalTabsIncludeCurrentCleanup -ClosedTabs @("TabA") -StartingTitle "CurrentTab" -OriginalHostTitle "OriginalTitle"`, `Invoke-TerminateWindowsTerminalTabsIncludeCurrentCleanup -ClosedTabs @("TabA") -StartingTitle "CurrentTab" -OriginalHostTitle "OriginalTitle" -CloseWaitSeconds 5`

Internal helper invoked by `Terminate-WindowsTerminalTabs` when `-IncludeCurrent` is used. It reports the total count of closed tabs (the already-closed `-ClosedTabs` plus the current tab's `-StartingTitle`), restores `-OriginalHostTitle` on the PowerShell host, and starts a hidden background PowerShell process as a safety net that force-closes the hosting `WindowsTerminal` process should it fail to exit on its own. Control then passes to the deterministic process-exit seam.

| Parameter            | Type       | Default | Description                                                                                   |
| -------------------- | ---------- | ------- | --------------------------------------------------------------------------------------------- |
| `-ClosedTabs`        | `string[]` | -       | Titles of tabs already closed before the current tab cleanup step.                            |
| `-StartingTitle`     | `string`   | -       | Original title of the current terminal tab.                                                   |
| `-OriginalHostTitle` | `string`   | -       | Original host title to restore before exiting.                                                |
| `-CloseWaitSeconds`  | `int`      | `0`     | Waits this many seconds (0-300) before closing the current tab so the summary stays readable. |

```powershell
# Finalize cleanup and exit the current terminal tab
Invoke-TerminateWindowsTerminalTabsIncludeCurrentCleanup -ClosedTabs @("TabA") -StartingTitle "CurrentTab" -OriginalHostTitle "OriginalTitle"

# Same, but hold the final status on screen for 5 seconds before the tab closes
Invoke-TerminateWindowsTerminalTabsIncludeCurrentCleanup -ClosedTabs @("TabA") -StartingTitle "CurrentTab" -OriginalHostTitle "OriginalTitle" -CloseWaitSeconds 5
```

## [Kill-All](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Kill-All.ps1)

- **Description:** Orchestrates a full desktop cleanup. Removes all virtual desktops except the first, stops Docker Desktop cleanly via `DockerWizard -Stop` before generic process termination, gracefully closes all configured browser processes (WM_CLOSE), terminates remaining processes with visible windows (except browsers and the `Universal.VisibleWindowExclusions` list) and the configured `Universal.TerminateProcessNames` processes, then waits a short RPC/DCOM quiescence window (500 ms) before closing extra Windows Terminal tabs so subsequent commands (e.g. `Open-Workspace`) do not hit `0x800706BA` from DCOM churn. Unless `-IncludeCurrent` is given, the surviving Windows Terminal is then centered on the primary monitor via `Center-Windows -OnPrimary` (pulled back from a secondary monitor if needed) and refocused via `Focus-TerminalTab`, so the run always ends on the terminal. Can optionally reload the PowerShell profile.
- **Parameters:** -Exclude (wildcard/regex patterns), -IncludeCurrent, -ReloadPowerShellProfile
- **Usage:** `Kill-All`, `Kill-All -Exclude "*YouTube*"`, `Kill-All -Exclude "*YouTube*", "*Gmail*", "(.*Obsidian.*|.*Notion.*)"`, `Kill-All -IncludeCurrent`, `Kill-All -ReloadPowerShellProfile`

Coordinates desktop cleanup as a sequence of terminators. If virtual desktop cleanup cannot recover from a VirtualDesktop/RPC failure, `Remove-VirtualDesktops` owns the failure reporting while `Kill-All` suppresses its nested `$false` return value so process cleanup continues. PowerToys (`PowerToys`, `PowerToys.FancyZones`, `PowerToys.Settings`) is excluded from the visible-window terminator by the default `Universal.VisibleWindowExclusions` configuration, since partially killing it leaves the FancyZones supervisor in a "running but FancyZones absent" half-state that breaks the next workspace layout application.

| Parameter                  | Description                                                                                                                                              |
| -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| `-Exclude`                 | One or more window title patterns to spare from termination. Supports both wildcard (`"*YouTube*"`, `"Chrome - *"`) and regex (`"^Chrome"`, `"(._Gmail._ | ._Inbox._)"`) patterns, same format as layout `.psd1` files. |
| `-IncludeCurrent`          | Also closes the current Windows Terminal tab.                                                                                                            |
| `-ReloadPowerShellProfile` | Reloads the PowerShell profile after terminating processes.                                                                                              |

```powershell
# Full cleanup: closes most GUI apps and extra terminal tabs
Kill-All

# Keep windows whose titles match the given patterns (wildcard and regex)
Kill-All -Exclude "*YouTube*", "*Obsidian*", "(.*Notion.*|.*Inbox.*)"

# Clean up and reload the shell afterward
Kill-All -ReloadPowerShellProfile
```

**See also:** [Remove-VirtualDesktops](system.md#remove-virtualdesktops), [Terminate-AllProcessesWithVisibleWindows](system.md#terminate-allprocesseswithvisiblewindows)

## [List-Drives](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/List-Drives.ps1)

- **Description:** Lists all FileSystem PSDrives (mounted drives). A thin alias for `Get-PSDrive -PSProvider FileSystem`, showing all mounted drives including local disks, network drives, and removable media along with their Name, Used (GB), Free (GB), Provider, and Root.
- **Usage:** `List-Drives`

## [Rebuild-IconCache](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Rebuild-IconCache.ps1)

- **Description:** Clears the Windows icon cache and restarts Explorer to fix missing or corrupted desktop/taskbar icons. Stops Explorer, deletes the icon cache database (`IconCache.db`) plus any `iconcache*` files from the paths configured in `Configuration.Universal.IconCacheDb` and `Configuration.Universal.IconCacheFolder`, then restarts Explorer. Requires administrator privileges.
- **Usage:** `Rebuild-IconCache`

```powershell
# Clear the icon cache and restart Explorer (run as administrator)
Rebuild-IconCache
```

**See also:** [Configuration: Machine Types](../configuration/machine-types.md)

## [Reload-PowerShellProfile](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Reload-PowerShellProfile.ps1)

- **Description:** Reloads all WinuX modules and the PowerShell profile. First calls `Reload-WinuXModules` to re-import every WinuX module, then dot-sources the profile files to pick up profile-level changes without restarting the terminal.
- **Usage:** `Reload-PowerShellProfile`

After re-importing the WinuX modules, the function dot-sources each of the `AllUsersAllHosts`, `AllUsersCurrentHost`, `CurrentUserAllHosts`, and `CurrentUserCurrentHost` profile scripts that exist, so any profile-level edits take effect in the current session.

Under verbose logging (`Set-LogLevel Verbose`) the `[Reloading PowerShell Profile]` header and the success message are suppressed. Add `-Verbose` to also log each profile file as it is sourced.

```powershell
# Reload all modules and profile scripts
Reload-PowerShellProfile

# Suppress the header/success banner and log each profile file as it is sourced
Reload-PowerShellProfile -Verbose
```

## [Reload-WinuXModules](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Reload-WinuXModules.ps1)

- **Description:** Removes and re-imports all WinuX PowerShell modules to pick up code changes. Scans the `Modules/` directory (and the `Modules/Custom` fork area, when populated) for folders containing both a `.psd1` manifest and a `.psm1` loader, removes any currently loaded version, and force-reimports each module globally. Folders missing either file are skipped with a verbose message.
- **Usage:** `Reload-WinuXModules`

Iterates every folder under `Modules/` (plus `Modules/Custom/` for whole fork-owned modules), and for each one expecting a matching `<ModuleName>.psd1` and `<ModuleName>.psm1` pair runs `Import-Module -Force -Global` so edited functions are reloaded into the current session without restarting PowerShell. Custom mirror payload folders carry no manifest and are skipped here - their function files reload with the `Custom` module itself. Modules that fail to import are reported in red but do not stop the loop.

```powershell
# Re-import every WinuX module after editing function source
Reload-WinuXModules
```

**See also:** [Reload-PowerShellProfile](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Reload-PowerShellProfile.ps1), [Fork Model: the Custom area](../contributing/fork-model.md)

## [Remove-VirtualDesktops](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Remove-VirtualDesktops.ps1)

- **Description:** Removes virtual desktops - by default all except desktop 0, resetting to a single-desktop state. With `-EmptyOnly`, removes only desktops that have no visible windows, which keeps workspace setups (e.g. alongside mode) idempotent on retry. At least one desktop is always preserved.
- **Parameters:** -EmptyOnly
- **Usage:** `Remove-VirtualDesktops`, `Remove-VirtualDesktops -EmptyOnly`

In default mode it removes every desktop except desktop `0`. In `-EmptyOnly` mode it builds the set of desktops that have at least one visible window and removes only the empty ones, iterating right-to-left so remaining indices stay stable; if desktop 0 is empty but others have windows, desktop 0 is removed last and Windows shifts the rest left. Window detection prefers `Get-WindowHandle` (EnumWindows-based, from the Window module) so it captures every visible window - including multiple browser or VSCode windows - and falls back to `Get-Process` `MainWindowHandle` when that module isn't loaded, though the fallback sees only one window per process and may treat desktops with secondary windows as empty.

Before cleanup it runs `Test-RpcServerHealth -Probe` so the preflight verifies the live VirtualDesktop RPC endpoint rather than only checking that Windows RPC services are running, rehydrating VirtualDesktop cmdlets if preflight recovery unloaded the module. Operations against `Get-DesktopList`, `Get-DesktopFromWindow`, `Get-DesktopIndex`, and `Remove-Desktop` run through the shared RPC retry helpers with exponential backoff; when an operation reports `0x800706BA` / `0x800706BE`, the current session's VirtualDesktop module state is reset before the next attempt so stale COM proxies recover without a fresh shell.

| Parameter    | Type     | Default | Description                                                                                                                             |
| ------------ | -------- | ------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `-EmptyOnly` | `switch` | -       | Removes only desktops that have no visible windows, iterating from the rightmost toward desktop 0; at least one desktop is always kept. |

```powershell
# Reset to a single desktop (removes all except desktop 0)
Remove-VirtualDesktops

# Remove only empty desktops, keeping any with visible windows
Remove-VirtualDesktops -EmptyOnly

# Verbose diagnostic output
Set-LogLevel Verbose { Remove-VirtualDesktops -EmptyOnly }
```

## [Rename-Machine](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Rename-Machine.ps1)

- **Description:** Sets the machine hostname from `Configuration.psd1` or interactively prompts for a new name. If the current hostname matches a configured name it skips the operation (idempotent); with `-Override` it allows re-entering a new hostname even when already configured. Enforces Windows naming rules. Requires administrator privileges.
- **Parameters:** -Override
- **Usage:** `Rename-Machine`, `Rename-Machine -Override`

Reads the configured hostnames from `HostnameToMachineType` in `Configuration.psd1` and compares them against the current `COMPUTERNAME`. When run without `-Override` and the name already matches, it reports the configured hostname and returns. Otherwise it prompts for a new name and validates it against Windows rules (max 63 characters, not all-numeric, only letters, digits, and hyphens) before calling `Rename-Computer`. A restart is required for the change to take effect.

| Parameter   | Description                                                                                             |
| ----------- | ------------------------------------------------------------------------------------------------------- |
| `-Override` | Force reconfiguration of the hostname even if it is already set, prompting to keep or enter a new name. |

```powershell
# Set the hostname if not already configured; report it if it is
Rename-Machine

# Re-enter a new hostname even when already configured
Rename-Machine -Override
```

**See also:** [Configuration: Machine Types](../configuration/machine-types.md)

## [Repair-RpcServer](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Repair-RpcServer.ps1)

- **Description:** Attempts to recover an unresponsive RPC server when `Test-RpcServerHealth -Probe` indicates the endpoint is hung (services Running but COM roundtrips fail with `0x800706BA` / `0x800706BE`). Runs a bounded retry loop (default 5 attempts, exponential backoff starting at 500 ms and capped at 8 s); each attempt does best-effort `Restart-Service RpcSs/DcomLaunch/RpcEptMapper -Force` when elevated, then tears down consumer-side state that the session can fix without admin (force-stops `PowerToys*`, unloads the cached `VirtualDesktop` module) before re-probing. Returns `$true` as soon as the probe reports healthy, `$false` once attempts are exhausted - callers continue their normal flow afterwards (no reboot message).
- **Parameters:** -ProbeTimeoutMs (default 2500), -MaxAttempts (default 5), -InitialBackoffMs (default 500)
- **Usage:** `Repair-RpcServer`, `Repair-RpcServer -MaxAttempts 10`

Used as a pre-flight by workspace layout commands (e.g. `Set-WorkspaceWindowLayout` and the rerun helper) when an RPC probe fails before expensive work. The service restart is genuinely best-effort: `RpcSs` is normally marked non-stoppable on a live Windows session, so the call typically no-ops (and requires admin), and a true RPC restart almost always demands a reboot. The recovery that actually works without admin is the consumer-side cleanup - dropping `PowerToys*` processes and unloading the cached `VirtualDesktop` COM proxies so the next probe re-establishes fresh COM connections.

**Per-attempt sequence:**

1. When elevated, attempts `Restart-Service RpcSs/DcomLaunch/RpcEptMapper -Force` (best-effort, caught per-service to keep the loop alive).
2. Force-stops all `PowerToys*` processes so stale COM client state is dropped.
3. Unloads the cached `VirtualDesktop` PowerShell module so the next probe re-creates fresh COM proxies.
4. Waits the current backoff window for DCOM to settle.
5. Re-runs `Test-RpcServerHealth -Probe` and exits the loop on success.

| Parameter           | Type  | Default | Description                                                 |
| ------------------- | ----- | ------- | ----------------------------------------------------------- |
| `-ProbeTimeoutMs`   | `int` | `2500`  | Hard timeout for each post-recovery RPC probe (ms).         |
| `-MaxAttempts`      | `int` | `5`     | Maximum recovery attempts before giving up.                 |
| `-InitialBackoffMs` | `int` | `500`   | Initial inter-attempt delay; doubles each attempt, 8 s cap. |

```powershell
# Pre-flight guard: only repair when the probe says the endpoint is hung
if (-not (Test-RpcServerHealth -Probe)) {
    [void](Repair-RpcServer)
}

# More aggressive retry budget
Repair-RpcServer -MaxAttempts 10

# Verbose diagnostic output
Set-LogLevel Verbose { Repair-RpcServer }
```

Even when `Repair-RpcServer` returns `$false`, callers continue their normal flow (the workspace rerun still spawns) rather than aborting; there is no reboot prompt. Running from an elevated shell gives the service-restart step better odds.

## [Restart-Explorer](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Restart-Explorer.ps1)

- **Description:** Restarts Windows Explorer by stopping the `explorer.exe` process and waiting for it to auto-restart. An optional message is shown with an animated loading spinner during the wait. Useful after theme, icon, or taskbar changes.
- **Parameters:** -Message, -Delay
- **Usage:** `Restart-Explorer`, `Restart-Explorer -Message "Waiting for changes to apply..."`, `Restart-Explorer -Message "Processing..." -Delay 3`

Stops the Explorer process and waits via `Loading-Spinner` before continuing (Explorer auto-restarts). When `-Message` is provided, the spinner displays that label; otherwise it spins without a label. The wait length is controlled by `-Delay` (defaults to 1 second).

| Parameter  | Description                                                                  |
| ---------- | ---------------------------------------------------------------------------- |
| `-Message` | Label to display in the loading spinner during the delay. Omit for no label. |
| `-Delay`   | Seconds to wait after stopping Explorer before continuing. Defaults to 1.    |

```powershell
# Restart Explorer with the default 1-second delay
Restart-Explorer

# Restart Explorer and show a spinner with a message for 3 seconds
Restart-Explorer -Message "Waiting for changes to apply..." -Delay 3
```

## [Restart-Machine](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Restart-Machine.ps1)

- **Description:** Prompts for confirmation and restarts the machine. Shows a Yes/No prompt via `Resolve-Selection`; if confirmed, displays a 5-second countdown then calls `Restart-Computer`.
- **Parameters:** -Selection
- **Usage:** `Restart-Machine`, `Restart-Machine -Selection "Yes"`

| Parameter    | Description                                                                                                        |
| ------------ | ------------------------------------------------------------------------------------------------------------------ |
| `-Selection` | Pre-selected answer ("Yes" or "No") to skip the interactive prompt. Pressing Enter at the prompt defaults to "No". |

```powershell
# Show the Yes/No confirmation prompt
Restart-Machine

# Restart immediately without prompting
Restart-Machine -Selection "Yes"
```

## [Send-WakeOnLan](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Send-WakeOnLan.ps1)

- **Description:** Sends Wake-on-LAN magic packets to one or more machines configured in `WakeOnLanConfig` in `Configuration.psd1`. Called with machine names it wakes those machines; called bare it shows an interactive selection menu. When a machine has an `Address` (IP or hostname) configured, it uses `Test-MachineOnline` to make waking reliable instead of fire-and-forget: it pings first and skips the machine if already online, then polls after sending until the machine responds or `-TimeoutSeconds` elapses, so the result reflects whether it actually woke. Machines without an `Address` fall back to fire-and-forget behaviour.
- **Parameters:** -Machine, -TimeoutSeconds, -NoWait
- **Usage:** `Send-WakeOnLan`, `Send-WakeOnLan -Machine "MyMachine"`, `Send-WakeOnLan -Machine "MyMachine" -NoWait`

Each machine entry specifies a MAC address, subnet-specific broadcast address and port, and optionally an `Address` for verification. With `-NoWait` the function sends the packet only, with no online pre-check or post-send verification (the original fire-and-forget behaviour). Verification is delegated to `Test-MachineOnline`.

| Parameter         | Description                                                                                                      |
| ----------------- | ---------------------------------------------------------------------------------------------------------------- |
| `-Machine`        | One or more machine names as defined in `Configuration.psd1`. Omit to show the interactive menu.                 |
| `-TimeoutSeconds` | Maximum seconds to wait for a machine to come online after the packet is sent (verification phase). Default 120. |
| `-NoWait`         | Switch. Send the magic packet without the online pre-check or post-send verification.                            |

```powershell
# Interactive menu of configured machines
Send-WakeOnLan

# Skip if already online (ping check), send the packet, then poll
# until it responds or -TimeoutSeconds (default 120) elapses
Send-WakeOnLan -Machine "MyMachine"

# Fire-and-forget: send the packet only, no ping check or verification
Send-WakeOnLan -Machine "MyMachine" -NoWait
```

Example `WakeOnLanConfig` entry in `Configuration.psd1`:

```powershell
WakeOnLanConfig = @{
    MyMachine = @{
        MacAddress                     = "00:11:22:33:44:55"
        SubNetSpecificBroadcastAddress = "192.0.2.255"
        Address                        = "192.0.2.10"  # IP/hostname; "" to disable ping checks
        Port                           = 9
    }
}
```

**See also:** [Test-MachineOnline](system.md#test-machineonline)

## [Set-CustomExecutionPolicy](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Set-CustomExecutionPolicy.ps1)

- **Description:** Sets the PowerShell execution policy to `Bypass` for a specified scope by calling `Set-ExecutionPolicy -ExecutionPolicy Bypass`, allowing unsigned scripts to run within that scope without user prompts.
- **Parameters:** -Scope
- **Usage:** `Set-CustomExecutionPolicy`, `Set-CustomExecutionPolicy -Scope CurrentUser`
- **Scopes:** Process, CurrentUser, LocalMachine

| Parameter | Description                                                                                                                                                                                             |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-Scope`  | The scope for the execution policy. Valid values: `Process` (current session only), `CurrentUser` (all sessions for the current user), `LocalMachine` (all users, all sessions). Defaults to `Process`. |

```powershell
# Bypass for the current process only (default)
Set-CustomExecutionPolicy

# Bypass for all sessions of the current user
Set-CustomExecutionPolicy -Scope CurrentUser
```

## [Set-DisplayLanguage](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Set-DisplayLanguage.ps1)

- **Description:** Sets the Windows display language. Reads available languages from `DisplayLanguages` in `Configuration.psd1`; pass a language code to set it directly, or call with no arguments to pick from an interactive menu (Enter selects the configured `DefaultDisplayLanguage`). Requires administrator privileges.
- **Parameters:** -Language
- **Usage:** `Set-DisplayLanguage`, `Set-DisplayLanguage -Language "en-US"`

Resolves the chosen language to its tag from `DisplayLanguages` and moves it to the front of the Windows user language list (adding it first if not already installed), then verifies the change took effect. If the requested language is already the active display language it is left unchanged. A sign-out and sign-in is required for the change to take full effect.

| Parameter   | Description                                                                                                      |
| ----------- | ---------------------------------------------------------------------------------------------------------------- |
| `-Language` | Language code as defined in `Configuration.psd1` (e.g. `"en-US"`, `"hr-HR"`). Omit to show the interactive menu. |

```powershell
# Show the interactive display language selection menu
Set-DisplayLanguage

# Set the display language directly to English (US)
Set-DisplayLanguage -Language "en-US"
```

## [Set-EnvironmentVariables](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Set-EnvironmentVariables.ps1)

- **Description:** Sets user environment variables from the configuration or manually. With `-Auto`, reads all variables from `AutoEnvironmentVariables` in `Configuration.psd1`, expands placeholder paths ({Dev}, {User}, {MachineType}), and sets them; it also appends any entries from `AutoPathAdditions` to the user PATH. Manual mode accepts `-Name` and `-Value` to set an individual variable. Requires administrator privileges.
- **Parameters:** -Name, -Value, -Auto
- **Usage:** `Set-EnvironmentVariables -Auto`, `Set-EnvironmentVariables -Name "MY_VAR" -Value "C:\Tools"`

In `-Auto` mode, each configured variable is path-expanded via `Expand-Hashtable` (resolving {Dev}, {User}, and {MachineType} placeholders against the current machine's base paths) and written to the `User` scope. Existing variables are skipped when already correct, updated when the value differs, and created otherwise (idempotent). Entries in `AutoPathAdditions` are then expanded and appended to the user PATH only if not already present. In manual mode, both `-Name` and `-Value` are required; the value is path-expanded the same way. After any run, all `User`-scope variables are refreshed into the current session via `env:`.

| Parameter | Description                                                                                                                                       |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-Name`   | Variable name for manual mode (e.g. `"MY_VAR"`).                                                                                                  |
| `-Value`  | Variable value for manual mode (e.g. `"C:\Tools"`); placeholder paths are expanded.                                                               |
| `-Auto`   | Reads all variables from `AutoEnvironmentVariables` (and PATH entries from `AutoPathAdditions`) in the configuration and sets them automatically. |

```powershell
# Set all configured variables and PATH additions automatically
Set-EnvironmentVariables -Auto

# Set a single variable manually
Set-EnvironmentVariables -Name "MY_VAR" -Value "C:\Tools"
```

## [Set-ExplorerOptions](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Set-ExplorerOptions.ps1)

- **Description:** Configures Windows File Explorer display and behavior options. Reads the desired registry settings from `ExplorerOptions` in `Configuration.psd1` and applies them (file extension visibility, hidden files, and similar). Takes no parameters - all settings come from the configuration.
- **Usage:** `Set-ExplorerOptions`

Compares the current registry values against the desired settings in `ExplorerOptions`; if everything already matches it reports that Explorer is already configured and does nothing. Otherwise it writes each setting (creating the registry key path when missing) and runs `Restart-Explorer` so the changes take effect. Typical settings applied include showing hidden files, showing file extensions, opening Explorer to "This PC" instead of Quick Access, and disabling recent files in Quick Access.

```powershell
# Apply all configured Explorer options to the registry
Set-ExplorerOptions
```

## [Set-KeyboardLayouts](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Set-KeyboardLayouts.ps1)

- **Description:** Configures keyboard layouts from predefined layout sets read from `KeyboardLayoutSets` in `Configuration.psd1` (e.g. "Gaming", "Development"). Each set is a named collection of keyboard layout codes. Passing a set name installs all its layouts; calling it without arguments shows an interactive menu of available sets (Enter selects the configured default). Idempotent: skips reconfiguration when the requested set is already active unless `-Override` is given.
- **Parameters:** -LayoutSet, -Override
- **Usage:** `Set-KeyboardLayouts`, `Set-KeyboardLayouts -LayoutSet "Gaming"`, `Set-KeyboardLayouts -LayoutSet "Development" -Override`

Resolves the target set from `KeyboardLayoutSets`, maps each layout name to its code via `KeyboardLayouts`, and applies the configuration through the live Windows input system (`Get-WinUserLanguageList` / `Set-WinUserLanguageList`) rather than relying solely on the legacy registry. It rebuilds input method tips per language tag, removes stale input methods from languages not in the target set, and reorders the language list so the first target layout's language is primary. The `HKCU:\Keyboard Layout\Preload` registry is also updated for legacy application compatibility. After applying, the final configuration is printed and verified from the actual input system. A log off / log on may be required for changes to take full effect.

| Parameter    | Description                                                                           |
| ------------ | ------------------------------------------------------------------------------------- |
| `-LayoutSet` | Name of the layout set to install (e.g. "Gaming"). Omit to show the interactive menu. |
| `-Override`  | Force reconfiguration even if the layout set is already active.                       |

```powershell
# Interactive layout-set selection menu (Enter picks the configured default)
Set-KeyboardLayouts

# Install a specific layout set
Set-KeyboardLayouts -LayoutSet "Gaming"

# Force reapply even if the set is already active
Set-KeyboardLayouts -LayoutSet "Development" -Override
```

## [Set-Locale](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Set-Locale.ps1)

- **Description:** Sets the system locale (user culture and home location). Reads available locales from `Locales` in `Configuration.psd1`. When given a locale name it sets that locale; called without arguments it shows an interactive menu of available locales. Requires administrator privileges.
- **Parameters:** -Locale
- **Usage:** `Set-Locale`, `Set-Locale -Locale "en-US"`, `Set-Locale -Locale "hr-HR"`

Validates admin privileges first, then resolves the target locale either from the `-Locale` argument or via an interactive selection menu (pressing Enter selects the configured `DefaultLocale`). The chosen locale's `Code` and `GeoId` are read from `Configuration.psd1`; the function applies the culture with `Set-Culture` and the home location with `Set-WinHomeLocation` (falling back to the `HKCU:\Control Panel\International\Geo` registry key if the cmdlet fails). If the current culture already matches the target, no change is made. Some settings may require a system restart to take full effect.

| Parameter | Description                                                                                                    |
| --------- | -------------------------------------------------------------------------------------------------------------- |
| `-Locale` | Locale name as defined in `Configuration.psd1` (e.g. `"en-US"`, `"hr-HR"`). Omit to show the interactive menu. |

```powershell
# Show the interactive locale selection menu (Enter picks the default)
Set-Locale

# Set the system locale to US English
Set-Locale -Locale "en-US"

# Set the system locale to Croatian
Set-Locale -Locale "hr-HR"
```

## [Set-LockScreenWallpaper](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Set-LockScreenWallpaper.ps1)

- **Description:** Sets the Windows lock screen background image to match the active theme and machine type via native registry settings. Resolves the image from the same `WallpaperLightSettings` / `WallpaperDarkSettings` configuration in `Configuration.psd1` as `Set-Wallpaper` (for multi-monitor configs the first monitor's file is used). With `-Theme Auto` (the default) it detects the current system theme from the registry; disables Windows Spotlight / rotating lock screen so the custom image is shown. Writes to the `PersonalizationCSP` key under elevation and falls back to per-user registry otherwise. Requires administrator privileges.
- **Parameters:** -Theme [Light | Dark | Auto]
- **Usage:** `Set-LockScreenWallpaper`, `Set-LockScreenWallpaper -Theme Dark`, `Set-LockScreenWallpaper -Theme Light`

Resolves the image path from the same `WallpaperDarkSettings` / `WallpaperLightSettings` configuration as `Set-Wallpaper`, picking the entry for the current machine type (falling back to `Default`). It then disables Windows Spotlight / rotating lock screen (`RotatingLockScreenEnabled`, `RotatingLockScreenOverlayEnabled`) and sets the lock screen image via the `PersonalizationCSP` registry key (`HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP`) when elevated; if the CSP write fails it falls back to per-user registry under `HKCU`. `Set-SystemTheme` calls this automatically alongside `Set-Wallpaper`, so you typically don't need to invoke it directly.

| Parameter | Type     | Default  | Description                                               |
| --------- | -------- | -------- | --------------------------------------------------------- |
| `-Theme`  | `string` | `"Auto"` | `Light`, `Dark`, or `Auto` (detect from system registry). |

```powershell
# Apply the lock screen image matching the current system theme (auto-detected)
Set-LockScreenWallpaper

# Force a specific theme variant
Set-LockScreenWallpaper -Theme Dark
Set-LockScreenWallpaper -Theme Light

# Verbose diagnostic output
Set-LogLevel Verbose { Set-LockScreenWallpaper }
```

**See also:** [Set-Wallpaper](system.md), [Set-SystemTheme](system.md)

## [Set-PowerButtonActions](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Set-PowerButtonActions.ps1)

- **Description:** Configures what happens when the power button is pressed, the sleep button is pressed, or the laptop lid is closed, for both battery and plugged-in states. Also controls Fast Startup, Sleep, and Hibernate visibility in the Power menu. With `-Auto` it reads per-machine settings from `PowerButtonActions` in `Configuration.psd1`; otherwise it accepts individual parameters with hardcoded defaults. Applies settings to ALL power schemes and enforces them via the registry to prevent Windows from reverting them. Idempotent - skips settings already at the desired value. Requires administrator privileges.
- **Parameters:** -Auto, -PowerButtonOnBattery, -PowerButtonPluggedIn, -SleepButtonOnBattery, -SleepButtonPluggedIn, -LidCloseOnBattery, -LidClosePluggedIn, -DisableFastStartup, -DisableSleep, -DisableHibernate
- **Usage:** `Set-PowerButtonActions -Auto`, `Set-PowerButtonActions`, `Set-PowerButtonActions -PowerButtonPluggedIn "ShutDown" -PowerButtonOnBattery "Sleep"`, `Set-PowerButtonActions -Auto -LidCloseOnBattery Hibernate`

With `-Auto`, the function determines the machine type and reads its block from `PowerButtonActions` in `Configuration.psd1`; explicit parameters override the configured values, and missing nullable toggles are left unmanaged. Without `-Auto`, omitted action parameters fall back to hardcoded defaults. The six button/lid actions are written through `powercfg` and reinforced directly in the registry across every power scheme, then the active scheme is re-activated to force the changes to take effect.

| Parameter               | Description                                                                                               |
| ----------------------- | --------------------------------------------------------------------------------------------------------- |
| `-Auto`                 | Reads all button and lid actions from `Configuration.psd1` per machine type.                              |
| `-PowerButtonOnBattery` | Action when the power button is pressed on battery. One of `DoNothing`, `Sleep`, `Hibernate`, `ShutDown`. |
| `-PowerButtonPluggedIn` | Action when the power button is pressed while plugged in. Same value set.                                 |
| `-SleepButtonOnBattery` | Action when the sleep button is pressed on battery. Same value set.                                       |
| `-SleepButtonPluggedIn` | Action when the sleep button is pressed while plugged in. Same value set.                                 |
| `-LidCloseOnBattery`    | Action when the laptop lid is closed on battery. Same value set.                                          |
| `-LidClosePluggedIn`    | Action when the laptop lid is closed while plugged in. Same value set.                                    |
| `-DisableFastStartup`   | `[bool]` toggle for Windows Fast Startup (hybrid sleep).                                                  |
| `-DisableSleep`         | `[bool]` toggle for Sleep visibility in the Power menu.                                                   |
| `-DisableHibernate`     | `[bool]` toggle for hibernation and its Power-menu entry.                                                 |

```powershell
# Read and apply all configured button actions for this machine type
Set-PowerButtonActions -Auto

# Apply hardcoded defaults without touching configuration
Set-PowerButtonActions

# Read from config but override a single behavior
Set-PowerButtonActions -Auto -LidCloseOnBattery Hibernate

# Set the power button action for both power states explicitly
Set-PowerButtonActions -PowerButtonPluggedIn "ShutDown" -PowerButtonOnBattery "Sleep"
```

**See also:** [Set-PowerPlan](system.md#set-powerplan)

## [Set-PowerPlan](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Set-PowerPlan.ps1)

- **Description:** Sets the Windows power plan to Balanced, HighPerformance, or UltimatePerformance. With `-Auto`, reads the plan for the current machine type from `PowerPlans[MachineType]` in `Configuration.psd1` and applies it. Without `-Auto` and without an explicit `-Mode`, prompts for interactive selection (defaults to Balanced). Idempotent - skips if the plan is already active. Requires administrator privileges.
- **Parameters:** -Auto, -Mode [Balanced | HighPerformance | UltimatePerformance]
- **Usage:** `Set-PowerPlan -Auto`, `Set-PowerPlan`, `Set-PowerPlan -Mode UltimatePerformance`

Resolves the target mode from configuration (`-Auto`), the explicit `-Mode` parameter, or an interactive menu, then activates the matching `powercfg` scheme. For UltimatePerformance it duplicates the hidden Ultimate Performance scheme if one is not already present. Before switching it checks the active scheme and returns early when the requested plan is already active.

| Parameter | Description                                                                                          |
| --------- | ---------------------------------------------------------------------------------------------------- |
| `-Auto`   | Reads the power plan for the current machine type from `PowerPlans` in `Configuration.psd1`.         |
| `-Mode`   | Power plan mode: `Balanced`, `HighPerformance`, or `UltimatePerformance`. Ignored if `-Auto` is set. |

```powershell
# Auto mode - reads the plan for this machine type from configuration
Set-PowerPlan -Auto

# Interactive selection (Enter for default => Balanced)
Set-PowerPlan

# Explicit mode
Set-PowerPlan -Mode UltimatePerformance
```

`PowerPlans` in `Configuration.psd1` maps each machine type to a plan, for example:

```powershell
PowerPlans = @{
    "PC"     = "UltimatePerformance"
    "Laptop" = "HighPerformance"
    "Work"   = "Balanced"
    "Test"   = "Balanced"
}
```

## [Set-SpecialFolders](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Set-SpecialFolders.ps1)

- **Description:** Redirects Windows special folders (such as Downloads and Screenshots) to custom paths defined in the `SpecialFolders` key of `Configuration.psd1`. Placeholder paths (e.g. `{Dev}`, `{User}`) are expanded before the redirections are written via registry entries. Requires administrator privileges.
- **Usage:** `Set-SpecialFolders`

Reads the redirection list from `SpecialFolders` in `Configuration.psd1`, expands any placeholders against the current machine's base paths, and applies each one through the `User Shell Folders` registry key. It first compares the current registry values to the desired ones and skips writing if everything is already correctly mapped (idempotent). By default the shipped configuration redirects Downloads and Screenshots to the Desktop.

```powershell
# Redirect all configured special folders (run as administrator)
Set-SpecialFolders
```

## [Set-SystemTheme](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Set-SystemTheme.ps1)

- **Description:** Sets the Windows system theme (Dark or Light) by modifying the relevant registry entries, then keeps the desktop wallpaper and lock screen image in sync. With `-Auto` it reads the theme for the current machine type from `Configuration.Themes[MachineType]`; with `-Theme` it applies an explicit theme; with no argument it defaults to Dark. Idempotent: if the theme is already configured it still re-applies the wallpapers. Requires administrator privileges.
- **Parameters:** -Theme [Dark | Light], -Auto, -KeepTerminalOpen
- **Usage:** `Set-SystemTheme -Auto`, `Set-SystemTheme -Auto -KeepTerminalOpen`, `Set-SystemTheme -Theme Dark`, `Set-SystemTheme -Theme Light`

Writes `AppsUseLightTheme`, `SystemUsesLightTheme`, and `ColorPrevalence` under `HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize` (value `0` for Dark, `1` for Light). Explorer is restarted _before_ the wallpaper updates run - this order is required, because restarting Explorer after a wallpaper change can cause Windows to reload stale wallpaper cache data and revert the desktop image. It then calls `Set-Wallpaper` (via the `IDesktopWallpaper` COM interface) and `Set-LockScreenWallpaper` so both backgrounds match the selected theme. When run inside Windows Terminal, the current tab is closed 5 seconds after a successful run unless `-KeepTerminalOpen` is set (useful for longer-running admin workflows such as `Bootstrap`).

| Parameter           | Type     | Description                                                                                                                               |
| ------------------- | -------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `-Theme`            | `string` | Explicit theme to apply: `Dark` or `Light`. Omit when using `-Auto`.                                                                      |
| `-Auto`             | `switch` | Reads the theme for the detected machine type from `Configuration.Themes[MachineType]` (defaults to Dark if the machine type is unknown). |
| `-KeepTerminalOpen` | `switch` | Skips the default delayed close of the current Windows Terminal tab after a successful run.                                               |

```powershell
# Apply the configured theme for the current machine type
Set-SystemTheme -Auto

# Keep the current elevated terminal open after the theme update (e.g. mid-Bootstrap)
Set-SystemTheme -Auto -KeepTerminalOpen

# Force a specific theme regardless of configuration
Set-SystemTheme -Theme Dark
Set-SystemTheme -Theme Light

# Verbose diagnostic output
Set-LogLevel Verbose { Set-SystemTheme -Auto }
```

**See also:** [Set-Wallpaper](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Set-Wallpaper.ps1)

## [Set-TaskbarAutoHide](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Set-TaskbarAutoHide.ps1)

- **Description:** Enables or disables taskbar auto-hide for the current user via `SHAppBarMessage` (`ABM_SETSTATE`) - the same mechanism the Taskbar settings page uses. The change applies to the live Explorer session immediately and Explorer persists it on exit, so it survives reboots. With `-Auto` it reads the `TaskbarAutoHide` boolean from the configuration; when the key is absent or `$false` the function changes nothing, keeping the vanilla default untouched. Idempotent - returns early when the taskbar is already in the desired state.
- **Parameters:** -Auto, -Enabled [$true | $false]
- **Usage:** `Set-TaskbarAutoHide -Auto`, `Set-TaskbarAutoHide -Enabled $true`, `Set-TaskbarAutoHide -Enabled $false`

Called during Bootstrap (after `Configure-Taskbar`) with `-Auto`, making taskbar auto-hide an opt-in provisioning step: the base configuration ships `TaskbarAutoHide = $false` (taskbar untouched) and a fork opts in via `Configuration.local.psd1`. This is purely cosmetic/UX parity - FancyZones zone geometry is computed from the monitor work area, so window snapping is correct whether the taskbar is visible or auto-hidden.

| Parameter  | Type     | Description                                                                                                |
| ---------- | -------- | ----------------------------------------------------------------------------------------------------------- |
| `-Auto`    | `switch` | Resolves the desired state from the `TaskbarAutoHide` configuration key. Absent or `$false` means "leave the taskbar alone". |
| `-Enabled` | `bool`   | Explicitly enable (`$true`) or disable (`$false`) taskbar auto-hide.                                       |

```powershell
# Apply the configured preference (no-op unless TaskbarAutoHide = $true in config)
Set-TaskbarAutoHide -Auto

# Enable or disable auto-hide explicitly
Set-TaskbarAutoHide -Enabled $true
Set-TaskbarAutoHide -Enabled $false
```

## [Set-VisualEffects](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Set-VisualEffects.ps1)

- **Description:** Applies the Performance Options "Visual Effects" settings (System Properties > Performance Options > Visual Effects tab) from the `VisualEffects` section in the configuration. Every key mirrors one dialog checkbox one-to-one (`$true` = effect on / appearance, `$false` = effect off / performance); keys left out of the configuration are not touched, and when the section is absent or empty the function changes nothing - the vanilla default. Explorer/DWM-backed effects are written to the registry; the remaining effects go through `SystemParametersInfo` (the dialog's own mechanism), which persists them to the user profile and applies them live. Sets the dialog's radio button to "Custom" (`VisualFXSetting = 3`) whenever at least one effect is managed, and runs `Restart-Explorer` only when a registry-backed effect actually changed. Idempotent - returns early when every configured effect already matches; when changes are applied, every managed effect is reported on its own colored row (green = enabled, red = disabled, yellow `[skipped]` = already at the configured value). Unknown keys are skipped with a warning. Takes no parameters - all settings come from the configuration.
- **Usage:** `Set-VisualEffects`

Called during Bootstrap (after `Set-TaskbarAutoHide`), making visual effects an opt-in provisioning step: the base configuration ships the `VisualEffects` section fully commented (no effects touched) and a fork defines its preferences in `Configuration.local.psd1`. Valid keys: `AnimateControlsAndElementsInsideWindows`, `AnimateWindowsWhenMinimisingAndMaximising`, `AnimationsInTheTaskbar`, `EnablePeek`, `FadeOrSlideMenusIntoView`, `FadeOrSlideToolTipsIntoView`, `FadeOutMenuItemsAfterClicking`, `SaveTaskbarThumbnailPreviews`, `ShowShadowsUnderMousePointer`, `ShowShadowsUnderWindows`, `ShowThumbnailsInsteadOfIcons`, `ShowTranslucentSelectionRectangle`, `ShowWindowContentsWhileDragging`, `SlideOpenComboBoxes`, `SmoothEdgesOfScreenFonts`, `SmoothScrollListBoxes`, `UseDropShadowsForIconLabelsOnTheDesktop`.

```powershell
# Apply all effects configured in the VisualEffects section
Set-VisualEffects
```

**See also:** [Set-ExplorerOptions](system.md#set-exploreroptions), [Set-TaskbarAutoHide](system.md#set-taskbarautohide)

## [Set-Wallpaper](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Set-Wallpaper.ps1)

- **Description:** Sets the desktop wallpaper based on `MachineType` and theme. With `-Auto` it reads paths from `WallpaperDarkSettings`/`WallpaperLightSettings` in `Configuration.psd1` (selecting the entry for the current machine type, falling back to `Default`); without `-Auto` it presents an interactive picker of available wallpapers and styles. Supports multi-monitor configurations with per-monitor wallpaper and style assignment via the `IDesktopWallpaper` COM interface, automatically filtering out disconnected/phantom monitors so only active displays are configured. When the `VirtualDesktop` module is available it applies the wallpaper across all virtual desktops; otherwise only the current desktop. Wallpaper style (Fill, Fit, Stretch, Tile, Center, Span) is read from `WallpaperStyles`. Requires administrator privileges, uses COM retry logic for transient failures, and is idempotent - skipping when wallpaper, style, and tile values are already correct.
- **Parameters:** -Auto, -Theme [Light | Dark | Auto]
- **Usage:** `Set-Wallpaper -Auto`, `Set-Wallpaper -Auto -Theme Dark`, `Set-Wallpaper` (interactive)

Requires administrator privileges. In `-Auto` mode the theme defaults to `Auto`, which detects the current system theme from the registry (`HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize\AppsUseLightTheme`), defaulting to `Dark` if detection fails. It then resolves the wallpaper entry for the current machine type, applying per-monitor images for multi-monitor configs or a single image otherwise, and propagates the result to every virtual desktop when the `VirtualDesktop` module is loaded. Without `-Auto`, it lists wallpapers from the WinuX Wallpapers folder and prompts for a wallpaper and a style (defaulting to `Fill`).

| Parameter | Description                                                                                               |
| --------- | --------------------------------------------------------------------------------------------------------- |
| `-Auto`   | Auto-detect the system theme and apply the matching configured wallpaper. Omit for an interactive picker. |
| `-Theme`  | Theme to use: `Light`, `Dark`, or `Auto`. Defaults to `Auto` (reads from the registry).                   |

```powershell
# Apply configured wallpaper, auto-detecting the current system theme
Set-Wallpaper -Auto

# Force a specific theme variant
Set-Wallpaper -Auto -Theme Dark
Set-Wallpaper -Auto -Theme Light

# Interactive selection from available wallpapers and styles
Set-Wallpaper

# Verbose diagnostic output
Set-LogLevel Verbose { Set-Wallpaper -Auto }
```

**See also:** [Set-LockScreenWallpaper](system.md#set-lockscreenwallpaper), [Set-SystemTheme](system.md#set-systemtheme)

## [Show-PinnedAppsWarning](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Show-PinnedAppsWarning.ps1)

- **Description:** Prints a yellow warning listing apps that are pinned (version-locked) to a specific version and will be skipped by the upgrade functions. Helper used by the upgrade routines (e.g. `Upgrade-All`).
- **Parameters:** -PinnedApps, -Message
- **Usage:** `Show-PinnedAppsWarning -PinnedApps @("git", "nodejs")`, `Show-PinnedAppsWarning -PinnedApps @("git") -Message "Version-locked packages"`

| Parameter     | Description                                                                       |
| ------------- | --------------------------------------------------------------------------------- |
| `-PinnedApps` | Array of pinned app names to display. Nothing is printed when the array is empty. |
| `-Message`    | Custom warning message prefix. Defaults to `"Skipping version-pinned packages"`.  |

```powershell
# Warn about the default set of version-pinned packages
Show-PinnedAppsWarning -PinnedApps @("git", "nodejs")

# Use a custom message prefix
Show-PinnedAppsWarning -PinnedApps @("git", "nodejs") -Message "Version-locked packages"
```

## [SymbolicLinkMaker](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/SymbolicLinkMaker.ps1)

- **Description:** Creates symbolic links defined in `SymbolicLinks` under `MachineSpecificPaths` in `Configuration.psd1` for the current machine type. Creates native Windows symbolic links for paths containing backslashes and WSL symlinks for paths containing forward slashes, choosing the right command automatically (`wsl ln -s` for WSL, `New-Item -ItemType SymbolicLink` for Windows). Idempotent: an existing link pointing at the correct target is left in place, and supports nested (hierarchical) configurations via recursive processing. Requires administrator privileges.
- **Usage:** `SymbolicLinkMaker`

The machine type is resolved via `DetermineMachineType`, then the `SymbolicLinks` hashtable for that machine is walked recursively. Each leaf entry is a hashtable with `Path` and `Target` keys; entries with empty or null values are skipped. Entries whose **target does not exist** are skipped with a warning - linking to a missing target would delete the real file at `Path`, leave a dangling link, and create stray parent folders; such entries self-heal on the next run once the target exists. WSL entries are likewise skipped when no WSL distribution is available. For WSL targets, the parent directory is created with `mkdir -p` if missing and any pre-existing file or symlink at the path is removed first. For Windows targets, the parent directory is created via `Initialize-Directory` if missing and any existing item is removed before the new link is made.

```powershell
# Create all configured symbolic links for the current machine type (run elevated)
SymbolicLinkMaker
```

## [Terminate-AllBrowserProcesses](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Terminate-AllBrowserProcesses.ps1)

- **Description:** Gracefully terminates every browser declared in `Configuration.Universal.Browsers` (Firefox, Tor, Chrome, Edge, Brave) by posting `WM_CLOSE` to each browser's visible top-level windows. Browsers are disambiguated by both process name (derived from the configured `Exe` filename) and a brand-specific window title regex, so browsers that share a process name (Firefox vs. Tor, both `firefox.exe`) and chromium child processes (GPU/renderer/utility) are handled correctly. With `-Exclude`, `WM_CLOSE` is posted only to non-matching windows - kept windows are never touched, so there is no foreground-focus race.
- **Parameters:** -Exclude
- **Usage:** `Terminate-AllBrowserProcesses`, `Terminate-AllBrowserProcesses -Exclude "*YouTube*"`, `Terminate-AllBrowserProcesses -Exclude "*YouTube*", "*Gmail*"`

Browser identification is two-staged: the process name is resolved from each browser's configured executable (`firefox.exe` -> `firefox`, `chrome.exe` -> `chrome`), and a brand-specific title regex selects only the real top-level windows. `WM_CLOSE` is posted directly to each non-excluded window handle (per handle, not via `SendKeys`), so it does not touch the foreground and excluded windows are never accidentally closed by a misfired keystroke.

| Parameter  | Description                                                                                                                                                                                                                                                                 |
| ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-Exclude` | One or more window title patterns to keep open. Supports wildcard (`*YouTube*`) and regex (`.*YouTube.*`, `(.*Gmail.*\|.*Inbox.*)`) patterns, same format as the layout `.psd1` files. Browser windows matching any pattern are kept; all other browser windows are closed. |

```powershell
# Close every configured browser
Terminate-AllBrowserProcesses

# Close all browser windows except a kept YouTube tab
Terminate-AllBrowserProcesses -Exclude "*YouTube*"

# Verbose diagnostic output
Set-LogLevel Verbose { Terminate-AllBrowserProcesses -Exclude "*YouTube*", "*Gmail*" }
```

## [Terminate-AllProcessesByName](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Terminate-AllProcessesByName.ps1)

- **Description:** Forcefully terminates every process named in the `Universal.TerminateProcessNames` configuration list using `Stop-Process -Force`. Missing processes are silently ignored, and the function warns and terminates nothing when the list is absent or empty. Processes whose windows match an exclusion pattern are skipped. Docker is intentionally handled separately by `DockerWizard` before this function runs.
- **Parameters:** -Exclude
- **Usage:** `Terminate-AllProcessesByName`, `Terminate-AllProcessesByName -Exclude "*Important Project*"`

Iterates the configured target process list (the base configuration ships a minimal example - keep your real cleanup targets in `Configuration.local.psd1`, which replaces the array wholesale on merge) and, for each, separates the running instances into those to terminate and those to exclude. `-Exclude` patterns are matched against each process's name and main window title (via `Test-WindowTitleMatch`), so a single match spares that instance while the rest are still killed. Under `Set-LogLevel Verbose` it prints the target list, per-process found/excluded/terminated counts, and PID/window details for excluded instances.

| Parameter  | Description                                                                                                                                                                                                             |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-Exclude` | Array of window title patterns to exclude from termination. Supports both wildcard (`"*YouTube*"`) and regex (`".*YouTube.*"`, `"(.*Gmail.*\|.*Inbox.*)"`) patterns, using the same format as the layout `.psd1` files. |

```powershell
# Terminate every configured named process
Terminate-AllProcessesByName

# Spare any VS Code / chat window whose title matches the pattern
Terminate-AllProcessesByName -Exclude "*Important Project*"

# Verbose diagnostic output
Set-LogLevel Verbose { Terminate-AllProcessesByName }
```

## [Terminate-AllProcessesWithVisibleWindows](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Terminate-AllProcessesWithVisibleWindows.ps1)

- **Description:** Forcefully terminates all processes that expose a visible top-level window (non-empty `MainWindowTitle`), preserving the default exclusions used by the desktop cleanup flow: every browser declared in `Configuration.Universal.Browsers` (handled gracefully by `Terminate-AllBrowserProcesses` instead) plus every process named in the `Universal.VisibleWindowExclusions` configuration list (`Rainmeter`, `WindowsTerminal`, `Docker Desktop`, `obs64`, and the PowerToys supervisor/FancyZones/Settings processes by default). Warns and terminates nothing when the exclusion list is absent or empty, since running without it would force-kill `WindowsTerminal` - the shell running the cleanup. Additional windows can be spared via the `-Exclude` parameter.
- **Parameters:** -Exclude
- **Usage:** `Terminate-AllProcessesWithVisibleWindows`, `Terminate-AllProcessesWithVisibleWindows -Exclude "*YouTube*"`, `Terminate-AllProcessesWithVisibleWindows -Exclude "*YouTube*", "*Obsidian*"`

Enumerates every process with a non-empty `MainWindowTitle`, then drops the default-excluded process names (from `Universal.VisibleWindowExclusions`) before deciding what to kill. Browser process names are pulled dynamically from `Configuration.Universal.Browsers` so this stays in sync with `Terminate-AllBrowserProcesses`, which has already closed those windows gracefully via `WM_CLOSE` - force-killing the underlying browser processes here would race that flow and also tear down deliberately-kept tabs. Any window whose title matches an `-Exclude` pattern (via `Test-WindowTitleMatch`) is skipped; the rest are stopped with `Stop-Process -Force`.

| Parameter  | Description                                                                                                                               |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `-Exclude` | Array of window-title patterns to spare from termination. Supports both wildcard (`"*YouTube*"`) and regex (`".*YouTube.*"`, `"(._Gmail._ | ._Inbox._)"`) forms, the same format used by layout `.psd1` files. Windows matching any pattern are not closed. |

> [!WARNING]
> The PowerToys exclusions are intentional. Killing only the visible `PowerToys.Settings` window leaves the supervisor in a "running but FancyZones absent" half-state that breaks subsequent workspace layout application and forces an expensive `Start-FancyZones -ForceRestart`. Never remove these from `Universal.VisibleWindowExclusions`.

```powershell
# Close every visible-window process except the built-in default exclusions
Terminate-AllProcessesWithVisibleWindows

# Additionally keep specific windows open (wildcard patterns)
Terminate-AllProcessesWithVisibleWindows -Exclude "*YouTube*", "*Obsidian*"

# Verbose diagnostic output
Set-LogLevel Verbose { Terminate-AllProcessesWithVisibleWindows }
```

## [Terminate-WindowsTerminalTabs](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Terminate-WindowsTerminalTabs.ps1)

- **Description:** Closes Windows Terminal tabs. It temporarily renames the current tab to a unique ID, then cycles through all other tabs with `Ctrl+Tab`, closing any tab that does not match the marker. Detection across all open Windows Terminal windows is supported (not just the hosting one), and `--suppressApplicationTitle` is handled by falling back to the original tab title when the marker is not reflected in the Win32 window title. With `-IncludeCurrent` the current tab is also closed at the end via a clean process exit; with `-OnlyCurrent` it closes only the calling tab through the same deterministic exit seam.
- **Parameters:** -IncludeCurrent, -OnlyCurrent, -CloseWaitSeconds
- **Usage:** `Terminate-WindowsTerminalTabs`, `Terminate-WindowsTerminalTabs -IncludeCurrent`, `Terminate-WindowsTerminalTabs -OnlyCurrent`, `Terminate-WindowsTerminalTabs -OnlyCurrent -CloseWaitSeconds 5`

Walks the parent-process chain from the current shell to identify the Windows Terminal process actually hosting it, so the right window is targeted even when several Windows Terminal processes are running (elevated and non-elevated, or multiple user windows). It marks the current tab with a unique title, cycles tabs with `Ctrl+Tab`, and closes non-marker tabs with `Ctrl+C` then `Ctrl+W`, using consecutive marker detection to know when all tabs have been cycled. Additional Windows Terminal windows are processed separately (since `Ctrl+Tab` only cycles within one window), and a retry verification pass re-checks and closes any tabs that survived. Each close attempt is verified to have actually changed the active tab or window, and a warning is emitted when tabs or windows remain open after cleanup.

| Parameter           | Type          | Default | Description                                                                                                                                             |
| ------------------- | ------------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-IncludeCurrent`   | `switch`      | -       | Also closes the current calling tab after all other tabs are processed.                                                                                 |
| `-OnlyCurrent`      | `switch`      | -       | Closes only the current (calling) tab without affecting any others. Useful when a new window has been opened and the original calling tab is redundant. |
| `-CloseWaitSeconds` | `int` (0-300) | `0`     | Waits this many seconds before closing the current tab when `-OnlyCurrent` or `-IncludeCurrent` is used, giving time to read the final status output.   |

```powershell
# Close every other Windows Terminal tab, keeping the current one
Terminate-WindowsTerminalTabs

# Close all tabs, including the current calling tab, then exit cleanly
Terminate-WindowsTerminalTabs -IncludeCurrent

# Close only the current (redundant) tab, after a 5-second pause to read output
Terminate-WindowsTerminalTabs -OnlyCurrent -CloseWaitSeconds 5

# Verbose diagnostic output
Set-LogLevel Verbose { Terminate-WindowsTerminalTabs }
```

## [Test-MachineOnline](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Test-MachineOnline.ps1)

- **Description:** Tests whether a machine is online (reachable via ICMP ping) and returns a boolean for use in conditional logic. The target is resolved from the `Address` field of `WakeOnLanConfig` in `Configuration.psd1` by machine name, or supplied directly as an IP address / hostname. Supports a single check (default) or a wait-for-online mode (`-WaitForOnline`) that polls until the host responds or `-TimeoutSeconds` elapses. Used by `Send-WakeOnLan` for its "already on" skip and to verify a machine has finished booting after a magic packet. Returns `$false` if no `Address` is configured.
- **Parameters:** -Machine, -Address, -DisplayName, -WaitForOnline, -TimeoutSeconds (default 120), -IntervalSeconds (default 3), -PingTimeoutMilliseconds (default 1000), -Quiet
- **Usage:** `Test-MachineOnline -Machine "MyMachine"`, `Test-MachineOnline -Address 192.0.2.10 -WaitForOnline -TimeoutSeconds 90`, `if (Test-MachineOnline -Machine "MyMachine" -Quiet) { "MyMachine is up" }`

Pings a target to determine whether it is currently powered on and reachable. With `-Machine`, the target is looked up by name in `WakeOnLanConfig` and its `Address` field is used; with `-Address`, the given IP/hostname is pinged directly (this is the path `Send-WakeOnLan` uses). In single-check mode it pings once and reports the result. In wait-for-online mode it polls at `-IntervalSeconds` intervals, printing a live countdown, until the host responds or the timeout elapses.

| Parameter                  | Description                                                                                           |
| -------------------------- | ----------------------------------------------------------------------------------------------------- |
| `-Machine`                 | Machine name as defined in `WakeOnLanConfig`; its `Address` field is used as the ping target.         |
| `-Address`                 | Explicit IP address or hostname to ping. Use instead of `-Machine` when the address is already known. |
| `-DisplayName`             | Friendly name used in console messages. Defaults to `-Machine` or `-Address`.                         |
| `-WaitForOnline`           | Poll repeatedly until the machine responds or `-TimeoutSeconds` is reached.                           |
| `-TimeoutSeconds`          | Maximum time to wait when `-WaitForOnline` is used. Default 120.                                      |
| `-IntervalSeconds`         | Delay between ping attempts when `-WaitForOnline` is used. Default 3.                                 |
| `-PingTimeoutMilliseconds` | Per-ping timeout in milliseconds. Default 1000.                                                       |
| `-Quiet`                   | Suppress all console output and only return the boolean result.                                       |

```powershell
# Single ICMP ping by configured machine name; reports and returns online/offline
Test-MachineOnline -Machine "MyMachine"

# Poll an explicit address until it responds or 90s elapses
Test-MachineOnline -Address 192.0.2.10 -WaitForOnline -TimeoutSeconds 90

# Use the result in a condition with no console output
if (Test-MachineOnline -Machine "MyMachine" -Quiet) { "MyMachine is up" }
```

**See also:** [Send-WakeOnLan](system.md#send-wakeonlan)

## [Test-PowerPlan](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Test-PowerPlan.ps1)

- **Description:** Checks whether the active power plan is set to the optimal performance mode for the current machine type. Uses WMI chassis type detection (`Win32_SystemEnclosure`) to determine if the machine is a laptop or desktop, then verifies High Performance for laptops/portables or Ultimate Performance for desktops, and warns if not optimally configured. Chassis types are defined in `Configuration.LaptopChassisTypes`.
- **Usage:** `Test-PowerPlan`

Reads the active scheme via `powercfg /getactivescheme` and compares it against the expected plan for the detected machine type. If the active plan is wrong, it prints a yellow warning suggesting `Set-PowerPlan -Auto` to fix it. Any failure during the check is reported as a red error. Commonly run at shell startup from the PowerShell profile.

```powershell
# Verify the active power plan matches the optimal mode for this machine
Test-PowerPlan
```

**See also:** [Set-PowerPlan](system.md#set-powerplan)

## [Test-RpcServerHealth](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Test-RpcServerHealth.ps1)

- **Description:** Verifies that required Remote Procedure Call (RPC) infrastructure services are running and, optionally, that the live RPC endpoint actually responds. Essential for FancyZones, virtual desktop management, and other system operations that depend on RPC. With `-Probe` it runs a lightweight VirtualDesktop COM roundtrip under a timeout to catch the "service is Running but the endpoint is hung" failure mode (`0x800706BA` / `0x800706BE`) that a status check alone cannot detect.
- **Parameters:** -ServiceNames (defaults to @("RpcSs", "DcomLaunch", "RpcEptMapper")), -Probe, -ProbeTimeoutMs (default 5000)
- **Usage:** `Test-RpcServerHealth`, `Test-RpcServerHealth -Probe`, `Test-RpcServerHealth -ServiceNames @("RpcSs", "DcomLaunch")`

Checks that each required RPC service is present and in `Running` state, returning `$false` on the first one that is missing or stopped. With `-Probe`, after confirming services are running it spins up a `Start-Job` (child `pwsh.exe`) that imports `VirtualDesktop` and runs a cheap `Get-DesktopList` COM call under a hard timeout. If the call hangs (timeout), or throws a classic RPC unavailability code (`0x800706BA` / `0x800706BE` / "RPC server is unavailable"), the function returns `$false`. Non-RPC probe failures (e.g. the `VirtualDesktop` module missing) and probe-infrastructure failures are treated as healthy so they don't trigger unnecessary service restarts. Returns `$true` only when all checks pass.

| Parameter         | Type       | Default                                    | Description                                                                                                                    |
| ----------------- | ---------- | ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------ |
| `-ServiceNames`   | `string[]` | `@("RpcSs", "DcomLaunch", "RpcEptMapper")` | RPC service names to verify.                                                                                                   |
| `-Probe`          | `switch`   | -                                          | Run a live VirtualDesktop COM roundtrip under a timeout to detect a Running-but-unresponsive endpoint.                         |
| `-ProbeTimeoutMs` | `int`      | `5000`                                     | Hard timeout for the live probe (ms). Kept generous because the child job must import VirtualDesktop before the COM call runs. |

Required services: **RpcSs** (Remote Procedure Call System service - core RPC transport), **DcomLaunch** (DCOM Server Process Launcher - distributed component initialization), **RpcEptMapper** (RPC Endpoint Mapper - service discovery and connectivity).

```powershell
# Test default RPC services (RpcSs, DcomLaunch, RpcEptMapper)
Test-RpcServerHealth                          # $true if all running, else $false

# Live readiness probe - catches "Running but endpoint hung" failures
Test-RpcServerHealth -Probe

# Verbose diagnostic output
Set-LogLevel Verbose { Test-RpcServerHealth -Probe }

# Verify only a specific subset of services
Test-RpcServerHealth -ServiceNames @("RpcSs", "DcomLaunch")
```

Used by `Start-FancyZones`, `Set-WorkspaceWindowLayout`, and `Initialize-WorkspaceWindowLayoutRerun` as the gate before expensive recovery actions. A plain status check is not enough: RPC services can sit in `Running` state while the endpoint is hung after heavy DCOM churn (mass `Stop-Process -Force`, repeated COM calls), so use `-Probe` when the decision to run a costly recovery depends on real responsiveness.

**See also:** [Repair-RpcServer](system.md#repair-rpcserver)

## [Test-WindowTitleMatch](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Test-WindowTitleMatch.ps1)

- **Description:** Tests whether a window/process matches any of the provided patterns, returning a boolean. It first checks for a case-insensitive exact match against the process name, then matches the window title against each pattern as either a wildcard or a regex. Used internally by `Kill-All` and `Terminate-*` functions for exclusion filtering.
- **Parameters:** -WindowTitle, -ProcessName, -Patterns (required)
- **Usage:** `Test-WindowTitleMatch -WindowTitle "YouTube - Google Chrome" -Patterns @("*YouTube*")`, `Test-WindowTitleMatch -ProcessName "Code" -WindowTitle "file.ps1 - Visual Studio Code" -Patterns @("Code")`, `Test-WindowTitleMatch -WindowTitle "Gmail Inbox" -Patterns @("(.*Gmail.*|.*Inbox.*)")`

Iterates over `-Patterns` and returns `$true` on the first match. For each pattern it first attempts a case-insensitive exact match against `-ProcessName`. If that fails (and a `-WindowTitle` is present) the pattern is treated as a regex; when it is not valid regex but looks like a wildcard, it is converted (`*` to `.*`, `?` to `.`) before matching against the title. Blank patterns are skipped, and `$false` is returned when nothing matches. Pattern format mirrors `Get-WindowHandle` and the window-layout `.psd1` files.

| Parameter      | Description                                                                                                                                                                                   |
| -------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------- |
| `-WindowTitle` | The actual window title to test against the patterns. May be empty.                                                                                                                           |
| `-ProcessName` | The process name to test against the patterns for exact (case-insensitive) matching. Optional.                                                                                                |
| `-Patterns`    | Required array of patterns. Each entry may be an exact process name (e.g. `"Code"`, `"firefox"`), a wildcard (e.g. `"*YouTube*"`, `"Chrome - *"`), or a regex (e.g. `"^Chrome"`, `"(._Gmail._ | ._Inbox._)"`). |

```powershell
# Wildcard match against the window title -> $true
Test-WindowTitleMatch -WindowTitle "YouTube - Google Chrome" -Patterns @("*YouTube*")

# Exact, case-insensitive match against the process name -> $true
Test-WindowTitleMatch -ProcessName "Code" -WindowTitle "file.ps1 - Visual Studio Code" -Patterns @("Code")

# No pattern matches -> $false
Test-WindowTitleMatch -WindowTitle "My Document - Word" -Patterns @("*YouTube*", "*Gmail*")

# Regex alternation against the window title -> $true
Test-WindowTitleMatch -WindowTitle "Gmail Inbox" -Patterns @("(.*Gmail.*|.*Inbox.*)")
```

## [Unpin-TaskbarApps](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Unpin-TaskbarApps.ps1)

- **Description:** Clears all taskbar pins and applies an XML layout policy that prevents further taskbar modifications. It first calls `Clear-TaskbarPins` to remove pin data directly from the registry, then writes an empty `TaskbarLayout` XML and deploys it via Group Policy under `HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer`, locking the layout until the policy registry key is removed. Restarts Explorer to apply the changes. Requires administrator privileges.
- **Parameters:** -SkipExplorerRestart, -FromBootstrap
- **Usage:** `Unpin-TaskbarApps`, `Unpin-TaskbarApps -SkipExplorerRestart`

Optimized for Windows 11 (Build 26100+). The empty layout XML is written directly to the machine-local `TaskbarLayoutFile` (`C:\ProgramData\provisioning\taskbar_layout.xml`), registered as `StartLayoutFile`, and the layout is locked via `LockedStartLayout` - no repo file and no symlink are involved. `-FromBootstrap` is used internally during bootstrap: it skips the Explorer restart, defers the layout lock to the caller, and passes `-SkipExplorerRestart` down to `Clear-TaskbarPins`.

| Parameter              | Description                                                                                                                        |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `-SkipExplorerRestart` | Skips the Explorer restart after clearing pins.                                                                                    |
| `-FromBootstrap`       | Internal use during bootstrap; skips the Explorer restart and defers locking the layout to the caller. |

```powershell
# Clear taskbar pins and apply the locking policy (restarts Explorer)
Unpin-TaskbarApps

# Clear and apply the policy without restarting Explorer (caller handles restart)
Unpin-TaskbarApps -SkipExplorerRestart
```

**See also:** [Configure-Taskbar](system.md), [Clear-TaskbarPins](system.md)

## [Update-DirectoryNames](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Update-DirectoryNames.ps1)

- **Description:** Scans directories under a given path for names ending in a date suffix (`YYYY_MM_DD`) and renames them so the date becomes today's date. Use `-WhatIf` to preview changes without renaming. Directories already carrying today's date are reported as up to date.
- **Parameters:** -Path, -WhatIf
- **Usage:** `Update-DirectoryNames`, `Update-DirectoryNames -Path "C:\My Folders"`, `Update-DirectoryNames -Path "C:\My Folders" -WhatIf`

Only directories whose name ends in three underscore-separated segments matching `YYYY`, `MM`, and `DD` are considered. The trailing date is replaced with the current date while any leading name segments are preserved (for example `MyDocs_2024_01_15` becomes `MyDocs_2026_06_24`). Rename failures are caught and reported per directory, and when nothing needs changing a summary line confirms all directories are up to date.

| Parameter | Description                                                                            |
| --------- | -------------------------------------------------------------------------------------- |
| `-Path`   | Root directory to scan for dated subdirectory names. Defaults to the current location. |
| `-WhatIf` | Shows what would be renamed without performing any changes.                            |

```powershell
# Update all dated directories in the current location
Update-DirectoryNames

# Preview changes for a specific path without renaming anything
Update-DirectoryNames -Path "C:\My Folders" -WhatIf
```

## [Upgrade-All](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/System/Functions/Upgrade-All.ps1)

- **Description:** Upgrades all packages across WinGet, Scoop, and/or Chocolatey. Reads pinned (version-locked) apps from the configured CSV files and prevents them from being upgraded. Without `-PackageManager` it upgrades across all managers listed in `PackageManagers` in `Configuration.psd1`; with `-PackageManager` it upgrades only the specified manager. Requires administrator privileges.
- **Parameters:** -PackageManager
- **Usage:** `Upgrade-All`, `Upgrade-All -PackageManager "WinGet"`

For each targeted manager the function first loads its version-pinned apps from the manager's CSV data file, warns about them, and pins them so they are excluded from the upgrade, then runs the manager's bulk upgrade (`winget upgrade --all`, `scoop update *`, or `choco upgrade all -y`) and reports success or the failing exit code per manager.

| Parameter         | Description                                                                                                                   |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `-PackageManager` | Single manager to upgrade: `WinGet`, `Scoop`, or `Chocolatey`. Omit to upgrade every manager configured in `PackageManagers`. |

```powershell
# Upgrade all packages across every configured manager (run as admin)
Upgrade-All

# Upgrade only WinGet packages
Upgrade-All -PackageManager "WinGet"
```

## Testing

> [!NOTE]
> System functions are covered by Pester tests in `Windows/PowerShell/Modules/Tests/Modules/System/`. Use `Run-Tests -TestName "System"` (or `Run-Tests`) to validate current behavior after changes.
