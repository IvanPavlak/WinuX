# Save-WorkspaceState

Records what an `Open-Workspace` invocation actually opened, so `Close-Workspace` can close it.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Save-WorkspaceState -Workspace 'Server' -ExistingWindowHandles $before -ExistingTerminalTabs $tabsBefore
Save-WorkspaceState -Entry $survivingEntries
```

## Related

- [`Save-WorkspaceState` in the Workflow module reference](../../../modules/workflow.md#save-workspacestate) - parameters, usage and behaviour
- [Workflow configuration guides](README.md) - every guide for this module
