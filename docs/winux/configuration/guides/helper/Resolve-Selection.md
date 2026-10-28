# Resolve-Selection

The canonical interactive menu selector used throughout the system.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Resolve-Selection
Resolve-Selection -OptionList @("Alpha", "Beta", "Gamma")
Resolve-Selection -OptionList @("English", "Espanol", "Francais") -PromptMessage "Select a language"
```

## Related

- [`Resolve-Selection` in the Helper module reference](../../../modules/helper.md#resolve-selection) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module
