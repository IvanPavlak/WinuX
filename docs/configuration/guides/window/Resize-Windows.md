# Resize-Windows

Resizes open windows either by a percentage (scaling each window's width and height while keeping its center point fixed) or to inset bounds within a target zone.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Resize-Windows
Resize-Windows -Percent 120
Resize-Windows -Percent 50 -ProcessName "chrome"
```

## Related

- [`Resize-Windows` in the Window module reference](../../../modules/window.md#resize-windows) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
