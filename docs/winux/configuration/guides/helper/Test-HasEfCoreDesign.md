# Test-HasEfCoreDesign

Reads a project file and checks whether it references the `Microsoft.EntityFrameworkCore.Design` package.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Test-HasEfCoreDesign -projectPath "MyProject.csproj"
if (Test-HasEfCoreDesign -projectPath "MyProject.csproj") { ... }
```

## Related

- [`Test-HasEfCoreDesign` in the Helper module reference](../../../modules/helper.md#test-hasefcoredesign) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module
