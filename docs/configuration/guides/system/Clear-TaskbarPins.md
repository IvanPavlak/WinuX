# Clear-TaskbarPins

Clears all pinned taskbar items by removing the taskbar pin values from the `Taskband` registry key (`HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband`).

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Clear-TaskbarPins
Clear-TaskbarPins -SkipExplorerRestart
```

## Related

- [`Clear-TaskbarPins` in the System module reference](../../../modules/system.md#clear-taskbarpins) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
