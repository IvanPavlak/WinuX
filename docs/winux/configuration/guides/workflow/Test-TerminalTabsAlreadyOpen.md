# Test-TerminalTabsAlreadyOpen

Checks which expected terminal tabs are already open by reading every Windows Terminal window's tab titles via UI Automation - no focus changes, no keystrokes.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
$result = Test-TerminalTabsAlreadyOpen -ExpectedTabNames @("MyProject.Root", "MyProject.DOCS") -ProjectName "MyProject"
```

## Related

- [`Test-TerminalTabsAlreadyOpen` in the Workflow module reference](../../../modules/workflow.md#test-terminaltabsalreadyopen) - parameters, usage and behaviour
- [Workflow configuration guides](README.md) - every guide for this module
