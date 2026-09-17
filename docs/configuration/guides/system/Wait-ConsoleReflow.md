# Wait-ConsoleReflow

Polls `Get-ConsoleWindowSize` until the window differs from the size read before a keystroke, or the timeout passes, and returns the last size read - the unchanged size is how a keystroke that changed nothing reports itself.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure. The timeout its caller passes comes from [`TerminalGreeting.Fastfetch.AutoFit.ReflowTimeoutMilliseconds`](../../configuration-reference.md#terminal-greeting-startup-and-the-c-alias), which is configured through [`Invoke-Fastfetch`](Invoke-Fastfetch.md).

## Usage

```powershell
$before = Get-ConsoleWindowSize
Send-TerminalFontKey -Action Decrease
$after = Wait-ConsoleReflow -Before $before -TimeoutMilliseconds 10
Wait-ConsoleReflow -Before $before -TimeoutMilliseconds 10 -PollIntervalMilliseconds 5
```

## Related

- [`Wait-ConsoleReflow` in the System module reference](../../../modules/system.md#wait-consolereflow) - parameters, usage and behaviour
- [`Get-ConsoleWindowSize`](Get-ConsoleWindowSize.md) - what it polls
- [`Send-TerminalFontKey`](Send-TerminalFontKey.md) - the keystroke it usually follows
- [`Invoke-Fastfetch`](Invoke-Fastfetch.md) - the `c` alias built on it
- [System configuration guides](README.md) - every guide for this module
