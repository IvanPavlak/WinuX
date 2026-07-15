# Configuration Reference

**`Configuration.psd1`** is the central hub for the entire WinuX system. It contains all settings, paths, and configurations that control how the PowerShell modules behave.

- **Location:** `Windows/PowerShell/Configuration.psd1`
- **Loaded during:** Bootstrap, profile initialization, manual load via `Load-PathConfiguration`
- **Global variables produced:** `$global:Configuration`, `$global:MachineSpecificPaths`, `$global:MachineType`
- **Placeholder system:** Enables machine-independent configuration via `{Dev}`, `{User}`, `{MachineType}`, `{RepoRoot}`, `{AppData}` tokens

---

## Universal Constants

Machine-independent settings that remain the same across all machines.

### Browser Configuration

Defines executable paths and command-line arguments for each browser.

**Keys:**

- `Browsers` - Hashtable mapping browser names to configurations
    - Each browser: `Exe` (path), `PrivateArg` (privacy mode flag), `NewWindowArg` (new window flag)
- `DefaultBrowser` - Browser used by `Open-Browser` when no browser specified (default: "Firefox")

**Consumer functions:** `Open-Browser`, `Invoke-Browser`, `Open-SecureBrowser`

**Example:**

```powershell
Browsers = @{
    Firefox = @{
        Exe          = "C:\Program Files\Mozilla Firefox\firefox.exe"
        PrivateArg   = "-private-window"
        NewWindowArg = "-new-window"
    }
    Tor = @{
        Exe = "{User}\Tor Browser\Browser\firefox.exe"
    }
}
DefaultBrowser = "Firefox"
```

### GitHub Configuration

Repository URLs and authentication base.

**Keys:**

- `GitHub.Base` - Authentication base URL (e.g., `https://MyUser@github.com`)
- `GitHub.Private.*` - Private repositories (dot-notation, e.g., `Private.WinuX`)
- `GitHub.MyOrg.*` - Work organization repositories

**Consumer functions:** `Initialize-Repository`, `Update-Repositories`, `Git-Obsidian`

### Application Executables

Paths to installed applications used by `Open-*` functions.

**Keys:**

- `FirefoxExe`, `LeagueOfLegendsExe`, `SteamExe`, `RiseupVpnExe`, `DbeaverExe`, `TeamViewerExe`, `FoundryVTTExe`, `NotepadPlusPlusExe`, `VisualStudio2026Exe`, `VirtualBoxExe`, `DockerExe`

**Consumer functions:** `Open-DBeaver`, `Open-Discord`, `Open-Obsidian`, `Open-Acrobat`, `Open-LeagueOfLegends`, etc.

### Universal Paths

Common system paths that do not vary by machine.

**Keys:**

- `Desktop` - User's desktop folder (auto-resolved at runtime)
- `Fonts` - Windows Fonts directory
- `TaskbarPinFolder` - Quick Launch taskbar pins folder
- `IconCacheDb`, `IconCacheFolder` - Windows Explorer icon cache
- `OhMyPoshThemeFile` - Oh-My-Posh theme location
- `WhatsAppLocalStoragePath` - WhatsApp cache directory

---

## Machine Type Detection

### Valid Machine Types

Valid hostname-based machine categories.

**Key:** `ValidMachineTypes` - Array of allowed types (e.g., `@("PC", "Laptop", "Work", "Test")`)

### Hostname to Machine Type Mapping

Maps current hostname to machine type for auto-detection.

**Key:** `HostnameToMachineType` - Hashtable mapping hostname → machine type

**Example:**

```powershell
HostnameToMachineType = @{
    "DESKTOP-GAMING"     = "PC"
    "LAPTOP-PERSONAL" = "Laptop"
}
```

**Consumer functions:** `DetermineMachineType` (called during Bootstrap)

**Behavior:** If current hostname not found in this map, `DetermineMachineType` prompts interactively.

### Default Machine Type

Fallback machine type if detection fails.

**Key:** `DefaultMachineType`

---

## Base Paths Per Machine Type

Defines root directories for each machine type. Used to expand `{Dev}` and `{User}` placeholders.

**Key:** `BasePaths` - Nested hashtable: `BasePaths.PC.Dev`, `BasePaths.Laptop.Dev`, etc.

**Example:**

```powershell
BasePaths = @{
    PC     = @{ Dev = "%USERPROFILE%\Development\GitHub"; User = "%USERPROFILE%" }
    Laptop = @{ Dev = "%USERPROFILE%\Development\GitHub"; User = "%USERPROFILE%" }
    Work   = @{ Dev = "%USERPROFILE%\Development\GitHub"; User = "%USERPROFILE%" }
    Test   = @{ Dev = "%USERPROFILE%\Development\GitHub"; User = "%USERPROFILE%" }
}
```

> [!NOTE]
> `BasePaths` values *define* the `{Dev}`/`{User}` placeholders, so they cannot use them -
> only environment variables (`%USERPROFILE%`) are expanded inside `BasePaths`.

**Consumer functions:** `Expand-ConfigPaths` (all path-dependent functions)

**Customization:** To use different development directories per machine, update `BasePaths` for each machine type.

---

## Path Templates & Placeholder System

Common paths and templates using placeholder tokens for machine independence.

**Placeholder tokens:**

- `{Dev}` - Machine's development root (from `BasePaths.Dev`)
- `{User}` - Machine's user root (from `BasePaths.User`)
- `{MachineType}` - Current machine type (PC, Laptop, Work, Test)
- `{RepoRoot}` - WinuX repository root path (auto-resolved)
- `{AppData}` - User's `AppData\Roaming` folder

**Key:** `PathTemplates` - Nested hashtable of template paths

**Example:**

```powershell
PathTemplates = @{
    ObsidianDirectory                = "{Dev}\Obsidian"
    TrainingBackupDirectory          = "{Dev}\ExampleBackup"

    Projects = @{
        OtherProject = @{
            Root     = "{Dev}\OtherProject"
            Solution = "{Dev}\OtherProject\OtherProject.sln"
            Api      = "{Dev}\OtherProject\src\OtherProject.Api"
            Ui       = "{Dev}\OtherProject\src\OtherProject.UI"
        }
    }
}
```

**Consumer functions:** `Expand-ConfigPaths`, `Expand-Hashtable`, all path-dependent functions

---

## Project Management

Defines projects and their associated actions, terminals, and run configurations.

### Projects List

All available projects for the `Open-Project` menu.

**Key:** `Projects` → Array of project names

**Consumer function:** `Open-Project`

### Project Actions

Defines what happens when a project opens. Each action is executed in order.

**Key:** `ProjectActions.{ProjectName}` → Array of action objects

**Action object format:**

```powershell
@{
    Action     = "Function-Name"                    # Function to invoke
    Parameters = @{ ParamName = "Value"; ... }      # Function parameters
}
```

**Special actions:**

- `"Open-ProjectTerminals-Or-RunProject"` - Opens project terminals; if `-RunApp` flag, runs the project
- `"Return"` - Terminates action sequence

**Consumer function:** `Open-Project` with parameter forwarding via `Get-FilteredParams`

**Example:**

```powershell
ProjectActions = @{
    MyProject = @(
        @{ Action = "Open-VSCode"; Parameters = @{ Folder = "MyProject" } }
        @{ Action = "Open-Browser"; Parameters = @{ Groups = @("MyProject-Api") } }
        @{ Action = "Open-ProjectTerminals" }
    )
}
```

### Project Terminals

Terminal tab configurations for each project. Defines terminal names and their working directories.

**Key:** `ProjectTerminals` → Array of per-project terminal configurations

**Terminal configuration format:**

```powershell
@{
    Name     = "MyProject"                # Project name (matched by Open-ProjectTerminals)
    BasePath = "Projects.MyProject"       # Dot-notation reference into the expanded paths (NOT a literal folder)
    Paths    = @("ROOT", "API", "UI")     # Subpath keys under that BasePath - one terminal tab each
}
```

**Consumer functions:** `Open-ProjectTerminals`, `Close-ProjectTerminals`, `Focus-TerminalTab`

### Runnable Project Mappings

Maps project names to run commands and startup configurations.

**Key:** `RunnableProjectMappings` → Array of run configurations

**Run command strings:**

- `"dnr"` → `dotnet run`
- `"dnbr"` → `dotnet build && dotnet run`
- `"nir"` → `npm install && npm start`
- `"<custom-string>"` → Executed as-is in terminal
- `""` (empty) → Terminal only (no auto-run)

**Consumer function:** `Run-Project` (invoked by `rp` alias)

**Example:**

```powershell
RunnableProjectMappings = @(
    @{
        Name              = "OtherProject"
        Commands          = @("dnr", "nir")       # One command per ProjectTerminals Paths entry, same order
        DatabaseProviders = @("PostgreSQL")       # Optional - starts Docker Compose via DockerWizard
    }
)
```

### Visual Studio Solutions

Maps solution names to `.sln` file paths.

**Key:** `VisualStudioSolutions` → Array of `@{ Name; Solution }` entries, where `Solution` is a
dot-notation reference into the expanded paths (not a literal `.sln` path)

**Consumer function:** `Open-VisualStudio`

**Example:**

```powershell
VisualStudioSolutions = @(
    @{ Name = "ExampleProject"; Solution = "Projects.ExampleProject.Solution" }
)
```

### VS Code Projects

Maps project names to folder paths for VS Code.

**Key:** `VSCodeProjects` → Array of `@{ Name; Path }` entries (`Path` is a dot-notation
reference into the expanded paths, e.g. `"Projects.Self.Root"`)

**Consumer function:** `Open-VSCode`

### VS Code Workspaces Path

Folder holding the `.code-workspace` files that `Open-VSCodeWorkspace` (and the `Open-Workspace -VSCodeWorkspace` override) can open.

**Key:** `PathTemplates.Projects.Self.VSCodeWorkspaces` → `"{RepoRoot}\VSCode\Workspaces"`

**Consumer functions:** `Open-VSCodeWorkspace`, `Get-VSCodeWorkspaceNames`, `Open-Workspace`

Each `*.code-workspace` file in this folder is addressed by its base name (e.g. `Consolidation.code-workspace` → `Consolidation`). This is one of the `Projects.Self` paths (alongside `Root`, `Modules`, `Layouts`, etc.) that point inside the repository via the `{RepoRoot}` placeholder.

---

## Browser Groups

Defines hierarchical URL groups for the `Open-Browser` function. Supports three nesting patterns.

**Key:** `BrowserGroups` → Nested hashtable of group definitions

**Nesting patterns:**

1. **Simple URL list** - Array of URLs

    ```powershell
    Resources = @(
        "https://github.com/MyUser/WinuX",
        "https://github.com/MyUser/Obsidian"
    )
    ```

2. **Named URLs** - Array of objects with `Name` and `Url`

    ```powershell
    Documentation = @(
        @{ Name = "PowerShell Docs"; Url = "https://docs.microsoft.com/powershell/" },
        @{ Name = "GitHub"; Url = "https://github.com" }
    )
    ```

3. **Nested sub-groups** - Hashtable with sub-group objects

    ```powershell
    Development = @{
        Frontend = @(
            @{ Name = "React"; Url = "https://react.dev" }
        )
        Backend = @(
            @{ Name = ".NET Docs"; Url = "https://dotnet.microsoft.com/docs" }
        )
    }
    ```

4. **Mixed arrays** - Single group can contain both named URLs and nested sub-groups
    ```powershell
    MyGroup = @(
        "https://url1.com",
        @{ Name = "Named"; Url = "https://url2.com" },
        @{ SubGroup = @( ... ) }
    )
    ```

**Consumer functions:** `Open-Browser`, `Collect-BrowserUrls`, `Test-BrowserGroupAlreadyOpen`

**Important:** Names must be unique across all groups (used by `Test-BrowserGroupAlreadyOpen` for idempotency checking).

---

## Acrobat Configuration

PDF document groups for `Open-Acrobat`.

**Keys:**

- `AcrobatPdfGroups` - Hashtable mapping group names → paths
- `AcrobatGroups` → Alternative naming (verify current config)

**Consumer function:** `Open-Acrobat`

**Example:**

```powershell
AcrobatPdfGroups = @{
    Learning = "{User}\Learning\Programming C 10 Build Cloud, Web, and Desktop Applications Ian Griffiths.pdf"
    DnD      = @{
        MyCampaign = "{Dev}\Obsidian\03_DungeonsAndDragons\Campaigns\...\.pdf"
    }
}
```

---

## Workspace Management

Defines workspaces and their associated actions.

### Workspaces List

All available workspaces for the `Open-Workspace` menu.

**Key:** `Workspaces` → Array of workspace names

**Consumer function:** `Open-Workspace`

### Workspace Actions

Defines what happens when a workspace opens.

**Key:** `WorkspaceActions.{WorkspaceName}` → Array of action objects

**Format:** Same as `ProjectActions` - array of `@{ Action = "...", Parameters = @{ ... } }` objects

**Special actions:** Same as `ProjectActions` (`Open-ProjectTerminals-Or-RunProject`, `Return`). When a workspace runs an `Open-Browser` action, the active project's `Swagger` group is automatically added via `Resolve-SwaggerBrowserGroup` (unless it is already open).

**Example:**

```powershell
WorkspaceActions = @{
    Training = @(
        @{ Action = "Open-Terminal"; Parameters = @{} }
        @{ Action = "Open-VSCode"; Parameters = @{ Folder = "TrainingDirectory" } }
        @{ Action = "Open-Browser"; Parameters = @{ Groups = @("Learning") } }
    )
}
```

### Default VS Code Workspaces

Optionally maps an `Open-Workspace` name to a `.code-workspace` base name (under `VSCode\Workspaces`). When a workspace has an entry here, running it opens that `.code-workspace` in place of the project folder. (The window layout needs no adjustment for this - VS Code layout entries match by process, so the workspace window lands in the VS Code slot like any other VS Code window.) A command-line `-VSCodeWorkspace <name>` overrides this default; a bare `-VSCodeWorkspace` shows a selection menu. Empty (the default) means normal project-folder behaviour.

**Key:** `DefaultVSCodeWorkspaces` → Hashtable mapping workspace name → `.code-workspace` base name (empty `@{}` by default)

**Consumer functions:** `Open-Workspace`, `Open-VSCodeWorkspace`

**Example:**

```powershell
DefaultVSCodeWorkspaces = @{
    dotfiles = "Consolidation"   # `w dotfiles` opens Consolidation.code-workspace instead of the folder
}
```

### Workspace Layouts

Window placement configurations. Defined in `Layouts/{MachineType}/{WorkspaceName}_{MachineType}.psd1` files.

Each layout file specifies:

- **Monitors:** Virtual desktop layout mapping
- **Layout:** Array of window placement rules with ProcessName, WindowTitle, DesktopNumber, Zone, Monitor

**Consumer function:** `Set-WorkspaceWindowLayout`

---

## System Theme & Wallpaper

### Themes

Per-machine theme configuration (light/dark).

**Key:** `Themes.{MachineType}` → "Light" or "Dark"

**Consumer function:** `Set-SystemTheme`

### Wallpaper Settings

Machine and theme-specific wallpaper configurations.

**Keys:**

- `WallpaperDarkSettings.{MachineType}` → Dark theme wallpaper paths (per monitor)
- `WallpaperLightSettings.{MachineType}` → Light theme wallpaper paths (per monitor)

**Format:** Per-monitor array (order matters for multi-monitor setups)

**Consumer function:** `Set-Wallpaper`, `Set-SystemTheme`

**Example:**

```powershell
WallpaperDarkSettings = @{
    # Single-monitor machine: one file + style
    Test = @{ File = "Black.jpg"; Style = "Fill" }
    # Multi-monitor machine: one entry per monitor, in monitor order
    PC   = @{ Monitors = @(
        @{ File = "DarkPrimary.jpg"; Style = "Fill" }
        @{ File = "DarkSecondary.jpg"; Style = "Fill" }
    )}
}
```

File names resolve against the repository's `Wallpapers/` folder.

---

## System Configuration

### Locale & Language

**Keys:**

- `Locales` - Hashtable keyed by language name → `@{ Code; GeoId }` (e.g. `Croatian = @{ Code = "hr-HR"; GeoId = 108 }`)
- `DisplayLanguages` - Hashtable keyed by language name → language code
- `DefaultLocale` / `DefaultDisplayLanguage` - Select which named entry Bootstrap applies

**Consumer functions:** `Set-Locale`, `Set-DisplayLanguage`

### Keyboard Layouts

**Key:** `KeyboardLayouts` → Hashtable mapping layout name → hex layout code
(e.g. `@{ "Croatian" = "0000041A"; "US" = "00000409" }`); `DefaultKeyboardLayoutSet` selects the set to apply

**Consumer function:** `Set-KeyboardLayouts`

### Power Plans

Per-machine power plan configuration.

**Key:** `PowerPlans.{MachineType}` → Power plan name or GUID

**Consumer function:** `Set-PowerPlan`

**Example:**

```powershell
PowerPlans = @{
    PC     = "High performance"
    Laptop = "Balanced"
}
```

### Power Button Actions

Power button and lid close behavior per machine type.

**Key:** `PowerButtonActions.{MachineType}` → Hash of power button configurations

**Consumer function:** `Set-PowerButtonActions`

### Taskbar Configuration

Pinned app configurations per machine type.

**Key:** `TaskbarConfiguration.{MachineType}` → Array of application names or paths to pin

**Consumer functions:** `Configure-Taskbar`, `Clear-TaskbarPins`, `Unpin-TaskbarApps`

---

## Symbolic Links

Defines symbolic links created by `SymbolicLinkMaker`.

**Key:** `PathTemplates.SymbolicLinks` → Nested hashtable of symlink definitions

**Format:**

```powershell
SymbolicLinks = @{
    PowerToys = @{
        Settings = @{
            Path   = "{AppData}\Microsoft\PowerToys\PowerToys Run\Settings.json"
            Target = "{RepoRoot}\Windows\PowerToys\Settings.json"
        }
    }
    VSCode = @{
        Path   = "{AppData}\Code\User\settings.json"
        Target = "{RepoRoot}\VSCode\settings.json"
    }
}
```

**Path detection:**

- Forward slashes (`/`) in `Target` → Creates WSL symlink
- Backslashes (`\`) in `Target` → Creates Windows symlink

**Consumer function:** `SymbolicLinkMaker`

---

## Git Configuration

**Key:** `GitConfig` → Hashtable of Git settings

**Subkeys:**

- `UserName` - Git commit author name (applied as `git config --global user.name`)
- `UserEmail` - Git commit author email (applied as `git config --global user.email`)
- `WingetPackageId` - The WinGet package id used to install Git

**Consumer function:** `Install-Git`

**Applied during:** Bootstrap with `git config --global` commands

---

## NuGet Configuration

**Key:** `PathTemplates.NuGetConfig` → Source and destination paths

**Consumer function:** `Configure-NuGetConfig`

---

## Bootstrap Configuration

Settings used during the Bootstrap process.

### Package Managers

**Key:** `PackageManagers` → Array of enabled package managers (`"WinGet"`, `"Scoop"`, `"Chocolatey"`)

**Consumer function:** `Bootstrap`

### BootstrapConfig

**Key:** `BootstrapConfig` → Hashtable of bootstrap process settings

**Subkeys:**

- `LogFileLocation` / `LogFilePrefix` - Where the bootstrap log is written (default: Desktop, `BootstrapLog`).
- `DefaultBranch` - Branch that clone/update operations target (default `master`).
- `RepositoryUpdateScope` - Which repositories Bootstrap clones/updates, per machine type
  (`"All"` / `"Private"` / `"Work"` / `"None"`; `Default` covers unlisted types; absent → `"All"`).
- `WSLSetup` - Whether Bootstrap provisions WSL, per machine type (`$true`/`$false`; `Default`
  covers unlisted types; absent → `$true`). The shipped `Test` profile skips WSL.
- `PersonalSteps` - Fork-defined optional bootstrap steps run right after `Upgrade-All`. Each
  entry is either a function name string (runs on every machine type) or a hashtable
  `@{ Function = "Install-MyTool"; Machine = "PC/Laptop" }` gated per machine type exactly like
  the app CSVs' `Machine` column (`All` covers every machine; tokens are validated via
  `Test-MachineTypeScope`, so unknown machine types are reported instead of silently never
  matching). The base ships an empty list, so a vanilla bootstrap runs none; a fork lists its
  personal tools in `Configuration.local.psd1`. Steps that do not resolve are skipped with a
  warning.
- `ExternalScripts` / `LocalScripts` - URLs and vendored script paths used by optional steps
  (Microsoft Activation Scripts, Win11Debloat).
- `PromptForActivation` / `PromptForDebloat` - Whether the optional first-run steps prompt.
- `DataFiles` - Repo-relative paths to the three package CSVs and the Conda environments folder.

**Consumer functions:** `Bootstrap`, `Install-Bootstrap`

### Taskbar Auto-Hide

**Key:** `TaskbarAutoHide` → Boolean; when `$true`, Bootstrap enables taskbar auto-hide for
the current user (`Set-TaskbarAutoHide -Auto`, applied after `Configure-Taskbar`). When
absent or `$false` the taskbar is left untouched - the vanilla default. Purely cosmetic:
FancyZones zone geometry is computed from the monitor work area, so window snapping is
correct with a visible taskbar too. A fork opts in via `Configuration.local.psd1`.

**Consumer function:** `Set-TaskbarAutoHide`

### Visual Effects

**Key:** `VisualEffects` → Hashtable of per-effect booleans; the programmatic equivalent of the
"Custom" profile in System Properties > Performance Options > Visual Effects. Every key mirrors
one dialog checkbox one-to-one: `$true` = effect on (appearance), `$false` = effect off
(performance). Keys left out of the configuration are not touched; when the section is absent or
empty (the shipped default - it is fully commented), Bootstrap changes nothing. A fork opts in
via `Configuration.local.psd1`. Explorer/DWM-backed effects are written to the registry, the
rest through `SystemParametersInfo`; when at least one effect is managed the dialog's radio
button is set to "Custom" (`VisualFXSetting = 3`).

**Valid keys** (the dialog checkboxes in PascalCase): `AnimateControlsAndElementsInsideWindows`,
`AnimateWindowsWhenMinimisingAndMaximising`, `AnimationsInTheTaskbar`, `EnablePeek`,
`FadeOrSlideMenusIntoView`, `FadeOrSlideToolTipsIntoView`, `FadeOutMenuItemsAfterClicking`,
`SaveTaskbarThumbnailPreviews`, `ShowShadowsUnderMousePointer`, `ShowShadowsUnderWindows`,
`ShowThumbnailsInsteadOfIcons`, `ShowTranslucentSelectionRectangle`,
`ShowWindowContentsWhileDragging`, `SlideOpenComboBoxes`, `SmoothEdgesOfScreenFonts`,
`SmoothScrollListBoxes`, `UseDropShadowsForIconLabelsOnTheDesktop`

**Example:**

```powershell
VisualEffects = @{
    SmoothEdgesOfScreenFonts        = $true
    ShowWindowContentsWhileDragging = $true
    AnimationsInTheTaskbar          = $false
    EnablePeek                      = $false
}
```

**Consumer function:** `Set-VisualEffects`

---

## More Sections (quick reference)

Sections not detailed above, with their real shapes and consumers:

| Key | Shape | Purpose | Consumer |
| --- | --- | --- | --- |
| `MachineOverrides` | `@{ <Type> = @{ ... } }` | Machine-specific values merged over the expanded paths after placeholder expansion - only for what cannot be templated (ships empty) | `Expand-ConfigPaths` |
| `NerdFonts` + `DefaultNerdFont` | font name → `@{ FolderName; SearchPattern }` | Repo-bundled fonts installable by name; `DefaultNerdFont` selects the one Bootstrap installs | `Configure-NerdFont` |
| `SpecialFolders` | array of `@{ Path; Name; Value; Description }` registry entries | Special-folder redirections (Downloads/Screenshots → Desktop) | `Set-SpecialFolders` |
| `ExplorerOptions` | array of registry entries (ships fully commented - Win11Debloat covers the defaults) | File Explorer tweaks applied via the registry | `Set-ExplorerOptions` |
| `AutoEnvironmentVariables` | name → path (placeholders allowed) | User environment variables written by `Set-EnvironmentVariables -Auto` | `Set-EnvironmentVariables` |
| `AutoPathAdditions` | array of directories | Directories persisted onto the User `PATH` (e.g. Oh My Posh install locations) | `Set-EnvironmentVariables` |
| `Logging` | `@{ DefaultLevel; Colors; ... }` | Console verbosity at session start (`Quiet`/`Normal`/`Verbose`), per-level console colors, and file-logging settings | Logging module (`Write-Log*`, `Set-LogLevel`) |
| `BrowserGroupMatching` | `@{ BrowserProcessNames; KeywordExtraction; ... }` | Maps browser labels to process names and tunes URL-keyword extraction for detecting already-open browser groups | `Test-BrowserGroupAlreadyOpen`, `Collect-BrowserUrls` |

---

## Wake-on-LAN Configuration

Allows waking machines over LAN via `Send-WakeOnLan`, and checking reachability via `Test-MachineOnline`.

**Keys:**

- `WakeOnLanMachines` - Array of machine names available for WOL. Each name must match a `WakeOnLanConfig` key exactly (quote keys with spaces, e.g. `"Proxmox Backup Server"`).
- `WakeOnLanConfig.{MachineName}` → MAC address, broadcast address, port, and optional `Address`
- `DefaultWakeOnLanMachine` - Default target machine

The optional `Address` (IP or hostname) makes Wake-on-LAN reliable: `Send-WakeOnLan` pings it to skip machines that are already on, and polls it after sending to confirm the machine actually woke up. Omit it (or set `""`) for fire-and-forget behaviour with no ping checks.

**Consumer functions:** `Send-WakeOnLan`, `Test-MachineOnline`

**Example:**

```powershell
WakeOnLanConfig = @{
    Server = @{
        MacAddress                     = "AA-BB-CC-DD-EE-FF"
        SubNetSpecificBroadcastAddress = "192.168.1.255"
        Address                        = "192.168.1.10"  # IP or hostname; "" to disable ping checks
        Port                           = 9
    }
}
```

---

## Repository Groups

Maps Git repository URLs to local paths for `Update-Repositories`, grouped by category.

**Key:** `RepositoryGroups` → Ordered list of repository groups

**Group format:**

```powershell
RepositoryGroups = @(
    @{ Private = @(
            @{
                Name      = "WinuX"                          # Repository name (selection + by-name updates)
                UrlPath   = "Universal.GitHub.Private.WinuX" # Dot-notation path to URL in config
                LocalPath = "Projects.Self.Root"             # Dot-notation path to local directory
            }
        )
    }
)
```

**Consumer functions:** `Update-Repositories`, `Initialize-Repository`

---

## UI & Display Configuration

### Console Colors

Colors used by various output functions.

**Keys:**

- `ListFunctionsColors` - Colors for `List-Functions`
- `ShowFunctionDetailsColors` - Colors for `Show-FunctionDetails`
- `DefaultTranslateLanguages` - Default languages for `Invoke-GoogleTranslate`

### Loading Spinners

Animation styles for long-running operations.

**Keys:**

- `LoadingSpinners` → Array of spinner style definitions
- `DefaultSpinner` → Default spinner style name

**Consumer function:** `Loading-Spinner`

---

## Window Management & FancyZones

### Layout Numbers & Zone Mappings

**Keys:**

- `LayoutNumbers` - Keyboard shortcut mapping to layout indices
- `ZoneNameMappings` → Human-readable zone names to indices

**Consumer functions:** `Apply-FancyZones`, `Get-FancyZone`, `Set-WorkspaceWindowLayout`

### Reset-Windows Defaults

Per-machine defaults for `Reset-Windows`, keyed by machine type (`PC`, `Laptop`, `Work`, `Test`, plus a `Default` fallback). Explicit `-VirtualDesktop` / `-Monitor` parameters override these.

**Key:** `ResetAllWindowsDefaults`

Each entry holds:

- `VirtualDesktop` → 1-based desktop to consolidate all windows onto
- `Monitor` → Target monitor for the move pass - index (`"2"`), label (`"Primary"`/`"Secondary"`), or device name; `""` skips monitor targeting

```powershell
ResetAllWindowsDefaults = @{
    PC      = @{ VirtualDesktop = 1; Monitor = "2" }  # consolidate onto monitor 2
    Laptop  = @{ VirtualDesktop = 1; Monitor = "" }   # single-monitor, no targeting
    Work    = @{ VirtualDesktop = 1; Monitor = "" }
    Test    = @{ VirtualDesktop = 1; Monitor = "" }
    Default = @{ VirtualDesktop = 1; Monitor = "" }
}
```

**Consumer function:** `Reset-Windows`

---

## WSL Configuration

**Key:** `DefaultWSLDistribution` → WSL distro name (default: "Ubuntu")

**Consumer functions:** `Configure-WSL`, `Initialize-WSLEnvironment`, `Test-WSLEnabled`

---

## Customization Guide

### Adding a New Machine

1. Add hostname → machine type mapping in `HostnameToMachineType`
2. Add base paths in `BasePaths`
3. Add machine-specific theme in `Themes`
4. Add wallpaper settings in `WallpaperDarkSettings` / `WallpaperLightSettings`
5. Add taskbar apps (optional) in `TaskbarConfiguration`
6. Create layout files in `Layouts/{MachineType}/` folder

### Adding a New Project

1. Add project path in `PathTemplates.Projects`
2. Add to `Projects` list for `Open-Project` menu
3. Add `ProjectActions` to define what happens when opened
4. (Optional) Add to `VSCodeProjects`, `VisualStudioSolutions`, `ProjectTerminals`, `RunnableProjectMappings`

### Adding a New Browser Group

1. Add group to `BrowserGroups` using one of the four supported formats
2. Ensure URL names are unique across all groups
3. Test with `Open-Browser -Groups "GroupName"`

### Adding a New Symbolic Link

1. Add entry to `PathTemplates.SymbolicLinks`
2. Use `{RepoRoot}` placeholder for source files
3. Use `/` for WSL symlinks, `\` for Windows symlinks
4. Run `SymbolicLinkMaker` to create the links
