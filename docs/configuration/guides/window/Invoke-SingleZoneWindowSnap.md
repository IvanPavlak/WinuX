# Invoke-SingleZoneWindowSnap

Snaps a window into a single-zone FancyZones layout through FancyZones' own mechanisms - clear a stale assignment, center the window in the zone at a deeper inset, `Win+Up`, shift-drag fallback - so the window ends up registered as zoned, not just positioned.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
$zone = Get-FancyZone -LayoutName "Zero" -ZoneName "Fullscreen" -MonitorWidth 3440 -MonitorHeight 1440
$result = Invoke-SingleZoneWindowSnap -WindowHandle $handle -TargetX $zone.X -TargetY $zone.Y -TargetWidth $zone.Width -TargetHeight $zone.Height
if ($result.Verified -and $result.Registered) { "snapped for real" }
```

## Related

- [`Invoke-SingleZoneWindowSnap` in the Window module reference](../../../modules/window.md#invoke-singlezonewindowsnap) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
