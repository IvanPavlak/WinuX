# ProcessGroupRecursive

Internal helper used by `Resolve-Selection` to recursively flatten and navigate hierarchical group configurations with unlimited nesting depth.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
ProcessGroupRecursive -GroupValue $value -IndexPath "1" -DisplayItems $items -LookupMap $map -PathNames $names
```

## Related

- [`ProcessGroupRecursive` in the Helper module reference](../../../modules/helper.md#processgrouprecursive) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module
