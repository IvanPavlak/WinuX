# Move-StableWindowEarly

Moves a window that just became stable to its layout entry's virtual desktop while the rest of the workspace is still loading - the `-OnWindowStable` callback of `Wait-ForWorkspaceWindows`.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
$onWindowStable = { param($entry, $window) Move-StableWindowEarly -Pipeline $pipeline -LayoutEntry $entry -Window $window }
```

## Related

- [`Move-StableWindowEarly` in the Window module reference](../../../modules/window.md#move-stablewindowearly) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
