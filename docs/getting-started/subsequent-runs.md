# Subsequent Runs

After initial setup, the Bootstrap function and profile are always available. Here's how to use them for ongoing maintenance.

## Running Bootstrap Again

Open any PowerShell terminal and run:

```powershell
Bootstrap

# Skip or force individual steps for one run (overrides BootstrapConfig.Steps)
Bootstrap -Skip UpgradeAll, WSL
Bootstrap -Include Win11Debloat
```

> [!NOTE]
> Without `-WithInitialSetup`, Bootstrap skips the first-time-only steps (Rename-Machine, Microsoft Activation Scripts, Win11Debloat - the latter two are opt-in via `BootstrapConfig.Steps` even then). Every step is individually toggleable via `BootstrapConfig.Steps`, with `-Skip`/`-Include` as per-invocation overrides - see [Resolve-BootstrapSteps](../modules/bootstrap.md#resolve-bootstrapsteps).

## What Happens on Subsequent Runs

Bootstrap is **idempotent** - safe to run multiple times:

| Action                    | Behavior                                       |
| ------------------------- | ---------------------------------------------- |
| **Update-Repositories**   | Pulls latest, stashes local changes if needed (opt-in via `Steps.RepositoryUpdate`) |
| **System Configuration**  | Re-applies settings (no-op if already correct) |
| **Package Installation**  | Installs new apps from CSV, skips existing     |
| **Upgrade-All**           | Updates packages of every manager in play      |
| **Symbolic Links**        | Re-creates (safe if already exist)             |
| **Environment Variables** | Re-applies (no-op if already set)              |
| **Taskbar**               | Reconfigures pinned apps                       |

Steps whose configuration section is empty (the base default) no-op with a "not configured"
warning - a run on the empty base changes nothing personal. Opt in per feature via
`Configuration.local.psd1`.

## Common Commands

### Repository Management

```powershell
# Update all repositories
Update-Repositories -All

# Update one group (group names come from RepositoryGroups - code knows none of them)
Update-Repositories -Group Private

# Update several groups, in that order
Update-Repositories -Group Private, Work

# Update specific repo
Update-Repositories WinuX
```

### Package Management

```powershell
# Upgrade every package manager in play (PackageManagers + non-empty app list)
Upgrade-All

# Upgrade specific manager - honoured as given, even if not in PackageManagers
Upgrade-All WinGet
Upgrade-All Scoop
Upgrade-All Chocolatey

# Upgrade more than one
Upgrade-All WinGet, Scoop

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

Every time you open PowerShell, the profile (`Microsoft.PowerShell_profile.ps1`) runs. Each block after the first is a **startup stage** - timed on every start (`$WinuXStartupTimings | Format-Table`), skippable for one start through `$env:WINUX_STARTUP_SKIP`, and measured one by one with `Measure-ShellStartup`:

```
┌─────────────────────────────────────────────────────────────────┐
│  PowerShell Profile Initialization                              │
├─────────────────────────────────────────────────────────────────┤
│  1. Minimal Bootstrap                                           │
│     ├─→ Locate Configuration.psd1, resolve the repo root        │
│     ├─→ Build modules path, add to $env:PSModulePath            │
│     └─→ Dot-source the stage guards + Get-ConfigSetting,        │
│         Test-ConfigValue (no Helper module import)              │
│                                                                 │
│  2. Stage Core (always runs)                                    │
│     ├─→ Import Configuration.psd1                               │
│     ├─→ Import Logging and Bootstrap modules                    │
│     └─→ Load-PathConfiguration -Configuration $global:Config... │
│         ├─→ Merges Configuration.local.psd1 over the base       │
│         ├─→ Registers Modules/ in PSModulePath for autoload     │
│         ├─→ Expands placeholders → $global:MachineSpecificPaths │
│         └─→ Sets $global:MachineType                            │
│                                                                 │
│  3. Stage Schema     → Test-ConfigurationSchema (warning-only)  │
│  4. Stage Greeting   → Clear, fastfetch (image logo in WT /     │
│                        WezTerm), onefetch inside a repository   │
│  5. Stage PSReadLine → Import-Module PSReadLine                 │
│  6. Stage Terminal-Icons → queued for after the first prompt    │
│  7. Stage PSReadLineOptions → history, predictions, key binds   │
│  8. Stage OhMyPosh   → Initialize-OhMyPosh (prompt theme)       │
│  9. Stage Aliases                                               │
│     ├─→ Git: gb, gbd, gsw, gp, gmm, gs, gdf                     │
│     ├─→ Workflow: w, cw, b, efm, rp, t                          │
│     ├─→ Dev tools: dnr, dnbr, dnp, nir, c, l                    │
│     └─→ Misc: translate                                         │
│  10. Stage PowerPlan → Test-PowerPlan (chassis type cached)     │
│  11. Stage LogMaintenance → queued                              │
│  12. Stage RepositoryUpdate → queued                            │
│                                                                 │
│  ── first prompt ──                                             │
│  13. PowerShell.OnIdle (once, ~300 ms after the prompt)         │
│     ├─→ Import-Module Terminal-Icons -Global                    │
│     ├─→ Invoke-LogMaintenance                                   │
│     └─→ Invoke-StartupRepositoryUpdate (opt-in, once a day)     │
└─────────────────────────────────────────────────────────────────┘
```

> [!NOTE]
> WinuX modules are **not imported at startup**. Each `.psd1` manifest declares `FunctionsToExport`, enabling PowerShell autoload. A module loads automatically - and silently - the first time one of its exported functions is called; this includes the fork-owned `Custom` module, whose `FunctionsToExport` the fork maintains (empty on a pure-upstream setup). Only `Logging` and `Bootstrap` (imported explicitly by the profile, in that order) are in memory at the first prompt. The few Helper, Configuration, System and Git functions the profile itself needs are dot-sourced from their files, because importing a whole module costs 4-6 ms per function file (Helper and System were measured at 330-500 ms each); the module's own copy replaces the dot-sourced one the first time the module autoloads.

> [!NOTE]
> `Terminal-Icons`, the log maintenance and the opt-in repository update run after the first prompt, from a one-shot `PowerShell.OnIdle` event. The only visible difference is a directory listing typed within the first ~300 ms of a new shell, which prints without icons - and, on the one shell a day where the repository update runs (`RepositoryUpdate.Startup`, off by default), its compact summary printed below the prompt, with typing held until the fetches finish. A shell that stays open into the next day runs it at its first prompt after the day starts (`Startup.DayStartHour`, default 06:00), the summary printed just above that prompt.

> [!TIP]
> A slow start is measured, not guessed: `Measure-ShellStartup` starts child shells with one stage added at a time and prints min / median / max per configuration. See [Slow Profile Load](../reference/troubleshooting.md#slow-profile-load).
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

# Close a workspace again - everything that open produced
Close-Workspace
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
