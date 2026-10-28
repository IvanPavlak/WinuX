# Get-WorkspaceOpenMeasurement

Replays the summary table of a `Measure-WorkspaceOpen` session from `WorkspaceOpenMeasurements.csv` - the most recent session by default, any session by id - or lists the recorded sessions, so the table is never lost with the terminal scrollback.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-WorkspaceOpenMeasurement -Formatted
Get-WorkspaceOpenMeasurement -ListSessions -Formatted
Get-WorkspaceOpenMeasurement -Session 20260907-135804 -Formatted
(Get-WorkspaceOpenMeasurement -PassThru).Runs | Format-Table Variant, Round, Outcome, Attempts, TotalSeconds
```

## Related

- [`Get-WorkspaceOpenMeasurement` in the Workflow module reference](../../../modules/workflow.md#get-workspaceopenmeasurement)
- [`Measure-WorkspaceOpen`](Measure-WorkspaceOpen.md) - the experiment whose sessions this replays
- [Workflow configuration guides](README.md)
