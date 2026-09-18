# Domain Context

Names for the seams in this repository, so an architecture review or a refactor reaches for the same word every time. The vocabulary for *how* these are described (module, interface, seam, adapter, depth, leverage, locality) is the deep-module vocabulary; the terms below are the domain's own.

## Workspace

A named set of actions (`WorkspaceActions`) that `Open-Workspace` runs and `Close-Workspace` reverses. A workspace has one **instance** per open; a plain open resets the virtual desktops and owns the screen, an **alongside** open adds itself on desktops to the right (`DesktopOffset`) without touching what is already there. The **tracker** (`OpenWorkspaces.txt`, written by `Save-WorkspaceState`) is the only source of truth for what an instance owns; configuration never is.

- **Protection** is what a plain open must leave alone: every live alongside instance of *another* workspace (`Get-WorkspaceOpenProtection`). A plain open **adopts** its own alongside instance instead of protecting it (`-Opening`): the same workspace opened plainly is a re-layout, never a second copy.
- **Claim**: a window becomes an instance's when the open diff records it, or when the first plain open of a run adopts what was already on screen (minus `Universal.VisibleWindowExclusions`).

## Layout

A per-workspace description of which window goes on which virtual desktop, monitor and FancyZones zone. Applying it is the **layout pipeline**: wait for windows, place, snap, confirm. Its raw dependencies are the two seams below.

## Win32 seam

`WindowModule.Native` (`Window/WindowNative.cs`), compiled once when the Window module loads, is the only place `user32`/`dwmapi` is declared. Every PowerShell function that needs a window operation calls a Window-module function that wraps it: `Get-CachedWindows` for enumeration (with `Clear-WindowCache` for a fresh read), `Set-WindowPosition` for placement, `Close-Window` for a graceful `WM_CLOSE`, `Test-WindowVisible` for liveness. No other module declares P/Invoke.

## Virtual desktop dependency

The third-party VirtualDesktop module's COM cmdlets (`Switch-Desktop`, `Get-DesktopCount`, `Move-Window`, ...). Called directly from many functions today; the COM proxies go stale per process after heavy desktop churn or an explorer restart, and each caller currently owns its own RPC recovery. Not yet behind an adapter (review candidate A).

## Configuration reader

`Get-ConfigSetting -Path 'Section.Key' -Default ...` is the one seam functions read the merged `Configuration.psd1` through. It is null-safe at every segment, returns the default only for a missing branch or a `$null` leaf, and returns every other configured value verbatim. `-Configuration` points it at another source: a function's own `[hashtable]$Configuration` parameter, a test's fake, or `$global:MachineSpecificPaths`. The **writers** (`Load-PathConfiguration`, `Initialize-Configuration`, `Expand-ConfigPaths`, the `Configuration` module's psd1 writers) address the hashtable directly because they build what the reader reads.
