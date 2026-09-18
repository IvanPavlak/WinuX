# Invoke-VirtualDesktopOperation

Runs one call against the third-party VirtualDesktop module's cmdlets - the Window module's one seam to that module - importing it lazily, reconnecting a stale COM session on an RPC failure and retrying with backoff.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
$count = [int](Invoke-VirtualDesktopOperation -Operation { Get-DesktopCount } -Label 'counting desktops')
Invoke-VirtualDesktopOperation -Operation { $null = Switch-Desktop -Desktop 2 -ErrorAction Stop } -Label 'switching desktop'
Invoke-VirtualDesktopOperation -Operation { Get-DesktopCount } -Label 'desktop cleanup' -MaxAttempts 5 -InitialDelayMs 250 -Probe
```

## Related

- [`Invoke-VirtualDesktopOperation` in the Window module reference](../../../modules/window.md#invoke-virtualdesktopoperation) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
