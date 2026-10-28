# Test-FancyZonesLayoutApplied

Tests whether FancyZones currently has a layout applied for a given virtual desktop, optionally narrowed to a specific monitor.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Test-FancyZonesLayoutApplied -VirtualDesktopGuid $guid
Test-FancyZonesLayoutApplied -VirtualDesktopGuid $guid -MonitorId "LEN8ABC"
```

## Related

- [`Test-FancyZonesLayoutApplied` in the Window module reference](../../../modules/window.md#test-fancyzoneslayoutapplied) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
