# Get-WindowsTerminalWindow

Lists the Windows Terminal windows that hold tabs, leaving out Windows Terminal's own helper windows.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-WindowsTerminalWindow
Get-WindowsTerminalWindow | Select-Object -First 1
```

## Related

- [`Get-WindowsTerminalWindow` in the Helper module reference](../../../modules/helper.md#get-windowsterminalwindow) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module
