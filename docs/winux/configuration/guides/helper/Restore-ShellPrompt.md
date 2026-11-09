# Restore-ShellPrompt

Draws the prompt again after something printed below it while PSReadLine was already waiting for input, through PSReadLine's `InvokePrompt`. Returns `$false` without throwing outside PSReadLine, so callers run it unconditionally after printing.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
$null = Restore-ShellPrompt
```

## Related

- [`Restore-ShellPrompt` in the Helper module reference](../../../modules/helper.md#restore-shellprompt) - parameters, usage and behaviour
- [`Invoke-StartupTasks`](../workflow/Invoke-StartupTasks.md) - its `-RedrawPrompt` calls it after the startup tasks of a newly opened terminal printed something (the automatic repository update is one of them)
- [`Import-TerminalIcons`](../system/Import-TerminalIcons.md) - its `-RedrawPrompt` calls it after a cache repair report
- [Helper configuration guides](README.md) - every guide for this module
