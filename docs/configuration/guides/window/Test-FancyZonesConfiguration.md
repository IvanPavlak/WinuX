# Test-FancyZonesConfiguration

Validates the FancyZones configuration quartet against each other: `custom-layouts.json` internal consistency, `$Configuration.ZoneNameMappings`, `$Configuration.LayoutNumbers`, and `layout-hotkeys.json`.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`LayoutNumbers`](../../configuration-reference.md#layout-numbers--zone-mappings) | hashtable of name to FancyZones layout number | hashtable, 10 keys (`One` .. `Ten`) | Maps a readable layout name to the FancyZones custom-layout index `Apply-FancyZones` applies. |
| [`ZoneNameMappings`](../../configuration-reference.md#layout-numbers--zone-mappings) | hashtable of layout name to zone-name map | hashtable, 10 keys | Human-readable zone names per FancyZones layout - what lets a layout file say `Zone = "Left"` instead of an index. `Get-FancyZone`, `Visualize-Layouts` and `Update-LayoutSectionHeaders` all read it. |

## Decisions

1. Do your FancyZones custom layouts sit at different indexes?
    - Options: Name to index. The names are what layout files and `Visualize-Layouts` use.
    - Default: The shipped `One` .. `Ten` mapping to 1 .. 10.
    - More detail: [`LayoutNumbers`](../../configuration-reference.md#layout-numbers--zone-mappings)
2. What should the zones in each of your layouts be called?
    - Options: Layout name to `@{ <ZoneName> = <index> }`. Run `Visualize-Layouts` to see the current mapping drawn out, and see [Configure Window Layout](../window/configure-window-layout.md) for the 3-layer system.
    - Default: The shipped mapping for layouts `One` .. `Ten`.
    - More detail: [`ZoneNameMappings`](../../configuration-reference.md#layout-numbers--zone-mappings)
3. Did you change a FancyZones layout in PowerToys?
    - Options: Then update its zone map here too, or layout files will place windows in the wrong zone.
    - Default: No change.
    - More detail: [`ZoneNameMappings`](../../configuration-reference.md#layout-numbers--zone-mappings)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `LayoutNumbers`
2. Set `ZoneNameMappings`
3. Reload and confirm the merge landed

## Step 1: Set `LayoutNumbers`

Maps a readable layout name to the FancyZones custom-layout index `Apply-FancyZones` applies.

```powershell
LayoutNumbers = @{
    One = 1
    Two = 2
}
```

## Step 2: Set `ZoneNameMappings`

Human-readable zone names per FancyZones layout - what lets a layout file say `Zone = "Left"` instead of an index. `Get-FancyZone`, `Visualize-Layouts` and `Update-LayoutSectionHeaders` all read it.

```powershell
ZoneNameMappings = @{
    Two = @{ Left = 0; Right = 1 }
}
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
$global:Configuration.ZoneNameMappings
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
    ZoneNameMappings = @{
        Two = @{ Left = 0; Right = 1 }
    }
}
```

## Related

- [`Test-FancyZonesConfiguration` in the Window module reference](../../../modules/window.md#test-fancyzonesconfiguration) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
- [Configure Window Layout](configure-window-layout.md) - the 3-layer layout system, zones and visualization
- [`Apply-FancyZones`](Apply-FancyZones.md) - reads the same configuration
- [`Get-FancyZoneCoordinates`](Get-FancyZoneCoordinates.md) - reads the same configuration
- [`Visualize-Layouts`](Visualize-Layouts.md) - reads the same configuration
- [`Generate-LayoutVisualization`](Generate-LayoutVisualization.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
