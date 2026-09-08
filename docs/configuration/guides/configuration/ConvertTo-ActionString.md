# ConvertTo-ActionString

Converts an action hashtable into a properly formatted `Configuration.psd1` entry string for insertion into `WorkspaceActions` or `ProjectActions` sections.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
ConvertTo-ActionString -Action @{ Action = "Open-Browser"; Parameters = @{ Groups = @("GroupName") } } -Indent "`t`t`t"

# Per-machine tables follow Parameters (nested hashtables, quoted scope-string keys, $null values); the scopes come last
ConvertTo-ActionString -Action @{ Action = "Open-Browser"; Parameters = @{ Groups = @("Google") }; LayoutMachineParameters = @{ PC = @{ Instances = 2 } }; Machine = "PC/Work" } -Indent "`t`t`t"
# @{ Action = "Open-Browser"; Parameters = @{ Groups = @("Google") }; LayoutMachineParameters = @{ PC = @{ Instances = "2" } }; Machine = "PC/Work" }
```

## Related

- [`ConvertTo-ActionString` in the Configuration module reference](../../../modules/configuration.md#convertto-actionstring) - parameters, usage and behaviour
- [Configuration configuration guides](README.md) - every guide for this module
