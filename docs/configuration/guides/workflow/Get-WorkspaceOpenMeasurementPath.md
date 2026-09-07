# Get-WorkspaceOpenMeasurementPath

Resolves the path of the experiment result file - `WorkspaceOpenMeasurements.csv` beside `WorkspaceBenchmark.csv` - so `Measure-WorkspaceOpen` and `Get-WorkspaceOpenMeasurement` can never disagree about where the rows live.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-WorkspaceOpenMeasurementPath
Import-Csv (Get-WorkspaceOpenMeasurementPath)
```

## Related

- [`Get-WorkspaceOpenMeasurementPath` in the Workflow module reference](../../../modules/workflow.md#get-workspaceopenmeasurementpath)
- [Workflow configuration guides](README.md)
