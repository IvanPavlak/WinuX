# Invoke-ReadyDesktopPass

Positions, resizes and snaps one virtual desktop as soon as the wait reports every entry on it stable - the `-OnDesktopReady` callback of `Wait-ForWorkspaceWindows`.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
$onDesktopReady = { param($d, $e, $h, $a) Invoke-ReadyDesktopPass -Pipeline $pipeline -ReadyDesktopNumber $d -ReadyEntries $e -StableWindowHandles $h -AbandonedEntries $a }
```

## Related

- [`Invoke-ReadyDesktopPass` in the Window module reference](../../../modules/window.md#invoke-readydesktoppass) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
