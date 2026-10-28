# Read-WorkspaceOpenMeasurement

Reads `WorkspaceOpenMeasurements.csv` as typed rows, session by session in the order the opens ran - the read side shared by `Get-WorkspaceOpenMeasurement` and your own analysis of a `Measure-WorkspaceOpen` run.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Read-WorkspaceOpenMeasurement -Session 20260907-135804 | Format-Table Variant, Round, Outcome, TotalSeconds
Read-WorkspaceOpenMeasurement | Group-Object Session | Select-Object Name, Count
```

## Related

- [`Read-WorkspaceOpenMeasurement` in the Workflow module reference](../../../modules/workflow.md#read-workspaceopenmeasurement)
- [Workflow configuration guides](README.md)
