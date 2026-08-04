# First Run

After `Install-Bootstrap` completes, the main `Bootstrap` function runs with `-WithInitialSetup`. Here's everything that happens.

## What a Vanilla First Run Actually Does

The base configuration ships **empty by default**: a vanilla install applies nothing personal - no
theme or wallpaper, no locale, keyboard layout, or display language, no power settings, no taskbar
pins, no personal symlinks. Every consumer function no-ops with a "not configured" warning when its
section is empty, and Microsoft Activation Scripts and Win11Debloat no longer prompt - they are
opt-in via `BootstrapConfig.Steps`. Personalization is opted into per feature via
`Configuration.local.psd1` (see the [Configuration Overview](../configuration/overview.md)).

What a vanilla run DOES do: update the repository, install the framework apps (PowerShell 7,
Windows Terminal, PowerToys), install the PowerShell modules, and create the framework symlinks
(the PowerShell profile + configuration and the FancyZones files).

Every step is individually toggleable via `BootstrapConfig.Steps` (or per invocation with
`Bootstrap -Skip <steps>` / `-Include <steps>`) - see the
[Bootstrap module](../modules/bootstrap.md#resolve-bootstrapsteps).

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
│  │   └─ Optional Windows/Office activation (opt-in via Steps)               │
│  └─→ Start-Win11Debloat                                                     │
│      └─ Runs local vendored Win11Debloat (opt-in via Steps)                 │
│                                                                             │
│  PHASE 2: REPOSITORY SYNCHRONIZATION                                        │
│  └─→ Update-Repositories                                                    │
│      ├─ Clone all configured Git repositories                               │
│      └─ Pull latest changes for existing repos                              │
│                                                                             │
│  PHASE 3: SYSTEM CONFIGURATION                                              │
│  ├─→ Set-CustomExecutionPolicy                                              │
│  ├─→ Enable-DeveloperMode (opt-in via Steps; for symlinks w/o admin)        │
│  ├─→ Set-PowerPlan -Auto                                                    │
│  ├─→ Set-PowerButtonActions -Auto                                           │
│  ├─→ Set-SystemTheme -Auto (Dark/Light based on Themes config)              │
│  ├─→ Set-Locale (from Locales config)                                       │
│  ├─→ Set-DisplayLanguage (from DisplayLanguages config)                     │
│  ├─→ Set-KeyboardLayouts (from KeyboardLayouts config)                      │
│  ├─→ Display-SystemLanguageSettings                                         │
│  ├─→ Configure-NerdFont (from NerdFonts config)                             │
│  ├─→ Install-PowerShellModules                                              │
│  ├─→ Set-SpecialFolders (from SpecialFolders config)                        │
│  ├─→ Restart-Explorer                                                       │
│  └─→ Configure-WSL (config-gated: Steps.WSL)                                │
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
│  │   └─ From AutoEnvironmentVariables config                                │
│  ├─→ Create-CondaEnvironments                                               │
│  └─→ Configure-NuGetConfig (opt-in via Steps)                               │
│                                                                             │
│  PHASE 7: TASKBAR & VISUAL CONFIGURATION                                    │
│  ├─→ Configure-Taskbar -FromBootstrap                                       │
│  │   └─ Pins configured apps in order                                       │
│  ├─→ Set-TaskbarSettings (config-gated: TaskbarSettings)                    │
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
│  ├─→ Lock taskbar layout (opt-in via Steps)                                 │
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

This adds the first-time-only steps:

| Step                               | Description                             | Default                                                    |
| ---------------------------------- | --------------------------------------- | ---------------------------------------------------------- |
| `Rename-Machine`                   | Set hostname for machine type detection | On (interactive prompt)                                    |
| `Start-MicrosoftActivationScripts` | Windows/Office activation               | Off - opt in via `BootstrapConfig.Steps` (no prompt)       |
| `Start-Win11Debloat`               | Runs local vendored Win11Debloat        | Off - opt in via `BootstrapConfig.Steps` (no prompt)       |

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

The committed CSVs hold only the software WinuX itself needs. **Your own apps go in a sibling
`<name>.local.csv`**, which is layered over the committed list at read time and is gitignored - so
you never edit a tracked file and upstream pulls never conflict on an app choice. See
[Software List: Machine-Local Overlay](../reference/software-list.md#machine-local-overlay).

**Machine column values:**

The values are not a fixed set - each row is matched against the machine types you define in
`Configuration.psd1` (`HostnameToMachineType` / `ValidMachineTypes`). Only `All` is special, and
`/` combines several types:

- `All` - install on every machine
- `Test` - install only on machines that resolve to your `Test` type
- `PC/Laptop` - install on your `PC` and `Laptop` types, and nothing else

See [Software List](../reference/software-list.md) for all installed applications.

## Symbolic Links Created

The base configuration ships only the framework links - what persists WinuX into every new shell
and what the window layouts need:

| Application        | Source (WinuX)                                        | Target (System)                     |
| ------------------ | ----------------------------------------------------- | ----------------------------------- |
| PowerShell Profile | `Windows\PowerShell\Microsoft.PowerShell_profile.ps1` | Documents\PowerShell                |
| PowerShell Config  | `Windows\PowerShell\Configuration.psd1`               | Documents\PowerShell                |
| FancyZones         | `Windows\FancyZones\*.json` (three files)             | PowerToys FancyZones settings       |

Everything else (Git, FastFetch, Oh-My-Posh, Windows Terminal, LazyGit, LazyDocker, ...) ships as
commented examples in the `SymbolicLinks` section - copy the ones you want into
`Configuration.local.psd1`.

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

WSL provisioning is optional and config-gated: `BootstrapConfig.Steps.WSL` in `Configuration.psd1`
is a plain boolean or a per-machine-type hashtable with a `Default` fallback (absent => `$true`;
the deprecated `BootstrapConfig.WSLSetup` key is still honored when `Steps` carries no `WSL`
entry). Even with the step on, `Configure-WSL`, `Initialize-WSLEnvironment`, and `Configure-WSLSSH`
no-op until `DefaultWSLDistribution` is set (the base ships it empty - opt in via
`Configuration.local.psd1`, e.g. `"Ubuntu"`), and `SymbolicLinkMaker` skips WSL symlinks whenever
no distribution is present.

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
