# Get-FilteredParams

Filters a parameter hashtable to include only the parameters accepted by a target command.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-FilteredParams -CommandName "Get-Item" -Params @{ Name = "file.txt"; Size = 100; Invalid = "xyz" }
```

## Related

- [`Get-FilteredParams` in the Helper module reference](../../../modules/helper.md#get-filteredparams) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module
