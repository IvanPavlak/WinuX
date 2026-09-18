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

## Virtual desktop seam

The third-party VirtualDesktop module's COM cmdlets (`Switch-Desktop`, `Get-DesktopCount`, `Move-Window`, ...) are reached through one Window-module adapter, `Invoke-VirtualDesktopOperation`. It runs a call, imports the module lazily, classifies an **RPC failure** (a stale COM session after heavy desktop churn or an Explorer restart - the module caches its COM proxies per process, so the failure repeats until they are reconnected), reconnects the session with `Reset-VirtualDesktopState`, and retries with backoff; any other error is rethrown at once; the module being absent is one clear exception. On top of it sit the verbs the rest of the repository uses: `Switch-VirtualDesktop` (switches, confirms the desktop is showing, retries, falls back to a session reset, clears the window cache) and the two reads `Get-VirtualDesktopCount` and `Get-CurrentVirtualDesktopIndex`; `Get-WindowDesktopIndex`, `Move-WindowToVirtualDesktop`, `Ensure-VirtualDesktops` and `Remove-VirtualDesktops` sit on the seam directly.

- **Callers** (`Focus-VirtualDesktop`, `Ensure-DesktopVisible`, `Snap-AllWindows`, `Apply-FancyZones`, `Set-WorkspaceWindowLayout`, `Confirm-WorkspaceWindowPositions`, `Move-Windows`, `Set-Wallpaper`) use the verbs and carry no retry or recovery block of their own.
- **Implementation** (`Reset-VirtualDesktopState`, `Reset-VirtualDesktopComProxy`, `Test-VirtualDesktopComHealth`, `Import-VirtualDesktopModule`) stays exported because the module loader exports every file under `Functions`, but only the adapter and the System module's RPC repair tooling (`Repair-RpcServer`, `Restart-Explorer`, `Test-RpcServerHealth`) call it.

## Configuration reader

`Get-ConfigSetting -Path 'Section.Key' -Default ...` is the one seam functions read the merged `Configuration.psd1` through. It is null-safe at every segment, returns the default only for a missing branch or a `$null` leaf, and returns every other configured value verbatim. `-Configuration` points it at another source: a function's own `[hashtable]$Configuration` parameter, a test's fake, or `$global:MachineSpecificPaths`. The **writers** (`Load-PathConfiguration`, `Initialize-Configuration`, `Expand-ConfigPaths`, the `Configuration` module's psd1 writers) address the hashtable directly because they build what the reader reads.
