# Format-WorkspaceStateContent

Renders open-workspace tracker entries as the PowerShell data file `Get-WorkspaceState` reads back, so the tracker is parsed in restricted language mode (data only, never executed) exactly like the repository's layout and configuration `.psd1` files.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Set-Content -Path $path -Value (Format-WorkspaceStateContent -Entry $entries) -NoNewline
```

## Related

- [`Format-WorkspaceStateContent` in the Workflow module reference](../../../modules/workflow.md#format-workspacestatecontent) - parameters, usage and behaviour
- [Workflow configuration guides](README.md) - every guide for this module
