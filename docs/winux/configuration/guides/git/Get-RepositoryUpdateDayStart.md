# Get-RepositoryUpdateDayStart

Deprecated: returns when the current day began, for a day that starts at a given hour - the day boundary of the daily repository update.

> [!WARNING]
> **Deprecated since 2.12.0, removed in 3.0.0.** The automatic repository update is a startup task now, and [`Test-StartupTaskDue`](../workflow/Test-StartupTaskDue.md) replaces this function: it works out the day boundary itself for `-Frequency OncePerDay`. This function keeps working unchanged until 3.0.0.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure. The hour it is handed was the deprecated [`RepositoryUpdate.Startup.DayStartHour`](../../configuration-reference.md#repository-update); its replacement is the `DayStartHour` key of a `Startup.Tasks` entry, see the [`Invoke-StartupRepositoryUpdate`](Invoke-StartupRepositoryUpdate.md) guide.

## Usage

```powershell
# Deprecated
Get-RepositoryUpdateDayStart -DayStartHour 6
Get-RepositoryUpdateDayStart -DayStartHour 6 -At ([datetime]'2026-10-08 05:30')

# The replacement: whether a once-a-day task is due, the day boundary included
Test-StartupTaskDue -StampFile (Join-Path (Get-LogPath -Directory) ".startup-task-MyTask.stamp") -Frequency OncePerDay -DayStartHour 6
```

## Related

- [`Get-RepositoryUpdateDayStart` in the Git module reference](../../../modules/git.md#get-repositoryupdatedaystart) - parameters, usage and behaviour
- [`Test-StartupTaskDue`](../workflow/Test-StartupTaskDue.md) - the replacement
- [`Invoke-StartupRepositoryUpdate`](Invoke-StartupRepositoryUpdate.md) - the migration to a startup task
- [Git configuration guides](README.md) - every guide for this module
