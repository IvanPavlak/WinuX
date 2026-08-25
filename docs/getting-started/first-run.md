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
(the PowerShell profile + configuration and the FancyZones files). It does **not** upgrade the
software already on the machine - `UpgradeAll` is opt-in (see below) - and it does not throw away
whatever it links over: a real file already sitting at a link path is backed up first.

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
│  │   Only managers in play run: listed in PackageManagers AND holding at    │
│  │   least one app for this machine. Base config => WinGet alone.           │
│  ├─→ Install-WinGetPackageManager                                           │
│  ├─→ Install-WinGetApps (from WinGetApps.csv)                               │
│  ├─→ Install-ScoopPackageManager (skipped: empty ScoopApps.csv)             │
│  ├─→ Install-ScoopApps (from ScoopApps.csv)                                 │
│  ├─→ Install-ChocolateyPackageManager (skipped: empty ChocolateyApps.csv)   │
│  ├─→ Install-ChocolateyApps (from ChocolateyApps.csv)                       │
│  └─→ Upgrade-All (opt-in via Steps.UpgradeAll; OFF by default)              │
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
│  ├─→ Deploy-CoreAiRules (opt-in via Steps.CoreAiRules)                      │
│  │   └─ CoreAiRules managed settings inside WSL (/etc/claude-code)          │
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

Steps that run on **every** Bootstrap but ship off, because they act the moment they run:

| Step                 | Description                                                     | Default                                       |
| -------------------- | --------------------------------------------------------------- | --------------------------------------------- |
| `UpgradeAll`         | `winget upgrade --all` (+ Scoop/Chocolatey), so **every** package already on the machine, not just WinuX's | Off - opt in via `BootstrapConfig.Steps` |
| `DeveloperMode`      | Enables Developer Mode (symlinks without admin)                 | Off - opt in via `BootstrapConfig.Steps`      |
| `NuGetConfig`        | Writes a NuGet config (prompts for a GitHub PAT)                | Off - opt in via `BootstrapConfig.Steps`      |
| `CoreAiRules`        | Machine-global AI agent policy                                  | Off - opt in via `BootstrapConfig.Steps`      |
| `LockedStartLayout`  | Locks the taskbar layout via registry policy                    | Off - opt in via `BootstrapConfig.Steps`      |

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

### What happens to a file already sitting at a link path

Two of the framework links land on paths a machine may well already be using: the PowerShell 7
profile, and the PowerToys FancyZones files (the same bootstrap installs PowerToys, so a machine
that already ran it has them).

Nothing is thrown away. Before a link replaces a **real** file or directory, WinuX copies it to:

```
<repo>\Backups\SymbolicLinks\<entry key>\<yyyy-MM-dd_HH-mm-ss>\
```

One folder per link entry, one timestamped folder per replacement, so every version ever displaced
sits side by side with the newest last. For example, a profile replaced by the `PowerShell.Profile`
entry lands in `Backups\SymbolicLinks\PowerShell.Profile\2026-08-24_18-30-00\`.

`Backups/` is gitignored (only a `.gitkeep` is tracked): the copies hold your own data and possibly
secrets, so they stay on your machine and are never committed.

Two details worth knowing:

- If the backup **cannot** be written, the link is skipped and the existing file is left alone. A
  file that could not be saved is never removed.
- An existing **symlink** is replaced without a backup. It carries no content of its own, so
  archiving it would just deposit a copy of WinuX's own link on every re-run.

WSL links behave the same way: a real file inside the distribution is copied out to the same
Windows-side folder before it is replaced, which matters most for files that only ever existed in
the distro (a shell profile, an SSH config) and so have no Windows copy to fall back on.

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
no distribution is present. Setting `DefaultWSLUsername` alongside it makes the first-install
account setup non-interactive (only the sudo password is prompted).

```powershell
# Check WSL status
wsl --status

# Redo the whole WSL setup from scratch (unregisters the distribution - deletes its data! -
# reinstalls, recreates the user, and re-runs the environment and SSH steps)
Configure-WSL -Force
```

## Next Steps

After the restart:

1. Open Windows Terminal - your profile is configured
2. You should see the Oh My Posh prompt
3. Run `List-Functions` to see all available commands
4. Continue to [Subsequent Runs](subsequent-runs.md)
5. Explore the [Configuration](../configuration/overview.md) to customize