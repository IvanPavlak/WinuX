# Test-WSLEnabled

Checks whether Windows Subsystem for Linux is installed and available.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Test-WSLEnabled
if (Test-WSLEnabled) { Write-Host "WSL is ready" }
```

## Related

- [`Test-WSLEnabled` in the Helper module reference](../../../modules/helper.md#test-wslenabled) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module
