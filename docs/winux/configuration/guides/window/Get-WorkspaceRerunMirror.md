# Get-WorkspaceRerunMirror

Reads and consumes the persisted mirror of a workspace rerun marker written by `Set-WorkspaceRerunMirror`.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-WorkspaceRerunMirror -Name 'WORKSPACE_RERUN_COUNT'
Get-WorkspaceRerunMirror -Name 'WORKSPACE_RERUN_COUNT' -TtlMinutes 1
```

## Related

- [`Get-WorkspaceRerunMirror` in the Window module reference](../../../modules/window.md#get-workspacererunmirror) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
