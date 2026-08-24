# Get-LogPath

Returns the path of the current structured session log, the shared error log, or the `Logs/` directory.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-Content (Get-LogPath) -Tail 40
Get-LogPath -ErrorLog
```

## Related

- [`Get-LogPath` in the Logging module reference](../../../modules/logging.md#get-logpath) - parameters, usage and behaviour
- [Logging configuration guides](README.md) - every guide for this module
