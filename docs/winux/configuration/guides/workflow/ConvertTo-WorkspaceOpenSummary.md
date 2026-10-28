# ConvertTo-WorkspaceOpenSummary

Turns the per-run rows of one `Measure-WorkspaceOpen` session into one summary per variant - runs, clean runs, retries, medians, and `Effect`/`Spread`/`Verdict` against a reference variant - the arithmetic shared by the live table and its replay.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Read-WorkspaceOpenMeasurement -Session 20260907-135804 | ConvertTo-WorkspaceOpenSummary | Format-Table -AutoSize
ConvertTo-WorkspaceOpenSummary -Row $rows -Reference 'ApplyMethod=Hotkeys'
```

## Related

- [`ConvertTo-WorkspaceOpenSummary` in the Workflow module reference](../../../modules/workflow.md#convertto-workspaceopensummary)
- [Workflow configuration guides](README.md)
