# Ensure-VirtualDesktops

Ensures the specified number of virtual desktops exist, creating additional desktops when too few exist and removing the excess when too many exist.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Ensure-VirtualDesktops -Count 3
Ensure-VirtualDesktops -Count 3 -SwitchToDesktop 2
```

## Related

- [`Ensure-VirtualDesktops` in the Window module reference](../../../modules/window.md#ensure-virtualdesktops) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
