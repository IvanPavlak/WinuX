# Test-StartupStage

The first half of the profile's stage guard: returns `$false` when the stage is named in the `WINUX_STARTUP_SKIP` environment variable (or the list says `All`), otherwise starts a Stopwatch for the stage and returns `$true`. `-Required` runs the stage whatever the list says, still timed.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

Its input is the `WINUX_STARTUP_SKIP` environment variable - a comma or semicolon separated list of stage names, case-insensitive - which `Measure-ShellStartup` sets per child shell and which you can set by hand to start one shell without a stage.

## Usage

```powershell
if (Test-StartupStage -Name "Terminal-Icons") { Import-Module Terminal-Icons; Complete-StartupStage }
$env:WINUX_STARTUP_SKIP = "Terminal-Icons,PowerPlan"; pwsh
```

## Related

- [`Test-StartupStage` in the Helper module reference](../../../modules/helper.md#test-startupstage) - parameters, usage and behaviour
- [`Complete-StartupStage`](Complete-StartupStage.md) - the second half of the guard
- [`Measure-ShellStartup`](../system/Measure-ShellStartup.md) - drives the guards to measure every stage
- [Helper configuration guides](README.md) - every guide for this module
