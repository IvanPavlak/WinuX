# Ensure-DesktopVisible

Brings a virtual desktop on screen - either a given index, or whichever desktop a given window lives on - and returns the index of the desktop that *was* visible so the caller can put the view back.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Ensure-DesktopVisible -WindowHandle $terminalHandle
Ensure-DesktopVisible -DesktopIndex 1
```

## Related

- [`Ensure-DesktopVisible` in the Window module reference](../../../modules/window.md#ensure-desktopvisible) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
