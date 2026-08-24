# Move-Windows

Enumerates all visible application windows and moves each one to a specified virtual desktop (1-based; desktop 1 is the first).

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Move-Windows
Move-Windows -VirtualDesktop 2
Move-Windows -Current
```

## Related

- [`Move-Windows` in the Window module reference](../../../modules/window.md#move-windows) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
