# Get-AppliedFancyZonesState

Reads (and briefly caches) the FancyZones `applied-layouts.json` file, which records the layout currently applied to each monitor on each virtual desktop.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
$state = Get-AppliedFancyZonesState
$freshState = Get-AppliedFancyZonesState -Force
```

## Related

- [`Get-AppliedFancyZonesState` in the Window module reference](../../../modules/window.md#get-appliedfancyzonesstate) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
