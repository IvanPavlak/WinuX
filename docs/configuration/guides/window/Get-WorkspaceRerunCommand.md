# Get-WorkspaceRerunCommand

Returns the exact `Open-Workspace` invocation recorded for the open in progress, or `$null`. `Set-WorkspaceWindowLayout` hands it to `ReRun-LastCommand -Command` when it escalates to a fresh shell.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
$command = Get-WorkspaceRerunCommand
if ($command) { ReRun-LastCommand -AutoAccept -Command $command }
```

## Related

- [`Get-WorkspaceRerunCommand` in the Window module reference](../../../modules/window.md#get-workspacereruncommand) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
