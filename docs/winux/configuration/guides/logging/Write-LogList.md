# Write-LogList

Writes a bulleted list of items (`  • <item>`, White) directly beneath a preceding summary line, with no leading blank line so the list sits under it.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Write-LogSuccess "Centered 2 window(s)!"; Write-LogList @("Windows Terminal", "Firefox")
```

## Related

- [`Write-LogList` in the Logging module reference](../../../modules/logging.md#write-loglist) - parameters, usage and behaviour
- [Logging configuration guides](README.md) - every guide for this module
