# Clear-OldLogs

Enforces log retention so the `Logs/` folder stays small but complete.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Clear-OldLogs
Clear-OldLogs -MaxSessionFiles 5
```

## Related

- [`Clear-OldLogs` in the Logging module reference](../../../modules/logging.md#clear-oldlogs) - parameters, usage and behaviour
- [Logging configuration guides](README.md) - every guide for this module
