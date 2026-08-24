# Invoke-SingleZoneWindowPlacement

Places a window directly at a single-zone layout's zone rectangle (via `Set-WindowPosition`) and verifies the result with `Wait-WindowRect`, replacing the ambiguous FancyZones `Win+Up` snap for layouts that define exactly one zone.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
$zone = Get-FancyZone -LayoutName "Zero" -ZoneName "Fullscreen" -MonitorWidth 3440 -MonitorHeight 1440
Invoke-SingleZoneWindowPlacement -WindowHandle $handle -TargetX $zone.X -TargetY $zone.Y -TargetWidth $zone.Width -TargetHeight $zone.Height
```

## Related

- [`Invoke-SingleZoneWindowPlacement` in the Window module reference](../../../modules/window.md#invoke-singlezonewindowplacement) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
