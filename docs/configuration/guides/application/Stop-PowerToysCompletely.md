# Stop-PowerToysCompletely

Performs a complete PowerToys shutdown sequence that mirrors manual tray exit behavior, used by FancyZones recovery and restart flows.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Stop-PowerToysCompletely
Stop-PowerToysCompletely -PreferGracefulExit
Stop-PowerToysCompletely -PreferGracefulExit -MaxGracefulWaitMs 5000
```

## Related

- [`Stop-PowerToysCompletely` in the Application module reference](../../../modules/application.md#stop-powertoyscompletely) - parameters, usage and behaviour
- [Application configuration guides](README.md) - every guide for this module
