# Get-VisibleWindowProcess

Lists every process that owns at least one visible, titled application window, discovered window-side through `EnumWindows` - the candidate discovery behind `Terminate-AllProcessesWithVisibleWindows` and the `Kill-All` survivor audit. Shell windows and shell processes are never returned.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-VisibleWindowProcess | Format-Table ProcessName, Id, MainWindowTitle
Get-VisibleWindowProcess | Where-Object { $_.WindowTitles.Count -gt 1 }
```

## Related

- [`Get-VisibleWindowProcess` in the System module reference](../../../modules/system.md#getvisiblewindowprocess) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
