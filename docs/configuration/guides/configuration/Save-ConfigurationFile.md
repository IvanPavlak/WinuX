# Save-ConfigurationFile

Writes a configuration file an `Add-*` writer edited, after backing the old one up.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Save-ConfigurationFile -Path $target.Path -Lines $newLines
```

## Related

- [`Save-ConfigurationFile` in the Configuration module reference](../../../modules/configuration.md#save-configurationfile) - parameters, usage and behaviour
- [Configuration configuration guides](README.md) - every guide for this module
