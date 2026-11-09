# Test-StartupTaskDue

Tells whether a startup task should run now, given its frequency and its stamp file: `$true` when the task has not succeeded yet since the boot, since the day began or within the interval.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure. The frequency, day start hour and interval it is handed are the `Frequency`, `DayStartHour` and `IntervalHours` keys of a [`Startup.Tasks`](../../configuration-reference.md#startup-tasks) entry, configured on the [`Invoke-StartupTasks`](Invoke-StartupTasks.md) guide and passed in by [`Invoke-StartupTask`](Invoke-StartupTask.md).

## Usage

```powershell
Test-StartupTaskDue -StampFile (Join-Path (Get-LogPath -Directory) ".startup-task-MyTask.stamp") -Frequency OncePerDay
Test-StartupTaskDue -StampFile (Join-Path (Get-LogPath -Directory) ".startup-task-MyTask.stamp") -Frequency OncePerDay -DayStartHour 4
Test-StartupTaskDue -StampFile (Join-Path (Get-LogPath -Directory) ".startup-task-MyTask.stamp") -Frequency Interval -IntervalHours 4
Test-StartupTaskDue -StampFile (Join-Path (Get-LogPath -Directory) ".startup-task-MyTask.stamp") -Frequency OncePerBoot
```

A task writes its stamp only after a run that succeeded, so a missing stamp is always due, and a task that failed or was skipped is due again at the next trigger. `EveryTime` is always due and never reads the stamp. With Windows Fast Startup a shutdown is a hibernation, so `OncePerBoot` only counts a restart.

It replaces the deprecated [`Test-RepositoryUpdateStampFresh`](../git/Test-RepositoryUpdateStampFresh.md) and [`Get-RepositoryUpdateDayStart`](../git/Get-RepositoryUpdateDayStart.md).

## Related

- [`Test-StartupTaskDue` in the Workflow module reference](../../../modules/workflow.md#test-startuptaskdue) - parameters, usage and behaviour
- [`Invoke-StartupTask`](Invoke-StartupTask.md) - the caller
- [Workflow configuration guides](README.md) - every guide for this module
