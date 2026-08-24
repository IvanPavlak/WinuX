# Wait-DesktopSwitch

Polls the current virtual desktop index (via the `VirtualDesktop` module) until it matches a target index, returning `$true` once the desktop is active or `$false` on timeout.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Wait-DesktopSwitch -TargetDesktopIndex 1
Wait-DesktopSwitch -TargetDesktopIndex 0 -TimeoutMs 1000
```

## Related

- [`Wait-DesktopSwitch` in the Window module reference](../../../modules/window.md#wait-desktopswitch) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
