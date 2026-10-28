# Complete-StartupStage

The second half of the profile's stage guard: stops the clock `Test-StartupStage` started, records the stage name and its milliseconds in `$global:WinuXStartupTimings`, and appends the same record as one tab-separated line to the file named by the `WINUX_STARTUP_TRACE` environment variable when it is set. Does nothing when no stage clock is running; a trace file that cannot be written is ignored.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
if (Test-StartupStage -Name "Aliases") { New-Alias -Name c -Value Show-TerminalGreeting; Complete-StartupStage }
$WinuXStartupTimings | Sort-Object Milliseconds -Descending | Format-Table
```

## Related

- [`Complete-StartupStage` in the Helper module reference](../../../modules/helper.md#complete-startupstage) - parameters, usage and behaviour
- [`Test-StartupStage`](Test-StartupStage.md) - the first half of the guard
- [`Read-ShellStartupTrace`](../system/Read-ShellStartupTrace.md) - reads the trace file back
- [Helper configuration guides](README.md) - every guide for this module
