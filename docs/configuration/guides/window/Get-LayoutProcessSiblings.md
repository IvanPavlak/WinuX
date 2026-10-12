# Get-LayoutProcessSiblings

Describes how the layout entries that share one process relate to each other (titled, catch-all, the other entries' titles), so the placement, the wait and the verification agree on which window belongs to which entry.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-LayoutProcessSiblings -LayoutConfig $config.Layout
Get-LayoutProcessSiblings -LayoutConfig @(
    @{ ProcessName = 'Code'; WindowTitle = 'MyProject - Visual Studio Code$' }
    @{ ProcessName = 'Code' }
)
```

## Related

- [`Get-LayoutProcessSiblings` in the Window module reference](../../../modules/window.md#get-layoutprocesssiblings) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
