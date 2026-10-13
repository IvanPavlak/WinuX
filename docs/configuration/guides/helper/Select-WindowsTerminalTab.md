# Select-WindowsTerminalTab

Makes one Windows Terminal tab the active tab through UI Automation - no focus change, no keystrokes.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Select-WindowsTerminalTab -WindowHandle $wtWindow.Handle -TabTitle "MyProject.Api"
```

## Related

- [`Select-WindowsTerminalTab` in the Helper module reference](../../../modules/helper.md#select-windowsterminaltab) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module
