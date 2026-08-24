# Get-LayoutDefinition

Retrieves a specific FancyZones layout definition from the `custom-layouts.json` configuration file by name.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
$layout = Get-LayoutDefinition -LayoutsJsonPath "C:\Users\<User>\custom-layouts.json" -LayoutName "Eight"
```

## Related

- [`Get-LayoutDefinition` in the Window module reference](../../../modules/window.md#get-layoutdefinition) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
