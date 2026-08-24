# Get-WindowsTerminalTabTitles

Reads a Windows Terminal window's tab titles through UI Automation - no focus changes, no keystrokes.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-WindowsTerminalTabTitles -WindowHandle $wtWindow.Handle
```

## Related

- [`Get-WindowsTerminalTabTitles` in the Helper module reference](../../../modules/helper.md#get-windowsterminaltabtitles) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module
