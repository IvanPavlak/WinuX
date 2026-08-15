# Repository Structure

This page documents the layout of the WinuX repository: the annotated repo-root directory tree and the `Windows/` subtree, plus the non-PowerShell configuration files that WinuX symlinks into place. Use it as a map when locating a component, adding a new configuration, or understanding how machine-specific files are named.

## Directory Tree

```
WinuX/
├── .github/                                        # CI workflows, issue/PR templates, AI instructions & prompts
├── AI/                                             # Layered AI context system (see docs/ai/overview.md)
├── Docker/                                         # Docker Compose files (centralized)
│   └── docker-compose.postgresql.yml               # Shared PostgreSQL (PG17 + PG16 + pgAdmin)
├── FastFetch/                                      # CLI system info
│   └── Windows/                                    # Windows-specific FastFetch configs
│       ├── config_{MachineType}.jsonc              # Machine-specific FastFetch configs (ships config_Test.jsonc)
│       ├── FastFetchLogo_{MachineType}.txt         # ASCII art logos per machine
│       └── Conda/                                  # Conda-specific FastFetch configs
│           ├── config_Conda_{MachineType}.jsonc    # Conda FastFetch configs
│           └── FastFetchLogo_Conda.txt             # Conda ASCII logo
├── Firefox/                                        # Firefox user.js template (fork-owned via merge=ours)
├── Git/                                            # Git config template (fork-owned via merge=ours)
├── JetBrainsMonoNerdFont/                          # Font files
├── LazyGit/                                        # LazyGit config
├── LazyDocker/                                     # LazyDocker config
├── NuGet/                                          # NuGet config template (fork-owned via merge=ours)
├── Wallpapers/                                     # Wallpapers
├── docs/                                           # Docsify documentation site (this site)
└── Windows/
    ├── FancyZones/                                 # PowerToys FancyZones settings
    │   ├── custom-layouts.json                     # Custom zone layouts (grid & canvas, arbitrary spacing)
    │   ├── layout-hotkeys.json                     # Layout hotkey bindings
    │   └── settings.json                           # FancyZones settings
    ├── Oh-My-Posh/                                 # Terminal prompt theme
    │   └── WinuX_{MachineType}.omp.json            # Machine-specific Oh-My-Posh themes
    ├── PowerShell/
    │   ├── Configuration.psd1                      # Central configuration hub
    │   ├── Microsoft.PowerShell_profile.ps1        # Profile loader
    │   └── Modules/
    │       ├── Application/                        # App launchers & installers
    │       ├── Bootstrap/                          # System initialization
    │       │   └── Data/
    │       │       ├── WinGetApps.csv              # WinGet applications (upstream baseline)
    │       │       ├── WinGetApps.local.csv        # your own apps, layered over it (gitignored)
    │       │       ├── ScoopApps.csv               # Scoop applications (+ ScoopApps.local.csv)
    │       │       └── ChocolateyApps.csv          # Chocolatey applications (+ .local.csv)
    │       ├── Configuration/                      # Programmatic config modifications
    │       ├── Custom/                             # Fork-owned functions & modules (see Fork Model)
    │       ├── Git/                                # Repository management
    │       ├── Helper/                             # Utility functions
    │       ├── Logging/                            # Unified terminal & file logging
    │       ├── System/                             # System configuration
    │       ├── Tests/                              # Pester test framework
    │       ├── Window/                             # "Tiling Window Manager" module
    │       │   └── Layouts/                        # Workspace layout configurations
    │       │       └── Test/                       # Layouts for the shipped Test profile
    │       │           └── {Workspace}_Test.psd1   # e.g., Example_Test.psd1 (add a folder per machine type you define)
    │       └── Workflow/                           # Development workflows
    │           └── State/                          # What each workspace open produced (gitignored)
    │               └── OpenWorkspaces.txt          # Read by Close-Workspace; safe to delete
    ├── Win11Debloat/                               # Vendored Win11Debloat + saved settings
    │   ├── CustomAppsList                          # Apps to remove
    │   └── LastUsedSettings.json                   # Last used settings
    ├── WindowsTerminal/                            # Windows Terminal settings
    │   ├── settings_{MachineType}.json             # Machine-specific terminal configs
    │   └── CondaLogo.png                           # Conda environment logo
    └── WinuX/                                      # WinuX branding and installer
        ├── WinuX.ps1                               # Installer entry point (source of WinuX.exe)
        ├── New-WinuXExecutable.ps1                 # Builds WinuX.exe via ps2exe (CI runs it per release)
        ├── WinuX.exe                               # Build output - gitignored; download from the release assets
        ├── WinuXLogo.ico                           # WinuX icon
        ├── WinuXLogo.png                           # WinuX logo
        ├── WinuXLogoTransparent.png                # Transparent logo variant
        └── ExecutableCreation.md                   # How the executable is built and released
```

### Notes on the Tree

- **FancyZones `custom-layouts.json`** - arbitrary spacing values and zone definitions (grid and canvas layouts) are supported; the zone math in `Get-FancyZoneCoordinates` replicates FancyZones exactly. `Test-FancyZonesConfiguration` validates the file (and its agreement with `ZoneNameMappings`, `LayoutNumbers`, and `layout-hotkeys.json`) automatically at every workspace open.
- **Window layout naming** - layout files under `Window/Layouts/{MachineType}/` follow the convention `{Workspace}_{MachineType}.psd1` (the base ships `Test/`; add a folder per machine type you define).
- **Machine-specific files** - components such as FastFetch, Oh-My-Posh, and Windows Terminal use a `{MachineType}` suffix so a single repository can drive multiple machines.
- **Runtime state is never committed** - `Logging/Logs/`, `Tests/Results/`, `Window/Layouts/CurrentLayout.txt` and `Workflow/State/` all hold per-machine, per-session data (each kept in git with a `.gitkeep`). Deleting any of them is safe; `Close-Workspace` in particular then reports that nothing is tracked rather than guessing what a workspace opened.
- **Fork payloads** - a personal fork typically grows additional top-level folders (an Obsidian vault, SSH config, keyboard firmware, ...). They are additive and never conflict with upstream pulls; see the [Fork Model](../contributing/fork-model.md).

## Non-PowerShell Configuration Files

While this repository is primarily PowerShell-based, several system components use their own configuration files:

| Component      | Location                              | Purpose                                                   |
| -------------- | ------------------------------------- | --------------------------------------------------------- |
| **FastFetch**  | `FastFetch/Windows/config_*.jsonc`    | System information display customization per machine type |
| **Oh-My-Posh** | `Windows/Oh-My-Posh/WinuX_*.omp.json` | PowerShell prompt theme configuration per machine type    |
| **LazyGit**    | `LazyGit/config.yml`                  | Git UI and keybindings                                    |
| **LazyDocker** | `LazyDocker/config.yml`               | Docker container UI and settings                          |

These configurations are symlinked from `Configuration.psd1` via the `SymbolicLinkMaker` function. For example, LazyGit links `LazyGit/config.yml` to `{User}\AppData\Local\lazygit\config.yml`, and LazyDocker links `LazyDocker/config.yml` to `{AppData}\lazydocker\config.yml`.
