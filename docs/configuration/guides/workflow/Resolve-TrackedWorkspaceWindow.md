# Resolve-TrackedWorkspaceWindow

Finds the live window a workspace tracker record refers to - by exact handle, then by a single-window process, then by process name plus exact title - for `Close-Workspace` and `Get-WorkspaceOpenProtection`.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Resolve-TrackedWorkspaceWindow -Record $record -LiveWindows (Get-WindowHandle)
```

## Related

- [`Resolve-TrackedWorkspaceWindow` in the Workflow module reference](../../../modules/workflow.md#resolve-trackedworkspacewindow) - parameters, usage and behaviour
- [Workflow configuration guides](README.md) - every guide for this module
