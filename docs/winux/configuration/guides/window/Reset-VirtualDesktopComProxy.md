# Reset-VirtualDesktopComProxy

Reconnects the `VirtualDesktop` module's cached COM proxies to the current shell via reflection.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Reset-VirtualDesktopComProxy
if (Test-RpcUnavailableError $_) { [void](Reset-VirtualDesktopComProxy) }
```

## Related

- [`Reset-VirtualDesktopComProxy` in the Window module reference](../../../modules/window.md#reset-virtualdesktopcomproxy) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
