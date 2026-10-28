# Initialize-LoggingState

Initializes (or, with `-Force`, resets) the shared `$global:LoggingState` that the engine reads on every call: active verbosity level, color palette, file-logging toggle, and resolved session/error log paths.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`Logging`](../../configuration-reference.md#more-sections-quick-reference) | hashtable, 4 keys | `@{ DefaultLevel = "Normal"; Colors; FileLogging; Maintenance }` | Console verbosity at session start (`Quiet` / `Normal` / `Verbose`), the per-level console colours (plus `Info`, Blue, which belongs to no level), file-logging settings, and the automatic idle-time log maintenance. Read by `Initialize-LoggingState` at profile load and by `Invoke-LogMaintenance`. |

This function reads `DefaultLevel`, `Colors` and `FileLogging` (`Enabled`, `Directory`, `ErrorFileName`) and keeps the whole `Logging` hashtable in the module state. The `Write-Log*` functions, `Get-LogPath` and `Protect-Log` read that state rather than configuration, which is why their guides have nothing to configure, and `Clear-OldLogs` takes its default limits from the `FileLogging.Retention` copy held there. `Maintenance` is the one sub-key read elsewhere, by [`Invoke-LogMaintenance`](Invoke-LogMaintenance.md). The state is built once per shell, so a changed `Logging` value takes effect in a new shell, or after `Initialize-LoggingState -Force` - `Reload-PowerShellProfile` alone keeps the existing state.

## Decisions

1. How chatty should a new session be?
    - Options: `Quiet`, `Normal` or `Verbose` under `DefaultLevel`. `Set-LogLevel` changes it for the current session without touching configuration.
    - Default: `Normal`.
    - More detail: [`Logging`](../../configuration-reference.md#more-sections-quick-reference)
2. Do you want different console colours?
    - Options: Override any of `Title`, `Step`, `Success`, `Warning`, `Error`, `Debug` or `Info` under `Colors` with a PowerShell console colour name. Only the entries you set change; the rest keep the house palette.
    - Default: The house palette (`Title` DarkCyan, `Step` White, `Success` Green, `Warning` Yellow, `Error` Red, `Debug` DarkCyan, `Info` Blue).
    - More detail: [`Logging`](../../configuration-reference.md#more-sections-quick-reference)
3. Do you want session logs written to disk, and where?
    - Options: `FileLogging.Enabled` switches file logging on or off; `FileLogging.Directory` moves the log folder (empty means the Logging module `Logs/` directory, which is gitignored); `FileLogging.ErrorFileName` renames the shared error log.
    - Default: Enabled, in the module `Logs/` folder, with the error log named `Errors.log`.
    - More detail: [`Logging`](../../configuration-reference.md#more-sections-quick-reference)
4. How long should old logs be kept?
    - Options: `FileLogging.Retention` - `MaxAgeDays`, `MaxSessionFiles`, `MaxTotalSizeMB` and `MaxErrorFileSizeMB`, enforced by `Clear-OldLogs` whenever `Stop-Logging` or the `Invoke-LogMaintenance` sweep runs. A value of `0` disables that one limit.
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

Console verbosity at session start (`Quiet` / `Normal` / `Verbose`), the per-level console colours (plus `Info`, Blue, which belongs to no level), and the file-logging settings, including retention. Set only the sub-keys you want to change - the hashtables deep-merge with the base values.

```powershell
Logging = @{
    DefaultLevel = "Normal"
    Colors       = @{ Debug = "DarkGray" }
    FileLogging  = @{
        Enabled   = $true
        Retention = @{ MaxAgeDays = 14; MaxSessionFiles = 40 }
    }
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it. The logging state itself is built once per shell, so open a new shell (or run `Initialize-LoggingState -Force`) for the new level, colours and file settings to apply.

```powershell
Reload-PowerShellProfile
$global:Configuration.Logging
```

## Verification

Read-only checks. None of these change anything.

```powershell
$global:Configuration.Logging | ConvertTo-Json -Depth 4
$global:LoggingState.Level
$global:LoggingState.Colors
Get-LogPath
Get-LogPath -ErrorLog
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    Logging = @{
        DefaultLevel = "Normal"
        Colors       = @{ Debug = "DarkGray" }
        FileLogging  = @{
            Enabled       = $true
            Directory     = ""             # empty => the module's own Logs/ folder
            ErrorFileName = "Errors.log"
            Retention     = @{
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

- [`Initialize-LoggingState` in the Logging module reference](../../../modules/logging.md#initialize-loggingstate) - parameters, usage and behaviour
- [Logging configuration guides](README.md) - every guide for this module
- [`Invoke-LogMaintenance`](Invoke-LogMaintenance.md) - reads `Logging.Maintenance`
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
