# Get-TerminalTabSnapshot

Captures the tab titles of every open Windows Terminal window as a hashtable keyed by window handle, so two calls can be differenced to learn which tabs a flow actually created.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-TerminalTabSnapshot
Get-TerminalTabSnapshot -EnsureVisible
```

## Related

- [`Get-TerminalTabSnapshot` in the Helper module reference](../../../modules/helper.md#get-terminaltabsnapshot) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module
