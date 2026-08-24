# Get-CurrentLayout

Reads the persisted `CurrentLayout.txt` snapshot written by `Save-CurrentLayout`.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-CurrentLayout -LayoutsDir $layoutsDir
Get-CurrentLayout -LayoutsDir $layoutsDir -Workspace "Example_PC"
```

## Related

- [`Get-CurrentLayout` in the Window module reference](../../../modules/window.md#get-currentlayout) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
