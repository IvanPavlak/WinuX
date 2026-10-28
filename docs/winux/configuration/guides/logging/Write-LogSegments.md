# Write-LogSegments

Writes one console line made of differently colored segments, mirrored to the session log as one line.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure. The colors come from the palette [`Initialize-LoggingState`](Initialize-LoggingState.md) builds from `Logging.Colors`.

## Usage

```powershell
Write-LogSegments @(@{ Text = "=> Totals => " }, @{ Text = "3 passed"; Style = "Success" }, @{ Text = ", " }, @{ Text = "1 failed"; Style = "Error" })
```

## Related

- [`Write-LogSegments` in the Logging module reference](../../../modules/logging.md#write-logsegments) - parameters, usage and behaviour
- [Logging configuration guides](README.md) - every guide for this module
