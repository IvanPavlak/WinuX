# Start-Logging

Begins PowerShell transcript logging to a timestamped `BootstrapLog_<yyyy-MM-dd_HH-mm-ss>.log` file on the Desktop (location preserved for fresh-machine parity), sets the global `$logPath`/`$startTime`, and opens a structured logging session so `Write-Log*` output is mirrored to the `Logs/` folder.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Start-Logging
```

## Related

- [`Start-Logging` in the Logging module reference](../../../modules/logging.md#start-logging) - parameters, usage and behaviour
- [Logging configuration guides](README.md) - every guide for this module
