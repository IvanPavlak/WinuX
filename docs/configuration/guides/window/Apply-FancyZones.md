# Apply-FancyZones

Applies predefined FancyZones layouts to monitors by sending the `Win+Ctrl+Alt+[Number]` shortcut against a window positioned on each monitor.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`LayoutNumbers`](../../configuration-reference.md#layout-numbers--zone-mappings) | hashtable of name to FancyZones layout number | hashtable, 10 keys (`One` .. `Ten`) | Maps a readable layout name to the FancyZones custom-layout index `Apply-FancyZones` applies. |
| [`FancyZonesApplyMethod`](../../configuration-reference.md#layout-numbers--zone-mappings) | string, `File` or `Hotkeys` | `File` | Whether the layouts are written into FancyZones' `applied-layouts.json` (one write, one probe shortcut, no desktop switching, shortcut pass as the per-desktop fallback) or sent as `Win+Ctrl+Alt+[Number]` on every desktop. |

## Decisions

1. Do your FancyZones custom layouts sit at different indexes?
    - Options: Name to index. The names are what layout files and `Visualize-Layouts` use.
    - Default: The shipped `One` .. `Ten` mapping to 1 .. 10.
    - More detail: [`LayoutNumbers`](../../configuration-reference.md#layout-numbers--zone-mappings)
2. Should the layouts be written into `applied-layouts.json` or sent as shortcuts on every desktop?
    - Options: `File` or `Hotkeys`.
    - Default: `File`. Keep it; a desktop whose entry FancyZones does not take falls back to the shortcut pass on its own. Switch to `Hotkeys` only when a PowerToys update changes the file format or the file watcher.
    - More detail: [`FancyZonesApplyMethod`](../../configuration-reference.md#layout-numbers--zone-mappings)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `LayoutNumbers`
2. Choose `FancyZonesApplyMethod` (optional)
3. Reload and confirm the merge landed

## Step 1: Set `LayoutNumbers`

Maps a readable layout name to the FancyZones custom-layout index `Apply-FancyZones` applies.

```powershell
LayoutNumbers = @{
    One = 1
    Two = 2
}
```

## Step 2: Choose `FancyZonesApplyMethod` (optional)

`File` (the default) writes the workspace's zone layouts into FancyZones' `applied-layouts.json`, lets FancyZones reload the file and proves the reload with one probe shortcut, so a workspace open no longer switches through its desktops to apply layouts. `Hotkeys` is the previous desktop-switching shortcut pass. Only set the key to switch back:

```powershell
FancyZonesApplyMethod = 'Hotkeys'
```

## Step 3: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.LayoutNumbers
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.LayoutNumbers
$global:Configuration.FancyZonesApplyMethod
Test-FancyZonesConfiguration
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    LayoutNumbers = @{
        One = 1
        Two = 2
    }
    FancyZonesApplyMethod = 'File'
}
```

## Related

- [`Apply-FancyZones` in the Window module reference](../../../modules/window.md#apply-fancyzones) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
- [Configure Window Layout](configure-window-layout.md) - the 3-layer layout system, zones and visualization
- [`Get-FancyZoneCoordinates`](Get-FancyZoneCoordinates.md) - reads the same configuration
- [`Test-FancyZonesConfiguration`](Test-FancyZonesConfiguration.md) - reads the same configuration
- [`Visualize-Layouts`](Visualize-Layouts.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
