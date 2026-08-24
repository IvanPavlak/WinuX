# Resolve-CenteredWindowPercent

Resolves `Center-Windows` width/height percentages from a target pixel size.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Resolve-CenteredWindowPercent -WorkAreaWidth 3440 -WorkAreaHeight 1400 -TargetWidthPx 1376 -TargetHeightPx 700 -MinWidthPercent 25 -MaxWidthPercent 72 -MinHeightPercent 35 -MaxHeightPercent 75
```

## Related

- [`Resolve-CenteredWindowPercent` in the Window module reference](../../../modules/window.md#resolve-centeredwindowpercent) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
