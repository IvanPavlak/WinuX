# Start-FancyZones

Ensures PowerToys FancyZones is running and actually ready before returning success, with RPC health verification.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Start-FancyZones
Start-FancyZones -MaxWaitSeconds 15
Start-FancyZones -ForceRestart
```

## Related

- [`Start-FancyZones` in the Application module reference](../../../modules/application.md#start-fancyzones) - parameters, usage and behaviour
- [Application configuration guides](README.md) - every guide for this module
