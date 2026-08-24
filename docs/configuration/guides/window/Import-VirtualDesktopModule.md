# Import-VirtualDesktopModule

Lazily imports the VirtualDesktop module with caching.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
if (Import-VirtualDesktopModule) { ... }
$hasModule = Import-VirtualDesktopModule -Silent
```

## Related

- [`Import-VirtualDesktopModule` in the Window module reference](../../../modules/window.md#import-virtualdesktopmodule) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
