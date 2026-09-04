# Get-WorkspaceBenchmark

Reads the workspace benchmark back - one row per recorded workspace open with the seconds spent per layout phase, or a per-workspace summary - so a change to the open flow is judged by measured numbers.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-WorkspaceBenchmark | Format-Table -AutoSize
Get-WorkspaceBenchmark -Workspace MyWorkspace -Last 20 | Format-Table Timestamp, Attempts, TotalSeconds, FancyZonesSeconds, WaitSeconds, SnapSeconds
Get-WorkspaceBenchmark -Summary | Format-Table -AutoSize
```

## Related

- [`Get-WorkspaceBenchmark` in the Workflow module reference](../../../modules/workflow.md#get-workspacebenchmark)
- [Workflow configuration guides](README.md)
