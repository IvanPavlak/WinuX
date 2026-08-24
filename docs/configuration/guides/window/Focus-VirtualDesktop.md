# Focus-VirtualDesktop

Switches to a virtual desktop and locks keyboard focus onto a window that lives there, used as the final `WorkspaceActions` step so a workspace run reliably lands the user on the first desktop.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Focus-VirtualDesktop
Focus-VirtualDesktop -DesktopNumber 1 -DesktopOffset 2
```

## Related

- [`Focus-VirtualDesktop` in the Window module reference](../../../modules/window.md#focus-virtualdesktop) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
