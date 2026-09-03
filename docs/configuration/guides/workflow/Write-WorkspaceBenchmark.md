# Write-WorkspaceBenchmark

Records how long one workspace open took and where the time went - appends a row to the workspace benchmark file and prints a one-line `Timing =>` summary. `Open-Workspace` calls it once per workspace.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Write-WorkspaceBenchmark -Workspace MyWorkspace -TotalSeconds 27.5 -ActionTimings @(@{ Action = 'Open-Browser'; Seconds = 0.8 }) -LayoutTimings (Get-WorkspaceLayoutTimings)
Write-WorkspaceBenchmark -Workspace MyWorkspace -TotalSeconds 5.3 -Quiet -PassThru
```

## Related

- [`Write-WorkspaceBenchmark` in the Workflow module reference](../../../modules/workflow.md#write-workspacebenchmark)
- [Workflow configuration guides](README.md)
