# Write-LogDebug

Writes a verbose-gated diagnostic message (DarkCyan by default).

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Write-LogDebug "Captured $n handle(s)"
Write-LogDebug "Using layout => [$file]" -Style Success
```

## Related

- [`Write-LogDebug` in the Logging module reference](../../../modules/logging.md#write-logdebug) - parameters, usage and behaviour
- [Logging configuration guides](README.md) - every guide for this module
