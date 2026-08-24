# Reset-VirtualDesktopState

Restores a working VirtualDesktop session in place after the COM/RPC state has gone stale (the `0x800706BA` failure family an Explorer restart leaves behind).

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Reset-VirtualDesktopState
if (Reset-VirtualDesktopState) { Switch-Desktop -Desktop 0 }
```

## Related

- [`Reset-VirtualDesktopState` in the Window module reference](../../../modules/window.md#reset-virtualdesktopstate) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
