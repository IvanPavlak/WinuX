# Test-AppliedFancyZonesLayouts

Verifies that FancyZones' `applied-layouts.json` holds the wanted layout for each monitor/desktop target, optionally after waiting for FancyZones to rewrite the file.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
$check = Test-AppliedFancyZonesLayouts -Targets $written.Targets -WaitForWriteAfterUtc $written.WrittenAtUtc
Test-AppliedFancyZonesLayouts -Targets $targets -AppliedLayoutsPath $path
```

## Related

- [`Test-AppliedFancyZonesLayouts` in the Window module reference](../../../modules/window.md#test-appliedfancyzoneslayouts) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
