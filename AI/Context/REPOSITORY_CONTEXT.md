# Repository Context

> **Purpose**: High-level architecture map for AI consumption. Read this before working on any task in this repository.
> **Last updated**: 2026-06-24

## ⚠️ CRITICAL SAFETY - Never Act Destructively On Your Own

You are NEVER allowed to commit, push, or perform ANY destructive or irreversible operation on your own initiative - EVER. Each such action requires an explicit, in-the-moment instruction from the user for that specific action. General prior approval, "continue", "do everything", or your own judgment do NOT count as permission.

Never do these without the user explicitly asking for that exact action in the current turn:

- `git commit`, `git push`, `git reset`, `git rebase`, `git branch -D`, `git checkout -- <file>`, tag or force operations, or anything that writes to git history or a remote
- Deleting or overwriting files/directories the user did not ask you to change (`Remove-Item`, `rm`, mass overwrites)
- Restructuring or moving core folders, or any other hard-to-reverse change

If such an action seems warranted, STOP and ask first, stating exactly what you intend to do, and wait for explicit confirmation. Default to the least destructive path. Creating/editing files for the task at hand and running read-only/verification commands are fine.

## What This Repository Is

A centralized dotfiles repository that automates the complete configuration of all machines and operating systems. One-command bootstrap installs software, configures settings, creates symbolic links, and sets up automated workflows - reproducible across PC, Laptop, Work, and Test machines. Linux integration is yet to be added.

## Architecture

```
Bootstrap Flow:
  Microsoft.PowerShell_profile.ps1
    → Loads Configuration.psd1 (central config hub)
    → Determines machine type from hostname
    → Adds Modules/ to PSModulePath
    → Imports Bootstrap module → Load-PathConfiguration
        → Expands placeholder paths ({Dev}, {User}, {MachineType}, etc.)
        → Imports all other modules
    → Configures Oh-My-Posh, FastFetch, PSReadLine
    → Sets aliases
    → Calls Test-PowerPlan
```

## Key Files

| File                                                  | Purpose                                     |
| ----------------------------------------------------- | ------------------------------------------- |
| `Windows/PowerShell/Microsoft.PowerShell_profile.ps1` | Entry point - loaded on every shell start   |
| `Windows/PowerShell/Configuration.psd1`               | Central config hub - ALL settings live here |
| `Windows/PowerShell/Modules/`                         | PowerShell modules and their functions      |
| `docs/`                                               | Docsify docs - SINGLE SOURCE OF TRUTH       |
| `docs/docs_overview.md`                               | Internal docs maintenance reference         |
| `AGENTS.md`                                           | AI workspace instructions                   |

> **Documentation model**: `docs/` (the docsify site) is the single source of truth; `README.md` at the repo root is a minimal pointer (logo + intro + demo-video placeholder + link to the docs) and carries no function reference - never add function entries to it or update it when a function changes.

## Modules

| Module            | Purpose                                         | Key Functions                                                                              |
| ----------------- | ----------------------------------------------- | ------------------------------------------------------------------------------------------ |
| **Application**   | App launchers, installers, browser management   | `Open-Browser`, `Open-VSCode`, `Install-WingetApps`, `Open-Workspace` triggers these       |
| **Bootstrap**     | System initialization, first-run setup          | `Bootstrap`, `Load-PathConfiguration`, `DetermineMachineType`, `Expand-ConfigPaths`        |
| **Git**           | Repository operations, version control          | `GitBranch`, `GitSwitch`, `Update-Repositories`, `Initialize-Repository`                   |
| **Helper**        | Core utilities used by all modules              | `Find-Item`, `Resolve-ProjectPath`, `Get-FilteredParams`, `Run-Project`                    |
| **System**        | OS configuration, maintenance                   | `SymbolicLinkMaker`, `Set-SystemTheme`, `Set-Wallpaper`, `Configure-WSL`                   |
| **Window**        | Window management, FancyZones, virtual desktops | `Set-WorkspaceWindowLayout`, `Apply-FancyZones`, `Move-WindowToVirtualDesktop`             |
| **Workflow**      | Workspace/project orchestration                 | `Open-Workspace`, `Open-Project`, `Open-ProjectTerminals`, `EfCoreMigrationWizard`         |
| **Configuration** | Reliable configuration modifications            | `Add-BrowserGroup`, `Add-Workspace`, `Add-Project`, `Add-SymbolicLink`, `Add-WindowLayout` |
| **Tests**         | Pester test framework                           | Test files in `Modules/Tests/Modules/`                                                     |

## Configuration.psd1 Structure

The central config hub uses a hierarchical hashtable with these major sections:

### Core Sections

- **Universal** - Machine-independent constants: Desktop, Fonts, Paths, Browser definitions, GitHub URLs
- **BasePaths** - Per-machine root directories (`{Dev} = "C:\Users\You\Development\GitHub"`)
- **PathTemplates** - Placeholder-based paths expanded at runtime

### Placeholder System

```
{Dev}          → Machine-specific development root (e.g., C:\Users\You\Development\GitHub)
{User}         → User profile directory (e.g., C:\Users\You)
{MachineType}  → PC, Laptop, Work, or Test
{RepoRoot} → This repository's root path
{AppData}      → AppData\Local path
```

Expanded by `Expand-ConfigPaths` at bootstrap time. All config entries use these placeholders for machine independence.

### Machine Type Detection

```
Hostname → Machine Type:
  DESKTOP-GAMING  → PC
  LAPTOP-PERSONAL → Laptop
  WORKSTATION-01  → Work
  Test            → Test
  Default         → Test (DefaultMachineType fallback for unmapped hostnames)
```

### Configuration Sections → Consumer Functions

| Config Section                    | Consumer                           | Purpose                                    |
| --------------------------------- | ---------------------------------- | ------------------------------------------ |
| `BrowserGroups`                   | `Open-Browser`, `Invoke-Browser`   | Hierarchical URL groups with nesting       |
| `Workspaces` / `WorkspaceActions` | `Open-Workspace`                   | Workspace definitions and action sequences |
| `Projects` / `ProjectActions`     | `Open-Project`                     | Project definitions and launch sequences   |
| `SymbolicLinks`                   | `SymbolicLinkMaker`                | Source→target symlink mappings (recursive) |
| `WindowLayouts`                   | `Set-WorkspaceWindowLayout`        | Per-workspace window positioning rules     |
| `Repositories`                    | `Update-Repositories`              | Git repository paths for batch updates     |
| `TerminalTabs`                    | `Open-ProjectTerminals`            | Terminal tab configurations per project    |
| `Applications` / `WingetApps`     | `Install-WingetApps`               | Software list for automated installation   |
| `Theme` / `Wallpaper`             | `Set-SystemTheme`, `Set-Wallpaper` | Visual customization per machine type      |

### Key Configuration Patterns

**Browser Groups** - Hierarchical with unlimited nesting:

```powershell
@{ GroupName = @( @{ Name = "Label"; Url = "https://..." } ) }
# Or nested: @{ Parent = @( @{ Child = @( @{ Name = "..."; Url = "..." } ) } ) }
```

**Workspace Actions** - Sequential action lists:

```powershell
WorkspaceActions = @{
    WorkspaceName = @(
        @{ Action = "Open-Project"; Parameters = @{ Project = "Name" } }
        @{ Action = "Open-Browser"; Parameters = @{ Groups = @("Group1", "Group2") } }
        @{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = "Name" } }
    )
}
```

**Symbolic Links** - Recursive hashtable with Path/Target leaf nodes:

```powershell
SymbolicLinks = @{
    AppName = @{
        Path   = "{User}\path\to\link"
        Target = "{RepoRoot}\path\to\target"
    }
}
```

## Common Extension Points

When you need to add or modify something, these are the typical operations:

1. **Add a new application** → Add to `WingetApps` CSV, create `Open-AppName.ps1` in Application module, add alias in profile
2. **Add a browser group** → Add entry to `BrowserGroups` in `Configuration.psd1`
3. **Add a workspace** → Add to `Workspaces` list + define `WorkspaceActions` entry
4. **Add a project** → Add to `Projects` list + define `ProjectActions` entry + optional `TerminalTabs`
5. **Add a symbolic link** → Add entry to `SymbolicLinks` section
6. **Add a window layout** → Add/modify layout `.psd1` file in appropriate machine-type folder
7. **Add a new function** → Create `.ps1` in the relevant module's `Functions/` dir, add to `.psd1` FunctionsToExport
8. **Add a new machine type** → Add to `ValidMachineTypes`, `HostnameToMachineType`, create machine-specific configs

## Related Directories

| Directory             | Purpose                                                                      |
| --------------------- | ---------------------------------------------------------------------------- |
| `AI/`                 | AI configuration hub - instructions, context, conversations, provider guides |
| `Codegen/`            | Code generation profiles for your projects                                   |
| `FastFetch/`          | Per-machine FastFetch configs and ASCII art logos                            |
| `Git/`                | Git configuration files                                                      |
| `Docker/`             | Docker Compose configurations                                                |
| `Conda/`              | Conda environment definitions                                                |
| `Firefox/`            | Firefox `user.js` configuration                                              |
| `Windows/Oh-My-Posh/` | Per-machine terminal prompt themes                                           |
| `Windows/FancyZones/` | PowerToys FancyZones layouts                                                 |
| `Windows/Rainmeter/`  | Per-machine Rainmeter desktop widgets                                        |
| `Windows/VSCode/`     | VS Code settings and profiles                                                |
| `docs/`               | Docsify documentation site                                                   |
