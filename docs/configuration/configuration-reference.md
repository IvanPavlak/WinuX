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
- `DefaultBrowser` - Browser used by `Open-Browser` when no browser specified. The base ships it
  empty; `Open-Browser` warns and returns until you set one (any `Browsers` key) in
  `Configuration.local.psd1`.

**Consumer functions:** `Open-Browser`, `Invoke-Browser`, `Open-SecureBrowser`, `Resolve-LayoutTokens` (expands the `Browser` layout token from this map)

**Example (opt-in via `Configuration.local.psd1`):**

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
- `GitHub.Private.*` - Private repositories (dot-notation, e.g., `Private.Dotfiles`)
- `GitHub.MyOrg.*` - Work organization repositories

**Consumer functions:** `Initialize-Repository`, `Update-Repositories`, `Git-Obsidian`

### Application Executables

Paths to installed applications used by `Open-*` functions.

**Keys:**

- `FirefoxExe`, `LeagueOfLegendsExe`, `SteamExe`, `RiseupVpnExe`, `DbeaverExe`, `TeamViewerExe`, `FoundryVTTExe`, `NotepadPlusPlusExe`, `VisualStudio2026Exe`, `VirtualBoxExe`, `DockerExe`

**Consumer functions:** `Open-DBeaver`, `Open-Discord`, `Open-Obsidian`, `Open-Acrobat`, `Open-LeagueOfLegends`, etc.

The base ships the personal executable paths (everything except the framework's own tools) empty;
each `Open-*` consumer warns and no-ops until you set its path in `Configuration.local.psd1`.

### Universal Paths

Common system paths that do not vary by machine.

**Keys:**

- `Desktop` - User's desktop folder (auto-resolved at runtime)
- `Fonts` - Windows Fonts directory
- `TaskbarPinFolder` - Quick Launch taskbar pins folder
- `IconCacheDb`, `IconCacheFolder` - Windows Explorer icon cache
- `OhMyPoshThemeFile` - Oh-My-Posh theme location
- `WhatsAppLocalStoragePath` - WhatsApp cache directory

### Process Cleanup

Process lists consumed by the `Kill-All` desktop cleanup flow.

**Keys:**

- `TerminateProcessNames` - Process names force-terminated by `Terminate-AllProcessesByName`. The base configuration ships a minimal example list (`Code`); keep your real cleanup targets in `Configuration.local.psd1` (the override replaces the array wholesale on merge).
- `VisibleWindowExclusions` - Process names `Terminate-AllProcessesWithVisibleWindows` never force-kills. Browser processes from `Browsers` are excluded automatically. The PowerToys entries are load-bearing (see the warning in the [System module](../modules/system.md#terminate-allprocesseswithvisiblewindows)); never remove them. The list is also what a plain `Open-Workspace` will not take *ownership* of when it claims the screen for [Close-Workspace](../modules/workflow.md#close-workspace) - so the terminal window you typed the open in, Rainmeter, and the rest are never a workspace's to close simply because they happened to be running. A window an open genuinely created is still recorded, whatever its process is called.

Both functions warn and terminate nothing when their list is absent or empty. To toggle whole `Kill-All` steps on/off (not just their process lists), see [Kill-All Step Toggles](#kill-all-step-toggles).

**Consumer functions:** `Terminate-AllProcessesByName`, `Terminate-AllProcessesWithVisibleWindows`

**Example:**

```powershell
TerminateProcessNames   = @(
    "Code"
    "WhatsApp.Root"
)
VisibleWindowExclusions = @(
    "Rainmeter"
    "WindowsTerminal"
    "PowerToys"
)
```

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

### Layout Set Overrides

Which machine type a machine's **window-arrangement** settings are read under: the `Layouts/` subfolder its layouts come from, and the `ResetAllWindowsDefaults` profile `Reset-Windows` applies. These two keys affect those settings only - base paths, symbolic links, wallpapers, themes, and the taskbar always keep using the detected machine type.

**Keys:**

- `LayoutMachineTypeOverrides` - Hashtable mapping a detected machine type → the layout machine type to use instead. A non-empty value redirects layout resolution to `Layouts/<value>/<WorkspaceName>_<value>.psd1`; `""` or an absent entry means no override.
- `SmallDisplayMachineType` - Layout machine type used when the primary display is at most 3000px wide (a laptop-class screen), regardless of the detected type. `""` disables it.

**Example:**

```powershell
# The desktop is temporarily on a different monitor setup: read its layouts from Layouts/Temp/
LayoutMachineTypeOverrides = @{
    PC     = "Temp"
    Laptop = ""
    Work   = ""
    Test   = ""
}

SmallDisplayMachineType = "Laptop"
```

**Consumer function:** `Get-LayoutMachineType`, used by `Set-WorkspaceWindowLayout`, `Reset-Windows`, and `Resolve-DisplayAwareProfile` (which picks the [display-aware window sizing](#display-aware-window-sizing) row)

**Behavior:** `LayoutMachineTypeOverrides` is checked first and wins over `SmallDisplayMachineType`, so an explicit choice is never overruled by display-size detection. The override folder needs its own `<WorkspaceName>_<value>.psd1` file per workspace you open; when one is missing, the "No layout configuration found" warning names the active layout set and the path it expected instead of silently falling back to the machine's own layouts. `ResetAllWindowsDefaults` follows the same resolution, so the profile `Reset-Windows` applies matches the monitor setup actually attached - add an entry for the override name (e.g. `Temp`) or it falls back to `Default`.

**Typical use:** a machine that has to run on a monitor setup its layouts were not authored for. Author the new geometry in its own folder, point the override at it, and clear the entry to switch back - the machine's real layout set is never edited.

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
- `{RepoRoot}` - Dotfiles repository root path (auto-resolved)
- `{AppData}` - User's `AppData\Roaming` folder

**Key:** `PathTemplates` - Nested hashtable of template paths

**Example:**

```powershell
PathTemplates = @{
    ObsidianDirectory                = "{Dev}\Obsidian"
    TrainingBackupDirectory          = "{Dev}\Training_Backup"

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
        "https://github.com/MyUser/Dotfiles",
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

### Default Workspace

Workspace opened when Enter is pressed with no input at the `Open-Workspace` menu.

**Key:** `DefaultWorkspace` → Workspace name (`"Default"` out of the box)

**Consumer function:** `Open-Workspace`

The name must have a `WorkspaceActions` entry - `Open-Workspace` only advertises the default in its prompt (`press [Enter] to open default workspace => Default`) when that entry exists. Set it to `""` to drop the offer: the prompt becomes `press [Enter] to cancel` and Enter exits without opening anything. Only the interactive Enter uses this; a mistyped `Open-Workspace Wrkspce` still exits rather than silently opening the default.

### Workspace Actions

Defines what happens when a workspace opens.

**Key:** `WorkspaceActions.{WorkspaceName}` → Array of action objects

**Format:** Same as `ProjectActions` - array of `@{ Action = "...", Parameters = @{ ... } }` objects

**Special actions:** Same as `ProjectActions` (`Open-ProjectTerminals-Or-RunProject`, `Return`).

**Project context (`{SelectedProjects}`):** A parameter whose FULL value is the literal string `"{SelectedProjects}"` resolves at runtime to the explicit `-Project` argument, otherwise to the projects selected by this workspace's `Open-Project` action; when neither exists the parameter is dropped so the action can no-op or apply its own default. Declare consumers after the `Open-Project` action. The one action that ships using it is `Open-ProjectSwagger`, the opt-in way to open a project's `Swagger` group:

```powershell
@{ Action = "Open-ProjectSwagger"; Parameters = @{ Project = "{SelectedProjects}" } }
```

Swagger is never added on its own - a workspace that does not declare that action runs no Swagger logic at all.

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

Which subfolder is read can be redirected per machine - see [Layout Set Overrides](#layout-set-overrides).

**Consumer function:** `Set-WorkspaceWindowLayout`

---

## System Theme & Wallpaper

### Themes

Per-machine theme configuration (light/dark).

**Key:** `Themes.{MachineType}` → "Light" or "Dark"

**Consumer function:** `Set-SystemTheme`

The base ships `Themes` empty; `Set-SystemTheme -Auto` warns and leaves the theme as-is until you
set it in `Configuration.local.psd1` (there is no Dark fallback).

### Wallpaper Settings

Machine and theme-specific wallpaper configurations.

**Keys:**

- `WallpaperDarkSettings.{MachineType}` → Dark theme wallpaper paths (per monitor)
- `WallpaperLightSettings.{MachineType}` → Light theme wallpaper paths (per monitor)

**Format:** Per-monitor array (order matters for multi-monitor setups)

**Consumer function:** `Set-Wallpaper`, `Set-SystemTheme`

The base ships both sections empty; `Set-Wallpaper` warns and leaves the wallpaper as-is until you
set them in `Configuration.local.psd1`.

The array does not have to match the display count. Monitors are paired with entries by index, and a
monitor past the end of the array **cycles** back to the start - a 2-entry array on 3 displays gives
the third display the first entry - with one warning when the counts differ. Only an empty array
leaves a display on the Windows default.

**Example (opt-in via `Configuration.local.psd1`):**

```powershell
WallpaperDarkSettings = @{
    # Single-monitor machine: one file + style
    Test = @{ File = "Black.jpg"; Style = "Fill" }
    # Multi-monitor machine: one entry per monitor, in monitor order.
    # Fewer entries than monitors is allowed - they cycle.
    PC   = @{ Monitors = @(
        @{ File = "DarkPrimary.jpg"; Style = "Fill" }
        @{ File = "DarkSecondary.jpg"; Style = "Fill" }
    )}
}
```

File names resolve against the repository's `Wallpapers/` folder.

### Set-SystemTheme Step Toggles

Enables/disables the follow-up steps `Set-SystemTheme` runs after writing the theme registry
values. `SystemTheme` is a top-level section (not under `Universal`, and separate from the `Themes`
map above). Each step value is either a plain boolean or a per-machine-type hashtable with a
`Default` fallback (the `BootstrapConfig.Steps.WSL` shape). The whole section and individual keys
are optional - missing entries use the built-in defaults.

**Keys:**

- `SystemTheme.Steps.RefreshBrowserTabs` - `Refresh-BrowserTabs` (default: **off**; only runs when the theme actually changed)
- `SystemTheme.Steps.RestartExplorer` - `Restart-Explorer` (default: on)
- `SystemTheme.Steps.SetWallpaper` - `Set-Wallpaper -Auto -Theme <theme>` (default: on)
- `SystemTheme.Steps.SetLockScreenWallpaper` - `Set-LockScreenWallpaper -Theme <theme>` (default: on)

Everything defaults on except `RefreshBrowserTabs`. Restarting Explorer is what makes the new theme
visible on shell chrome, so it belongs to applying a theme rather than being collateral of it - skip
it and the taskbar and open Explorer windows keep the old theme until Explorer restarts on its own or
you sign out. The wallpaper steps are on because both functions no-op when their configuration
section is empty, so on the empty base config they apply nothing. Reloading every browser tab is the
one action with real collateral - it takes focus per window and hard-reloads pages, discarding
unsaved page state - so it is the only opt-in step.

`RestartExplorer` runs *before* the wallpaper steps and must stay there: restarting Explorer
afterwards can make Windows reload stale wallpaper cache data and revert the desktop image.

Per invocation, `Set-SystemTheme -Skip <steps>` forces steps off and `Set-SystemTheme -Include <steps>`
forces them on, both overriding this config (`-Skip` wins when a step appears in both).

**Consumer functions:** `Set-SystemTheme`, `Resolve-SystemThemeSteps`

**Example:**

```powershell
# Configuration.local.psd1 - hashtables deep-merge per key, so only the steps
# you change need restating:
SystemTheme = @{
    Steps = @{
        RefreshBrowserTabs = $true
    }
}

# Per-machine-type value with Default fallback:
SystemTheme = @{
    Steps = @{
        SetLockScreenWallpaper = @{ Default = $true; Work = $false }
    }
}
```

---

## System Configuration

### Locale & Language

**Keys:**

- `Locales` - Hashtable keyed by language name → `@{ Code; GeoId }` (e.g. `Croatian = @{ Code = "hr-HR"; GeoId = 108 }`)
- `DisplayLanguages` - Hashtable keyed by language name → language code
- `DefaultLocale` / `DefaultDisplayLanguage` - Select which named entry Bootstrap applies

**Consumer functions:** `Set-Locale`, `Set-DisplayLanguage`

The base ships all four empty; both consumers warn and leave the system language settings as-is
until you set them in `Configuration.local.psd1`.

### Keyboard Layouts

**Key:** `KeyboardLayouts` → Hashtable mapping layout name → hex layout code
(e.g. `@{ "Croatian" = "0000041A"; "US" = "00000409" }`); `KeyboardLayoutSets` names layout
combinations and `DefaultKeyboardLayoutSet` selects the set to apply

**Consumer function:** `Set-KeyboardLayouts`

The base ships these empty; `Set-KeyboardLayouts` warns and leaves the layouts as-is until you set
them in `Configuration.local.psd1`.

### Power Plans

Per-machine power plan configuration.

**Key:** `PowerPlans.{MachineType}` → Power plan name or GUID

**Consumer function:** `Set-PowerPlan`

The base ships `PowerPlans` empty; `Set-PowerPlan -Auto` warns and leaves the active plan as-is
until you set it in `Configuration.local.psd1` (there is no Balanced fallback).

**Example (opt-in via `Configuration.local.psd1`):**

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

The base ships `PowerButtonActions` empty; `Set-PowerButtonActions -Auto` warns and leaves the
power settings as-is until you set it in `Configuration.local.psd1` (it no longer applies
hardcoded defaults).

### Taskbar Configuration

Pinned apps, applied by `Configure-Taskbar`. A flat, ordered array (entry order sets pin order);
each row is machine-scoped through its `Machine` field.

**Key:** `TaskbarConfiguration` → Array of `@{ Name; Type; Value; Machine }` rows, where `Type`
is `AUMID` or `Path` and `Machine` is a scope string (`All`, `Test`, `PC/Laptop`, ...) matched
against the current machine type by `Test-MachineTypeScope` - the same gate the app CSVs use. A
row without `Machine` (or a blank one) defaults to `All`, so one list can drive every machine.
Keep your real, machine-tagged list in `Configuration.local.psd1` (it replaces the base array
wholesale on merge). The base ships the section empty; `Configure-Taskbar` warns and leaves the
existing pins as-is until it is set (an empty list never clears your pins).

A `Path` row may additionally carry an `Aumid` key for apps that register their own
AppUserModelID at runtime via `SetCurrentProcessExplicitAppUserModelID` - Eclipse/SWT apps such
as DBeaver, and some Java and Electron apps. The taskbar groups a pin with a running window only
when both carry the same identity: without `Aumid`, such an app's pin is identified by the exe
path while its window is identified by the runtime AUMID, so launching it opens a second,
separate taskbar icon next to the pin. With `Aumid`, `Configure-Taskbar` pins the row through a
shortcut stamped with that identity (via `Set-ShortcutAumid`), and the running window docks onto
the pin:

```powershell
@{ Name = "DBeaver"; Type = "Path"; Value = "{User}\AppData\Local\DBeaver\dbeaver.exe"; Aumid = "DBeaver"; Machine = "All" }
```

**Discovering a runtime AUMID.** `Get-StartApps` only shows the identity a shortcut declares -
for exactly the apps that need this key, that differs from the identity the running process
registers. To read the runtime identity, launch the app, use it once (open a file/connection so
Windows records a jump list), then match its jump-list file name against a candidate identity -
the file name is a CRC64 hash of the uppercased AUMID:

```powershell
# Hash a candidate AUMID (e.g. "DBeaver") and look for a matching jump-list file:
#   $env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations\<hash>.automaticDestinations-ms
# For SWT/Eclipse apps the AUMID is usually the plain product name ("DBeaver").
```

Alternatively, right-click the running app's taskbar icon → Pin to taskbar, then read the
identity the shell recorded on the created pin:

```powershell
$pin = "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\<App>.lnk"
(New-Object -ComObject Shell.Application).Namespace((Split-Path $pin)).ParseName((Split-Path $pin -Leaf)).ExtendedProperty("System.AppUserModel.ID")
```

**Consumer functions:** `Configure-Taskbar`, `Clear-TaskbarPins`, `Unpin-TaskbarApps`

### Kill-All Step Toggles

Enables/disables individual `Kill-All` cleanup steps. `KillAll` is a top-level section (not under `Universal`). Each step value is either a plain boolean or a per-machine-type hashtable with a `Default` fallback (the `BootstrapConfig.Steps.WSL` shape). The whole section and individual keys are optional - missing entries use the built-in defaults (everything on except `ReloadProfile`), so an absent section reproduces the classic full run.

**Keys:**

- `KillAll.Steps.VirtualDesktops` - `Remove-VirtualDesktops` (default: on)
- `KillAll.Steps.Docker` - `DockerWizard -Stop` (default: on)
- `KillAll.Steps.Browsers` - `Terminate-AllBrowserProcesses` (default: on)
- `KillAll.Steps.VisibleWindows` - `Terminate-AllProcessesWithVisibleWindows` (default: on)
- `KillAll.Steps.NamedProcesses` - `Terminate-AllProcessesByName` (default: on)
- `KillAll.Steps.TerminalTabs` - `Terminate-WindowsTerminalTabs` (default: on)
- `KillAll.Steps.CenterTerminal` - `Center-Terminal`, only without `-IncludeCurrent` (default: on)
- `KillAll.Steps.FocusTerminal` - `Focus-TerminalTab`, only without `-IncludeCurrent` (default: on)
- `KillAll.Steps.ReloadProfile` - `Reload-PowerShellProfile` (default: **off**)

Per invocation, `Kill-All -Skip <steps>` forces steps off and `Kill-All -Include <steps>` forces them on, both overriding this config (`-Skip` wins when a step appears in both).

**Consumer functions:** `Kill-All`, `Resolve-KillAllSteps`

**Example:**

```powershell
# Configuration.local.psd1 - hashtables deep-merge per key, so only the steps
# you change need restating:
KillAll = @{
    Steps = @{
        Docker = $false
    }
}

# Per-machine-type value with Default fallback:
KillAll = @{
    Steps = @{
        Docker = @{ Default = $true; Laptop = $false }
    }
}
```

---

## Symbolic Links

Defines symbolic links created by `SymbolicLinkMaker`.

**Key:** `PathTemplates.SymbolicLinks` → Nested hashtable of symlink definitions

The base ships only the framework entries: `PowerShell.Profile` and `PowerShell.Configuration`
(what persists WinuX into every new shell) plus the three PowerToys FancyZones files the window
layouts need. Everything else (Git, FastFetch, Oh My Posh, Windows Terminal, LazyGit, ...) is a
commented example - copy the ones you want into `Configuration.local.psd1`.

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

### PackageManagers

**Key:** `PackageManagers` → Array of opted-in package managers (`"WinGet"`, `"Scoop"`, `"Chocolatey"`)

**Consumer function:** [`Resolve-PackageManagers`](../modules/bootstrap.md#resolve-packagemanagers), and through it [`Bootstrap`](../modules/bootstrap.md#bootstrap) and [`Upgrade-All`](../modules/system.md#upgrade-all)

The opt-in list of package managers WinuX uses. A manager absent from this list is never installed by Bootstrap and never touched by `Upgrade-All`.

Being listed is necessary but not sufficient: `Resolve-PackageManagers` also drops a listed manager whose effective app list has no entries for the current machine type (overlay included), because installing a package manager that then manages nothing is a download, a PATH entry and a shim directory bought for no apps. The list and the CSVs therefore cannot drift into that state - emptying an overlay is enough to stop installing its manager.

The base ships **WinGet alone**: it carries the framework apps (PowerShell, Windows Terminal, PowerToys), while `ScoopApps.csv` and `ChocolateyApps.csv` ship empty. Add a manager in `Configuration.local.psd1` when your overlay gives it apps - arrays replace wholesale on merge, so name every manager you want, not just the additions:

```powershell
PackageManagers = @("WinGet", "Scoop")
```

Anything other than the three valid values is reported as unknown rather than silently ignored.

### BootstrapConfig

**Key:** `BootstrapConfig` → Hashtable of bootstrap process settings

**Subkeys:**

- `LogFileLocation` / `LogFilePrefix` - Where the bootstrap log is written (default: Desktop, `BootstrapLog`).
- `DefaultBranch` - Branch that clone/update operations target (default `master`).
- `RepositoryUpdateScope` - Which repositories Bootstrap clones/updates, per machine type
  (`"All"` / `"Private"` / `"Work"` / `"None"`; `Default` covers unlisted types; absent → `"All"`).
- `Steps` - Per-step toggles for the Bootstrap sequence, resolved by `Resolve-BootstrapSteps`.
  Each step is either a plain boolean or a per-machine-type hashtable with a `Default` fallback
  (e.g. `WSL = @{ Default = $true; Test = $false }`). The whole section and individual keys are
  optional - missing entries use the built-in defaults. Most steps default on because their
  functions no-op when their configuration section is empty; the steps that act the moment they
  run default OFF and are opted into here: `MicrosoftActivationScripts`, `Win11Debloat`,
  `DeveloperMode`, `NuGetConfig` (prompts for a GitHub PAT), `UpgradeAll` (`Upgrade-All` runs
  `winget upgrade --all` and its Scoop/Chocolatey equivalents, so it upgrades every package
  already on the machine, not only the ones WinuX installs - the base spells this one out as
  `$false` rather than leaving it to the default), `CoreAiRules` (machine-global AI
  agent policy applied via `Deploy-CoreAiRules` and the opt-in `SymbolicLinks` entries - see
  [CoreAiRules](../ai/coreairules.md)), `LockedStartLayout`. Per invocation,
  `Bootstrap -Skip <steps>` / `-Include <steps>` override this config. Repository updates are
  governed by `RepositoryUpdateScope` above, not by a step. The full step list in execution
  order is documented next to the section in `Configuration.psd1`. The deprecated `WSLSetup`
  key (same shape as `Steps.WSL`) is still honored when `Steps` carries no `WSL` entry.
- `PersonalSteps` - Fork-defined optional bootstrap steps run right after `Upgrade-All`. Each
  entry is either a function name string (runs on every machine type) or a hashtable
  `@{ Function = "Install-MyTool"; Machine = "PC/Laptop" }` gated per machine type exactly like
  the app CSVs' `Machine` column (`All` covers every machine; tokens are validated via
  `Test-MachineTypeScope`, so unknown machine types are reported instead of silently never
  matching). The base ships an empty list, so a vanilla bootstrap runs none; a fork lists its
  personal tools in `Configuration.local.psd1`. Steps that do not resolve are skipped with a
  warning.
- `ExternalScripts` / `LocalScripts` - URLs and vendored script paths used by optional steps
  (Microsoft Activation Scripts, Win11Debloat). The steps themselves are enabled via
  `Steps.MicrosoftActivationScripts` / `Steps.Win11Debloat` (both off by default).
- `DataFiles` - Repo-relative paths to the three package CSVs and the Conda environments folder.

**Consumer functions:** `Bootstrap`, `Install-Bootstrap`

### Taskbar Settings

**Key:** `TaskbarSettings` → Hashtable of per-control values; the programmatic equivalent of the
Settings > Personalisation > Taskbar page. Every key mirrors one control on that page one-to-one:
the checkboxes and toggles take `$true` / `$false`, the dropdowns take one of the named tokens
listed below (case insensitive, PascalCase of the dropdown label). Keys left out of the
configuration are not touched; when the section is absent or empty (the shipped default - it is
fully commented), Bootstrap changes nothing. A fork opts in via `Configuration.local.psd1`.

The commented lines are not placeholders. They are the taskbar WinuX recommends and its author
runs on every machine - search hidden, task view off, buttons combined, bar auto-hidden - so the
window layouts do the work instead of the shell chrome. Uncomment the lot to get exactly that, or
cherry-pick individual controls.

Every control is a per-user `HKCU` registry value that Explorer only reads on startup, so one
Explorer restart follows when any of them changed. Most are DWords; `AutomaticallyHideTheTaskbar`
is one bit inside Explorer's `StuckRects3` binary blob, rewritten in place so the surrounding
bytes are preserved.

**Valid keys** (the page's controls in PascalCase, in page order):

| Key | Accepted values |
| --- | --- |
| `Search` | `Hide`, `SearchIconOnly`, `SearchBox`, `SearchIconAndLabel` |
| `TaskView` | `$true` / `$false` |
| `Resume` | `$true` / `$false` |
| `EmojiAndMore` | `Never`, `WhileTyping`, `Always` |
| `PenMenu` | `$true` / `$false` |
| `TouchKeyboard` | `Never`, `Always`, `WhenNoKeyboardAttached` |
| `TaskbarAlignment` | `Left`, `Centre` (`Center` also accepted) |
| `AutomaticallyHideTheTaskbar` | `$true` / `$false` |
| `ShowBadgesOnTaskbarApps` | `$true` / `$false` |
| `ShowFlashingOnTaskbarApps` | `$true` / `$false` |
| `ShowTaskbarOnAllDisplays` | `$true` / `$false` |
| `TaskbarAppsOnMultipleDisplays` | `AllTaskbars`, `MainTaskbarAndTaskbarWhereWindowIsOpen`, `TaskbarWhereWindowIsOpen` |
| `ShareAnyWindowFromTaskbar` | `$true` / `$false` |
| `SelectFarCornerToShowDesktop` | `$true` / `$false` |
| `CombineTaskbarButtonsAndHideLabels` | `Always`, `WhenTaskbarIsFull`, `Never` |
| `CombineTaskbarButtonsAndHideLabelsOnOtherTaskbars` | `Always`, `WhenTaskbarIsFull`, `Never` |
| `ShowSmallerTaskbarButtons` | `Always`, `Never`, `WhenTaskbarIsFull` |

**Example:**

```powershell
TaskbarSettings = @{
    Search                             = "Hide"
    TaskView                           = $false
    TaskbarAlignment                   = "Centre"
    AutomaticallyHideTheTaskbar        = $true
    ShowBadgesOnTaskbarApps            = $true
    CombineTaskbarButtonsAndHideLabels = "Always"
}
```

**Consumer function:** `Set-TaskbarSettings`

> [!NOTE]
> This is the taskbar *settings page*. Which apps are **pinned** to the taskbar is a separate
> key, `TaskbarConfiguration`, consumed by `Configure-Taskbar`.

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
| `NerdFonts` + `DefaultNerdFont` | font name → `@{ FolderName; SearchPattern }` | Repo-bundled fonts installable by name; `DefaultNerdFont` selects the one Bootstrap installs (ships empty - `Configure-NerdFont` no-ops until set in `Configuration.local.psd1`) | `Configure-NerdFont` |
| `SpecialFolders` | array of `@{ Path; Name; Value; Description }` registry entries | Special-folder redirections, e.g. Downloads/Screenshots → Desktop (ships empty - `Set-SpecialFolders` no-ops until set in `Configuration.local.psd1`) | `Set-SpecialFolders` |
| `ExplorerOptions` | array of registry entries (ships empty - Win11Debloat covers the defaults) | File Explorer tweaks applied via the registry | `Set-ExplorerOptions` |
| `AutoEnvironmentVariables` | name → path (placeholders allowed) | User environment variables written by `Set-EnvironmentVariables -Auto` (ships empty - no-ops until set in `Configuration.local.psd1`) | `Set-EnvironmentVariables` |
| `AutoPathAdditions` | array of directories | Directories persisted onto the User `PATH`, e.g. Oh My Posh install locations (ships empty - no-ops until set in `Configuration.local.psd1`) | `Set-EnvironmentVariables` |
| `Logging` | `@{ DefaultLevel; Colors; ... }` | Console verbosity at session start (`Quiet`/`Normal`/`Verbose`), per-level console colors, file-logging settings, and automatic idle-time log maintenance | Logging module (`Write-Log*`, `Set-LogLevel`, `Invoke-LogMaintenance`) |
| `BrowserGroupMatching` | `@{ BrowserProcessNames; KeywordExtraction; ... }` | Maps browser labels to process names and tunes URL-keyword extraction for detecting already-open browser groups | `Test-BrowserGroupAlreadyOpen`, `Collect-BrowserUrls` |

---

## Wake-on-LAN Configuration

Allows waking machines over LAN via `Send-WakeOnLan`, and checking reachability via `Test-MachineOnline`.

**Keys:**

- `WakeOnLanMachines` - Array of machine names available for WOL. Each name must match a `WakeOnLanConfig` key exactly (quote keys with spaces, e.g. `"Proxmox Backup Server"`).
- `WakeOnLanConfig.{MachineName}` → MAC address, broadcast address, port, and optional `Address`
- `DefaultWakeOnLanMachine` - Default target machine

The optional `Address` (IP or hostname) makes Wake-on-LAN reliable: `Send-WakeOnLan` pings it to skip machines that are already on, and polls it after sending to confirm the machine actually woke up. Omit it (or set `""`) for fire-and-forget behaviour with no ping checks.

The base ships all three keys empty; `Send-WakeOnLan` and `Test-MachineOnline` warn and no-op until you set them in `Configuration.local.psd1` (no placeholder packet is ever sent).

**Consumer functions:** `Send-WakeOnLan`, `Test-MachineOnline`

**Example (opt-in via `Configuration.local.psd1`):**

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
                Name      = "Dotfiles"                          # Repository name (selection + by-name updates)
                UrlPath   = "Universal.GitHub.Private.Dotfiles" # Dot-notation path to URL in config
                LocalPath = "Projects.Self.Root"                # Dot-notation path to local directory
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

- `LayoutNumbers` - Maps layout names (from `custom-layouts.json`) to `Win+Ctrl+Alt+[Number]` hotkey slots. Layout names are arbitrary; up to 10 layouts, values 0-9, each value unique, and every name must exist in `custom-layouts.json`. Each entry must also stay in sync with `layout-hotkeys.json`: the same-numbered hotkey there must point at that layout's uuid, or `Apply-FancyZones` applies the wrong layout.
- `ZoneNameMappings` → Human-readable zone names to zone indices, per layout. Indices must exist in the layout's `custom-layouts.json` definition (for canvas layouts, a zone's index is its position in the `zones` array); update the mappings in lockstep when adding or reshaping layouts.

`Test-FancyZonesConfiguration` validates all of these constraints (plus `custom-layouts.json` internal consistency) automatically at the start of every workspace open.

**Consumer functions:** `Apply-FancyZones`, `Get-FancyZone`, `Set-WorkspaceWindowLayout`, `Test-FancyZonesConfiguration`

### Reset-Windows Defaults

Per-machine defaults for `Reset-Windows`, keyed by machine type (`PC`, `Laptop`, `Work`, `Test`, plus a `Default` fallback). Explicit `-VirtualDesktop` / `-Monitor` parameters override these.

The key used is the one `Get-LayoutMachineType` resolves, not the raw detected type: a [layout set override](#layout-set-overrides) (or a small primary display) selects the matching reset profile, so a machine on a borrowed monitor setup does not consolidate windows onto a monitor it no longer has. Give the override name its own entry when its setup needs different targeting.

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
    Temp    = @{ VirtualDesktop = 1; Monitor = "" }   # matches a LayoutMachineTypeOverrides value
    Default = @{ VirtualDesktop = 1; Monitor = "" }
}
```

**Consumer function:** `Reset-Windows`

### Display-Aware Window Sizing

Three sections decide how large windows end up. Two of them are **display-aware**: they are hashtables of rows, and the row that applies is resolved in this order.

1. `SmallDisplay` - present **and** the live primary display is at most 3000px wide (laptop-class)
2. The row named after the machine type `Get-LayoutMachineType` resolves, so a [layout set override](#layout-set-overrides) or `SmallDisplayMachineType` steers these sections too
3. `Default`
4. Nothing matched → the function's own built-in value

`SmallDisplay` is checked first because the machine type cannot express it. A laptop reports the machine type `Laptop` both on its own panel and docked to a large external monitor, so a `Laptop` row alone can only be right in one of those two states. `SmallDisplay` is the state-dependent one: it wins while the small panel is primary and disappears the moment a big display takes over. A machine that never uses a laptop-class display simply omits the row - the display is only measured when the row exists.

An invalid value never throws; it falls back to the built-in default, so a typo cannot abort a workspace open mid-loop.

#### `CenterTerminalSizing`

The on-screen pixel size `Center-Terminal` aims the Windows Terminal at. `Center-Terminal` converts it to per-monitor percentages at run time, so **one target already produces the same physical terminal size on every display** - the rows exist to *tune* that target per machine, not to make it uniform.

Each row holds `TargetWidthPx` / `TargetHeightPx` (desired on-screen size) plus `Min*Percent` / `Max*Percent` clamps. The shipped `Default` targets 1376x700 px, which is exactly what the legacy 40% x 50% yields on a 3440x1440 ultrawide.

The **legacy flat shape** - `TargetWidthPx` and friends directly in the section, with no rows - is still accepted and applies to every machine. It is detected first and wins outright, which is what keeps the hybrid case correct: `Configuration.local.psd1` deep-merges over the base, so a flat local override on top of a keyed base leaves both in one hashtable, and the flat keys are the ones the user actually edited.

```powershell
CenterTerminalSizing = @{
    Default      = @{ TargetWidthPx = 1376; TargetHeightPx = 700; MinWidthPercent = 25; MaxWidthPercent = 72; MinHeightPercent = 35; MaxHeightPercent = 75 }
    SmallDisplay = @{ TargetWidthPx = 1152; TargetHeightPx = 624; MinWidthPercent = 25; MaxWidthPercent = 90; MinHeightPercent = 35; MaxHeightPercent = 90 }
}
```

**Consumer functions:** `Center-Terminal` (via `Resolve-CenterTerminalSizing`), `Kill-All`

#### `ResizeWindowsPercent`

The percentage `Resize-Windows` shrinks windows by when it is called **without** an explicit `-Percent` - which is how `Set-WorkspaceWindowLayout`'s first-open normalization and its retry passes call it. An explicit `-Percent` always wins.

Valid range is 10-500; a missing section, an unmatched row, or an invalid value all fall back to the built-in `70`. A laptop panel typically wants a gentler shrink than a wide monitor, since it has far less room to give up - that is the `SmallDisplay` row's job.

```powershell
ResizeWindowsPercent = @{
    Default      = 70
    SmallDisplay = 80   # shrink less on a laptop-class panel
}
```

**Consumer function:** `Resize-Windows` (via `Resolve-ResizeWindowsPercent`)

#### `SnapInsetPercent`

A plain number, not a keyed section. The fraction of a target zone trimmed off **each side** before a window is handed to FancyZones for snapping, so the snap target stays unambiguous.

Valid range is `0.0`-`0.49` (two insets of `0.5` would leave a zero-width window); an invalid or missing value falls back to the built-in `0.05`. This is the single source of truth for all five placement paths - previously the same `0.05` was hardcoded in each of them.

```powershell
SnapInsetPercent = 0.05
```

**Consumer functions:** `Get-WindowInsetPercent`, read by `Resize-Windows`, `Get-InsetWindowBounds`, `Resize-PositionedWindows`, `Set-WindowLayouts`, `Snap-AllWindows`

---

## WSL Configuration

**Key:** `DefaultWSLDistribution` → WSL distro name

**Consumer functions:** `Configure-WSL`, `Initialize-WSLEnvironment`, `Test-WSLEnabled`

The base ships it empty; WSL provisioning (`Configure-WSL`, `Initialize-WSLEnvironment`,
`Configure-WSLSSH`), `Open-WSLTab`, and WSL symlinks all no-op until you set a distribution
(e.g. `"Ubuntu"`) in `Configuration.local.psd1`. All provisioning targets this distribution
explicitly (`wsl -d <distro>`) and `Configure-WSL` pins it as the WSL default on every run -
Docker Desktop and podman machines routinely steal the default distribution, which would
otherwise silently redirect bare `wsl` commands into the wrong distro.

**Key:** `DefaultWSLUsername` → WSL account username (lowercase)

**Consumer function:** `Configure-WSL`

Optional. When set (e.g. `"ivan"` in `Configuration.local.psd1`), `Configure-WSL` creates the
account non-interactively on first installation and makes it the distribution's default user
via `/etc/wsl.conf`; only the sudo password is still prompted - passwords never live in
configuration. The base ships it empty, which falls back to the distribution's interactive
first-launch account wizard. Mixed-case values are lowercased automatically (Linux usernames
are lowercase - note the WSL user routinely differs from the Windows username, e.g. Windows
`Ivan` vs WSL `ivan`).

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
