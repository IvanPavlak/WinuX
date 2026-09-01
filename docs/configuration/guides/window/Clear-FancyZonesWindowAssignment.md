# Clear-FancyZonesWindowAssignment

Removes FancyZones' zone-assignment marker from a window, so a stale assignment (which survives every programmatic move) cannot make the single-zone keyboard snap no-op or throw the window across monitors.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
if (Get-FancyZonesWindowAssignment -WindowHandle $handle) {
    $null = Clear-FancyZonesWindowAssignment -WindowHandle $handle
}
```

## Related

- [`Clear-FancyZonesWindowAssignment` in the Window module reference](../../../modules/window.md#clear-fancyzoneswindowassignment) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
