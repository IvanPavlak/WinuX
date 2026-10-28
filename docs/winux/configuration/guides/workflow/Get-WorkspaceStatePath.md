# Get-WorkspaceStatePath

Resolves the path of the open-workspace tracker file - `Workflow\State\OpenWorkspaces.txt` inside the repository this function was loaded from - so neither the writer nor the reader has to know the folder depth and the two can never disagree.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-WorkspaceStatePath
Get-Content (Get-WorkspaceStatePath)
```

## Related

- [`Get-WorkspaceStatePath` in the Workflow module reference](../../../modules/workflow.md#get-workspacestatepath) - parameters, usage and behaviour
- [Workflow configuration guides](README.md) - every guide for this module
