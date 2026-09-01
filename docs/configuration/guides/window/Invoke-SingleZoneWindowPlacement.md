# Invoke-SingleZoneWindowPlacement

Places a window directly at a single-zone layout's zone rectangle (via `Set-WindowPosition`, grown by the window's frame margins so the visible window lands flush with the zone) and verifies the result with `Wait-WindowRect`. Direct placement bypasses FancyZones, so the window is not registered as zoned - it serves the simple-layout path (invisible desktops); the workspace flow snaps single-zone windows through `Invoke-SingleZoneWindowSnap` instead.

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
