# Get-MonitorDeviceIdentityMap

Maps display device names (`\\.\DISPLAY1`) to the EDID code and PnP instance path FancyZones keys `applied-layouts.json` by.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
$identity = Get-MonitorDeviceIdentityMap
$identity.Edid['\\.\DISPLAY1']
$identity.Instance['\\.\DISPLAY1']
```

## Related

- [`Get-MonitorDeviceIdentityMap` in the Window module reference](../../../modules/window.md#get-monitordeviceidentitymap) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
