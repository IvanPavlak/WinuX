# Write-LogWarning

Writes a warning (Yellow), rendered as `` `n Message`` - a leading-space indent with **no** `=>` prefix (unlike success and error).

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Write-LogWarning "No layout configuration found for workspace => [GroupName]"
```

## Related

- [`Write-LogWarning` in the Logging module reference](../../../modules/logging.md#write-logwarning) - parameters, usage and behaviour
- [Logging configuration guides](README.md) - every guide for this module
