# Write-AppliedFancyZonesLayouts

Writes zone layouts for virtual desktops straight into FancyZones' `applied-layouts.json`, cloning each monitor's device block from an entry FancyZones wrote itself and preserving every other entry.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
$result = Write-AppliedFancyZonesLayouts -Targets @(
    @{ Monitor = 'DELA1A8'; MonitorInstance = '4&1cfdc60e&0&UID8262'; VirtualDesktop = '{413742B8-DC0B-4412-9D80-A2EAD2DE3829}'; LayoutName = 'Five' }
)
Write-AppliedFancyZonesLayouts -Targets $targets -Force
```

## Related

- [`Write-AppliedFancyZonesLayouts` in the Window module reference](../../../modules/window.md#write-appliedfancyzoneslayouts) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
