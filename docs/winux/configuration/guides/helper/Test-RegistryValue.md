# Test-RegistryValue

Verifies that a registry value matches expected content.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Test-RegistryValue -Path 'HKCU:\Control Panel\Desktop' -Name 'Wallpaper' -ExpectedValue 'C:\my.jpg'
```

## Related

- [`Test-RegistryValue` in the Helper module reference](../../../modules/helper.md#test-registryvalue) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module
