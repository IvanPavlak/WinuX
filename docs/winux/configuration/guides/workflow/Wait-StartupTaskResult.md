# Wait-StartupTaskResult

Waits for a startup task that runs in another shell - its own tab or a hidden shell - by reading the task's result file, and returns how it ended.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure. The time it waits is the `Timeout` key of a [`Startup.Tasks`](../../configuration-reference.md#startup-tasks) entry, configured on the [`Invoke-StartupTasks`](Invoke-StartupTasks.md) guide and passed in by its callers.

## Usage

```powershell
$resultFile = Join-Path (Get-LogPath -Directory) ".startup-task-MyTask.result"
Wait-StartupTaskResult -Name MyTask -ResultFile $resultFile -Timeout 120
Wait-StartupTaskResult -Name MyTask -ResultFile $resultFile -Timeout 0 -StampFile (Join-Path (Get-LogPath -Directory) ".startup-task-MyTask.stamp")
```

The returned object has `Name`, `Status`, `Reason` and `ResultFile`. The status is the task's own final status, or `Ended` when the task's shell closed before it reported one (a workspace that ends by closing its terminal tab does that; with `-StampFile` the stamp is then written as after a success), or `TimedOut` when `-Timeout` seconds passed. Nothing is stopped on a timeout: the task may still finish later and write its own stamp.

## Related

- [`Wait-StartupTaskResult` in the Workflow module reference](../../../modules/workflow.md#wait-startuptaskresult) - parameters, usage and behaviour
- [`Invoke-StartupTask`](Invoke-StartupTask.md) and [`Invoke-StartupTasks`](Invoke-StartupTasks.md) - the callers
- [`Start-StartupTaskShell`](Start-StartupTaskShell.md) - starts the shell this function waits for
- [Workflow configuration guides](README.md) - every guide for this module
