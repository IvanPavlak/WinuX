# Get-VirtualDesktopCount

Returns how many virtual desktops exist, read through the Window module's seam so a stale COM session is reconnected first.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-VirtualDesktopCount
$offset = Get-VirtualDesktopCount
```

## Related

- [`Get-VirtualDesktopCount` in the Window module reference](../../../modules/window.md#get-virtualdesktopcount) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
