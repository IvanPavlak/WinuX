# Get-TargetTerminalWindow

Locates a specific Windows Terminal window from an optional `IntPtr` handle, or returns the first available Windows Terminal window when no handle is given (or no window matches the supplied handle).

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-TargetTerminalWindow
Get-TargetTerminalWindow -TerminalWindowHandle $handle
```

## Related

- [`Get-TargetTerminalWindow` in the Helper module reference](../../../modules/helper.md#get-targetterminalwindow) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module
