# Subsequent Runs

After initial setup, the Bootstrap function and profile are always available. Here's how to use them for ongoing maintenance.

## Running Bootstrap Again

Open any PowerShell terminal and run:

```powershell
Bootstrap
```

> [!NOTE]
> Without `-WithInitialSetup`, Bootstrap skips the initial prompts (Rename-Machine, activation, Start-Win11Debloat).

## What Happens on Subsequent Runs

Bootstrap is **idempotent** - safe to run multiple times:

| Action                    | Behavior                                       |
| ------------------------- | ---------------------------------------------- |
| **Update-Repositories**   | Pulls latest, stashes local changes if needed  |
| **System Configuration**  | Re-applies settings (no-op if already correct) |
| **Package Installation**  | Installs new apps from CSV, skips existing     |
| **Upgrade-All**           | Updates all installed packages                 |
| **Symbolic Links**        | Re-creates (safe if already exist)             |
| **Environment Variables** | Re-applies (no-op if already set)              |
| **Taskbar**               | Reconfigures pinned apps                       |

## Common Commands

### Repository Management

```powershell
# Update all repositories
Update-Repositories -All

# Update only private repos
Update-Repositories -Private

# Update only work repos
Update-Repositories -Work

# Update specific repo
Update-Repositories WinuX
```

### Package Management

```powershell
# Upgrade everything
Upgrade-All

# Upgrade specific manager
Upgrade-All WinGet
Upgrade-All Scoop
Upgrade-All Chocolatey

# Install new WinGet apps (after editing CSV)
Install-WinGetApps

# Install new Scoop apps
Install-ScoopApps

# Install new Chocolatey apps
Install-ChocolateyApps
```

### Symbolic Links

```powershell
# Re-create all symlinks
SymbolicLinkMaker
```

### Configuration Reload

After editing `Configuration.psd1`:

```powershell
# Reload without restart
Reload-PowerShellProfile

# Or simply start a new terminal
```

## Profile Initialization

Every time you open PowerShell, the profile (`Microsoft.PowerShell_profile.ps1`) runs:

```
┌─────────────────────────────────────────────────────────────────┐
│  PowerShell Profile Initialization                              │
├─────────────────────────────────────────────────────────────────┤
│  1. Minimal Bootstrap                                           │
│     ├─→ Import Configuration.psd1                               │
│     ├─→ Determine MachineType from hostname                     │
│     ├─→ Build modules path, add to $env:PSModulePath            │
│     └─→ Import Bootstrap module                                 │
│                                                                 │
│  2. Load-PathConfiguration -Configuration $global:Configuration │
│     ├─→ Reuses pre-loaded config (no second file read)          │
│     ├─→ Registers Modules/ in PSModulePath for autoload         │
│     ├─→ Expands placeholders → $global:MachineSpecificPaths     │
│     └─→ Sets $global:Configuration, $global:MachineType         │
│                                                                 │
│  3. Console Enhancement                                         │
│     ├─→ Oh-My-Posh (WinuX_{MachineType}.omp.json theme)         │
│     ├─→ FastFetch (system info display)                         │
│     ├─→ PSReadLine (history, predictions, key bindings)         │
│     └─→ Terminal-Icons (file/folder icons)                      │
│                                                                 │
│  4. Register Aliases                                            │
│     ├─→ Git: gb, gbd, gsw, gp, gmm, gs, gdf                     │
│     ├─→ Workflow: w, b, efm, rp, t                              │
│     ├─→ Dev tools: dnr, dnbr, dnp, nir, c, l                    │
│     └─→ Misc: translate                                         │
│                                                                 │
│  5. Startup Checks                                              │
│     └─→ Test-PowerPlan (dot-sourced directly, no module import) │
└─────────────────────────────────────────────────────────────────┘
```

> [!NOTE]
> WinuX modules are **not imported at startup**. Each `.psd1` manifest declares `FunctionsToExport`, enabling PowerShell autoload. A module loads automatically - and silently - the first time one of its exported functions is called. Only `Logging` and `Bootstrap` (imported explicitly by the profile, in that order), the fork-owned `Custom` module (imported eagerly because its wildcard manifest cannot autoload; empty on a pure-upstream setup), and `Helper` (autoloaded during path-expansion) are guaranteed to be in memory at startup.

> [!NOTE]
> `Test-PowerPlan` is dot-sourced directly from its `.ps1` file rather than importing the entire `System` module at startup. This avoids loading ~46 system functions just for one startup check.

## Checking Current State

```powershell
# View machine type
$global:MachineType
# Output: Test

# View configuration (raw)
$global:Configuration

# View expanded paths
$global:MachineSpecificPaths

# View specific path
$global:MachineSpecificPaths.Projects.Self.Root
# Output: C:\Users\You\Development\GitHub\WinuX

# List all available functions
List-Functions

# Get details on a function
Show-FunctionDetails Open-Workspace
```

## Quick Reference

### Daily Workflow

```powershell
# Open a project
Open-Project

# Open a workspace (project + tools + browser tabs + layout)
Open-Workspace

# Run the current project
Run-Project
```

### Maintenance

```powershell
# Full system sync
Bootstrap

# Just update repos
Update-Repositories -All

# Just update packages
Upgrade-All
```

### Customization

```powershell
# Edit configuration
code $global:MachineSpecificPaths.Projects.Self.Root

# After editing, reload
Reload-PowerShellProfile
```

## Partial Bootstrap

If you only need specific parts:

```powershell
# Only system configuration
Set-SystemTheme -Auto
Set-Locale -Locale "Croatian"
Set-KeyboardLayouts -Layout "Croatian-US"

# Only package updates
Upgrade-All

# Only symlinks
SymbolicLinkMaker

# Only taskbar
Configure-Taskbar
```

## Troubleshooting

### Profile Not Loading

```powershell
# Check profile path
$PROFILE

# Test if profile exists
Test-Path $PROFILE

# Manually source profile
. $PROFILE
```

### Functions Not Available

```powershell
# Reload profile to re-import everything
Reload-PowerShellProfile

# Or simply open a new terminal
```

### Configuration Not Updating

```powershell
# Force reload profile and configuration
Reload-PowerShellProfile

# Or manually re-run Load-PathConfiguration
$RepoRoot = $global:MachineSpecificPaths.Projects.Self.Root
Load-PathConfiguration -RepoRoot $RepoRoot
```

## Next Steps

- Explore [Configuration](../configuration/overview.md) to customize settings
- Learn about [Workspaces](../modules/workflow.md) for productivity automation
