# Get-WindowFrameMargin

Measures the per-edge gap between a window's frame rectangle and the frame the user actually sees - the DWM invisible resize border. The zone rectangle grown by these margins is the exact frame rect a FancyZones snap produces, which is what `Invoke-SingleZoneWindowSnap` verifies against and `Invoke-SingleZoneWindowPlacement` places at.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
$margin = Get-WindowFrameMargin -WindowHandle $handle
$placeWidth = $zone.Width + $margin.Left + $margin.Right
```

## Related

- [`Get-WindowFrameMargin` in the Window module reference](../../../modules/window.md#get-windowframemargin) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
