# Invoke-Clear

Clears the terminal screen with `Clear-Host`. The first step of [`Show-TerminalGreeting`](Show-TerminalGreeting.md), and thin by design, so that all three greeting steps are switched on and off the same way.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure. The one flag that turns it off - [`TerminalGreeting.Clear.Enabled`](../../configuration-reference.md#terminal-greeting-startup-and-the-c-alias) - reaches it in the settings tree the greeting hands it, and is configured through [`Show-TerminalGreeting`](Show-TerminalGreeting.md).

## Usage

```powershell
Invoke-Clear
Invoke-Clear -Settings (Resolve-TerminalGreetingSettings)
Set-LogLevel Verbose { Invoke-Clear }
```

## Related

- [`Invoke-Clear` in the System module reference](../../../modules/system.md#invoke-clear) - parameters, usage and behaviour
- [`Show-TerminalGreeting`](Show-TerminalGreeting.md) - the orchestrator, and where the flag is configured
- [`Invoke-Fastfetch`](Invoke-Fastfetch.md), [`Invoke-Onefetch`](Invoke-Onefetch.md) - the other two steps
- [`Resolve-TerminalGreetingSettings`](Resolve-TerminalGreetingSettings.md) - what produces the settings it is handed
- [System configuration guides](README.md) - every guide for this module
