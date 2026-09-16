# Resolve-FastfetchAutoFitSettings

Resolves the font auto-fit settings `Invoke-ClearAndFastfetch` runs with: per key, an explicit parameter beats the `FastfetchAutoFit` configuration section, which beats the built-in default. Out-of-range or non-integer values are reported with a warning and replaced by the default for that key.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships the framework defaults, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`FastfetchAutoFit`](../../configuration-reference.md#fastfetch-auto-fit-the-c-alias) | hashtable, 3 keys | `MaxShrinkSteps = 10`, `ReflowTimeoutMilliseconds = 10`, `PromptReserve = 1` | The section this function reads by default. A `$null` or missing key means "use the built-in default" silently; a value out of range (`MaxShrinkSteps` 0-50, `ReflowTimeoutMilliseconds` any positive integer, `PromptReserve` 0-20) or not an integer warns and uses the default. |

The decisions themselves - how far to shrink, how long to wait, how many rows to reserve - are walked in the [`Invoke-ClearAndFastfetch` guide](Invoke-ClearAndFastfetch.md). This function is the resolver behind them; you call it directly to see what `c` would run with under the current configuration.

## Decisions

1. Which layer should win?
    - Options: Configure the section for every call, or pass `-MaxShrinkSteps` / `-ReflowTimeoutMilliseconds` / `-PromptReserve` to `Invoke-ClearAndFastfetch` (or to this function) for one call. Only the parameters actually passed override; an unpassed one leaves the configured value alone.
    - Default: The base section - `10` / `10` / `1`, the same numbers the function falls back to when the section is missing.
    - More detail: [`FastfetchAutoFit`](../../configuration-reference.md#fastfetch-auto-fit-the-c-alias)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so setting one key under `FastfetchAutoFit` leaves the other two at the base values. **Scalars replace wholesale.** This section has no arrays.

## Steps Overview

1. Set `FastfetchAutoFit`
2. Reload and confirm the merge landed

## Step 1: Set `FastfetchAutoFit`

Only the keys you change.

```powershell
FastfetchAutoFit = @{
    MaxShrinkSteps = 3
}
```

## Step 2: Reload and confirm the merge landed

```powershell
Reload-PowerShellProfile
Resolve-FastfetchAutoFitSettings
```

## Usage

```powershell
Resolve-FastfetchAutoFitSettings
Resolve-FastfetchAutoFitSettings -MaxShrinkSteps 0
Resolve-FastfetchAutoFitSettings -Settings @{ PromptReserve = 2 }
Set-LogLevel Verbose { Resolve-FastfetchAutoFitSettings }
```

## Verification

Read-only checks. None of these change anything.

```powershell
$global:Configuration.FastfetchAutoFit
Resolve-FastfetchAutoFitSettings
Set-LogLevel Verbose { Resolve-FastfetchAutoFitSettings }
```

The verbose form names the layer each key came from (`default`, `configuration` or `parameter`). A `Configuration.FastfetchAutoFit.<Key> must be ...` warning means the local value is out of range or not an integer and the default was used; a `-<Key> must be ...` warning means an explicit parameter was, and the configured (or default) value was kept.

## Complete Example

```powershell
# Configuration.local.psd1
@{
    FastfetchAutoFit = @{
        MaxShrinkSteps            = 3
        ReflowTimeoutMilliseconds = 150
        PromptReserve             = 2
    }
}
```

## Related

- [`Resolve-FastfetchAutoFitSettings` in the System module reference](../../../modules/system.md#resolve-fastfetchautofitsettings) - parameters, layering and behaviour
- [`Invoke-ClearAndFastfetch`](Invoke-ClearAndFastfetch.md) - the caller, and the decisions behind each key
- [System configuration guides](README.md) - every guide for this module
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
