# New-WorkspaceLayoutPipelineState

Creates the shared state of one workspace layout pass - its inputs and the tallies the per-desktop passes fill in - for `Move-StableWindowEarly` and `Invoke-ReadyDesktopPass`.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
$pipeline = New-WorkspaceLayoutPipelineState -LayoutConfig $layout -Claims $claims -MonitorInfo $monitors -MonitorConfig $config.Monitors -DesktopCount 3
```

## Related

- [`New-WorkspaceLayoutPipelineState` in the Window module reference](../../../modules/window.md#new-workspacelayoutpipelinestate) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
