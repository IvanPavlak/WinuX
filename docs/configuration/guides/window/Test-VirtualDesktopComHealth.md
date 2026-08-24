# Test-VirtualDesktopComHealth

Probes THIS session's VirtualDesktop COM state with a live roundtrip (`[VirtualDesktop.Desktop]::Count`) on a background runspace inside the current process, under a hard timeout.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Test-VirtualDesktopComHealth
$probe = Test-VirtualDesktopComHealth -TimeoutMs 2500
```

## Related

- [`Test-VirtualDesktopComHealth` in the Window module reference](../../../modules/window.md#test-virtualdesktopcomhealth) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
