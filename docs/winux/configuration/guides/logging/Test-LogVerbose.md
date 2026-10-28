# Test-LogVerbose

Returns `$true` when verbose logging is active (`Set-LogLevel Verbose`, a scoped verbose command, or a global `$VerbosePreference = 'Continue'`).

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
if (Test-LogVerbose) { Write-LogDebug "diag" }
```

## Related

- [`Test-LogVerbose` in the Logging module reference](../../../modules/logging.md#test-logverbose) - parameters, usage and behaviour
- [Logging configuration guides](README.md) - every guide for this module
