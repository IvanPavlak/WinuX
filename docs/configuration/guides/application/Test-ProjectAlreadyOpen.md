# Test-ProjectAlreadyOpen

Checks whether a project is already open in a given application by matching the project name against the application's window titles.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Test-ProjectAlreadyOpen -ProjectName MyProject -ProcessName "devenv" -ApplicationName "Visual Studio"
Test-ProjectAlreadyOpen -ProjectName MyProject -ProcessName "Code" -ApplicationName "VS Code"
```

## Related

- [`Test-ProjectAlreadyOpen` in the Application module reference](../../../modules/application.md#test-projectalreadyopen) - parameters, usage and behaviour
- [Application configuration guides](README.md) - every guide for this module
