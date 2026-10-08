# Get-RepositoryUpdateDayStart

Returns when the current day began, for a day that starts at a given hour - the day boundary of the daily repository update.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure. The hour it is handed is [`RepositoryUpdate.Startup.DayStartHour`](../../configuration-reference.md#repository-update), which [`Invoke-StartupRepositoryUpdate`](Invoke-StartupRepositoryUpdate.md) reads.

## Usage

```powershell
Get-RepositoryUpdateDayStart -DayStartHour 6
Get-RepositoryUpdateDayStart -DayStartHour 6 -At ([datetime]'2026-10-08 05:30')
```

## Related

- [`Get-RepositoryUpdateDayStart` in the Git module reference](../../../modules/git.md#get-repositoryupdatedaystart) - parameters, usage and behaviour
- [Git configuration guides](README.md) - every guide for this module
