# Software List

Everything the base WinuX bootstrap installs, and where it comes from. The CSV files under
`Windows\PowerShell\Modules\Bootstrap\Data\` are the source of truth - each fork curates its
own lists (the CSVs are `merge=ours` fork-owned, so upstream pulls never overwrite them). This
page documents the shipped template.

## How installs are driven

| File                 | Manager    | Format                                         | Shipped active rows |
| -------------------- | ---------- | ---------------------------------------------- | ------------------- |
| `WinGetApps.csv`     | WinGet     | `App,Version,Scope,Interactive,Source,Machine` | 7                   |
| `ScoopApps.csv`      | Scoop      | `App,Version,Global,Machine`                   | 0                   |
| `ChocolateyApps.csv` | Chocolatey | `App,Version,Params,Force,Machine`             | 0                   |

- **Scope**: `d` (default), `m` (machine-wide), `u` (user). **Source**: `w` (winget), `s` (msstore).
- **Machine** is matched against the machine types you define in `Configuration.psd1` - only
  `All` is special, and `/` combines several types (`PC/Laptop`). The base config ships only `Test`.
- All three package managers are installed by Bootstrap even when their CSV is empty - add rows
  and re-run to install more.

## Shipped WinGet apps

The minimal set a WinuX install needs to work end-to-end. All rows are `Machine = All`:

| Software           | WinGet ID                    |
| ------------------ | ---------------------------- |
| Windows Terminal   | `Microsoft.WindowsTerminal`  |
| PowerShell 7       | `Microsoft.PowerShell`       |
| Oh My Posh         | `JanDeDobbeleer.OhMyPosh`    |
| fastfetch          | `fastfetch`                  |
| Visual Studio Code | `Microsoft.VisualStudioCode` |
| Mozilla Firefox    | `Mozilla.Firefox`            |
| PowerToys          | `Microsoft.PowerToys`        |

## Installed outside the CSVs

| What                     | Installed by                                          |
| ------------------------ | ----------------------------------------------------- |
| Git                      | `Install-Git` (runs during `Install-Bootstrap`)       |
| JetBrainsMono Nerd Font  | `Configure-NerdFont` (bundled in the repository)      |
| PowerShell modules below | `Install-PowerShellModules`                           |
| dotnet-ef                | `Install-DotnetEf` (skipped unless a .NET SDK exists) |

## PowerShell Modules

Installed via `Install-PowerShellModules`:

| Module           | Purpose                            |
| ---------------- | ---------------------------------- |
| `Terminal-Icons` | File/folder icons in terminal      |
| `PSReadLine`     | Advanced command-line editing      |
| `z`              | Smart directory jumping (frecency) |
| `VirtualDesktop` | Virtual desktop management (pinned 1.5.11) |
| `ps2exe`         | Convert scripts to .exe            |
| `Pester`         | Testing framework                  |

## Commented examples

`WinGetApps.csv` ships a block of commented example rows you can uncomment or use as patterns:
editors and dev toolchains (Neovim, Visual Studio Community, .NET SDK, Node.js, Python, Docker
Desktop, VirtualBox), CLI utilities (7zip, ripgrep, fzf, zoxide, fd, jq, lazygit), and apps
(Obsidian, Notepad++, VLC). It also carries a commented `TorProject.TorBrowser` row for
[`Open-SecureBrowser`](../modules/application.md#open-securebrowser) - WinGet installs Tor
Browser as a portable build onto the Desktop; move the "Tor Browser" folder to
`{User}\Tor Browser`, where the default `Universal.Browsers.Tor` entry points.
