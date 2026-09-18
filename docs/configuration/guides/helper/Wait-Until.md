# Wait-Until

Polls a condition until it holds or a time budget runs out - the one poll loop in the repository, reading time through a wait clock.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Wait-Until -Condition { (Get-CurrentVirtualDesktopIndex) -eq 2 } -TimeoutMs 750 -PollIntervalMs 10
Wait-Until -Condition { Test-Path $marker } -TimeoutMs 500 -SleepFirst
```

## Related

- [`Wait-Until` in the Helper module reference](../../../modules/helper.md#wait-until) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module
