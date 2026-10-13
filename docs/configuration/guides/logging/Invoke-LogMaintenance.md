# Invoke-LogMaintenance

Periodic, silent housekeeping sweep over the repository's generated state: session logs, the unified backup sink, and stale test-run artifacts.

> [!NOTE]
> The same sweep also enforces backup retention over `Backups\Windows` through [`Clear-OldBackups`](../helper/Clear-OldBackups.md), whose limits come from the separate `Backups.Retention` section (see [Backups](../../../reference/backups.md)).

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`Logging`](../../configuration-reference.md#more-sections-quick-reference) | hashtable, 4 keys | `@{ DefaultLevel = "Normal"; Colors; FileLogging; Maintenance }` | This function reads `Logging.Maintenance` - `Enabled` (`$true`) switches the automatic idle-time sweep on or off, and `IntervalHours` (`24`) is the minimum gap between sweeps. The session-log limits it enforces through `Clear-OldLogs` come from `Logging.FileLogging.Retention`, covered on the [`Initialize-LoggingState`](Initialize-LoggingState.md) page. |

## Decisions

1. Should the housekeeping sweep run automatically?
    - Options: `Maintenance.Enabled = $true` runs it from the profile once the shell is idle; `$false` opts out, and the sweep then only runs when you call `Invoke-LogMaintenance -Force` (`-Force` also ignores the interval).
    - Default: `$true`.
    - More detail: [`Logging`](../../configuration-reference.md#more-sections-quick-reference)
2. How often should it run?
    - Options: Any whole number of hours under `Maintenance.IntervalHours`. The sweep is throttled by the stamp file `Logs\.last-maintenance`, so a shell opened inside the interval skips it in about a millisecond.
    - Default: `24`.
    - More detail: [`Logging`](../../configuration-reference.md#more-sections-quick-reference)
3. How long should old session logs be kept?
    - Options: The `FileLogging.Retention` limits (`MaxAgeDays`, `MaxSessionFiles`, `MaxTotalSizeMB`, `MaxErrorFileSizeMB`), which the sweep applies through `Clear-OldLogs`. The `Tests\Results` pruning (newest ten run logs, orphaned XMLs and abandoned `Work\` folders older than a day) is fixed and has no setting.
    - Default: 7 days, 20 session files, 50 MB of session logs, and an error log trimmed past 5 MB.
    - More detail: [`Logging`](../../configuration-reference.md#more-sections-quick-reference)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `Logging`
2. Reload and confirm the merge landed

## Step 1: Set `Logging`

`Logging.Maintenance` switches the automatic idle-time sweep on or off and sets the minimum hours between sweeps; `Logging.FileLogging.Retention` sets the session-log limits the sweep enforces.

```powershell
Logging = @{
    Maintenance = @{ Enabled = $true; IntervalHours = 12 }
    FileLogging = @{ Retention = @{ MaxAgeDays = 14 } }
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.Logging
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.Logging
$global:Configuration.Logging.Maintenance
$global:Configuration.Logging.Maintenance | ConvertTo-Json -Depth 3
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    Logging = @{
        Maintenance = @{
            Enabled       = $true
            IntervalHours = 12
        }
        FileLogging = @{
            Retention = @{
                MaxAgeDays         = 14
                MaxSessionFiles    = 40
                MaxTotalSizeMB     = 100
                MaxErrorFileSizeMB = 5
            }
        }
    }
}
```

## Related

- [`Invoke-LogMaintenance` in the Logging module reference](../../../modules/logging.md#invoke-logmaintenance) - parameters, usage and behaviour
- [Logging configuration guides](README.md) - every guide for this module
- [`Initialize-LoggingState`](Initialize-LoggingState.md) - reads the rest of `Logging`, including the retention limits
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
