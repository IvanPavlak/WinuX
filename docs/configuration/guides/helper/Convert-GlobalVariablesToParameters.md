# Convert-GlobalVariablesToParameters

Analyzes a PowerShell function definition and converts every `$global:Variable` reference into a regular parameter with an inferred default value.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Convert-GlobalVariablesToParameters -FunctionDefinition $definition
Convert-GlobalVariablesToParameters -FunctionDefinition $definition -GlobalVariables MachineSpecificPaths
```

## Related

- [`Convert-GlobalVariablesToParameters` in the Helper module reference](../../../modules/helper.md#convert-globalvariablestoparameters) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module
