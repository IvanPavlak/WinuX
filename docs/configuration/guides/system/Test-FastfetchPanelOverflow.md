# Test-FastfetchPanelOverflow

Tells whether a fastfetch panel of the given size overflows a window of the given size - wider than the window, or taller than the window minus the cursor row and `-PromptReserve` rows. Pure, returns `[bool]`.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure. The `-PromptReserve` its caller passes comes from [`TerminalGreeting.Fastfetch.AutoFit.PromptReserve`](../../configuration-reference.md#terminal-greeting-startup-and-the-c-alias), which is configured through [`Invoke-Fastfetch`](Invoke-Fastfetch.md).

## Usage

```powershell
Test-FastfetchPanelOverflow -PanelWidth 106 -PanelHeight 22 -WindowWidth 120 -WindowHeight 30
Test-FastfetchPanelOverflow -PanelWidth 106 -PanelHeight 22 -WindowWidth 120 -WindowHeight 30 -PromptReserve 2
```

## Related

- [`Test-FastfetchPanelOverflow` in the System module reference](../../../modules/system.md#test-fastfetchpaneloverflow) - parameters, usage and behaviour
- [`Invoke-Fastfetch`](Invoke-Fastfetch.md) - the `c` alias that judges by this rule
- [System configuration guides](README.md) - every guide for this module
