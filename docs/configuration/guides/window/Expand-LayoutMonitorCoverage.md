# Expand-LayoutMonitorCoverage

Extends a layout configuration's `Monitors` section to cover every attached monitor, cloning the per-desktop layouts of the first defined monitor as a template.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
$added = Expand-LayoutMonitorCoverage -Config $config -MonitorInfo $monitors
```

## Related

- [`Expand-LayoutMonitorCoverage` in the Window module reference](../../../modules/window.md#expand-layoutmonitorcoverage) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
