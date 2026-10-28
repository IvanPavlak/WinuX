# Switch-VirtualDesktop

Brings a virtual desktop on screen and confirms it is showing, retrying and falling back to a VirtualDesktop session reset before clearing the window cache.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Switch-VirtualDesktop -Index 2
if (-not (Switch-VirtualDesktop -Index 0)) { Write-LogError "Desktop 1 did not come on screen" }
Switch-VirtualDesktop -Index 1 -TimeoutMs 1000 -MaxAttempts 5
```

## Related

- [`Switch-VirtualDesktop` in the Window module reference](../../../modules/window.md#switch-virtualdesktop) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
