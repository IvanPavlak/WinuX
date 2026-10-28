# ConvertTo-InternalDesktopIndex

Converts a 1-based layout desktop number (Desktop 1, 2, 3...) to the 0-based index used by the VirtualDesktop module, applying the workspace desktop offset via `(DesktopNumber - 1) + DesktopOffset`.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
ConvertTo-InternalDesktopIndex -DesktopNumber 1
ConvertTo-InternalDesktopIndex -DesktopNumber 1 -DesktopOffset 2
```

## Related

- [`ConvertTo-InternalDesktopIndex` in the Window module reference](../../../modules/window.md#convertto-internaldesktopindex) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
