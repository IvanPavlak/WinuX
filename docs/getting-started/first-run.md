# First Run

After `Install-Bootstrap` completes, the main `Bootstrap` function runs with `-WithInitialSetup`. Here's everything that happens.

## Complete Bootstrap Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      BOOTSTRAP -WithInitialSetup                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  PHASE 1: INITIAL SETUP (only with -WithInitialSetup flag)                  │
│  ├─→ Rename-Machine                                                         │
│  │   └─ Prompts to set hostname for machine type detection                  │
│  ├─→ Start-MicrosoftActivationScripts                                       │
│  │   └─ Optional Windows/Office activation (user prompted)                  │
│  └─→ Start-Win11Debloat                                                     │
│      └─ Runs local vendored Win11Debloat (user prompted)                    │
│                                                                             │
│  PHASE 2: REPOSITORY SYNCHRONIZATION                                        │
│  └─→ Update-Repositories                                                    │
│      ├─ Clone all configured Git repositories                               │
│      └─ Pull latest changes for existing repos                              │
│                                                                             │
│  PHASE 3: SYSTEM CONFIGURATION                                              │
│  ├─→ Set-CustomExecutionPolicy                                              │
│  ├─→ Enable-DeveloperMode (required for symlinks without admin)             │
│  ├─→ Set-PowerPlan -Auto                                                    │
│  ├─→ Set-PowerButtonActions -Auto                                           │
│  ├─→ Set-SystemTheme -Auto (Dark/Light based on Themes config)              │
│  ├─→ Set-Locale (hr-HR regional format)                                     │
│  ├─→ Set-DisplayLanguage (en-US UI language)                                │
│  ├─→ Set-KeyboardLayouts (Croatian + US)                                    │
│  ├─→ Display-SystemLanguageSettings                                         │
│  ├─→ Configure-NerdFont (JetBrainsMono Nerd Font)                           │
│  ├─→ Install-PowerShellModules                                              │
│  ├─→ Set-SpecialFolders (redirect Downloads to Desktop)                     │
│  ├─→ Restart-Explorer                                                       │
│  └─→ Configure-WSL (WSL; config-gated: WSLSetup)                            │
│                                                                             │
│  PHASE 4: PACKAGE MANAGEMENT                                                │
│  ├─→ Install-WinGetPackageManager                                           │
│  ├─→ Install-WinGetApps (from WinGetApps.csv)                               │
│  ├─→ Install-ScoopPackageManager                                            │
│  ├─→ Install-ScoopApps (from ScoopApps.csv)                                 │
│  ├─→ Install-ChocolateyPackageManager                                       │
│  ├─→ Install-ChocolateyApps (from ChocolateyApps.csv)                       │
│  └─→ Upgrade-All (update all packages)                                      │
│                                                                             │
│  PHASE 5: DEVELOPMENT TOOLS                                                 │
│  ├─→ PersonalSteps (fork-defined; base config runs none)                    │
│  └─→ Install-DotnetEF (Entity Framework tools)                              │
│                                                                             │
│  PHASE 6: ENVIRONMENT CONFIGURATION                                         │
│  ├─→ Set-EnvironmentVariables -Auto                                         │
│  │   └─ Sets Conda, Claude, Cargo paths                                     │
│  ├─→ Create-CondaEnvironments                                               │
│  └─→ Configure-NuGetConfig                                                  │
│                                                                             │
│  PHASE 7: TASKBAR & VISUAL CONFIGURATION                                    │
│  ├─→ Configure-Taskbar -FromBootstrap                                       │
│  │   └─ Pins configured apps in order                                       │
│  ├─→ Set-TaskbarAutoHide -Auto (config-gated: TaskbarAutoHide)              │
│  └─→ Set-VisualEffects (config-gated: VisualEffects)                        │
│                                                                             │
│  PHASE 8: WSL & SYMBOLIC LINKS                                              │
│  ├─→ Initialize-WSLEnvironment                                              │
│  │   └─ Full WSL setup and distribution install                             │
│  ├─→ SymbolicLinkMaker                                                      │
│  │   └─ Creates all symlinks from SymbolicLinks config                      │
│  └─→ Configure-WSLSSH                                                       │
│      └─ Sets up SSH keys in WSL                                             │
│                                                                             │
│  PHASE 9: FINALIZATION                                                      │
│  ├─→ Lock taskbar layout (prevent modifications)                            │
│  ├─→ Restart-Explorer                                                       │
│  └─→ Restart-Machine (prompt user)                                          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Running with Initial Setup

First-time installation automatically uses:

```powershell
Bootstrap -WithInitialSetup
```

This adds three initial prompts:

| Step                               | Description                             | Optional?      |
| ---------------------------------- | --------------------------------------- | -------------- |
| `Rename-Machine`                   | Set hostname for machine type detection | Yes            |
| `Start-MicrosoftActivationScripts` | Windows/Office activation               | Yes (prompted) |
| `Start-Win11Debloat`               | Runs local vendored Win11Debloat        | Yes (prompted) |

## What Gets Installed

### PowerShell Modules

| Module           | Purpose                            |
| ---------------- | ---------------------------------- |
| `Terminal-Icons` | File/folder icons in terminal      |
| `PSReadLine`     | Advanced command-line editing      |
| `z`              | Smart directory jumping (frecency) |
| `VirtualDesktop` | Virtual desktop management         |
| `ps2exe`         | Convert scripts to .exe            |
| `Pester`         | Testing framework                  |

### Package Managers

| Manager        | Purpose                              |
| -------------- | ------------------------------------ |
| **WinGet**     | Microsoft's official package manager |
| **Scoop**      | Developer-focused CLI tools          |
| **Chocolatey** | Community-maintained packages        |

### Applications

Applications are defined in CSV files and **filtered by machine type**:

| File                 | Manager    | Format                                         |
| -------------------- | ---------- | ---------------------------------------------- |
| `WinGetApps.csv`     | WinGet     | `App,Version,Scope,Interactive,Source,Machine` |
| `ScoopApps.csv`      | Scoop      | `App,Version,Global,Machine`                   |
| `ChocolateyApps.csv` | Chocolatey | `App,Version,Params,Force,Machine`             |

**Machine column values:**

The values are not a fixed set - each row is matched against the machine types you define in
`Configuration.psd1` (`HostnameToMachineType` / `ValidMachineTypes`). Only `All` is special, and
`/` combines several types:

- `All` - install on every machine
- `Test` - install only on machines that resolve to your `Test` type
- `PC/Laptop` - install on your `PC` and `Laptop` types, and nothing else

See [Software List](../reference/software-list.md) for all installed applications.

## Symbolic Links Created

All configuration files are symlinked from the WinuX repository:

| Application        | Source (WinuX)                                        | Target (System)                     |
| ------------------ | ----------------------------------------------------- | ----------------------------------- |
| Git                | `Git\.gitconfig`                                      | `~\.gitconfig`                      |
| Windows Terminal   | `Windows\WindowsTerminal\settings_{MachineType}.json` | LocalState settings                 |
| Oh-My-Posh         | `Windows\Oh-My-Posh\WinuX_{MachineType}.omp.json`     | Themes folder                       |
| FastFetch          | `FastFetch\Windows\config_{MachineType}.jsonc`        | `~\.config\fastfetch\`              |
| PowerShell Profile | `Windows\PowerShell\Microsoft.PowerShell_profile.ps1` | Documents\PowerShell                |
| FancyZones         | `Windows\FancyZones\*.json`                           | PowerToys settings                  |
| And more...        | See Configuration.psd1                                | SymbolicLinks section               |

## Logging

All output is logged to Desktop:

```
BootstrapLog_2026-01-21_14-30-25.log
```

Review this file if any step fails.

## Handling Errors

### Package Installation Fails

```powershell
# Retry specific package manager
Install-WinGetApps
Install-ScoopApps
Install-ChocolateyApps
```

### Symlink Creation Fails

Ensure Developer Mode is enabled:

```powershell
Enable-DeveloperMode
```

Then retry:

```powershell
SymbolicLinkMaker
```

### WSL Issues

WSL provisioning is optional and config-gated: `BootstrapConfig.WSLSetup` in `Configuration.psd1`
maps machine type => `$true`/`$false` ("Default" fallback; absent => `$true`). The minimal `Test`
profile disables it - test VMs skip `Configure-WSL`, `Initialize-WSLEnvironment`, and
`Configure-WSLSSH` (no Ubuntu download, no first-launch prompt, no extra reboot), and
`SymbolicLinkMaker` skips WSL symlinks whenever no distribution is present.

```powershell
# Check WSL status
wsl --status

# Reinstall if needed
wsl --install
```

## Next Steps

After the restart:

1. Open Windows Terminal - your profile is configured
2. You should see the Oh My Posh prompt
3. Run `List-Functions` to see all available commands
4. Continue to [Subsequent Runs](subsequent-runs.md)
5. Explore the [Configuration](../configuration/overview.md) to customize
