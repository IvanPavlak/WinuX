# Create-Executable

Creates a standalone executable from a PowerShell function and its dependencies.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Create-Executable -FunctionName MyFunction
Create-Executable -FunctionName MyFunction -OutputPath C:\Tools\MyFunction.exe -Title "My Tool"
Create-Executable -FunctionName MyFunction -RequireAdmin -NoConsole
```

## Related

- [`Create-Executable` in the Helper module reference](../../../modules/helper.md#create-executable) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module
