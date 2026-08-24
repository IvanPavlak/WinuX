# Restart-Explorer

Restarts Windows Explorer by stopping the `explorer.exe` process and waiting for it to auto-restart.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Restart-Explorer
Restart-Explorer -Message "Waiting for changes to apply..."
Restart-Explorer -Message "Processing..." -Delay 3
```

## Related

- [`Restart-Explorer` in the System module reference](../../../modules/system.md#restart-explorer) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
