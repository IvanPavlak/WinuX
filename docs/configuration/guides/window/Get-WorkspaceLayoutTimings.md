# Get-WorkspaceLayoutTimings

Returns the phase timings the most recent `Set-WorkspaceWindowLayout` run in this session published - seconds per phase, attempt count and outcome - which `Open-Workspace` folds into the workspace benchmark row.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-WorkspaceLayoutTimings
(Get-WorkspaceLayoutTimings).Phases
```

## Related

- [`Get-WorkspaceLayoutTimings` in the Window module reference](../../../modules/window.md#get-workspacelayouttimings)
- [Window configuration guides](README.md)
