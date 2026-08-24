# Write-LogStep

Writes a plain step/progress statement (White), replacing the `Write-Host -ForegroundColor White` idiom.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Write-LogStep "Opening training file..."
Write-LogStep " ItemName => [enabled]" -Style Success
```

## Related

- [`Write-LogStep` in the Logging module reference](../../../modules/logging.md#write-logstep) - parameters, usage and behaviour
- [Logging configuration guides](README.md) - every guide for this module
