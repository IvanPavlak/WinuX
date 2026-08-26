# Backups

Every WinuX function that overwrites or displaces an existing file first copies it into one
unified, OS-namespaced backup sink at the repository root:

```
<repo>\Backups\Windows\<Category>\<Key>\<yyyy-MM-dd_HH-mm-ss>\
```

One folder per key, one timestamped folder per replacement, so every version ever displaced sits
side by side with the newest last. The sink is gitignored (only `Backups\.gitkeep` is tracked):
the copies hold your own machine's data and possibly secrets, so they stay local and are never
committed. The OS namespace exists so a fork that also carries macOS or Linux tooling can give
each system its own sibling (`Backups\macOS\...`, `Backups\Linux\...`) without the sinks mixing.

All backups are taken by one primitive, [`Backup-RepositoryItem`](../configuration/guides/helper/Backup-RepositoryItem.md),
and pruned by one retention function, [`Clear-OldBackups`](../configuration/guides/helper/Clear-OldBackups.md).

## What lands where

| Category | Key | Written by | When |
| -------- | --- | ---------- | ---- |
| `SymbolicLinks` | The link's dotted config key (e.g. `PowerShell.Profile`) | `New-WindowsSymbolicLink`, `New-WSLSymbolicLink` (via `SymbolicLinkMaker`) | A **real** file or directory sits where a symlink must go. Existing symlinks are replaced without a backup - they carry no content of their own. |
| `Config` | `Configuration` | `Add-SymbolicLink`, `Add-BrowserGroup`, `Add-Workspace`, `Add-Project`, `Add-WindowLayout` | Before every write to the tracked base `Configuration.psd1`, so all five writers share one undo history. |
| `Config` | `Configuration.local` | `Initialize-Configuration -Force` | Before regenerating an existing `Configuration.local.psd1`. Also the path AI assistants use - see below. |
| `Config` | `<name>.local` (e.g. `WinGetApps.local`) | `Save-AppCsvOverlay` | Before replacing an existing app-list overlay (`-NoBackup` opts out). |
| `Config` | `WindowLayouts.<name>` | `Visualize-Layouts -Update` | Before rewriting a window-layout `.psd1`. |
| `System` | `TaskbarLayout` | `Configure-Taskbar`, `Unpin-TaskbarApps` | Before overwriting the machine's taskbar layout XML in `C:\ProgramData\provisioning\`. |
| `System` | `NuGetConfig` | `Configure-NuGetConfig` | Before overwriting an existing real `NuGet.Config` at the destination. |

## The contract: skip, never destroy

If a backup cannot be taken, the write it protects **does not happen**. The symlink writers skip
the link and leave the existing file alone; the configuration writers abort before touching the
file. A file that could not be saved is never removed. `Backup-RepositoryItem` also removes any
partially created backup folder before reporting failure, so the sink never holds a half-taken
backup that looks like a good restore point.

## Retention

The sink is bounded by [`Clear-OldBackups`](../configuration/guides/helper/Clear-OldBackups.md),
which the idle-time maintenance sweep (`Invoke-LogMaintenance`, the same one that prunes logs)
runs automatically. Three independent limits from `Configuration.psd1`'s `Backups.Retention`
section, each disabled by `0`:

| Key | Shipped default | What it does |
| --- | --------------- | ------------ |
| `MaxAgeDays` | `0` (never) | Delete backups older than this many days. Ships off - replaced originals are precious. |
| `MaxBackupsPerKey` | `10` | Keep at most this many timestamped backups per key, newest retained. Also enforced opportunistically right after every backup. |
| `MaxTotalSizeMB` | `500` | Cap the whole sink's combined size; oldest backups removed first. |

Whatever the limits, **the newest backup of every key is never deleted**. Backups taken by WinuX
versions older than the unified sink (directly under `Backups\SymbolicLinks`) sit outside the
scanned root and are never pruned.

## Restoring a backup

Find what you are looking for, newest last:

```powershell
Get-ChildItem (Join-Path (Get-RepositoryPath).Repo "Backups\Windows") -Recurse -Directory
```

Restore is one copy. For a file a symlink displaced, remove the link first:

```powershell
Remove-Item $PROFILE -Force
Copy-Item "<repo>\Backups\Windows\SymbolicLinks\PowerShell.Profile\<timestamp>\Microsoft.PowerShell_profile.ps1" $PROFILE
```

For a configuration file, copy straight over the current one:

```powershell
Copy-Item "<repo>\Backups\Windows\Config\Configuration.local\<timestamp>\Configuration.local.psd1" `
    (Join-Path (Get-RepositoryPath).PowerShell "Configuration.local.psd1")
```

## The AI-assistant convention

An AI assistant editing `Configuration.local.psd1` (the [WinuXConfigurator](../configuration/winux-configurator.md)
protocol, or any other agent) follows the same policy as the code: before its **first** write to
the file, it copies the existing file to
`Backups\Windows\Config\Configuration.local\<yyyy-MM-dd_HH-mm-ss>\` so there is a one-step way
back. An assistant that cannot create directories falls back to the legacy sidecar copy
`Configuration.local.psd1.bak` beside the file - that exact name stays gitignored for this reason.

## What this policy does not cover

- **Win11Debloat registry snapshots.** The vendored Win11Debloat tool keeps its own sink at
  `Windows\Win11Debloat\vendor\Backups\` with its own restore UI. It is third-party code and its
  internals are deliberately untouched; `Update-Win11DebloatVendor` preserves that folder across
  vendor updates.
- **Legacy sidecar `.bak` files.** Older WinuX versions left `Configuration.local.psd1.bak` and
  `Data\*.local.csv.bak` beside the files they backed up. The writers no longer produce them, but
  the gitignore entries remain so stale copies on existing machines (and the AI fallback above)
  can never be committed.
- **Backups as versioned artifacts.** Committing encrypted exports (password-manager vaults, NAS
  configs) into a private fork is a deliberate, separate pattern: those are tracked files managed
  by hand, not runtime copies, and no retention applies to them.

## Related

- [First Run](../getting-started/first-run.md#what-happens-to-a-file-already-sitting-at-a-link-path) - what a first install backs up and why
- [Troubleshooting](troubleshooting.md) - recovery recipes
- [`Backup-RepositoryItem`](../configuration/guides/helper/Backup-RepositoryItem.md) - the primitive every writer calls
- [`Clear-OldBackups`](../configuration/guides/helper/Clear-OldBackups.md) - the retention sweep
- [Repository Structure](../configuration/repository-structure.md) - where `Backups/` sits in the tree
