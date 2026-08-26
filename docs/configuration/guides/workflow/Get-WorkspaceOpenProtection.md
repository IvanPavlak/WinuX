# Get-WorkspaceOpenProtection

Resolves what a plain workspace open must leave alone: tracked `-Alongside` workspaces that still have at least one live window, returned as their verbatim tracker entries plus the set of live window handles they own.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-WorkspaceOpenProtection
Get-WorkspaceOpenProtection -StatePath 'C:\path\to\OpenWorkspaces.txt'
```

## Related

- [`Get-WorkspaceOpenProtection` in the Workflow module reference](../../../modules/workflow.md#get-workspaceopenprotection) - parameters, usage and behaviour
- [Workflow configuration guides](README.md) - every guide for this module
