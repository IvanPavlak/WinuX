# Focus-TerminalTab

Helper that focuses Windows Terminal and optionally navigates to a specific tab by title.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Focus-TerminalTab
Focus-TerminalTab -TargetTitle "PowerShell"
Focus-TerminalTab -WindowHandle $window.Handle -Quiet
```

## Related

- [`Focus-TerminalTab` in the Workflow module reference](../../../modules/workflow.md#focus-terminaltab) - parameters, usage and behaviour
- [Workflow configuration guides](README.md) - every guide for this module
