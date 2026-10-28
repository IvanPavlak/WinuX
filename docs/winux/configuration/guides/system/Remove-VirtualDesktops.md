# Remove-VirtualDesktops

Removes virtual desktops - by default all except desktop 0, resetting to a single-desktop state.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Remove-VirtualDesktops
Remove-VirtualDesktops -EmptyOnly
Remove-VirtualDesktops -Index 3, 4, 5
```

## Related

- [`Remove-VirtualDesktops` in the System module reference](../../../modules/system.md#remove-virtualdesktops) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
