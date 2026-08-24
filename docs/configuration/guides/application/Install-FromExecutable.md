# Install-FromExecutable

Unified, reliable, self-cleaning runner for installer-style executables.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Install-FromExecutable -Name "7-Zip" -Url "https://www.7-zip.org/a/7z2408-x64.exe" -Arguments "/S"
Install-FromExecutable -Name "MyApp" -Path "D:\setup.exe"
```

## Related

- [`Install-FromExecutable` in the Application module reference](../../../modules/application.md#install-fromexecutable) - parameters, usage and behaviour
- [Application configuration guides](README.md) - every guide for this module
