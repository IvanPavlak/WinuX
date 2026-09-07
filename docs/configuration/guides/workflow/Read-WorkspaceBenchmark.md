# Read-WorkspaceBenchmark

Reads `WorkspaceBenchmark.csv` as typed rows, oldest first - the read side shared by `Get-WorkspaceBenchmark` and `Measure-WorkspaceOpen`.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Read-WorkspaceBenchmark | Where-Object Workspace -eq MyWorkspace | Select-Object -Last 1
@(Read-WorkspaceBenchmark).Count
```

## Related

- [`Read-WorkspaceBenchmark` in the Workflow module reference](../../../modules/workflow.md#read-workspacebenchmark)
- [Workflow configuration guides](README.md)
