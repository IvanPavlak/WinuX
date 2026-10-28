# Measure-ShellStartup

Measures how long a shell takes to reach its first prompt, stage by stage: a bare `pwsh -NoProfile`, then `Core`, then every profile stage added one at a time (or the full start minus one stage at a time with `-Mode Isolated`), each configuration started `-Runs` times and reported as min / median / max with the delta to the previous row and the stage's own in-shell time.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

The stages it walks are the ones the profile guards with `Test-StartupStage`; it drives them through the `WINUX_STARTUP_SKIP` and `WINUX_STARTUP_TRACE` environment variables of the child shells it starts, never through configuration.

## Usage

```powershell
Measure-ShellStartup
Measure-ShellStartup -Mode Isolated -Runs 3
Measure-ShellStartup -Stages Greeting, FastfetchImageLogo -PassThru
```

Run it from the terminal whose start you want to measure - a Windows Terminal tab, in the directory a new tab opens in - because the child shells share that console and inherit what makes the start real: `WT_SESSION`, the interactive console, the terminal's cell-size reply. Expect the screen to be cleared and redrawn once per child; the table is printed when the last child has exited.

## Related

- [`Measure-ShellStartup` in the System module reference](../../../modules/system.md#measure-shellstartup) - parameters, usage and behaviour
- [`Invoke-ShellStartupSample`](Invoke-ShellStartupSample.md) - one child shell, one sample
- [`Test-StartupStage`](../helper/Test-StartupStage.md) - the guard the profile wraps every stage in
- [Slow profile load](../../../reference/troubleshooting.md#slow-profile-load) - reading the table
- [System configuration guides](README.md) - every guide for this module
