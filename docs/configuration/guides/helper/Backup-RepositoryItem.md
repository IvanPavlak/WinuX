# Backup-RepositoryItem

Copies an item into the repository's unified backup sink (`<Repo>\Backups\Windows\<Category>\<Key>\<timestamp>\`) before a writer replaces it.

> [!NOTE]
> This is the single backup primitive every WinuX writer calls before overwriting or displacing an existing file. The sink is gitignored (it holds your machine's data, which may include secrets) and bounded by [`Clear-OldBackups`](Clear-OldBackups.md). If the backup cannot be taken, the function throws and the caller skips the replacement - a file that could not be saved is never removed. See [Backups](../../../reference/backups.md) for the full policy.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships with working defaults, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`Backups.Retention.MaxBackupsPerKey`](../../configuration-reference.md#backups) | int | `10` | After every successful backup, the key's own folder is pruned down to this many timestamped entries (newest kept). `0` disables the opportunistic prune; the full sweep in [`Clear-OldBackups`](Clear-OldBackups.md) still applies its own limits. |

## Decisions

1. How many versions of each replaced file should pile up per key?
    - Options: Any count; `10` keeps a healthy undo history without unbounded growth. `0` turns the per-backup prune off entirely.
    - Default: `10`.
    - More detail: [`Backups.Retention`](../../configuration-reference.md#backups)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `Backups.Retention.MaxBackupsPerKey`
2. Reload and confirm the merge landed

## Step 1: Set `Backups.Retention.MaxBackupsPerKey`

How many timestamped backups each key keeps after the opportunistic post-backup prune.

```powershell
Backups = @{
    Retention = @{
        MaxBackupsPerKey = 10
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
            MaxBackupsPerKey = 10
        }
    }
}
```

## Related

- [`Backup-RepositoryItem` in the Helper module reference](../../../modules/helper.md#backup-repositoryitem) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module
- [`Clear-OldBackups`](Clear-OldBackups.md) - the retention sweep over the same sink
- [Backups](../../../reference/backups.md) - the unified backup policy
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
