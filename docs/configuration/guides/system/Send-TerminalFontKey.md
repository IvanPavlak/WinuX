# Send-TerminalFontKey

Sends one of Windows Terminal's font-size keystrokes to the active window: `Reset` is `Ctrl+0`, `Decrease` is `Ctrl+Minus`. Honours `-WhatIf`, which logs the mapping and sends nothing.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure. It relies on the two Windows Terminal default key bindings being present; a custom `actions` list that drops them makes the keystroke a no-op, which [`Invoke-ClearAndFastfetch`](Invoke-ClearAndFastfetch.md) detects through [`Wait-ConsoleReflow`](Wait-ConsoleReflow.md).

## Usage

```powershell
Send-TerminalFontKey -Action Reset
Send-TerminalFontKey -Action Decrease
Send-TerminalFontKey -Action Decrease -WhatIf
```

## Related

- [`Send-TerminalFontKey` in the System module reference](../../../modules/system.md#send-terminalfontkey) - parameters, usage and behaviour
- [`Wait-ConsoleReflow`](Wait-ConsoleReflow.md) - how the effect of the keystroke is observed
- [`Invoke-ClearAndFastfetch`](Invoke-ClearAndFastfetch.md) - the `c` alias built on it
- [System configuration guides](README.md) - every guide for this module
