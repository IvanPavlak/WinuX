# Generate-DynamicVisualization

Dynamically generates an ASCII visualization for any grid-based layout.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
$visual = Generate-DynamicVisualization -LayoutInfo $layoutDef.info -ZoneContent $zoneContent -ZoneNames $zoneIndexToName
Generate-DynamicVisualization -LayoutInfo $layout.info -ZoneContent @{0 = @("Firefox", "YouTube")} -ZoneNames @{0 = "Top-Left"; 1 = "Top-Right"} -TotalWidth 80
```

## Related

- [`Generate-DynamicVisualization` in the Window module reference](../../../modules/window.md#generate-dynamicvisualization) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
