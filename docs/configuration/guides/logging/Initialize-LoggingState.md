# Initialize-LoggingState

Initializes (or, with `-Force`, resets) the shared `$global:LoggingState` that the engine reads on every call: active verbosity level, color palette, file-logging toggle, and resolved session/error log paths.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`Logging`](../../configuration-reference.md#more-sections-quick-reference) | hashtable, 4 keys | `@{ DefaultLevel = "Normal"; Colors; FileLogging; Maintenance }` | Console verbosity at session start (`Quiet` / `Normal` / `Verbose`), the per-level console colours, file-logging settings, and the automatic idle-time log maintenance. Read by `Initialize-LoggingState` at profile load and by `Invoke-LogMaintenance`. |

This is the only place the `Logging` key is read at profile load, which is why the other 15 Logging functions have nothing to configure: `Write-Log*` and friends read the module state this function populated. Change `Logging` here, reload, and the whole module follows.

## Decisions

1. How chatty should a new session be?
    - Options: `Quiet`, `Normal` or `Verbose` under `DefaultLevel`. `Set-LogLevel` changes it for the current session without touching configuration.
    - Default: `Normal`.
    - More detail: [`Logging`](../../configuration-reference.md#more-sections-quick-reference)
2. Do you want session logs written to disk?
    - Options: The `FileLogging` sub-hashtable switches it on and sets retention. Logs land under the Logging module `Logs/` directory, which is gitignored.
    - Default: The shipped `FileLogging` settings.
    - More detail: [`Logging`](../../configuration-reference.md#more-sections-quick-reference)
3. How long should old logs be kept?
    - Options: The `Maintenance` sub-hashtable drives `Clear-OldLogs` through `Invoke-LogMaintenance`.
    - Default: The shipped retention.
    - More detail: [`Logging`](../../configuration-reference.md#more-sections-quick-reference)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `Logging`
2. Reload and confirm the merge landed

## Step 1: Set `Logging`

Console verbosity at session start (`Quiet` / `Normal` / `Verbose`), the per-level console colours, file-logging settings, and the automatic idle-time log maintenance. Read by `Initialize-LoggingState` at profile load and by `Invoke-LogMaintenance`.

```powershell
Logging = @{
    DefaultLevel = "Normal"
    FileLogging  = @{ Enabled = $true }
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
$global:Configuration.Logging | ConvertTo-Json -Depth 3
Write-Log "verification line"
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    Logging = @{
        DefaultLevel = "Normal"
        FileLogging  = @{ Enabled = $true }
    }
}
```

## Related

- [`Initialize-LoggingState` in the Logging module reference](../../../modules/logging.md#initialize-loggingstate) - parameters, usage and behaviour
- [Logging configuration guides](README.md) - every guide for this module
- [`Invoke-LogMaintenance`](Invoke-LogMaintenance.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
