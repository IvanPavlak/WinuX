# Configuration Reference

**`Configuration.psd1`** is the central hub for the entire WinuX system. It contains all settings, paths, and configurations that control how the PowerShell modules behave.

- **Location:** `Windows/PowerShell/Configuration.psd1`
- **Loaded during:** Bootstrap, profile initialization, manual load via `Load-PathConfiguration`
- **Global variables produced:** `$global:Configuration`, `$global:MachineSpecificPaths`, `$global:MachineType`
- **Placeholder system:** Enables machine-independent configuration via `{Dev}`, `{User}`, `{MachineType}`, `{RepoRoot}`, `{AppData}` tokens

---

## Ordered Sections

Every section whose entries become a menu is an **ordered list**: an array of single-key
hashtables, one per entry, where the key is the entry name and the value is the entry.

```powershell
WorkspaceActions = @(
    @{ Default = @( <actions> ) }
    @{ WinuX   = @( <actions> ) }
)
```

The menu follows the order they are written in, and an entry is defined exactly once - there is no
separate name list to keep in sync with the definitions. A plain hashtable cannot carry the order:
`Import-PowerShellDataFile` returns a `System.Collections.Hashtable`, and key order is lost at load
time, so a hashtable-shaped section renders sorted instead of following the file.
`Test-ConfigurationSchema` reports a section still written as a hashtable.

Sections shaped this way: `BrowserGroups`, `RepositoryGroups`, `ProjectActions`,
`WorkspaceActions`, `CampaignResources`, `AcrobatPdfGroups`, `WakeOnLanConfig`, `Locales`,
`KeyboardLayoutSets` and `NerdFonts`. `RunnableProjectMappings` is an ordered record array (each
record carries its own `Name`) and reads the same way.

Plain hashtables stay plain where order means nothing - a lookup table keyed by machine type
(`Themes`, `PowerPlans`) or by name (`KeyboardLayouts`, `DisplayLanguages`).

Reading one from PowerShell:

```powershell
Get-OrderedNames $global:Configuration.WorkspaceActions            # the names, in menu order
Get-OrderedEntry $global:Configuration.WorkspaceActions "WinuX"    # one entry, by name
```

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
- `FastFetchImageLogo` - **Opt-in.** An image fastfetch renders instead of its text logo, in the
  terminals that can display one (WezTerm, Windows Terminal). Ships `$null`, which keeps the text
  logo everywhere. Takes either a **string** (one image for every machine) or a **hashtable keyed
  by machine type** (each machine its own; a machine with no entry gets none, so adding one never
  turns the feature on for the others). Placeholders expand inside the map as they do in a plain
  string. Also needs the `PathTemplates.SymbolicLinks.PowerShell.AllHostsProfile` link, since that
  is what deploys the profile which applies it. WinuX ships its own logo at
  `Windows\WinuX\WinuXLogoTransparent.png` to point it at. See
  [Get-FastfetchLogoArgument](guides/system/Get-FastfetchLogoArgument.md).

**Consumer functions:** `Get-FastfetchLogoArgument` (`FastFetchImageLogo`), `Initialize-OhMyPosh`,
`Clear-WhatsAppLocalStorage`, `Rebuild-IconCache`

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

**Consumer function:** `Get-LayoutMachineType`, used by `Set-WorkspaceWindowLayout`, `Reset-Windows`, `Resolve-DisplayAwareProfile` (which picks the [display-aware window sizing](#display-aware-window-sizing) row) and `Resolve-WorkspaceActions` (which matches a `LayoutMachine` scope on a [workspace action](#workspace-actions) against the same set, so an action that produces windows for the layout follows the redirect too)

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

**Deprecated:** `PathTemplates.ObsidianStartupScript` - `Open-Obsidian` launched Obsidian through this Python script until 0.1.61 and now starts it detached through WMI (`Start-ObsidianDetached`). The key still parses and is ignored; remove it from your local file at leisure. See [Open-Obsidian](guides/application/Open-Obsidian.md#legacy-startup-script).

---

## Project Management

Defines projects and their associated actions, terminals, and run configurations.

### Project Actions

Every project the `Open-Project` menu offers, and what opening each one does. This is an
[ordered section](#ordered-sections): one single-key hashtable per project, the key being the
project name and the value its action list. The menu follows the order written here, and a project
is defined exactly once - there is no separate project list.

**Key:** `ProjectActions` → Ordered list of `@{ <ProjectName> = @( <actions> ) }`

Each action is executed in order.

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
ProjectActions = @(
    @{ MyProject = @(
            @{ Action = "Open-VSCode"; Parameters = @{ Folder = "MyProject" } }
            @{ Action = "Open-Browser"; Parameters = @{ Groups = @("MyProject-Api") } }
            @{ Action = "Open-ProjectTerminals" }
        )
    }
)
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

Every project the `Run-Project` menu offers, with its run commands and startup configuration.
The menu follows the order written here - this list is the only definition of a runnable project.

**Key:** `RunnableProjectMappings` → Ordered array of run configurations, each carrying its own `Name`

`Commands` is a hashtable keyed by the `ProjectTerminals` path the command runs in, so a command
sits next to the path it belongs to instead of lining up with it by position. A path that is not
named in `Commands` opens its terminal tab with nothing run in it.

**Run command strings:**

- `"dnr"` → `dotnet run`
- `"dnbr"` → `dotnet build && dotnet run`
- `"nir"` → `npm install && npm start`
- `"<custom-string>"` → Executed as-is in terminal

**Consumer function:** `Run-Project` (invoked by `rp` alias)

**Example:**

```powershell
RunnableProjectMappings = @(
    @{
        Name              = "OtherProject"
        Commands          = @{ API = "dnr"; UI = "nir" }   # Keyed by ProjectTerminals path
        DatabaseProviders = @("PostgreSQL")                # Optional - starts Docker Compose via DockerWizard
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

**Key:** `AcrobatPdfGroups` → Ordered list of `@{ <GroupName> = @( <paths> ) }`

An [ordered section](#ordered-sections): the menu offers the groups in the order written here, and
a group is defined exactly once. Paths are dot-notation references into the expanded paths.

**Consumer function:** `Open-Acrobat`

**Example:**

```powershell
AcrobatPdfGroups = @(
    @{ Learning = @("Learning.CSharpInDepth") }
    @{ MyCampaign = @("Dnd.MyCharacter") }
)
```

---

## Obsidian Configuration

How `Open-Obsidian` addresses the vault and which Obsidian workspace a cold start lands on. `Open-Obsidian` drives Obsidian through its official command line interface (Obsidian 1.12.4+, enabled once per machine under Settings > General > Advanced > Command line interface or with `Enable-ObsidianCli`). Inside a workspace open it loads the Obsidian workspace named like the WinuX workspace when the vault has one - the name arrives through the `CurrentWorkspace` parameter `Open-Workspace` injects into every action - and `Parameters = @{ Workspace = "Name" }` on the action overrides that. The vault root itself is `PathTemplates.ObsidianDirectory`.

**Key:** `Obsidian` → Hashtable with two optional string keys (both `""` by default)

- `DefaultWorkspace` - Obsidian workspace to load on a cold start when neither `-Workspace` nor a same-named match resolves. Empty leaves Obsidian where it was (or to plugins such as Homepage). Never applied to an already-running Obsidian.
- `Vault` - Vault name for the CLI. Empty means the leaf folder of `PathTemplates.ObsidianDirectory`.

**Consumer function:** `Open-Obsidian`

**Example:**

```powershell
Obsidian = @{
    DefaultWorkspace = "Empty"   # cold start lands here unless a workspace resolves
    Vault            = ""        # folder name is the vault name
}
```

Deep-merges: set only the key you need in `Configuration.local.psd1`. Persisting `%LOCALAPPDATA%\Programs\obsidian` in `AutoPathAdditions` keeps the `obsidian` command on PATH for every shell; the function also probes that folder directly.

---

## Workspace Management

Defines workspaces and their associated actions.

### Default Workspace

Workspace opened when Enter is pressed with no input at the `Open-Workspace` menu.

**Key:** `DefaultWorkspace` → Workspace name (`"Default"` out of the box)

**Consumer function:** `Open-Workspace`

The name must have a `WorkspaceActions` entry - `Open-Workspace` only advertises the default in its prompt (`press [Enter] to open default workspace => Default`) when that entry exists. Set it to `""` to drop the offer: the prompt becomes `press [Enter] to cancel` and Enter exits without opening anything. Only the interactive Enter uses this; a mistyped `Open-Workspace Wrkspce` still exits rather than silently opening the default.

### Workspace Benchmark

Opt-in measurement of every workspace open. When enabled, `Open-Workspace` times each configured action, reads back the phase clock `Set-WorkspaceWindowLayout` publishes (`Preamble`, `Desktops`, `FancyZones`, `Wait`, `Normalize`, `Position`, `Snap`, `Verify`, `Retry`, `Save`), appends one row per workspace to `WorkspaceBenchmark.csv` next to the session logs through `Write-WorkspaceBenchmark`, and shows the result at the end of the open. Off by default, so a vanilla install prints exactly what it printed before.

**Key:** `WorkspaceBenchmark` → Hashtable

- `Enabled` - `$false` out of the box. `$true` records the row and shows the result after every open.
- `Display` - what the end of an open shows: `"Table"` (the workspace's recent runs, exactly as `Get-WorkspaceBenchmark -Workspace <name> -Formatted` prints them - the default), `"Line"` (one `Timing [Workspace] => ...` line listing the phases above 0.05 s, with `retries N` when the layout needed more than one attempt), or `"None"` (record only).
- `Last` - how many recent runs the `Table` display shows (`10`).
- `Source` - stamped on every row written while it is set (empty in the base and normally left so). `Measure-WorkspaceOpen` sets it to `Measure-WorkspaceOpen <session>` for the duration of an experiment, which is how `Get-WorkspaceBenchmark` tells the experiment's rows from your everyday opens and leaves them out unless asked (`-IncludeMeasured`).

**Consumer function:** `Open-Workspace` (records through `Write-WorkspaceBenchmark`, shows through `Get-WorkspaceBenchmark`)

Hashtables deep-merge, so opting in from `Configuration.local.psd1` needs only the flag; `Display` and `Last` fall through to the base.

**Example (opt-in via `Configuration.local.psd1`):**

```powershell
WorkspaceBenchmark = @{
    Enabled = $true
}
```

The history can be read at any time with `Get-WorkspaceBenchmark` (`-Workspace`, `-Last`, `-Summary`, `-Formatted`), whether or not the automatic display is on. The rows are per-machine measurements and the file is git-ignored. To decide between configuration flags, do not compare rows by hand: `Measure-WorkspaceOpen` runs the interleaved experiment (teardown, settle, open, collect, repeat) on the shipped `Example` workspace or one of yours, forces this key on for its duration (with `Display = "None"` and a `Source` tag), restores it afterwards, and its table can be replayed with `Get-WorkspaceOpenMeasurement`.

### Workspace Actions

Every workspace the `Open-Workspace` menu offers, and what opening each one does. This is an
[ordered section](#ordered-sections): one single-key hashtable per workspace, the key being the
workspace name and the value its action list. The menu follows the order written here, and a
workspace is defined exactly once - there is no separate workspace list.

**Key:** `WorkspaceActions` → Ordered list of `@{ <WorkspaceName> = @( <actions> ) }`

**Format:** Same as `ProjectActions` - array of `@{ Action = "...", Parameters = @{ ... } }` objects

**Special actions:** Same as `ProjectActions` (`Open-ProjectTerminals-Or-RunProject`, `Return`).

**Project context (`{SelectedProjects}`):** A parameter whose FULL value is the literal string `"{SelectedProjects}"` resolves at runtime to the explicit `-Project` argument, otherwise to the projects selected by this workspace's `Open-Project` action; when neither exists the parameter is dropped so the action can no-op or apply its own default. Declare consumers after the `Open-Project` action. The one action that ships using it is `Open-ProjectSwagger`, the opt-in way to open a project's `Swagger` group:

```powershell
@{ Action = "Open-ProjectSwagger"; Parameters = @{ Project = "{SelectedProjects}" } }
```

Swagger is never added on its own - a workspace that does not declare that action runs no Swagger logic at all.

**Workspace context (`CurrentWorkspace`):** Every action that declares a `CurrentWorkspace` parameter receives the name of the workspace being opened; `Get-FilteredParams` drops it from actions that do not, and a configured `Parameters` value of that name wins over the injected one. `Open-Obsidian` uses it to load the Obsidian workspace of the same name when the vault has one, so a bare `@{ Action = "Open-Obsidian" }` under `WorkspaceActions.Server` lands Obsidian on its `Server` workspace with no per-entry configuration; `Parameters = @{ Workspace = "Name" }` overrides that.

**Machine scope and per-machine parameters (`Machine`, `LayoutMachine`, `MachineParameters`, `LayoutMachineParameters`):** An action may say where it runs and what differs per machine, with four optional keys. Every key takes the scope string `Test-MachineTypeScope` understands (`All`, one type, or several separated by `/`) - the same shape as the `TaskbarConfiguration` rows and the app CSVs' `Machine` column. Two axes:

- `Machine`, `MachineParameters` - matched against the **detected** machine type (`$global:MachineType`). Identity-shaped: a Work-only `Open-Outlook`. Tokens must exist in `ValidMachineTypes`.
- `LayoutMachine`, `LayoutMachineParameters` - matched against the **layout set** `Get-LayoutMachineType` resolves ([Layout Set Overrides](#layout-set-overrides): a non-empty `LayoutMachineTypeOverrides` entry, else `SmallDisplayMachineType` on a small display, else the detected type) - the set `Set-WorkspaceWindowLayout` reads the layout file from. Display-shaped: a window count that has to agree with the layout, such as `Open-Browser -Instances 2`. Tokens may also be any non-empty `LayoutMachineTypeOverrides` value or the `SmallDisplayMachineType` (a layout set such as `Temp` is not a machine type).

The two **scopes** decide whether the action runs: an absent or blank key means every machine, an action runs only when both match, the rest of the list runs unchanged, and a workspace whose every action is scoped to another machine is reported and skipped. The two **tables** vary one action that runs everywhere: `@{ "<scope>" = @{ <parameter overrides> } }`. `Parameters` is the default; every row whose scope covers this machine is deep-merged over a copy of it (nested hashtables merge key by key, everything else is replaced) - the `All` row first, then the other matching rows alphabetically, `MachineParameters` before `LayoutMachineParameters` so the layout set wins - and a parameter a row sets to `$null` is removed. The configured entry is never modified. The list is resolved by `Resolve-WorkspaceActions` before anything runs.

A token that is not a known type (or layout set) is reported with the workspace, action and table named and never matches, so a typo cannot silently skip or keep an action or a row.

```powershell
# One Google window everywhere (fullscreen on the Laptop and Work layouts, and on the PC while
# LayoutMachineTypeOverrides redirects it to the Work layouts); two on the PC's own layout set
LeagueOfLegends = @(
    @{ Action = "Open-LeagueOfLegends" }
    @{ Action = "Open-Browser"; Parameters = @{ Groups = @("Google") }; LayoutMachineParameters = @{ PC = @{ Instances = 2 } } }
    @{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = "LeagueOfLegends" } }
)
```

**Example:**

```powershell
WorkspaceActions = @{
    Training = @(
        @{ Action = "Open-Terminal"; Parameters = @{} }
        @{ Action = "Open-VSCode"; Parameters = @{ Folder = "TrainingDirectory" } }
        @{ Action = "Open-Browser"; Parameters = @{ Groups = @("Learning") } }
        @{ Action = "Open-Project"; Parameters = @{ Project = "Client"; RunApp = $true }; MachineParameters = @{ "Laptop/Work" = @{ RunApp = $null; Project = "ClientLite" } } }
        @{ Action = "Open-Outlook"; Machine = "Work" }
    )
}
```

**Consumer functions:** `Open-Workspace`, `Resolve-WorkspaceActions` (the scope filter), `Measure-WorkspaceOpen` (its pre-checks)

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

- `Locales` - [Ordered section](#ordered-sections): `@( @{ Croatian = @{ Code = "hr-HR"; GeoId = 108 } } ... )`, offered in the order written
- `DisplayLanguages` - Hashtable keyed by language name → language code
- `DefaultLocale` / `DefaultDisplayLanguage` - Select which named entry Bootstrap applies

**Consumer functions:** `Set-Locale`, `Set-DisplayLanguage`

The base ships all four empty; both consumers warn and leave the system language settings as-is
until you set them in `Configuration.local.psd1`.

### Keyboard Layouts

**Key:** `KeyboardLayouts` → Hashtable mapping layout name → hex layout code
(e.g. `@{ "Croatian" = "0000041A"; "US" = "00000409" }`); `KeyboardLayoutSets` names layout
combinations as an [ordered section](#ordered-sections)
(`@( @{ "Croatian-US" = @("Croatian", "US") } ... )`, offered in the order written) and
`DefaultKeyboardLayoutSet` selects the set to apply

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
- `RepositoryUpdateScope` - **Which** repository groups Bootstrap clones/updates, per machine type.
  Each value is `"All"` or one or more group names from [`RepositoryGroups`](#repository-groups),
  written as a comma-separated string (`"Work, Private"`) or an array (`@("Work", "Private")`).
  Matched case-insensitively and kept in the order given; `Default` covers unlisted types;
  absent → `"All"`. Resolved by `Resolve-RepositoryUpdateScope`. **Whether** the step runs at
  all is `Steps.RepositoryUpdate` below - this key has no off value.
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
  [CoreAiRules](../ai/coreairules.md)), `AiSkills` (machine-global Agent Skills linked into every
  AI harness via `Deploy-AiSkills` - see [AI Skills](../ai/skills.md)), `ObsidianCli` (`Enable-ObsidianCli -CreateIfMissing`
  writes `"cli": true` into Obsidian's per-machine `%APPDATA%\obsidian\obsidian.json`, which a synced vault never carries,
  so `Open-Obsidian` can load workspaces - see [Enable-ObsidianCli](guides/application/Enable-ObsidianCli.md)),
  `RepositoryUpdate` (clones and pulls every repository the machine's `RepositoryUpdateScope`
  names, which reaches outside this repository the moment it runs - forks that want the previous
  always-on behaviour set it `$true`), `LockedStartLayout`. Per invocation,
  `Bootstrap -Skip <steps>` / `-Include <steps>` override this config. The full step list in execution
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

## AI Skills

**Key:** `AiSkills` → Hashtable: where Agent Skills live and which AI harnesses they are linked into

**Consumer functions:** [`Deploy-AiSkills`](../modules/ai.md#deploy-aiskills), [`Update-AiSkills`](../modules/ai.md#update-aiskills), both through [`Resolve-AiSkillsConfig`](../modules/ai.md#resolve-aiskillsconfig)

**Subkeys:**

- `Root` - The skills root (default `{RepoRoot}\AI\Skills`): one subfolder per source, each holding flat `<skill>\SKILL.md` folders. Vendored upstreams live in `<Root>\<source>\` and are filled by `Update-AiSkills`; hand-written skills go in `<Root>\own\`, which no refresh touches.
- `Harnesses` - The Windows directories `Deploy-AiSkills` links every skill into, one symbolic link per skill (default `{User}\.claude\skills` for Claude Code and `{User}\.agents\skills` for Codex CLI and Gemini CLI). The `{User}` entries also yield the WSL twins under `/home/<DefaultWSLUsername>/`. An array - it replaces wholesale on merge.
- `Sources` - Upstream skill repositories vendored by `Update-AiSkills`, keyed by the folder name under `Root`. Each entry: `Repository` (`owner/name`), `Ref` (branch, tag or commit; default `main`; `UPSTREAM.md` records the exact commit it resolved to), `Folders` (upstream folders whose skill subfolders are flattened; default `skills`), `Exclude` (skill names to leave out - a personal skill replaces a Claude Code built-in of the same name, so `code-review` is the usual candidate). Ships empty.

Only `{RepoRoot}`, `{User}` and `{AppData}` are expanded in this section - it is machine-type independent and does not go through `PathTemplates`. Deployment is opt-in via `BootstrapConfig.Steps.AiSkills`. Design: [AI Skills](../ai/skills.md).

```powershell
AiSkills = @{
    Root      = "{RepoRoot}\AI\Skills"
    Harnesses = @("{User}\.claude\skills", "{User}\.agents\skills")
    Sources   = @{
        mattpocock = @{
            Repository = "mattpocock/skills"
            Ref        = "main"
            Folders    = @("skills/engineering", "skills/productivity")
            Exclude    = @()
        }
    }
}
```

---

## Backups

Retention limits for the unified backup sink at `<Repo>\Backups\Windows` (gitignored), where every WinuX writer keeps a timestamped copy of whatever it replaces - files displaced by symlinks, rewritten configuration files, overwritten system files. See [Backups](../reference/backups.md) for the full policy.

**Keys:**

- `Backups.Retention.MaxAgeDays` - Delete backups older than this many days. Ships `0` (never) - replaced originals are precious, unlike logs.
- `Backups.Retention.MaxBackupsPerKey` - Keep at most this many timestamped backups per key, newest retained. Ships `10`; also enforced opportunistically after every backup.
- `Backups.Retention.MaxTotalSizeMB` - Cap the whole sink's combined size, oldest removed first. Ships `500`.

A limit set to `0` is disabled. Whatever the limits, **the newest backup of every key is never deleted**. Enforced by `Clear-OldBackups`, which the idle-time maintenance sweep (`Invoke-LogMaintenance`) runs automatically.

---

## More Sections (quick reference)

Sections not detailed above, with their real shapes and consumers:

| Key | Shape | Purpose | Consumer |
| --- | --- | --- | --- |
| `MachineOverrides` | `@{ <Type> = @{ ... } }` | Machine-specific values merged over the expanded paths after placeholder expansion - only for what cannot be templated (ships empty) | `Expand-ConfigPaths` |
| `NerdFonts` + `DefaultNerdFont` | [ordered section](#ordered-sections): `@( @{ <FontName> = @{ FolderName; SearchPattern } } ... )` | Repo-bundled fonts installable by name; `DefaultNerdFont` selects the one Bootstrap installs (ships empty - `Configure-NerdFont` no-ops until set in `Configuration.local.psd1`) | `Configure-NerdFont` |
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

- `WakeOnLanConfig` → Ordered list of `@{ <MachineName> = @{ MacAddress; SubNetSpecificBroadcastAddress; Port; Address } }`. An [ordered section](#ordered-sections): the menu offers the machines in the order written here (quote a name with spaces, e.g. `"Proxmox Backup Server"`). `Send-WakeOnLan` appends its own `All` and `None` options - they are not machines and are never configured.
- `DefaultWakeOnLanMachine` - Default target machine

The optional `Address` (IP or hostname) makes Wake-on-LAN reliable: `Send-WakeOnLan` pings it to skip machines that are already on, and polls it after sending to confirm the machine actually woke up. Omit it (or set `""`) for fire-and-forget behaviour with no ping checks.

The base ships both keys empty; `Send-WakeOnLan` and `Test-MachineOnline` warn and no-op until you set them in `Configuration.local.psd1` (no placeholder packet is ever sent).

**Consumer functions:** `Send-WakeOnLan`, `Test-MachineOnline`

**Example (opt-in via `Configuration.local.psd1`):**

```powershell
WakeOnLanConfig = @(
    @{ Server = @{
            MacAddress                     = "AA-BB-CC-DD-EE-FF"
            SubNetSpecificBroadcastAddress = "192.168.1.255"
            Address                        = "192.168.1.10"  # IP or hostname; "" to disable ping checks
            Port                           = 9
        }
    }
)
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

**Group names are freely configurable and never known to code.** Add, rename or remove groups as you like: `Update-Repositories -Group <name>[, <name>]` takes whatever keys you define (matched case-insensitively), `-All` and the interactive menu follow the whole list, and an unknown name is reported with the configured ones rather than guessed at. Repositories are walked in the order the configuration lists them - inside a group and across several requested groups - and a repository listed in more than one selected group is updated only once.

**Consumer functions:** `Resolve-RepositoryTargets` (expands a selection), `Update-Repositories`, `Initialize-Repository`, `Resolve-ProjectPath -ForRepository` (resolves one entry)

---

## PSReadLine (Interactive Shell Options)

Every editing, history and prediction option the profile applies to PSReadLine on shell start, in one section. Applied by `Initialize-PSReadLine` (System module), which the profile calls after `Import-Module PSReadLine` and **before** `Initialize-OhMyPosh` - `EditMode` installs a whole key map, and applying it after a theme has bound `Enter` for its transient prompt would reset that binding.

Every key is optional. `$null` (or a missing key) means "do not touch it": `Initialize-PSReadLine` makes no call for that key and PSReadLine keeps its own default. The base ships the behaviour the profile always hardcoded and leaves the history limits alone.

**Keys:**

- `EditMode` - `Windows`, `Emacs` or `Vi`. Ships `Windows`. Always applied first.
- `KeyHandlers` - `@{ <Key> = "<PSReadLine function>" }`, one `Set-PSReadLineKeyHandler` per entry. Ships `UpArrow = "HistorySearchBackward"` and `DownArrow = "HistorySearchForward"` (prefix search instead of plain history walk). Merges per key: add a binding by adding a key; drop a base binding by setting that key to `$null`.
- `MaximumHistoryCount` - **Opt-in.** Positive integer. Sets **both** PSReadLine's recall cap (arrow keys, `Ctrl+R`) and the session `$MaximumHistoryCount` (`Get-History`, `Invoke-History`); the latter is clamped to PowerShell's 32767 ceiling, so 32767 makes the two agree exactly. Ships `$null` (PSReadLine's own 4096). Anything that is not a positive integer is reported with a warning at shell start and both limits are left alone. PSReadLine never trims its history file - it appends every command and loads the newest `MaximumHistoryCount` lines at startup - so this is what is recallable, not what is stored.
- `HistorySavePath` - **Opt-in.** Where PSReadLine writes its history file. `%ENV%` variables are expanded. Ships `$null` (PSReadLine's `%APPDATA%\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt`).
- `HistoryNoDuplicates` - `$true`/`$false`. Ships `$true`. Hides repeated commands during recall and search (each distinct line shown once, at its most recent position); every invocation is still written to the file.
- `PredictionSource` - `None`, `History`, `Plugin` or `HistoryAndPlugin`. Ships `History`.
- `PredictionViewStyle` - `InlineView` or `ListView`. Ships `ListView`.

The two prediction keys are applied last and inside a `try`/`catch`: they are the only calls that throw on a console without virtual-terminal support (redirected output, CI, automation hosts), and everything above them has already applied when they do.

**Consumer function:** `Initialize-PSReadLine`

**Example:**

```powershell
# Configuration.local.psd1 - raise both recall limits, keep everything else
PSReadLine = @{
    MaximumHistoryCount = 32767
}
```

See [Initialize-PSReadLine](guides/system/Initialize-PSReadLine.md).

---

## Fastfetch Auto-Fit (the `c` alias)

How `Invoke-ClearAndFastfetch` (alias `c`, System module) fits the fastfetch panel into the Windows Terminal window. The function resets the font to the profile default, then presses `Ctrl+Minus` one step at a time - waiting for the terminal to reflow after each - until the panel fits, `MaxShrinkSteps` steps have been taken, or the terminal stops shrinking (its minimum font). Nothing in this section is per machine: the fit is measured against the live window on every call, so a small laptop display or a high DPI scale needs no value of its own. The image logo follows the font on its own, because `Get-FastfetchLogoArgument` re-reads the cell size at display time.

Resolved by `Resolve-FastfetchAutoFitSettings`, per key: an explicit parameter on the `Invoke-ClearAndFastfetch` call beats the configured value, which beats the built-in default. A value outside its range, or not an integer, is reported with a warning at the prompt and the built-in default is used for that key; `$null` (or a missing key) means "use the default" silently. The base ships the built-in defaults, so a vanilla install and a missing section behave identically.

**Keys:**

- `MaxShrinkSteps` - Integer, 0-50. `Ctrl+Minus` steps allowed below the default font. Ships `10`. `0` resets the font to the default and never shrinks, which shows whether the panel fits at all at the default size.
- `ReflowTimeoutMilliseconds` - Any positive integer, no upper bound. How long `Wait-ConsoleReflow` polls the window size after a keystroke before assuming the terminal is not going to change. Ships `10`. This is the knob to tweak and test per terminal and machine: too short and a shrink step reads the old size before the terminal has reflowed, so the loop stops early with `cannot shrink further` in the verbose log; too long and every `c` waits the full value once, because the reset when the font is already at the default changes nothing. Every shrink step that does reflow returns as soon as the change is seen.
- `PromptReserve` - Integer, 0-20. Rows kept free below the panel for the upcoming prompt when judging vertical overflow (one further row is always kept for the line the cursor ends on). Ships `1`.

**Consumer functions:** `Invoke-ClearAndFastfetch`, `Resolve-FastfetchAutoFitSettings`

**Example:**

```powershell
# Configuration.local.psd1 - allow at most three steps and give the prompt two rows
FastfetchAutoFit = @{
    MaxShrinkSteps = 3
    PromptReserve  = 2
}
```

See [Invoke-ClearAndFastfetch](guides/system/Invoke-ClearAndFastfetch.md) and [Resolve-FastfetchAutoFitSettings](guides/system/Resolve-FastfetchAutoFitSettings.md).

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
- `FancyZonesApplyMethod` - How `Apply-FancyZones` puts a workspace's zone layouts onto its virtual desktops. `"File"` (the shipped default) writes the entries for every desktop into FancyZones' `applied-layouts.json`, lets FancyZones reload the file and proves the reload with one probe shortcut on the current desktop, so no desktop is switched to; any desktop that does not verify falls back to the shortcut pass automatically. `"Hotkeys"` is the previous behaviour: switch to every desktop and send `Win+Ctrl+Alt+[Number]` there. Set it in `Configuration.local.psd1` when a PowerToys update changes the file format or the file watcher; anything other than these two values is treated as `"File"` with a note in the verbose log.
- `WorkspaceLayoutPipelining` - Whether `Set-WorkspaceWindowLayout` positions and snaps each virtual desktop as soon as every window on it is stable, while the slower windows on other desktops are still loading (`$true`, the shipped default), or waits for the slowest window of the whole workspace and does all of it afterwards (`$false`). Verification stays global and the in-process retries run the full layout either way; the flag exists to compare the two orders with `Get-WorkspaceBenchmark` and as an escape hatch.
- `WorkspaceLayoutPrepareEarly` - Whether `Open-Workspace` runs the layout preamble - the RPC probe, the layout file and its validation, the virtual desktop resize and the FancyZones zone layouts (`Set-WorkspaceWindowLayout -PrepareOnly`) - BEFORE the launch actions (`$true`, the shipped default) or leaves all of it to the layout action after them (`$false`). That work depends on no window and ran at 3.4 s under the start-up load of a dozen applications against 0.2 s idle; the layout action then finds the desktops and zone layouts in place and skips them. A window-only retry is never prepared, and a failed preparation leaves the action to do the work as before.

`Test-FancyZonesConfiguration` validates all of these constraints (plus `custom-layouts.json` internal consistency) automatically at the start of every workspace open.

Whether any of the three flags actually makes a workspace open faster on a given machine is a question for `Measure-WorkspaceOpen`, which opens the workspace under each value in interleaved rounds and compares medians, not for two opens compared by eye - the spread between two opens of the same configuration is larger than any flag's effect.

**Consumer functions:** `Apply-FancyZones`, `Get-FancyZone`, `Open-Workspace`, `Set-WorkspaceWindowLayout`, `Test-FancyZonesConfiguration`

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
2. Add a `ProjectActions` entry - it defines what opening does AND puts the project in the `Open-Project` menu
3. (Optional) Add to `VSCodeProjects`, `VisualStudioSolutions`, `ProjectTerminals`, `RunnableProjectMappings`

### Adding a New Browser Group

1. Add group to `BrowserGroups` using one of the four supported formats
2. Ensure URL names are unique across all groups
3. Test with `Open-Browser -Groups "GroupName"`

### Adding a New Symbolic Link

1. Add entry to `PathTemplates.SymbolicLinks`
2. Use `{RepoRoot}` placeholder for source files
3. Use `/` for WSL symlinks, `\` for Windows symlinks
4. Run `SymbolicLinkMaker` to create the links
