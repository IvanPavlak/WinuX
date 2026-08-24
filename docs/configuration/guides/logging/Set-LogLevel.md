# Set-LogLevel

Sets console verbosity for the logging engine - `Quiet` (Warning/Error only), `Normal` (default; Debug hidden), or `Verbose` (everything, including `Write-LogDebug`).

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Set-LogLevel Verbose
Set-LogLevel Verbose { Open-Workspace }
Set-LogLevel Normal
```

## Related

- [`Set-LogLevel` in the Logging module reference](../../../modules/logging.md#set-loglevel) - parameters, usage and behaviour
- [Logging configuration guides](README.md) - every guide for this module
