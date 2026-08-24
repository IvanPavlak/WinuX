# Confirm-WorkspaceWindowPositions

Performs a final verification that every window defined in the layout config exists and is at its expected zone position.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Confirm-WorkspaceWindowPositions -LayoutConfig $config.Layout -MonitorInfo $monitorInfo -MonitorConfig $config.Monitors
Confirm-WorkspaceWindowPositions -LayoutConfig $config.Layout -MonitorInfo $monitorInfo -MonitorConfig $config.Monitors -DesktopOffset $DesktopOffset
```

## Related

- [`Confirm-WorkspaceWindowPositions` in the Window module reference](../../../modules/window.md#confirm-workspacewindowpositions) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
