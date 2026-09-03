# Send-FancyZonesLayoutShortcut

Sends the FancyZones `Win+Ctrl+Alt+[Number]` layout shortcut for the monitor at a given rectangle: cursor to the monitor's center, desktop window to the foreground, batched `SendInput`.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Send-FancyZonesLayoutShortcut -LayoutNumber 5 -MonitorX 0 -MonitorY 0 -MonitorWidth 3440 -MonitorHeight 1440
```

## Related

- [`Send-FancyZonesLayoutShortcut` in the Window module reference](../../../modules/window.md#send-fancyzoneslayoutshortcut) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
