# Set-WindowLayouts

Applies a predefined window layout configuration.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Set-WindowLayouts -LayoutConfig $layout
Set-WindowLayouts -ConfigPath "<DevRoot>\MyLayouts\development.json"
Set-WindowLayouts -LayoutConfig $layout -MonitorInfo $monitors -MonitorConfig $config.Monitors
```

## Related

- [`Set-WindowLayouts` in the Window module reference](../../../modules/window.md#set-windowlayouts) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
