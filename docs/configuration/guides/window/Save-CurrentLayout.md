# Save-CurrentLayout

Writes the most recently applied workspace layout to `Window\Layouts\CurrentLayout.txt` (read back by `Get-CurrentLayout`).

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Save-CurrentLayout -Workspace "Example_PC" -LayoutsDir $layoutsDir -MachineType "PC" -DesktopCount $requiredVirtualDesktops -MonitorConfig $config.Monitors -LayoutConfig $config.Layout
```

## Related

- [`Save-CurrentLayout` in the Window module reference](../../../modules/window.md#save-currentlayout) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
