# Get-WorkspaceBenchmarkPath

Resolves the path of the workspace benchmark file - `WorkspaceBenchmark.csv` next to the session logs - so the writer and the reader of the benchmark can never disagree about where the rows live.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-WorkspaceBenchmarkPath
Import-Csv (Get-WorkspaceBenchmarkPath)
```

## Related

- [`Get-WorkspaceBenchmarkPath` in the Workflow module reference](../../../modules/workflow.md#get-workspacebenchmarkpath)
- [Workflow configuration guides](README.md)
