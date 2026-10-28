# Format-CanvasZoneListing

Renders a FancyZones canvas layout as a textual per-zone listing.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Format-CanvasZoneListing -LayoutInfo $layoutDef.info -ZoneContent @{} -ZoneNames @{ 0 = "Left" }
```

## Related

- [`Format-CanvasZoneListing` in the Window module reference](../../../modules/window.md#format-canvaszonelisting) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
