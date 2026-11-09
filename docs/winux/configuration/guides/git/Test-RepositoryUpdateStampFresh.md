# Test-RepositoryUpdateStampFresh

Deprecated: tells whether the startup repository update ran recently enough to skip it - `$true` when the stamp file was written since the day began (Daily) or within the interval (Interval).

> [!WARNING]
> **Deprecated since 2.12.0, removed in 3.0.0.** The automatic repository update is a startup task now, and [`Test-StartupTaskDue`](../workflow/Test-StartupTaskDue.md) replaces this function (it answers the opposite question: `$true` when the task should run). This function keeps working unchanged until 3.0.0, but nothing calls it any more.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure. The schedule, day start hour and interval it is handed were the deprecated [`RepositoryUpdate.Startup`](../../configuration-reference.md#repository-update) keys; their replacement, one `Startup.Tasks` entry, is on the [`Invoke-StartupRepositoryUpdate`](Invoke-StartupRepositoryUpdate.md) guide.

## Usage

```powershell
# Deprecated. Since 2.12.0 the update no longer writes Logs\.last-repository-update, so pass the stamp of the startup task
$stamp = Join-Path (Get-LogPath -Directory) ".startup-task-RepositoryUpdate.stamp"
Test-RepositoryUpdateStampFresh -StampFile $stamp -DayStartHour 6
Test-RepositoryUpdateStampFresh -StampFile $stamp -Schedule Interval -IntervalHours 24

# The replacement ($true = due, the opposite of fresh)
Test-StartupTaskDue -StampFile $stamp -Frequency OncePerDay -DayStartHour 6
Test-StartupTaskDue -StampFile $stamp -Frequency Interval -IntervalHours 24
```

## Related

- [`Test-RepositoryUpdateStampFresh` in the Git module reference](../../../modules/git.md#test-repositoryupdatestampfresh) - parameters, usage and behaviour
- [`Test-StartupTaskDue`](../workflow/Test-StartupTaskDue.md) - the replacement
- [`Invoke-StartupRepositoryUpdate`](Invoke-StartupRepositoryUpdate.md) - the former caller, and the migration to a startup task
- [Git configuration guides](README.md) - every guide for this module
