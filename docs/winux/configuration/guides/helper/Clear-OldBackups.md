# Clear-OldBackups

Enforces backup retention so `Backups\Windows` stays bounded but never loses the last copy of anything.

> [!NOTE]
> Unlike a log, a replaced original is not regenerable, so **the newest backup of every key is never deleted by any limit**. The sweep runs automatically from the same idle-time maintenance pass that prunes logs ([`Invoke-LogMaintenance`](../logging/Invoke-LogMaintenance.md)); it is safe to run manually at any time. See [Backups](../../../reference/backups.md) for the full policy.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships with working defaults, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`Backups.Retention.MaxAgeDays`](../../configuration-reference.md#backups) | int | `0` | Delete backups older than this many days. Ships `0` (never) - replaced originals are precious. |
| [`Backups.Retention.MaxBackupsPerKey`](../../configuration-reference.md#backups) | int | `10` | Keep at most this many timestamped backups per key, newest retained. `0` = unlimited. |
| [`Backups.Retention.MaxTotalSizeMB`](../../configuration-reference.md#backups) | int | `500` | Cap the whole sink's combined size; oldest backups removed first. `0` = uncapped. |

## Decisions

1. Should backups expire by age at all?
    - Options: `0` keeps everything regardless of age (shipped). A positive number of days prunes older backups, but a key's newest copy always survives.
    - Default: `0` - never.
    - More detail: [`Backups.Retention`](../../configuration-reference.md#backups)
2. How many versions per key, and how much disk overall?
    - Options: Any counts. The shipped `10` per key and `500` MB overall keep a deep undo history on a bounded footprint.
    - Default: `MaxBackupsPerKey = 10`, `MaxTotalSizeMB = 500`.
    - More detail: [`Backups.Retention`](../../configuration-reference.md#backups)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `Backups.Retention`
2. Reload and confirm the merge landed

## Step 1: Set `Backups.Retention`

The three limits, applied in order: age, per-key count, total size. Any limit set to `0` is disabled. Whatever you set, a key's newest backup is never removed.

```powershell
Backups = @{
    Retention = @{
        MaxAgeDays       = 0
        MaxBackupsPerKey = 10
        MaxTotalSizeMB   = 500
    }
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.Backups.Retention
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.Backups.Retention
Get-ChildItem (Join-Path (Get-RepositoryPath).Repo "Backups\Windows") -Recurse -Directory -ErrorAction SilentlyContinue
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    Backups = @{
        Retention = @{
            MaxAgeDays       = 0
            MaxBackupsPerKey = 10
            MaxTotalSizeMB   = 500
        }
    }
}
```

## Related

- [`Clear-OldBackups` in the Helper module reference](../../../modules/helper.md#clear-oldbackups) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module
- [`Backup-RepositoryItem`](Backup-RepositoryItem.md) - the writer that fills the same sink
- [`Invoke-LogMaintenance`](../logging/Invoke-LogMaintenance.md) - the idle-time sweep that runs this automatically
- [Backups](../../../reference/backups.md) - the unified backup policy
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
