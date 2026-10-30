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
│       ├── AI/                                # AI artifacts (skills, mods, rules, prompts, agents) + marketplaces
│       ├── Bootstrap/                         # Install-Bootstrap.ps1 + CSV data files
│       ├── Helper/
│       ├── Application/
│       ├── Configuration/
│       ├── Git/
│       ├── Logging/
│       ├── System/
│       ├── Window/                            # WindowNative.cs (cached as an assembly by Import-NativeAssembly.ps1) + WindowModuleState.ps1 + Layouts/
│       ├── Workflow/                          # + State/ (what each workspace open produced)
│       └── Tests/                             # Pester test files + Invoke-TestSuite.ps1 harness and its helper scripts
└── docs/                                      # Docsify documentation site
```

---

## Source of Truth: Functions by Module

The authoritative, always-current function reference is the set of per-module pages under `modules/*.md` (parsed by `List-Functions`). Each function is one man-style entry: a `## [FunctionName](github-source-url)` heading followed by a contiguous `- **Key:** value` bullet block (Description first, then Parameters / Usage / Alias). For the complete, current list of functions - with parameters, usage, and aliases - open the relevant module page:

- [AI](modules/ai.md) | [Application](modules/application.md) | [Bootstrap](modules/bootstrap.md) | [Configuration](modules/configuration.md) | [Git](modules/git.md) | [Helper](modules/helper.md) | [Logging](modules/logging.md) | [System](modules/system.md) | [Window](modules/window.md) | [Workflow](modules/workflow.md) | [Tests](modules/tests.md)

> Function lists are intentionally NOT duplicated here, to avoid drift. Run `List-Functions` (or `List-Functions -Category <Module>`) for the live in-session view, and `List-Functions -ListDiscrepancies` to confirm the docs match the loaded functions.

---

## Source of Truth: Configuration Keys

### Machine Detection

| Config Key              | Purpose                                | Example                                                                                                  |
| ----------------------- | -------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `ValidMachineTypes`     | Allowed machine type values            | `@("PC", "Laptop", "Work", "Test")`                                                                      |
| `HostnameToMachineType` | Maps hostname → machine type           | `@{ "DESKTOP-GAMING" = "PC"; "LAPTOP-PERSONAL" = "Laptop"; "WORKSTATION-01" = "Work"; "Test" = "Test" }` |
| `DefaultMachineType`    | Fallback if hostname not found         | `"Test"` (the shipped value)                                                                             |
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

The curated table below is the quick map. The exhaustive per-function version lives under
`configuration/guides/<module>/` - one page per exported function, listing the keys it reads, the
decisions behind them, and where the values go. Each module's `README.md` indexes its own functions;
[`winux-configurator.md`](configuration/winux-configurator.md) walks all of them with you.

| Config Section                                     | Used By                                            |
| -------------------------------------------------- | -------------------------------------------------- |
| `GitConfig` (WingetPackageId, UserName, UserEmail) | `Install-Git`                                      |
| `GitStatusArguments`                               | `GitStatus`                                        |
| `HostnameToMachineType`, `ValidMachineTypes`       | `DetermineMachineType`, `Test-MachineTypeScope`    |
| `BasePaths`, `PathTemplates`                       | `Expand-ConfigPaths`, all path-dependent functions |
| `PathTemplates.SymbolicLinks`                      | `SymbolicLinkMaker`                                |
| `RepositoryGroups`                                 | `Update-Repositories`, `Resolve-RepositoryTargets` |
| `PathTemplates.ObsidianDirectory`                  | `Open-Obsidian`, `Git-Obsidian`                    |
| `Obsidian` (DefaultWorkspace, Vault, GitEndLocation) | `Open-Obsidian`, `Git-Obsidian` (`GitEndLocation`) |
| `Logging`                                          | `Initialize-LoggingState`                          |
| `Logging.Maintenance`                              | `Invoke-LogMaintenance`                            |
| `Logging.FileLogging.Retention`                    | `Clear-OldLogs`                                    |
| `RepositoryUpdate`                                 | `Update-Repositories`, `Resolve-RepositoryDefaultBranch`, `Get-RepositoryUpdateStartupSettings`, `Invoke-StartupRepositoryUpdate` |
| `BrowserGroups`                                    | `Open-Browser`, `Test-BrowserGroupAlreadyOpen`, `Resolve-SwaggerBrowserGroup`, `Get-SwaggerCloseTitlePatterns` |
| `PathTemplates.Projects`, `ProjectActions`         | `Open-Project` (`ProjectActions` also by `Close-Project`, `Open-Workspace`, `Resolve-WorkspaceActions`, `Merge-LayoutProjectOverrides`) |
| `DefaultWorkspace`, `WorkspaceActions`, `WorkspaceBenchmark` | `Open-Workspace`                         |
| `WorkspaceActions` entry scopes (`Machine`, `LayoutMachine`, `Project`) and tables (`MachineParameters`, `LayoutMachineParameters`, `ProjectParameters`) | `Resolve-WorkspaceActions` (for `Open-Workspace`, `Measure-WorkspaceOpen`) |
| `WorkspaceTemplates`, templated `WorkspaceActions` entries, `{Workspace}` | `Resolve-WorkspaceTemplate` (expanded at load by `Expand-WorkspaceTemplates`, again by `Open-Workspace` for command-line variables), `Test-ConfigurationSchema`, `Add-Workspace -Template` |
| Layout file `ProjectOverrides` (checked against `ProjectActions`, `ZoneNameMappings`) | `Merge-LayoutProjectOverrides` (for `Set-WorkspaceWindowLayout -Project`, `Validate-Layout`, `Visualize-Layouts`) |
| `Themes`                                           | `Set-SystemTheme`                                  |
| `SystemTheme.Steps`                                | `Set-SystemTheme`, `Resolve-SystemThemeSteps`      |
| `WallpaperDarkSettings`, `WallpaperLightSettings`, `WallpaperStyles` | `Set-Wallpaper`, `Set-LockScreenWallpaper`       |
| `TaskbarConfiguration`                             | `Configure-Taskbar`                                |
| `TaskbarSettings`                                  | `Set-TaskbarSettings`                              |
| `VisualEffects`                                    | `Set-VisualEffects`                                |
| `NpmRegistries`, `PathTemplates.NpmConfig`         | `Configure-NpmConfig`                              |
| `LayoutNumbers`, `ZoneNameMappings`, `FancyZonesApplyMethod` | `Apply-FancyZones`, `Get-FancyZone`, `Test-FancyZonesConfiguration`, `Visualize-Layouts` (`LayoutNumbers`, `ZoneNameMappings`), `Generate-LayoutVisualization`, `Update-LayoutSectionHeaders`, `Merge-LayoutProjectOverrides` (`ZoneNameMappings`) |
| `WorkspaceLayoutPipelining`, `SimpleLayoutWorkspaces` | `Set-WorkspaceWindowLayout` (`SimpleLayoutWorkspaces` is written by `Add-WindowLayout -Simple`) |
| `WorkspaceLayoutPrepareEarly`                      | `Open-Workspace`                                   |
| `LayoutMachineTypeOverrides`, `SmallDisplayMachineType` | `Get-LayoutMachineType` (for `Set-WorkspaceWindowLayout`, `Reset-Windows`, `Resolve-DisplayAwareProfile`, `Resolve-WorkspaceActions`) |
| `ResetAllWindowsDefaults`                          | `Reset-Windows`                                    |
| `CenterTerminalSizing`                             | `Center-Terminal` (via `Resolve-CenterTerminalSizing`) |
| `ResizeWindowsPercent`                             | `Resize-Windows` (via `Resolve-ResizeWindowsPercent`) |
| `SnapInsetPercent`                                 | `Get-WindowInsetPercent` (for the five pre-snap placement paths) |
| `TerminalGreeting`                                 | `Show-TerminalGreeting` (alias `c`, and shell startup), `Invoke-Clear`, `Invoke-Fastfetch`, `Invoke-Onefetch`, `Format-OnefetchPanel` (via `Resolve-TerminalGreetingSettings`); `Onefetch.InProjectTerminals` also drives `Open-ProjectTerminals` |
| `KillAll.Steps`                                    | `Kill-All`, `Resolve-KillAllSteps`                 |
| `BootstrapConfig.Steps`                            | `Bootstrap`, `Resolve-BootstrapSteps` (incl. the opt-in `AiArtifacts` step → `Deploy-AiArtifacts`, the `AiMarketplaces` step → `Deploy-AiMarketplaces`, and the `AiMcpServers` step → `Deploy-AiMcpServers`) |
| `AiArtifacts`, `AiHarnesses`                       | `Deploy-AiArtifacts`, `Update-AiArtifacts`, `List-AiArtifacts`, `Get-AiArtifactPlan`, `Get-AiArtifactRoster` (via `Resolve-AiArtifactsConfig`); the `claude-plugin-dirs` hook of `Deploy-AiArtifacts` writes `env.CLAUDE_CODE_PLUGIN_DIRS` of `~\.claude\settings.json` through `Resolve-AiModsPluginDirs` and `Set-ClaudeSettingsEnv`, and checks the CLI with `Test-AiModsCli` |
| `AiMarketplaces`                                   | `Deploy-AiMarketplaces`; writes `extraKnownMarketplaces` and `pluginConfigs` of `~\.claude\settings.json` through `Set-ClaudeSettingsKey` and each marketplace's `Env` variables into its `env` block through `Set-ClaudeSettingsEnv`, then adds the marketplaces and installs the plugins through the Claude Code CLI |
| `AiMcpServers`                                     | `Deploy-AiMcpServers`; adds the servers to Claude Code through `claude mcp add --scope user` (reading `mcpServers` of `~\.claude.json`) and writes their `[mcp_servers.<name>]` tables into Codex's `config.toml`; `Machine` scopes go through `Test-MachineTypeScope` |
| `AutoEnvironmentVariables`, `AutoPathAdditions`, `BasePaths` | `Set-EnvironmentVariables`                   |
| `Locales`, `DefaultLocale`                         | `Set-Locale`                                       |
| `DisplayLanguages`, `DefaultDisplayLanguage`       | `Set-DisplayLanguage`                              |
| `KeyboardLayouts`, `KeyboardLayoutSets`, `DefaultKeyboardLayoutSet` | `Set-KeyboardLayouts`                 |
| `AutoElevate`                                      | `Test-AdminPrivileges`                             |

---

## Profile Startup Sequence

The profile (`Microsoft.PowerShell_profile.ps1`) executes this exact sequence. Every numbered step from 4 on is a **startup stage**, wrapped in `if (Test-StartupStage -Name "<Stage>") { ...; Complete-StartupStage }` (Helper module), so it is timed on every start (`$WinuXStartupTimings`) and can be left out of one start through `WINUX_STARTUP_SKIP`; `Measure-ShellStartup` (System module) drives the stages to build the strip-then-add-one-at-a-time table (see [Slow Profile Load](reference/troubleshooting.md#slow-profile-load)).

```
1. Locate Configuration.psd1, resolve the repo from its real path (Get-RepositoryPath), add Modules/ to $env:PSModulePath
2. Dot-source Helper\Functions\{Test-StartupStage, Complete-StartupStage, Get-ConfigSetting, Test-ConfigValue, Resolve-WorkspaceTemplate, Expand-WorkspaceTemplates, Restore-ShellPrompt}.ps1
   (the only Helper functions used before the prompt - dot-sourced so the 80+-file Helper module is NOT autoloaded at startup;
   the two workspace-template functions run inside Load-PathConfiguration's template expansion, and Restore-ShellPrompt lets
   the deferred work below draw the prompt again without importing Helper from idle time)
3. Stage Core (Required - always runs, always timed)
   ├─ Import Configuration.psd1 → $global:Configuration
   ├─ Import-Module Logging → Import-Module Bootstrap
   └─ Load-PathConfiguration -RepoRoot <path> -Configuration $global:Configuration -Quiet
      ├─ Merges Configuration.local.psd1, reuses the pre-loaded base config (no second file read)
      ├─ Registers Modules/ (and Modules/Custom) in PSModulePath for autoload
      ├─ Expands placeholders → $global:MachineSpecificPaths
      └─ Sets $global:MachineType (all other modules deferred to autoload)
4. Stage Schema - dot-source Configuration\Functions\{Test-ConfigurationKeyPath, Test-ConfigurationSchema}.ps1, then Test-ConfigurationSchema (warning-only)
5. Stage Greeting - dot-source the System greeting files (orchestrator, three steps, settings resolver, onefetch restyler,
   and the three image-logo functions the all-hosts fastfetch wrapper calls) + Git\Functions\Test-GitRepository.ps1, then Show-TerminalGreeting -NoResize
6. Stage PSReadLine - Import-Module PSReadLine (console host only)
7. Stage Terminal-Icons - QUEUED for after the first prompt (see step 12)
8. Stage PSReadLineOptions - Initialize-PSReadLine (edit mode, key handlers, history, predictions from Configuration.PSReadLine)
9. Stage OhMyPosh - . Initialize-OhMyPosh (must stay AFTER PSReadLine: a transient-prompt theme binds Enter, and -EditMode would reset it)
10. Stage Aliases - register aliases
11. Stage PowerPlan - dot-source System\Functions\{Get-ChassisType, Test-PowerPlan}.ps1, then Test-PowerPlan (chassis type from a per-machine cache)
12. Stage LogMaintenance - QUEUED
13. Stage RepositoryUpdate - QUEUED; one PowerShell.OnIdle subscription then runs the queue once the prompt is rendered and the shell
    has been idle ~300 ms: Import-TerminalIcons -RedrawPrompt (Import-Module Terminal-Icons -Global; a torn theme cache file is
    moved aside and the import retried), Invoke-LogMaintenance, Invoke-StartupRepositoryUpdate
    (no-op unless RepositoryUpdate.Startup.Enabled; once a day from Startup.DayStartHour, or once per
    Startup.IntervalHours with Schedule "Interval"), then Register-RepositoryUpdatePromptCheck (Daily only:
    wraps the prompt so a shell still open the next day runs it at its first prompt). An entry that throws is reported
    through Write-LogError (console, session log and error log) and the prompt is drawn again (Restore-ShellPrompt)
```

> **Module autoload:** All WinuX modules declare `FunctionsToExport` in their `.psd1` manifests. PowerShell builds an autoload index at startup (no code executed) and imports a module automatically the first time one of its exported functions is called. `Logging` and `Bootstrap` are imported eagerly by the profile (in that order, so Bootstrap and all other modules can log from the start); nothing else is imported before the first prompt - the handful of Helper, Configuration, System and Git functions the profile needs are dot-sourced from their files, because importing a module costs 4-6 ms per function file (Helper and System were measured at 330-500 ms each) and the first autoload adds PowerShell's module discovery on top. The fork-owned `Custom` module autoloads the same way via its `FunctionsToExport` (which the fork maintains, one entry per Custom function; empty on a pure-upstream setup). `Start-Logging`/`Stop-Logging` live in the `Logging` module (moved out of `Helper`).

---
## Bootstrap Execution Flow

`Bootstrap -WithInitialSetup` runs these phases in order:

```
Phase 0 (Schema):                Load-PathConfiguration → Test-ConfigurationSchema (missing keys and
                                 deprecated keys or step names, warning-only)
Phase 1 (Initial Setup only):    Initialize-Configuration (then Load-PathConfiguration again) → Rename-Machine → Start-MicrosoftActivationScripts → Start-Win11Debloat
                                 (MAS and Win11Debloat are opt-in via BootstrapConfig.Steps)
Phase 2 (Repos):                 Git identity guarantee (restored from GitConfig when unset)
                                 → Update-Repositories (opt-in via BootstrapConfig.Steps.RepositoryUpdate;
                                 -All or -Group <names>, per BootstrapConfig.RepositoryUpdateScope)
Phase 3 (System Config):         Set-CustomExecutionPolicy → Enable-DeveloperMode
                                 → Set-PowerPlan → Set-PowerButtonActions → Set-SystemTheme
                                 → Set-Locale → Set-DisplayLanguage → Set-KeyboardLayouts
                                 → Display-SystemLanguageSettings → Configure-NerdFont
                                 → Install-PowerShellModules → Set-SpecialFolders
                                 → Restart-Explorer → Configure-WSL (config-gated: Steps.WSL)
Phase 4 (Packages):              Resolve-PackageManagers (base => WinGet alone)
                                 → Install-WinGetPackageManager → Install-WingetApps
                                 → Install-ScoopPackageManager → Install-ScoopApps
                                 → Install-ChocolateyPackageManager → Install-ChocolateyApps → Upgrade-All
                                 (each manager runs only if in play: PackageManagers + non-empty app list)
Phase 5 (Dev Tools):             PersonalSteps (fork-defined; base runs none) → Install-DotnetEf
Phase 6 (Environment):           Set-EnvironmentVariables -Auto → Create-CondaEnvironments
                                 → Configure-NuGetConfig → Configure-NpmConfig
Phase 7 (Taskbar):               Configure-Taskbar -FromBootstrap → Set-TaskbarSettings → Set-VisualEffects
Phase 8 (WSL & Symlinks):        Initialize-WSLEnvironment → SymbolicLinkMaker
                                 → Deploy-AiArtifacts (opt-in via BootstrapConfig.Steps.AiArtifacts)
                                 → Deploy-AiMarketplaces (opt-in via BootstrapConfig.Steps.AiMarketplaces)
                                 → Deploy-AiMcpServers (opt-in via BootstrapConfig.Steps.AiMcpServers)
                                 → Enable-ObsidianCli (opt-in via BootstrapConfig.Steps.ObsidianCli)
                                 → Deploy-VSCodeProfiles (opt-in via BootstrapConfig.Steps.VSCodeProfiles;
                                   links VSCodeProfiles.Extensions first via Install-VSCodeLocalExtensions)
                                 → Configure-WSLSSH (WSL steps config-gated)
Phase 9 (Finalize):              Lock taskbar (opt-in via BootstrapConfig.Steps.LockedStartLayout)
                                 → Restart-Explorer → Restart-Machine
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
docs/                                       # The site root, shared with any other project of the repository
├── index.html                              # Generic docsify shell: config, theme (names no project)
├── .nojekyll                               # Stops GitHub Pages running Jekyll over the site
├── _sidebar.md                             # Landing sidebar: one line per project (winux/, custom/)
├── README.md                               # Landing page (root /)
├── docs_overview.md                        # Generic pointer to each project's own overview
├── custom/                                 # The fork's Custom-area pages (a template upstream)
│
docs/winux/                                 # WinuX's pages (published at #/winux/...)
├── _sidebar.md                             # WinuX's navigation, shown on every page under /winux/
├── README.md                               # WinuX overview
├── docs_overview.md                        # THIS FILE
├── roadmap.md                              # Who WinuX is for, its non-goals, where it's headed
│
├── assets/                                 # logo.png, showcase.svg, UltrawideDemo.webp, StackedUltrawideDemo.webp
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
│   ├── winux-configurator.md               # AI-assisted interview that configures WinuX with you
│   └── guides/                             # One guide per exported function, grouped by module.
│       │                                   #   Full template where the function reads config,
│       │                                   #   stub (sentinel + usage) where it does not.
│       │                                   #   Task guides live in the module they belong to.
│       ├── ai/            (README + guides)
│       ├── application/   (README + guides)     # + add-browser-group.md
│       ├── bootstrap/     (README + guides)     # + add-new-machine.md
│       ├── configuration/ (README + guides)
│       ├── git/           (README + guides)     # + add-new-repository.md
│       ├── helper/        (README + guides)
│       ├── logging/       (README + guides)
│       ├── system/        (README + guides)     # + add-symbolic-link.md
│       ├── tests/         (README + guides)
│       ├── window/        (README + guides)     # + configure-window-layout.md
│       └── workflow/      (README + guides)     # + add-new-project.md, add-new-workspace.md
│
├── modules/
│   ├── ai.md                               # AI artifacts deployment and vendoring, marketplaces, MCP servers
│   ├── application.md                      # install, launch, browser, VS Code profiles
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
│   ├── overview.md                         # Layered AI context system, product skills
│   ├── agent-system.md                     # Instructions, skills, prompts and agents as artifacts
│   ├── artifacts.md                        # The AI artifacts mechanism: kinds, harnesses, WSL, migration
│   ├── coreairules.md                      # Rules items and Claude Code managed settings (opt-in)
│   ├── skills.md                           # Machine-global Agent Skills (opt-in)
│   ├── mods.md                             # Machine-global Claude Code mods (opt-in)
│   └── mcp-servers.md                      # MCP servers added to Claude Code and Codex (opt-in)
│
├── contributing/
│   └── fork-model.md                       # Fork model, config + app-list overrides, merge=ours
│
└── reference/
    ├── software-list.md                    # Packages installed from the CSV files
    ├── backups.md                          # Unified backup sink: taxonomy, retention, restore recipes
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

### When adding a page to the fork-owned `custom/` area

Every page in `docs/custom/` must open with a marker naming the contract it is under -
`<!-- reference: functions windows/Custom -->`, `<!-- reference: skills -->`, `<!-- reference: guide -->`
or `<!-- reference: none -->` - because that area is sovereign and holds Agent Skills and prose
alongside functions, all of which use the same `## [Name](url)` heading. Only pages marked
`functions windows/Custom` are parsed by `List-Functions` and checked against `Custom.psd1`. A page with
no valid marker fails the Infrastructure function-reference test on purpose: silence used to be the state
in which a page claimed a contract by accident. See [the Custom area docs](../custom/README.md).

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

_Last verified: October 13, 2026_
