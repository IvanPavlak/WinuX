# Get-WindowInsetPercent

Returns the pre-snap inset fraction every FancyZones placement path trims off each side of a target zone.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`SnapInsetPercent`](../../configuration-reference.md#snapinsetpercent) | double | `0.05` | How far in from the screen edge the five pre-snap placement paths inset a window, as a fraction. Read through `Get-WindowInsetPercent`. |

## Decisions

1. How much inset should pre-snap placement use?
    - Options: A fraction between 0 and 0.5. `0.05` is 5 percent.
    - Default: `0.05`.
    - More detail: [`SnapInsetPercent`](../../configuration-reference.md#snapinsetpercent)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `SnapInsetPercent`
2. Reload and confirm the merge landed

## Step 1: Set `SnapInsetPercent`

How far in from the screen edge the five pre-snap placement paths inset a window, as a fraction. Read through `Get-WindowInsetPercent`.

```powershell
SnapInsetPercent = 0.05
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.SnapInsetPercent
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.SnapInsetPercent
Get-WindowInsetPercent
$global:Configuration.SnapInsetPercent
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    SnapInsetPercent = 0.05
}
```

## Related

- [`Get-WindowInsetPercent` in the Window module reference](../../../modules/window.md#get-windowinsetpercent) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
- [Configure Window Layout](configure-window-layout.md) - the 3-layer layout system, zones and visualization
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
