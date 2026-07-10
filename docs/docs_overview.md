# Documentation Overview

This file is the **master reference** for maintaining the WinuX documentation. It contains the complete source-of-truth for all modules, functions, aliases, configuration keys, and documentation pages - everything needed to verify accuracy and make updates.

---

## Quick Reference: Repository Structure

```
Windows/
├── WinuX/WinuX.ps1                           # Installer entry point (WinuX.exe source: local clone → Bootstrap, else Install-Bootstrap)
├── PowerShell/
│   ├── Configuration.psd1                     # Central config hub
│   ├── Microsoft.PowerShell_profile.ps1       # Profile
│   └── Modules/
│       ├── Bootstrap/                         # Install-Bootstrap.ps1 + CSV data files
│       ├── Helper/
│       ├── Application/
│       ├── Configuration/
│       ├── Git/
│       ├── Logging/
│       ├── System/
│       ├── Window/                            # WindowNative.cs + Layouts/
│       ├── Workflow/
│       └── Tests/                             # Pester test files
└── docs/                                      # Docsify documentation site
```

---

## Source of Truth: Functions by Module

The authoritative, always-current function reference is the set of per-module pages under `modules/*.md` (parsed by `List-Functions`). Each function is one man-style entry: a `## [FunctionName](github-source-url)` heading followed by a contiguous `- **Key:** value` bullet block (Description first, then Parameters / Usage / Alias). For the complete, current list of functions - with parameters, usage, and aliases - open the relevant module page:

- [Application](modules/application.md) | [Bootstrap](modules/bootstrap.md) | [Configuration](modules/configuration.md) | [Git](modules/git.md) | [Helper](modules/helper.md) | [Logging](modules/logging.md) | [System](modules/system.md) | [Window](modules/window.md) | [Workflow](modules/workflow.md) | [Tests](modules/tests.md)

> Function lists are intentionally NOT duplicated here, to avoid drift. Run `List-Functions` (or `List-Functions -Category <Module>`) for the live in-session view, and `List-Functions -ListDiscrepancies` to confirm the docs match the loaded functions.

---

## Source of Truth: Configuration Keys

### Machine Detection

| Config Key              | Purpose                                | Example                                                                                                  |
| ----------------------- | -------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `ValidMachineTypes`     | Allowed machine type values            | `@("PC", "Laptop", "Work", "Test")`                                                                      |
| `HostnameToMachineType` | Maps hostname → machine type           | `@{ "DESKTOP-GAMING" = "PC"; "LAPTOP-PERSONAL" = "Laptop"; "WORKSTATION-01" = "Work"; "Test" = "Test" }` |
| `DefaultMachineType`    | Fallback if hostname not found         | `"Laptop"`                                                                                               |
| `LaptopChassisTypes`    | WMI chassis types for laptop detection | `@(8, 9, 10, 11, 14, 30, 31, 32)`                                                                        |
| `BasePaths`             | Root directories per machine type      | `@{ PC = @{ Dev = "..."; User = "..." } }`                                                               |

### Placeholders (expanded by `Expand-Hashtable`)

| Placeholder     | Resolves To                                |
| --------------- | ------------------------------------------ |
| `{Dev}`         | `BasePaths.Dev` for current machine        |
| `{User}`        | `BasePaths.User` for current machine       |
| `{MachineType}` | Current machine type string                |
| `{RepoRoot}`    | Resolved WinuX repository root             |
| `{AppData}`     | `$env:APPDATA` (Users\...\AppData\Roaming) |

### Key Config Sections → Consumer Functions

| Config Section                                     | Used By                                            |
| -------------------------------------------------- | -------------------------------------------------- |
| `GitConfig` (WingetPackageId, UserName, UserEmail) | `Install-Git`                                      |
| `HostnameToMachineType`, `ValidMachineTypes`       | `DetermineMachineType`                             |
| `BasePaths`, `PathTemplates`                       | `Expand-ConfigPaths`, all path-dependent functions |
| `SymbolicLinks`                                    | `SymbolicLinkMaker`                                |
| `RepositoryGroups`                                 | `Update-Repositories`, `Initialize-Repository`     |
| `BrowserGroups`                                    | `Open-Browser`, `Collect-BrowserUrls`              |
| `Projects`, `ProjectActions`                       | `Open-Project`                                     |
| `Workspaces`, `WorkspaceActions`                   | `Open-Workspace`                                   |
| `Themes`                                           | `Set-SystemTheme`                                  |
| `WallpaperDarkSettings`, `WallpaperLightSettings`  | `Set-Wallpaper`                                    |
| `TaskbarConfiguration`                             | `Configure-Taskbar`                                |
| `LayoutNumbers`, `ZoneNameMappings`                | `Apply-FancyZones`, `Get-FancyZone`                |
| `AutoEnvironmentVariables`                         | `Set-EnvironmentVariables`                         |
| `Locales`, `DefaultLocale`                         | `Set-Locale`                                       |
| `DisplayLanguages`                                 | `Set-DisplayLanguage`                              |
| `KeyboardLayouts`, `DefaultKeyboardLayoutSet`      | `Set-KeyboardLayouts`                              |

---

## Profile Startup Sequence

The profile (`Microsoft.PowerShell_profile.ps1`) executes this exact sequence:

```
1. Import Configuration.psd1 → $global:Configuration
2. Determine machine type from $env:COMPUTERNAME → HostnameToMachineType (fallback: DefaultMachineType)
3. Build modules path, add to $env:PSModulePath
4. Import-Module Logging → Import-Module Bootstrap
5. Load-PathConfiguration -RepoRoot <path> -Configuration $global:Configuration -Quiet
   ├─ Reuses pre-loaded config (no second file read)
   ├─ Registers Modules/ in PSModulePath for autoload
   ├─ Expands placeholders → $global:MachineSpecificPaths
   └─ Sets $global:MachineType (all other modules deferred to autoload)
6. Oh-My-Posh init (WinuX.omp.json - symlinked to WinuX_{MachineType}.omp.json in the repo)
7. fastfetch
8. PSReadLine (history, predictions, key bindings)
9. Terminal-Icons
10. Register aliases
11. Dot-source System\Functions\Test-PowerPlan.ps1, then call Test-PowerPlan
    (avoids loading the entire System module for one startup check)
```

> **Module autoload:** All WinuX modules declare `FunctionsToExport` in their `.psd1` manifests. PowerShell builds an autoload index at startup (no code executed) and imports a module automatically the first time one of its exported functions is called. `Logging` and `Bootstrap` are imported eagerly by the profile (in that order, so Bootstrap and all other modules can log from the start); `Helper` is the first to autoload (during path-expansion in step 5); the fork-owned `Custom` module autoloads the same way via its `FunctionsToExport` (which the fork maintains, one entry per Custom function; empty on a pure-upstream setup). `Start-Logging`/`Stop-Logging` live in the `Logging` module (moved out of `Helper`).

---

## Bootstrap Execution Flow

`Bootstrap -WithInitialSetup` runs these phases in order:

```
Phase 1 (Initial Setup only):    Rename-Machine → Start-MicrosoftActivationScripts → Start-Win11Debloat (local vendor)
Phase 2 (Repos):                 Update-Repositories -All
Phase 3 (System Config):         Set-CustomExecutionPolicy → Enable-DeveloperMode
                                 → Set-PowerPlan → Set-PowerButtonActions → Set-SystemTheme
                                 → Set-Locale → Set-DisplayLanguage → Set-KeyboardLayouts
                                 → Display-SystemLanguageSettings → Configure-NerdFont
                                 → Install-PowerShellModules → Set-SpecialFolders
                                 → Restart-Explorer → Configure-WSL (config-gated: WSLSetup)
Phase 4 (Packages):              Install-WinGetPackageManager → Install-WinGetApps
                                 → Install-ScoopPackageManager → Install-ScoopApps
                                 → Install-ChocolateyPackageManager → Install-ChocolateyApps → Upgrade-All
Phase 5 (Dev Tools):             PersonalSteps (fork-defined; base runs none) → Install-DotnetEF
Phase 6 (Environment):           Set-EnvironmentVariables -Auto → Create-CondaEnvironments
                                 → Configure-NuGetConfig
Phase 7 (Taskbar):               Configure-Taskbar -FromBootstrap → Set-TaskbarAutoHide -Auto → Set-VisualEffects
Phase 8 (WSL & Symlinks):        Initialize-WSLEnvironment → SymbolicLinkMaker → Configure-WSLSSH (WSL steps config-gated)
Phase 9 (Finalize):              Lock taskbar → Restart-Explorer → Restart-Machine
```

---

## Documentation Site Architecture

### Technology

- **Docsify** - renders markdown on-the-fly (no build step)
- **GitHub Pages** - serves from `/docs` folder
- **Themeable** - light/dark theme toggle
- **Plugins** - search, copy-code, pagination, tabs

### Docsify Features Used

| Feature        | Syntax                                                 |
| -------------- | ------------------------------------------------------ |
| Callout blocks | `> [!NOTE]`, `> [!TIP]`, `> [!WARNING]`, `> [!DANGER]` |
| Tabbed content | `<!-- tabs:start -->` / `<!-- tabs:end -->`            |
| Ignore heading | `<!-- {docsify-ignore} -->`                            |
| Custom anchor  | `:id=custom-anchor`                                    |

### All Documentation Pages

```
docs/
├── index.html                              # Docsify config, theme, splash screen
├── _sidebar.md                             # Navigation menu hierarchy
├── README.md                               # Landing page (root /)
├── docs_overview.md                        # THIS FILE
├── roadmap.md                              # Where WinuX is and where it's headed
│
├── getting-started/
│   ├── prerequisites.md                    # Windows 11, WinGet, admin, hostname
│   ├── installation.md                     # One-liner command, Install-Bootstrap flow
│   ├── first-run.md                        # Bootstrap -WithInitialSetup phases
│   └── subsequent-runs.md                  # Profile init, daily commands, partial runs
│
├── configuration/
│   ├── overview.md                         # Configuration.psd1 structure, sections
│   ├── placeholder-system.md               # {Dev}, {User}, {MachineType}, {RepoRoot}, {AppData}
│   ├── machine-types.md                    # Test + your own types, detection, overrides
│   ├── configuration-reference.md          # Section-by-section key reference
│   ├── repository-structure.md             # What lives where in the repo
│   └── guides/
│       ├── add-new-machine.md              # 7-step guide for new machine type
│       ├── add-new-project.md              # 9-step guide for project config
│       ├── add-new-repository.md           # 3-step guide for Git repos
│       ├── add-new-workspace.md            # 4-step guide for Open-Workspace
│       ├── add-symbolic-link.md            # Symlink config, placeholders, WSL
│       ├── add-browser-group.md            # Browser groups, nesting, search
│       └── configure-window-layout.md      # 3-layer system, zones, visualization
│
├── modules/
│   ├── application.md                      # install, launch, browser
│   ├── bootstrap.md                        # Bootstrap, Load-PathConfiguration, etc.
│   ├── configuration.md                    # programmatic config modifications
│   ├── git.md                              # Git ops, repo management
│   ├── helper.md                           # utilities, prompts, path resolution
│   ├── logging.md                          # Write-Log*, Set-LogLevel, file logging
│   ├── system.md                           # registry, locale, taskbar
│   ├── window.md                           # FancyZones, virtual desktops
│   ├── workflow.md                         # workspaces, projects, terminals
│   └── tests.md                            # Test runner and test organization
│
├── ai/
│   ├── overview.md                         # Layered AI context system, slash commands
│   └── agent-system.md                     # Custom agents, prompts, instructions
│
├── contributing/
│   └── fork-model.md                       # Fork model, merge=ours, config override
│
└── reference/
    ├── software-list.md                    # Packages installed from the CSV files
    ├── troubleshooting.md                  # Common issues and solutions
    └── known-issues.md                     # Known problems and workarounds
```

---

## Verification Checklist

When updating documentation, verify these critical items:

### Config Key Names (common mistakes to avoid)

| ✅ Correct                                                     | ❌ Wrong                                                    |
| -------------------------------------------------------------- | ----------------------------------------------------------- |
| `HostnameToMachineType`                                        | `MachineHostnameMapping`                                    |
| `Install-WingetApps` (function; data file is `WinGetApps.csv`) | `Install-WinGetApps` (the function name uses a lowercase g) |
| `credential.helper manager`                                    | `credential.helper manager-core`                            |
| GitMergeM "merges main INTO current"                           | "merges current into main"                                  |

---

## How to Update Documentation

> **Function docs live in `modules/*.md` and are the single source of truth.** They are parsed by
> `List-Functions` (Helper module). Each function is one man-style entry: a
> `## [FunctionName](<github-source-url>)` heading followed _immediately_ by a contiguous block of
> `- **Key:** value` bullets (Description first, then Parameters, Usage, Alias, …). Optional human-only
> prose, parameter tables, examples, and a `**See also:**` line may follow after a blank line - the parser
> stops collecting fields at the first blank or non-bullet line, so extended prose is safe.

### When a new function is added

1. In the function's module page (`modules/<module>.md`), insert a `## [FunctionName](<github-source-url>)`
   entry in **alphabetical** order.
2. Directly beneath the heading add the bullet block: `- **Description:**` (required), then
   `- **Parameters:**`, `- **Usage:**`, `- **Alias:**` as applicable (omit a bullet entirely when it does
   not apply). Use genericized example values.
3. Optionally add extended prose / a parameter table / examples below a blank line.
4. Run `List-Functions -ListDiscrepancies` - it must report no discrepancies.

### When a function is renamed or removed

1. Update or remove its `## [Name](url)` entry in the module page.
2. Search all `.md` files for the old name and fix references.
3. Run `List-Functions -ListDiscrepancies` to confirm the documentation matches the loaded functions.

### When Configuration.psd1 changes

1. Check `configuration/overview.md` for structural changes
2. Check relevant guide pages for new config keys
3. Update `configuration/placeholder-system.md` if new placeholders
4. Update `configuration/machine-types.md` if new machine types

### When CSV package lists change

1. Update `reference/software-list.md`

---

_Last verified: June 24, 2026_
