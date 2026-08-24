# Write-LogError

Writes an error in the house `=> ` style (Red), mirrors it to the session log, and appends a verbose entry (message + exception + stack trace, when `-Exception` is supplied) to the shared error log so failures can always be inspected later.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Write-LogError "No solution file found!"
catch { Write-LogError "Build failed: $($_.Exception.Message)" -Exception $_ }
```

## Related

- [`Write-LogError` in the Logging module reference](../../../modules/logging.md#write-logerror) - parameters, usage and behaviour
- [Logging configuration guides](README.md) - every guide for this module
