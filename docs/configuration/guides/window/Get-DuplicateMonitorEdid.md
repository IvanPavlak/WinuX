# Get-DuplicateMonitorEdid

Returns the distinct EDID hardware codes that are shared by more than one display in a display-name-to-EDID map.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-DuplicateMonitorEdid -DisplayToEdidMap @{ '\\.\DISPLAY1' = 'AOCB316'; '\\.\DISPLAY2' = 'AOCB316' }
```

## Related

- [`Get-DuplicateMonitorEdid` in the Window module reference](../../../modules/window.md#get-duplicatemonitoredid) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
