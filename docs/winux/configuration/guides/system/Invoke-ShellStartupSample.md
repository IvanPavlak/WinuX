# Invoke-ShellStartupSample

Starts one child PowerShell in the current console with a given `WINUX_STARTUP_SKIP` list and a fresh `WINUX_STARTUP_TRACE` file, times it from launch to exit, and returns the wall time together with the per-stage milliseconds the profile's stage guards wrote - one sample for `Measure-ShellStartup`.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Invoke-ShellStartupSample
Invoke-ShellStartupSample -Skip "Greeting,Terminal-Icons"
Invoke-ShellStartupSample -Bare
```

## Related

- [`Invoke-ShellStartupSample` in the System module reference](../../../modules/system.md#invoke-shellstartupsample) - parameters, usage and behaviour
- [`Measure-ShellStartup`](Measure-ShellStartup.md) - runs this once per configuration and run
- [`Read-ShellStartupTrace`](Read-ShellStartupTrace.md) - turns the trace file into per-stage times
- [System configuration guides](README.md) - every guide for this module
