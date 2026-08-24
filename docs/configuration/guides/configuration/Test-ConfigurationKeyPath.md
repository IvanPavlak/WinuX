# Test-ConfigurationKeyPath

Tests whether an ordered configuration key path resolves to a non-empty value.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Test-ConfigurationKeyPath -Table $Configuration -Path @("GitConfig", "UserName")
```

## Related

- [`Test-ConfigurationKeyPath` in the Configuration module reference](../../../modules/configuration.md#test-configurationkeypath) - parameters, usage and behaviour
- [Configuration configuration guides](README.md) - every guide for this module
