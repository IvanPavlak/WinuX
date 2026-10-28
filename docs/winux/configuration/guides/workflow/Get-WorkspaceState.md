# Get-WorkspaceState

Reads the open-workspace tracker written by `Save-WorkspaceState`, parsing it with the same `Import-PowerShellDataFile` used for layout and configuration `.psd1` files.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-WorkspaceState
Get-WorkspaceState -Workspace Server
```

## Related

- [`Get-WorkspaceState` in the Workflow module reference](../../../modules/workflow.md#get-workspacestate) - parameters, usage and behaviour
- [Workflow configuration guides](README.md) - every guide for this module
