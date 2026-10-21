# Get-ConfigurationWriteTarget

Resolves the configuration file an `Add-*` writer edits, and its lines ready for the edit.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-ConfigurationWriteTarget -CopySection 'BrowserGroups'
Get-ConfigurationWriteTarget -HashtableSection 'PathTemplates.SymbolicLinks'
Get-ConfigurationWriteTarget -Base
```

## Related

- [`Get-ConfigurationWriteTarget` in the Configuration module reference](../../../modules/configuration.md#get-configurationwritetarget) - parameters, usage and behaviour
- [Configuration configuration guides](README.md) - every guide for this module
