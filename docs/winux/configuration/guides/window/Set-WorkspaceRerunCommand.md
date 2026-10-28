# Set-WorkspaceRerunCommand

Records (or clears) the exact `Open-Workspace` invocation of the open in progress, so a failure-path respawn reruns precisely that command. Module state on purpose - an environment variable would be inherited by every terminal tab the open spawns.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Set-WorkspaceRerunCommand -Command "Open-Workspace -Workspace 'WinuX'"
Set-WorkspaceRerunCommand -Clear
```

## Related

- [`Set-WorkspaceRerunCommand` in the Window module reference](../../../modules/window.md#set-workspacereruncommand) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
