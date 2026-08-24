# Center-Terminal

Centers the Windows Terminal on the primary monitor at a physically-constant size.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`CenterTerminalSizing`](../../configuration-reference.md#centerterminalsizing) | hashtable of profile name to sizing rules | hashtable, 1 key (`Default`) | How large `Center-Terminal` makes the terminal, per display profile. `Resolve-CenterTerminalSizing` picks the profile from the attached monitors, falling back to `Default`. |

## Decisions

1. How large should a centred terminal be on this machine?
    - Options: A percentage-of-screen pair under a profile name. Add a named profile for a second monitor setup and keep `Default` as the fallback.
    - Default: The shipped `Default` profile.
    - More detail: [`CenterTerminalSizing`](../../configuration-reference.md#centerterminalsizing)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `CenterTerminalSizing`
2. Reload and confirm the merge landed

## Step 1: Set `CenterTerminalSizing`

How large `Center-Terminal` makes the terminal, per display profile. `Resolve-CenterTerminalSizing` picks the profile from the attached monitors, falling back to `Default`.

```powershell
CenterTerminalSizing = @{
    Default = @{ WidthPercent = 60; HeightPercent = 70 }
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.CenterTerminalSizing
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.CenterTerminalSizing
$global:Configuration.CenterTerminalSizing | ConvertTo-Json -Depth 3
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    CenterTerminalSizing = @{
        Default = @{ WidthPercent = 60; HeightPercent = 70 }
    }
}
```

## Related

- [`Center-Terminal` in the Window module reference](../../../modules/window.md#center-terminal) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
- [Configure Window Layout](configure-window-layout.md) - the 3-layer layout system, zones and visualization
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
