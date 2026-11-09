# Start-StartupTaskShell

Starts the shell a startup task runs in - a terminal tab in the Windows Terminal window `WinuXStartup`, or a hidden shell - and returns without waiting for it.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure. Whether a task gets a tab or a hidden shell, and whether the tab stays open, are the `Window` and `KeepOpen` keys of a [`Startup.Tasks`](../../configuration-reference.md#startup-tasks) entry, configured on the [`Invoke-StartupTasks`](Invoke-StartupTasks.md) guide and passed in by [`Invoke-StartupTask`](Invoke-StartupTask.md).

## Usage

```powershell
# Not called by hand: Invoke-StartupTask calls it for a task whose Window is Tab or Hidden
$resultFile = Join-Path (Get-LogPath -Directory) ".startup-task-MyTask.result"
$arguments = @{ Name = "MyTask"; Command = "Open-Workspace MyWorkspace"; Window = "Current"; ResultFile = $resultFile }

Start-StartupTaskShell -Name MyTask -Arguments $arguments
Start-StartupTaskShell -Name MyTask -Arguments $arguments -Window Hidden
Start-StartupTaskShell -Name MyTask -Arguments $arguments -KeepOpen Always -Administrator
```

A tab loads the profile as any terminal does and closes itself according to `-KeepOpen`; a hidden shell loads the profile without its interactive stages, cannot ask a question, and exits when the task is over. `-Administrator` starts the shell elevated, which raises the Windows consent dialog unless the caller is elevated already; a declined dialog throws.

## Related

- [`Start-StartupTaskShell` in the Workflow module reference](../../../modules/workflow.md#start-startuptaskshell) - parameters, usage and behaviour
- [`Invoke-StartupTask`](Invoke-StartupTask.md) - the caller
- [`New-StartupTaskShellCommand`](New-StartupTaskShellCommand.md) - builds the command the new shell runs
- [`Wait-StartupTaskResult`](Wait-StartupTaskResult.md) - how the caller learns the result
- [`Open-Terminal`](../application/Open-Terminal.md) - opens the tab
- [Workflow configuration guides](README.md) - every guide for this module
