# Resolve-MonitorLabel

Converts between a monitor's 0-based ordinal and its standardized label, in either direction.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Resolve-MonitorLabel -Index 2
Resolve-MonitorLabel -Label "Monitor3"
$entries | Sort-Object { Resolve-MonitorLabel -Label $_.Monitor }
```

## Related

- [`Resolve-MonitorLabel` in the Window module reference](../../../modules/window.md#resolve-monitorlabel) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
