# Generate-LayoutVisualization

Generates an ASCII art visualization of a FancyZones layout, showing which processes and windows are assigned to each zone.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`ZoneNameMappings`](../../configuration-reference.md#layout-numbers--zone-mappings) | hashtable of layout name to zone-name map | hashtable, 10 keys | Human-readable zone names per FancyZones layout - what lets a layout file say `Zone = "Left"` instead of an index. `Get-FancyZone`, `Visualize-Layouts` and `Update-LayoutSectionHeaders` all read it. |

## Decisions

1. What should the zones in each of your layouts be called?
    - Options: Layout name to `@{ <ZoneName> = <index> }`. Run `Visualize-Layouts` to see the current mapping drawn out, and see [Configure Window Layout](../window/configure-window-layout.md) for the 3-layer system.
    - Default: The shipped mapping for layouts `One` .. `Ten`.
    - More detail: [`ZoneNameMappings`](../../configuration-reference.md#layout-numbers--zone-mappings)
2. Did you change a FancyZones layout in PowerToys?
    - Options: Then update its zone map here too, or layout files will place windows in the wrong zone.
    - Default: No change.
    - More detail: [`ZoneNameMappings`](../../configuration-reference.md#layout-numbers--zone-mappings)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `ZoneNameMappings`
2. Reload and confirm the merge landed

## Step 1: Set `ZoneNameMappings`

Human-readable zone names per FancyZones layout - what lets a layout file say `Zone = "Left"` instead of an index. `Get-FancyZone`, `Visualize-Layouts` and `Update-LayoutSectionHeaders` all read it.

```powershell
ZoneNameMappings = @{
    Two = @{ Left = 0; Right = 1 }
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.ZoneNameMappings
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.ZoneNameMappings
Visualize-Layouts
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    ZoneNameMappings = @{
        Two = @{ Left = 0; Right = 1 }
    }
}
```

## Related

- [`Generate-LayoutVisualization` in the Window module reference](../../../modules/window.md#generate-layoutvisualization) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
- [Configure Window Layout](configure-window-layout.md) - the 3-layer layout system, zones and visualization
- [`Get-FancyZone`](Get-FancyZone.md) - reads the same configuration
- [`Test-FancyZonesConfiguration`](Test-FancyZonesConfiguration.md) - reads the same configuration
- [`Update-LayoutSectionHeaders`](Update-LayoutSectionHeaders.md) - reads the same configuration
- [`Visualize-Layouts`](Visualize-Layouts.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
