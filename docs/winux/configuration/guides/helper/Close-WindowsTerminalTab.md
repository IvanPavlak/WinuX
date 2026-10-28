# Close-WindowsTerminalTab

Closes one Windows Terminal tab by exact title via its UI Automation close button - no focus changes, no keystrokes.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Close-WindowsTerminalTab -WindowHandle $wtWindow.Handle -TabTitle "MyProject.Api"
```

## Related

- [`Close-WindowsTerminalTab` in the Helper module reference](../../../modules/helper.md#close-windowsterminaltab) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module
