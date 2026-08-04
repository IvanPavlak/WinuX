# Software List

Everything the base WinuX bootstrap installs, and where it comes from. The CSV files under
`Windows\PowerShell\Modules\Bootstrap\Data\` are the source of truth. WinuX ships only the
software its own features need; everything you add for yourself goes in a machine-local
`<name>.local.csv` beside it - see [Machine-Local Overlay](#machine-local-overlay).

## How installs are driven

| File                 | Manager    | Format                                         | Shipped active rows |
| -------------------- | ---------- | ---------------------------------------------- | ------------------- |
| `WinGetApps.csv`     | WinGet     | `App,Version,Scope,Interactive,Source,Machine` | 3                   |
| `ScoopApps.csv`      | Scoop      | `App,Version,Global,Machine`                   | 0                   |
| `ChocolateyApps.csv` | Chocolatey | `App,Version,Params,Force,Machine`             | 0                   |

- **Scope**: `d` (default), `m` (machine-wide), `u` (user). **Source**: `w` (winget), `s` (msstore).
- **Machine** is matched against the machine types you define in `Configuration.psd1` - only
  `All` is special, and `/` combines several types (`PC/Laptop`). The base config ships only `Test`.
  Tokens are validated against `ValidMachineTypes` via `Test-MachineTypeScope` - unknown machine
  types are reported via `Write-LogError` and never match.
- All three package managers are installed by Bootstrap even when their CSV is empty - add rows
  to the matching overlay and re-run to install more.

## Machine-Local Overlay

Each committed list may have a machine-local overlay beside it in `Modules/Bootstrap/Data/`:

| Committed list       | Machine-local overlay      |
| -------------------- | -------------------------- |
| `WinGetApps.csv`     | `WinGetApps.local.csv`     |
| `ScoopApps.csv`      | `ScoopApps.local.csv`      |
| `ChocolateyApps.csv` | `ChocolateyApps.local.csv` |

[`Import-AppCsv`](../modules/bootstrap.md#import-appcsv) layers the overlay over the committed list
at read time, and every reader goes through it - all three installers and `Get-PinnedApps` - so what
the overlay says is what gets installed and what stays pinned.
[`Save-AppCsvOverlay`](../modules/configuration.md#save-appcsvoverlay) is the only thing that writes
an overlay, and **neither ever modifies a committed CSV**.

This is for app lists what `Configuration.local.psd1` is for settings: the tracked list stays the
shipped baseline upstream can keep improving, everything chosen for this machine lives beside it, so
a fork never edits a tracked CSV and pulling upstream never conflicts on an app choice. WinuX
gitignores the overlays for the same reason it gitignores `Configuration.local.psd1`.

An overlay uses the same columns as the list it sits beside, and the same rule that the **header is
line 1** with any comments after it - `Import-Csv` reads line 1 as the header unconditionally, so a
leading comment would be taken as the column names and every row below it would be discarded.

### Adding, overriding and removing an app

```csv
App,Version,Scope,Interactive,Source,Machine

# WinGetApps.local.csv - this machine's own app choices.
# Added: an App the committed list does not have
Obsidian.Obsidian,Latest,d,n,w,All
# Override: the same App as a committed row, so it replaces it (here to pin a version)
Microsoft.PowerShell,7.4.6,d,n,w,All
# Removed: a leading - opts this machine out of a shipped app
-Microsoft.PowerToys,Latest,d,n,w,All
```

- **Add** - a new `App` is appended after the shipped rows, so the committed install order is kept
  and your own apps follow it.
- **Override** - an `App` matching a committed row replaces that row in place, which is how you pin
  a version, change the `Scope`, or re-target the `Machine` column without touching the base list.
  Matching is case-insensitive, because package ids are.
- **Remove** - an `App` written as `-<id>` drops the committed row. This is the only way to opt out
  of a shipped app; commenting the row out in the committed CSV would edit a tracked file.
- A row whose `App` starts with `#` or is blank is ignored, in the overlay exactly as in the
  committed list. A header-only overlay is valid and changes nothing.
- If one overlay both removes and overrides the same `App`, the **removal wins**, whichever order
  the two rows are written in.

You can write an overlay by hand, or through `Save-AppCsvOverlay`, which validates every row before
it replaces anything (an empty `App`, a blank `Machine` cell, or an unknown machine token is refused,
because such a row would look installed and never install), keeps a `.bak` of the previous overlay,
and swaps the new one in atomically.

### Committing your overlays in a fork

WinuX gitignores `*.local.csv`, exactly as it gitignores `Configuration.local.psd1`: both are
personal, and upstream ships only the generic baseline. If you run several machines and want your
app choices to travel between them, **commit the overlays in your fork** - remove the ignore line
(or `git add -f` them). Upstream never tracks those paths, so committing them downstream never
conflicts on a pull. Ignore the writers' `.bak` files either way; they are noise.

## Shipped WinGet apps

The minimal set a WinuX install needs to work end-to-end - the framework apps only. All rows are
`Machine = All`:

| Software         | WinGet ID                   | Version                |
| ---------------- | --------------------------- | ---------------------- |
| PowerShell 7     | `Microsoft.PowerShell`      | Latest                 |
| Windows Terminal | `Microsoft.WindowsTerminal` | Latest                 |
| PowerToys        | `Microsoft.PowerToys`       | **Pinned to 0.100.2**  |

PowerToys is pinned because FancyZones is the backbone of the window layout system and updates can
silently break it; the pin - along with every other tested dependency version - is tracked in the
`TESTED VERSIONS` comment block at the top of `WinGetApps.csv` (the single source of truth).

### Recommended companions

These used to ship active but are not required by the framework, so they are now commented rows in
`WinGetApps.csv`. Opt in by copying a row (uncommented) into `WinGetApps.local.csv`:

```csv
JanDeDobbeleer.OhMyPosh,Latest,d,n,w,All
fastfetch,Latest,d,n,w,All
Microsoft.VisualStudioCode,Latest,d,n,w,All
Mozilla.Firefox,Latest,d,n,w,All
```

The profile uses Oh My Posh and fastfetch when they are present; fastfetch is skipped silently
when absent and Oh My Posh prints a single install hint.

## Installed outside the CSVs

| What                     | Installed by                                          |
| ------------------------ | ----------------------------------------------------- |
| Git                      | `Install-Git` (runs during `Install-Bootstrap`)       |
| JetBrainsMono Nerd Font  | `Configure-NerdFont` (bundled in the repository; opt-in - the base ships `NerdFonts` empty) |
| PowerShell modules below | `Install-PowerShellModules`                           |
| dotnet-ef                | `Install-DotnetEf` (skipped unless a .NET SDK exists) |

## PowerShell Modules

Installed via `Install-PowerShellModules`:

| Module           | Purpose                            |
| ---------------- | ---------------------------------- |
| `Terminal-Icons` | File/folder icons in terminal      |
| `PSReadLine`     | Advanced command-line editing      |
| `z`              | Smart directory jumping (frecency) |
| `VirtualDesktop` | Virtual desktop management (pinned 1.5.11; tracked in the `TESTED VERSIONS` block in `WinGetApps.csv`) |
| `ps2exe`         | Convert scripts to .exe            |
| `Pester`         | Testing framework                  |

## Adding your own software

Put it in the [machine-local overlay](#machine-local-overlay), never in the committed CSV. Some
common starting points, all `Machine = All`:

| Category                | Rows for `WinGetApps.local.csv`                                                                                                                                                       |
| ----------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Editors / dev toolchains | `Neovim.Neovim`, `Microsoft.VisualStudio.Community`, `Microsoft.DotNet.SDK.9`, `OpenJS.NodeJS.LTS`, `Python.Python.3.13`, `Docker.DockerDesktop`, `Oracle.VirtualBox`                 |
| CLI utilities            | `7zip.7zip`, `BurntSushi.ripgrep.MSVC`, `junegunn.fzf`, `ajeetdsouza.zoxide`, `sharkdp.fd`, `jqlang.jq`, `JesseDuffield.lazygit`                                                      |
| Apps                     | `Obsidian.Obsidian`, `Notepad++.Notepad++`, `VideoLAN.VLC`                                                                                                                            |

```csv
App,Version,Scope,Interactive,Source,Machine

Obsidian.Obsidian,Latest,d,n,w,All
BurntSushi.ripgrep.MSVC,Latest,d,n,w,All
```

`TorProject.TorBrowser` is the one worth calling out: it is what
[`Open-SecureBrowser`](../modules/application.md#open-securebrowser) needs, and the base bootstrap
does not install it. WinGet installs Tor Browser as a portable build onto the Desktop; move the
"Tor Browser" folder to `{User}\Tor Browser`, where the default `Universal.Browsers.Tor` entry
points.
