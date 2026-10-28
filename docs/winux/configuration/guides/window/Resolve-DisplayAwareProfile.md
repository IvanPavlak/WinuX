# Resolve-DisplayAwareProfile

The shared row resolver for configuration sections whose value depends on the display the windows will land on (`CenterTerminalSizing`, `ResizeWindowsPercent`).

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Resolve-DisplayAwareProfile -Section $global:Configuration.ResizeWindowsPercent
Resolve-DisplayAwareProfile -Section $sizing -MonitorInfo $monitors
```

## Related

- [`Resolve-DisplayAwareProfile` in the Window module reference](../../../modules/window.md#resolve-displayawareprofile) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
