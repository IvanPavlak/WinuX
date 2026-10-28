# Get-PowerShellFunctionDependencies

Analyzes a PowerShell function to discover its dependencies using the AST (Abstract Syntax Tree).

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-PowerShellFunctionDependencies -FunctionName "MyFunction"
Get-PowerShellFunctionDependencies -FunctionName "MyFunction" -Recursive
```

## Related

- [`Get-PowerShellFunctionDependencies` in the Helper module reference](../../../modules/helper.md#get-powershellfunctiondependencies) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module
