# Custom-ReadHost

Wrapper around `Read-Host` that prompts the user for input with customizable colors and formatting.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Custom-ReadHost -PromptMessage "Enter value: "
Custom-ReadHost -PromptMessage "Enter value: " -ForegroundColor Yellow
Custom-ReadHost -PromptMessage "Enter password: " -AsSecureString
```

## Related

- [`Custom-ReadHost` in the Helper module reference](../../../modules/helper.md#custom-readhost) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module
