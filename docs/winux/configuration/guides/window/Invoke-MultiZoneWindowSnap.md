# Invoke-MultiZoneWindowSnap

Snaps a pre-positioned window into its FancyZones zone - `Win+Up`, shift-drag fallback, three attempts - and reports the outcome instead of deciding what happens when the attempts are exhausted. `Snap-AllWindows` owns that decision (a zone-grid reset and a second round for the same window).

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
$snap = Invoke-MultiZoneWindowSnap -WindowHandle $handle -ExpectedX 3 -ExpectedY 3 -ExpectedWidth 1717 -ExpectedHeight 1434 -WindowTitle 'Code'
if (-not $snap.Verified) { "exhausted after $($snap.Attempts) attempts" }
```

## Related

- [`Invoke-MultiZoneWindowSnap` in the Window module reference](../../../modules/window.md#invoke-multizonewindowsnap) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
