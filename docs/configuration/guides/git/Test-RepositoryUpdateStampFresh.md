# Test-RepositoryUpdateStampFresh

Tells whether the startup repository update ran recently enough to skip it: `$true` when the stamp file exists and is younger than the interval.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure. The interval it is handed is [`RepositoryUpdate.Startup.IntervalHours`](../../configuration-reference.md#repository-update), which [`Invoke-StartupRepositoryUpdate`](Invoke-StartupRepositoryUpdate.md) reads.

## Usage

```powershell
Test-RepositoryUpdateStampFresh -StampFile (Join-Path $global:LoggingState.LogsDir ".last-repository-update") -IntervalHours 24
```

## Related

- [`Test-RepositoryUpdateStampFresh` in the Git module reference](../../../modules/git.md#test-repositoryupdatestampfresh) - parameters, usage and behaviour
- [`Invoke-StartupRepositoryUpdate`](Invoke-StartupRepositoryUpdate.md) - the caller
- [Git configuration guides](README.md) - every guide for this module
