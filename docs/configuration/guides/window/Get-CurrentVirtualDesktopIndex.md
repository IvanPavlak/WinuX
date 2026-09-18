# Get-CurrentVirtualDesktopIndex

Returns the 0-based index of the virtual desktop currently on screen, read through the Window module's seam so a stale COM session is reconnected first.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-CurrentVirtualDesktopIndex
$returnTo = Get-CurrentVirtualDesktopIndex
```

## Related

- [`Get-CurrentVirtualDesktopIndex` in the Window module reference](../../../modules/window.md#get-currentvirtualdesktopindex) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
