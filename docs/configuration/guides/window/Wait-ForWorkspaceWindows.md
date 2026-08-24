# Wait-ForWorkspaceWindows

Waits for all expected windows from a workspace layout to be ready.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Wait-ForWorkspaceWindows -LayoutConfig $config.Layout
Wait-ForWorkspaceWindows -LayoutConfig $layout -TimeoutSeconds 30 -PollIntervalSeconds 0.5
Wait-ForWorkspaceWindows -LayoutConfig $layout -FocusWindows:$false
```

## Related

- [`Wait-ForWorkspaceWindows` in the Window module reference](../../../modules/window.md#wait-forworkspacewindows) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
