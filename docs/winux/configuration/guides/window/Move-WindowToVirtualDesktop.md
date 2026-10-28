# Move-WindowToVirtualDesktop

Moves a window (identified by its handle) to the specified virtual desktop number.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Move-WindowToVirtualDesktop -WindowHandle $handle -DesktopNumber 0
Move-WindowToVirtualDesktop -WindowHandle $handle -DesktopNumber 1
```

## Related

- [`Move-WindowToVirtualDesktop` in the Window module reference](../../../modules/window.md#move-windowtovirtualdesktop) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
