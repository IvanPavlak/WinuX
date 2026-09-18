# Resolve-TerminalGreetingSettings

Resolves the settings `Show-TerminalGreeting` and its three steps run with: per key, an explicit parameter beats the `TerminalGreeting` configuration section, which beats the built-in default. Out-of-range or non-integer values are reported with a warning and replaced by the default for that key.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships the framework defaults, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`TerminalGreeting`](../../configuration-reference.md#terminal-greeting-startup-and-the-c-alias) | hashtable, 3 branches | `Clear` on, `Fastfetch` on (auto-fit on, `10` / `10` / `1`), `Onefetch` off (and its `Style` off) | The section this function reads by default. A `$null` or missing key means "use the built-in default" silently; a value out of range (`MaxShrinkSteps` 0-50, `ReflowTimeoutMilliseconds` any positive integer, `PromptReserve` 0-20) or not an integer warns and uses the default. A missing section behaves exactly like the shipped values. |

The decisions themselves - which steps run, how far to shrink, how long to wait, how many rows to reserve, what onefetch gets - are walked in the [`Show-TerminalGreeting` guide](Show-TerminalGreeting.md). This function is the resolver behind them; you call it directly to see what `c` would run with under the current configuration.

## Decisions

1. Which layer should win?
    - Options: Configure the section for every call, or pass `-MaxShrinkSteps` / `-ReflowTimeoutMilliseconds` / `-PromptReserve` to `Show-TerminalGreeting` (or to this function) for one call. Only the parameters actually passed override; an unpassed one leaves the configured value alone. The boolean flags and `Arguments` have no parameter form here - per-call, those are the `-NoClear` / `-NoFastfetch` / `-NoOnefetch` switches on the orchestrator and `-Arguments` on `Invoke-Onefetch`.
    - Default: The base section - clear on, fastfetch on with the fit at `10` / `10` / `1`, onefetch off - the same values the function falls back to when the section is missing.
    - More detail: [`TerminalGreeting`](../../configuration-reference.md#terminal-greeting-startup-and-the-c-alias)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so setting one key leaves every other key in the section at the base value. **Scalars replace wholesale.** **Arrays replace wholesale**, which applies to `Onefetch.Arguments`.

## Steps Overview

1. Set `TerminalGreeting`
2. Reload and confirm the merge landed

## Step 1: Set `TerminalGreeting`

Only the keys you change.

```powershell
TerminalGreeting = @{
    Onefetch = @{
        Enabled = $true
    }
}
```

## Step 2: Reload and confirm the merge landed

```powershell
Reload-PowerShellProfile
Resolve-TerminalGreetingSettings
```

## Usage

```powershell
Resolve-TerminalGreetingSettings
Resolve-TerminalGreetingSettings -MaxShrinkSteps 0
Resolve-TerminalGreetingSettings -Settings @{ Onefetch = @{ Enabled = $true } }
(Resolve-TerminalGreetingSettings).Fastfetch.AutoFit
Set-LogLevel Verbose { Resolve-TerminalGreetingSettings }
```

## Verification

Read-only checks. None of these change anything.

```powershell
$global:Configuration.TerminalGreeting
Resolve-TerminalGreetingSettings
(Resolve-TerminalGreetingSettings).Onefetch
Set-LogLevel Verbose { Resolve-TerminalGreetingSettings }
```

The verbose form names the layer each key came from (`default`, `configuration` or `parameter`), one line per key. A `Configuration.TerminalGreeting.<Path> must be ...` warning means the local value is out of range or not an integer and the default was used; a `-<Key> must be ...` warning means an explicit parameter was, and the configured (or default) value was kept.

## Complete Example

```powershell
# Configuration.local.psd1
@{
    TerminalGreeting = @{
        Fastfetch = @{
            AutoFit = @{
                MaxShrinkSteps            = 3
                ReflowTimeoutMilliseconds = 150
                PromptReserve             = 2
            }
        }
        Onefetch  = @{
            Enabled   = $true
            Arguments = @("--no-art")
            Style     = @{
                Enabled   = $true
                Separator = " -> "
                Colors    = @{ "12" = "38;2;30;144;255" }
            }
        }
    }
}
```

## Related

- [`Resolve-TerminalGreetingSettings` in the System module reference](../../../modules/system.md#resolve-terminalgreetingsettings) - parameters, the resolved tree, layering and behaviour
- [`Show-TerminalGreeting`](Show-TerminalGreeting.md) - the caller, and the decisions behind each key
- [`Invoke-Clear`](Invoke-Clear.md), [`Invoke-Fastfetch`](Invoke-Fastfetch.md), [`Invoke-Onefetch`](Invoke-Onefetch.md) - the three steps it settles the values for
- [`Format-OnefetchPanel`](Format-OnefetchPanel.md) - the consumer of the `Onefetch.Style` branch it resolves
- [System configuration guides](README.md) - every guide for this module
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
