# New-WaitClock

Creates the wait clock every poll loop reads time from and sleeps through (`Now`, `ElapsedMs`, `Sleep`), so a test can hand `Wait-Until` and every waiter built on it a fake clock instead.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
$clock = New-WaitClock
Wait-Until -Condition { Test-Path $marker } -TimeoutMs 500 -Clock $clock
```

## Related

- [`New-WaitClock` in the Helper module reference](../../../modules/helper.md#new-waitclock) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module
