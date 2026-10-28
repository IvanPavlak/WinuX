# Get-FancyZonesWindowAssignment

Reads FancyZones' own zone-assignment marker for a window (the `FancyZones_zones` window property, a zone-index bitmask) - zero means the window is only positioned, not registered as snapped.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
$mask = Get-FancyZonesWindowAssignment -WindowHandle $handle
if ($mask -eq 0) { "window is only positioned, not snapped" }
```

## Related

- [`Get-FancyZonesWindowAssignment` in the Window module reference](../../../modules/window.md#get-fancyzoneswindowassignment) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
