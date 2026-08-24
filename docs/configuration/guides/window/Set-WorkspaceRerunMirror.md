# Set-WorkspaceRerunMirror

Writes or clears the persisted mirror of a workspace rerun marker, stamped as `value|unix-timestamp` for `Get-WorkspaceRerunMirror` to age out.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Set-WorkspaceRerunMirror -Name 'WORKSPACE_RERUN_COUNT' -Value '1'
Set-WorkspaceRerunMirror -Name 'WORKSPACE_RERUN_COUNT' -Value $null
```

## Related

- [`Set-WorkspaceRerunMirror` in the Window module reference](../../../modules/window.md#set-workspacererunmirror) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
