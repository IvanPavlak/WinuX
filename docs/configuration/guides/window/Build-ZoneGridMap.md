# Build-ZoneGridMap

Builds a map of zones to their grid positions from a cell-child-map.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
$gridInfo = Build-ZoneGridMap -CellChildMap $layoutDef.info.'cell-child-map'
```

## Related

- [`Build-ZoneGridMap` in the Window module reference](../../../modules/window.md#build-zonegridmap) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
