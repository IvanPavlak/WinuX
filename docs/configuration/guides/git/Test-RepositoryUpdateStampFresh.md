# Test-RepositoryUpdateStampFresh

Tells whether the startup repository update ran recently enough to skip it: `$true` when the stamp file was written since the day began (Daily) or within the interval (Interval).

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure. The schedule, day start hour and interval it is handed are [`RepositoryUpdate.Startup`](../../configuration-reference.md#repository-update), which [`Invoke-StartupRepositoryUpdate`](Invoke-StartupRepositoryUpdate.md) reads.

## Usage

```powershell
Test-RepositoryUpdateStampFresh -StampFile (Join-Path $global:LoggingState.LogsDir ".last-repository-update") -DayStartHour 6
Test-RepositoryUpdateStampFresh -StampFile (Join-Path $global:LoggingState.LogsDir ".last-repository-update") -Schedule Interval -IntervalHours 24
```

## Related

- [`Test-RepositoryUpdateStampFresh` in the Git module reference](../../../modules/git.md#test-repositoryupdatestampfresh) - parameters, usage and behaviour
- [`Invoke-StartupRepositoryUpdate`](Invoke-StartupRepositoryUpdate.md) - the caller
- [Git configuration guides](README.md) - every guide for this module
