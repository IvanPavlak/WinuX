# ConvertTo-ActionString

Converts an action hashtable into a properly formatted `Configuration.psd1` entry string for insertion into `WorkspaceActions` or `ProjectActions` sections.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
ConvertTo-ActionString -Action @{ Action = "Open-Browser"; Parameters = @{ Groups = @("GroupName") } } -Indent "`t`t`t"

# The optional Machine / LayoutMachine scopes are written after Parameters
ConvertTo-ActionString -Action @{ Action = "Open-Browser"; Parameters = @{ Groups = @("Google") }; LayoutMachine = "Laptop/Work" } -Indent "`t`t`t"
# @{ Action = "Open-Browser"; Parameters = @{ Groups = @("Google") }; LayoutMachine = "Laptop/Work" }
```

## Related

- [`ConvertTo-ActionString` in the Configuration module reference](../../../modules/configuration.md#convertto-actionstring) - parameters, usage and behaviour
- [Configuration configuration guides](README.md) - every guide for this module
