# Get-ConsoleWindowSize

Reads the console window size in character cells - `Width` and `Height` from `[Console]::WindowWidth` / `WindowHeight` - and throws in a host with no console window, which is the signal `Invoke-Fastfetch` uses to skip its font auto-fit.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-ConsoleWindowSize
$window = Get-ConsoleWindowSize; $window.Width; $window.Height
```

## Related

- [`Get-ConsoleWindowSize` in the System module reference](../../../modules/system.md#get-consolewindowsize) - parameters, usage and behaviour
- [`Wait-ConsoleReflow`](Wait-ConsoleReflow.md) - polls this until the window changes
- [`Invoke-Fastfetch`](Invoke-Fastfetch.md) - the `c` alias that judges the panel against it
- [System configuration guides](README.md) - every guide for this module
