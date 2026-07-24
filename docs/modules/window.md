# Window Module

The Window module provides **window management**, **virtual desktop control**, and **"tiling window manager"** functionality via FancyZones integration.

## [Add-PositionedWindow](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Add-PositionedWindow.ps1)

- **Description:** Adds a window handle to the positioned windows tracking set. Registers a window handle as having been positioned by `Set-WindowLayouts`, storing the expected window state (position, dimensions, title, virtual desktop number, and optional process fingerprint) for validation before snapping. `Snap-AllWindows` uses this tracking metadata to verify windows are still in the expected state - detecting stale or reassigned handles in long-running shells and re-resolving windows - and retries positioning if needed.
- **Parameters:** -WindowHandle, -ExpectedX, -ExpectedY, -ExpectedWidth, -ExpectedHeight, -WindowTitle, -DesktopNumber, -ExpectedProcessName, -ExpectedProcessId
- **Usage:** `Add-PositionedWindow -WindowHandle $window.Handle -ExpectedX 100 -ExpectedY 200 -ExpectedWidth 800 -ExpectedHeight 600 -WindowTitle "MyApp" -DesktopNumber 0`

If a handle is already tracked it is removed and re-added so the stored expected state always reflects the most recent positioning. State is held in the module-scoped `$script:PositionedWindowHandles` collection consumed by the snap-validation functions.

| Parameter              | Type   | Default | Description                                                    |
| ---------------------- | ------ | ------- | -------------------------------------------------------------- |
| `-WindowHandle`        | IntPtr | -       | Handle of the window to track. (Mandatory)                     |
| `-ExpectedX`           | int    | -       | Expected X position of the window. (Mandatory)                 |
| `-ExpectedY`           | int    | -       | Expected Y position of the window. (Mandatory)                 |
| `-ExpectedWidth`       | int    | -       | Expected width of the window. (Mandatory)                      |
| `-ExpectedHeight`      | int    | -       | Expected height of the window. (Mandatory)                     |
| `-WindowTitle`         | string | -       | Window title used for identification. (Mandatory)              |
| `-DesktopNumber`       | int    | `0`     | Virtual desktop number (0-based) where the window was moved.   |
| `-ExpectedProcessName` | string | -       | Optional process name fingerprint captured during positioning. |
| `-ExpectedProcessId`   | uint32 | `0`     | Optional process ID fingerprint captured during positioning.   |

```powershell
# Track a window after positioning it, with optional process fingerprint
Add-PositionedWindow -WindowHandle $window.Handle `
    -ExpectedX 100 -ExpectedY 200 -ExpectedWidth 800 -ExpectedHeight 600 `
    -WindowTitle "MyApp" -DesktopNumber 0 `
    -ExpectedProcessName "myapp" -ExpectedProcessId $window.ProcessId
```

**See also:** [Window module](../modules/window.md)

## [Apply-FancyZones](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Apply-FancyZones.ps1)

- **Description:** Applies predefined FancyZones layouts to monitors by sending the `Win+Ctrl+Alt+[Number]` shortcut against a window positioned on each monitor. Reads a `MonitorConfig` hashtable (per-monitor `Layout`, or per-desktop `VirtualDesktopLayouts`), restarts FancyZones first to ensure reliability and fails fast if readiness cannot be verified, then applies layouts. The operation is idempotent: it reads FancyZones' applied-layouts state and skips redundant shortcut sends (and skips switching to desktops that are already fully correct). When two or more monitors share the same EDID (identical models), plain EDID keys collide - but newer FancyZones schemas record a per-device `monitor-instance` and the applied-state lookup stores instance-qualified keys (`EDID|INSTANCE:GUID`), so idempotency stays enabled whenever every duplicated display has an instance path; the skip is only disabled when instance data is missing (old schema). Supports multi-workspace scenarios via `-DesktopOffset` and `-DesktopCount`, and invalidates the applied-layouts cache after any shortcuts are actually sent.
- **Parameters:** -MonitorConfig, -DesktopNumber, -MonitorInfo, -DesktopOffset, -DesktopCount
- **Usage:** `Apply-FancyZones -MonitorConfig $config.Monitors`, `Apply-FancyZones -MonitorConfig $config.Monitors -DesktopNumber 2`, `Apply-FancyZones -MonitorConfig $config.Monitors -DesktopOffset 2 -DesktopCount 3`

Only `-MonitorConfig` is mandatory. With no `-DesktopNumber`, it applies layouts across all virtual desktops (using the VirtualDesktop module, when available) and returns to the starting desktop. Every desktop switch is confirmed via `Wait-DesktopSwitch` before the layout hotkey is injected - an unconfirmed switch skips that desktop (and the return-desktop re-apply), closing the race where a layout was silently recorded under the previous desktop's GUID. Layout names resolve to shortcut numbers (0-9) via `LayoutNumbers` in `Configuration.psd1`. Returns a result array (one row per monitor/desktop) with a `Status` such as `Shortcut Sent`, `Already Applied`, `Monitor Not Found`, or `Failed`.

| Parameter        | Description                                                                                                                                                                                                                                                                                       |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-MonitorConfig` | Hashtable of monitor configs keyed by monitor (e.g. `Primary`, `Secondary`). Each has a simple `Layout` (e.g. `@{ Layout = "One" }`), an optional legacy `LayoutNumber`, or per-desktop `VirtualDesktopLayouts` (1-based desktop index → layout name or `@{ Layout = ...; LayoutNumber = ... }`). |
| `-DesktopNumber` | Virtual desktop number to apply layouts for; if set and the monitor has `VirtualDesktopLayouts`, uses that desktop's layout.                                                                                                                                                                      |
| `-MonitorInfo`   | Pre-fetched monitor info array to reuse instead of calling `Get-MonitorInfo` (caching optimization).                                                                                                                                                                                              |
| `-DesktopOffset` | Virtual desktop offset for multi-workspace placement; layouts apply to desktops starting from this index.                                                                                                                                                                                         |
| `-DesktopCount`  | Caps how many desktops are processed (from the offset), preventing overwrite of adjacent workspaces' layouts.                                                                                                                                                                                     |

```powershell
# Apply layouts from a workspace layout data file
$config = Import-PowerShellDataFile -Path "WinuX-workspace-layout.psd1"
Apply-FancyZones -MonitorConfig $config.Monitors

# Apply only the layout configured for a specific virtual desktop
Apply-FancyZones -MonitorConfig $config.Monitors -DesktopNumber 2

# Verbose diagnostic output
Set-LogLevel Verbose { Apply-FancyZones -MonitorConfig $config.Monitors -DesktopOffset 2 -DesktopCount 3 }
```

**See also:** [Configuration overview](../configuration/overview.md)

## [Build-ZoneGridMap](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Build-ZoneGridMap.ps1)

- **Description:** Builds a map of zones to their grid positions from a cell-child-map. Analyzes the cell-child-map from a FancyZones layout definition to determine which grid cells each zone occupies and calculates their boundaries (min/max rows and cols). Used internally by the dynamic visualization system to determine zone positioning and spanning.
- **Parameters:** -CellChildMap
- **Usage:** `$gridInfo = Build-ZoneGridMap -CellChildMap $layoutDef.info.'cell-child-map'`

Iterates over the cell-child-map (a row/column array where each cell holds the index of the zone occupying it) and records, for every zone, the cells it spans and the bounding min/max row and column. Cell indices are cast to `[int]` so the hashtable keys match the `Int32` type expected elsewhere (JSON parsing yields `Int64`). Returns a hashtable with `ZoneMap` (zone index to cell positions and spans), `NumRows`, and `NumCols`.

| Parameter       | Description                                                   |
| --------------- | ------------------------------------------------------------- |
| `-CellChildMap` | The cell-child-map array from a FancyZones layout definition. |

## [Center-Terminal](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Center-Terminal.ps1)

- **Description:** Centers the Windows Terminal on the primary monitor at a physically-constant size. Rather than a fixed percentage, it targets a fixed on-screen pixel size (`CenterTerminalSizing` in `Configuration.psd1`) and derives the width/height percentages from the LIVE primary monitor's work area at run time, then delegates the move/resize to `Center-Windows -OnPrimary`. Because the size is computed from the live monitor (not the hostname-derived `$global:MachineType`), an undocked laptop on its small panel gets a proportionally larger window while a docked laptop or the ultrawide stays at its usual size - with no per-machine configuration. Falls back to `Center-Windows`' default 40% x 50% when the config section or monitor information is unavailable. Used by `Kill-All` to re-center the surviving terminal after cleanup.
- **Usage:** `Center-Terminal`

Resolves the target size via `Get-MonitorInfo` (live primary monitor work area) and `Resolve-CenteredWindowPercent` (target-px to clamped percentages), then calls `Center-Windows -ProcessName "WindowsTerminal" -OnPrimary` with the resolved percentages. The defaults shipped in `CenterTerminalSizing` anchor the target to 1376x700 px - exactly what 40% x 50% yields on a 3440x1440 ultrawide - so the ultrawide is unchanged while smaller panels scale up (e.g. ~72% x 67% on a 1920x1080 laptop).

```powershell
# Re-center Windows Terminal on the primary monitor at the adaptive size
Center-Terminal
```

**See also:** [Center-Windows](window.md#center-windows), [Resolve-CenteredWindowPercent](window.md#resolve-centeredwindowpercent)

## [Center-Windows](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Center-Windows.ps1)

- **Description:** Centers all open windows on their respective monitors. Enumerates all visible application windows, determines which monitor each window is currently on based on its center point, then moves and resizes every window to a centered position within that monitor's work area. By default windows are resized to 40% of the monitor work area width and 50% of the height (override with `-WidthPercent` / `-HeightPercent`). Off-screen windows are automatically moved to the primary monitor. Pass `-OnPrimary` to force every matched window onto the primary monitor (whichever is currently primary), regardless of where it currently lives. Optionally restrict centering to matching windows with `-ProcessName` and/or `-WindowTitle` (exact, wildcard, or regex; OR logic when both are given), delegated to `Get-WindowHandle` - the same filtering path as `Move-Windows`. The actual move/resize is delegated to `Resize-Windows` in target-bounds mode (with `-InsetPercent 0` for exact placement), so all window placement flows through a single shared path (DRY).
- **Parameters:** -WidthPercent, -HeightPercent, -ProcessName, -WindowTitle, -OnPrimary
- **Usage:** `Center-Windows`, `Center-Windows -WidthPercent 60 -HeightPercent 70`, `Center-Windows -ProcessName "chrome"`, `Center-Windows -ProcessName "*chrome*"`, `Center-Windows -ProcessName "(chrome|firefox|msedge)"`, `Center-Windows -WindowTitle "*YouTube*"`, `Center-Windows -ProcessName "WindowsTerminal" -OnPrimary`

Builds on existing module helpers: `Get-WindowHandle` for pattern filtering when `-ProcessName`/`-WindowTitle` is supplied (otherwise `Get-CachedWindows` enumerates all windows; the cache is cleared first to read fresh positions), `Get-MonitorInfo` for monitor bounds and work areas, `Resize-Windows` (target-bounds mode, `-InsetPercent 0`) for reliable, centralized placement, and `Ensure-WindowsFormsLoaded` for the `System.Windows.Forms` dependency. System and shell windows (Program Manager, Windows Input Experience, search/start surfaces, overlays, etc.) and windows with no meaningful size are skipped. Under `Set-LogLevel Verbose` it prints a per-window trace plus a diagnostics summary with enumerated, eligible, centered, and skipped counts and exclusion counts (skip-title and invalid-size) to explain why some windows were not centered.

| Parameter        | Description                                                                                                                                                                                         |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-WidthPercent`  | Percentage of the monitor work area width per window. Default `40`. Range 10-100.                                                                                                                   |
| `-HeightPercent` | Percentage of the monitor work area height per window. Default `50`. Range 10-100.                                                                                                                  |
| `-ProcessName`   | Only center windows whose process matches this pattern (without `.exe`). Supports exact names, wildcards (`*`, `?`), and regex. Omit to center all visible windows.                                 |
| `-WindowTitle`   | Only center windows whose title matches this pattern. Supports wildcards (`*`, `?`) and regex. Combine with `-ProcessName` (OR logic). Omit (with no `-ProcessName`) to center all visible windows. |
| `-OnPrimary`     | Force every matched window onto the primary monitor (whichever is currently primary), pulling it back from a secondary monitor if needed. Omit to center each window on its current monitor.        |

```powershell
# Center every window at the default 40% x 50% on its current monitor
Center-Windows

# Use larger centered tiles
Center-Windows -WidthPercent 60 -HeightPercent 70

# Verbose diagnostic output
Set-LogLevel Verbose { Center-Windows -ProcessName "chrome" }

# Center windows whose process name contains "chrome" (wildcard match)
Center-Windows -ProcessName "*chrome*"

# Center windows for any of several browsers (regex match)
Center-Windows -ProcessName "(chrome|firefox|msedge)"

# Pull Windows Terminal onto the primary monitor and center it there
Center-Windows -ProcessName "WindowsTerminal" -OnPrimary
```

**See also:** [Reset-Windows](window.md#reset-windows)

## [Center-Text](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Center-Text.ps1)

- **Description:** Centers a string within a specified character width by adding padding on both sides. If the text is longer than the width, it is truncated to fit. Used by Generate-LayoutVisualization to create centered text in ASCII-art layout visualizations.
- **Parameters:** -Text, -Width
- **Usage:** `Center-Text -Text "Hello" -Width 20`

## [Clear-FancyZonesCache](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Clear-FancyZonesCache.ps1)

- **Description:** Clears the FancyZones layout cache. Invalidates the cached FancyZones layout data (resetting its data, path, and timestamp), forcing the next `Get-CachedFancyZonesLayouts` call to re-read from the JSON file.
- **Usage:** `Clear-FancyZonesCache`

**See also:** [Get-CachedFancyZonesLayouts](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Get-CachedFancyZonesLayouts.ps1)

## [Clear-MonitorCache](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Clear-MonitorCache.ps1)

- **Description:** Clears the monitor information cache. Invalidates the cached monitor data, forcing the next `Get-CachedMonitors` call to refresh from the Windows Forms API. Useful when the monitor configuration changes.
- **Usage:** `Clear-MonitorCache`

## [Clear-WindowCache](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Clear-WindowCache.ps1)

- **Description:** Clears the window enumeration cache. Invalidates the cached window information, forcing the next `Get-CachedWindows` call to refresh from the native API. Also clears the C# process name cache.
- **Usage:** `Clear-WindowCache`

## [Confirm-WindowForeground](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Confirm-WindowForeground.ps1)

- **Description:** Acquires and verifies stable foreground focus for a window. Repeatedly forces the target window to the foreground and confirms the change took effect before returning. Because focus handoff is asynchronous, a single `ForceForegroundWindow` call can race with input injection; this helper retries with an increasing settle delay and only reports success once `GetForegroundWindow` confirms the window is actually focused.
- **Parameters:** -WindowHandle, -BaseSettleMs (default: 10), -MaxAttempts (default: 3)
- **Usage:** `Confirm-WindowForeground -WindowHandle $handle`, `Confirm-WindowForeground -WindowHandle $handle -BaseSettleMs 10 -MaxAttempts 3`

Used by `Snap-AllWindows` immediately before injecting snap hotkeys, and reusable by any flow that must guarantee focus before sending input. Each attempt forces the window foreground, settles for a progressively longer delay (floored at 10 ms), and re-checks `GetForegroundWindow`. This prevents snaps from being sent to a window that briefly lost focus, a common cause of missed keyboard snaps.

| Parameter       | Type   | Default | Description                                                                                                                                        |
| --------------- | ------ | ------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-WindowHandle` | IntPtr | -       | Handle of the window to bring to the foreground (mandatory).                                                                                       |
| `-BaseSettleMs` | int    | `10`    | Base settle delay in milliseconds after the first focus attempt. Each subsequent attempt adds 25 ms; the effective delay is never less than 10 ms. |
| `-MaxAttempts`  | int    | `3`     | Maximum number of force-foreground attempts before giving up.                                                                                      |

Returns `Boolean`: `$true` once the window is confirmed foreground, otherwise `$false`.

```powershell
# Guarantee focus before injecting a snap hotkey
if (Confirm-WindowForeground -WindowHandle $handle) { [WindowModule.Native]::SendSnapKey($true) }

# Tune the retry behavior explicitly
Confirm-WindowForeground -WindowHandle $handle -BaseSettleMs 10 -MaxAttempts 3
```

## [Confirm-WorkspaceWindowPositions](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Confirm-WorkspaceWindowPositions.ps1)

- **Description:** Performs a final verification that every window defined in the layout config exists and is at its expected zone position. After `Set-WindowLayouts` positions windows and `Snap-AllWindows` snaps them into FancyZones, it walks the layout config, resolves each entry's expected zone coordinates, finds a matching live window, reads its actual position via the native `GetWindowRect` API, and compares against the expected bounds within `Tolerance`. Called automatically by `Set-WorkspaceWindowLayout` after snapping; returns a result hashtable whose failure objects carry the live window handle so the workspace rerun path can resize only the failing window before retrying.
- **Parameters:** -LayoutConfig, -MonitorInfo, -MonitorConfig, -DesktopOffset, -Tolerance (default: 50)
- **Usage:** `Confirm-WorkspaceWindowPositions -LayoutConfig $config.Layout -MonitorInfo $monitorInfo -MonitorConfig $config.Monitors`, `Confirm-WorkspaceWindowPositions -LayoutConfig $config.Layout -MonitorInfo $monitorInfo -MonitorConfig $config.Monitors -DesktopOffset $DesktopOffset`

This is the last verification pass in the workspace layout pipeline. For each layout entry it resolves the expected zone coordinates using the same logic as `Set-WindowLayouts`, locates a live window matching `ProcessName` / `WindowTitle` against a fresh window cache, and compares the actual `GetWindowRect` bounds against the expected zone within `Tolerance` pixels. It catches windows that were never found on the first pass (e.g. an app not yet started), windows whose handles became invalid after positioning, and windows that ended up in the wrong place.

When multiple live windows match the same `ProcessName`/`WindowTitle`, candidates are scored by how closely their actual bounds match the expected bounds and the best-matching one is selected; a `$claimedHandles` set guarantees each duplicate-keyed layout entry claims a unique window so identical titles (e.g. two browser windows) are never misassigned. A title-drift fallback handles non-browser apps whose captions change at runtime (e.g. new Outlook / `Olk` titling its window after the selected folder): when strict process-and-title matching finds nothing and exactly one unclaimed process window remains, that window is accepted rather than false-failing. Candidates on the expected virtual desktop are preferred, falling back to cross-desktop candidates only when none exist there. As a last resort before declaring an entry "window not found", the tracked positioned window whose expected bounds and desktop match the entry is accepted, provided its handle is still alive and unclaimed - covering browser windows whose title drifted between positioning and verification (a tab finished loading), which previously escalated to reruns that could never fix a title mismatch.

| Parameter        | Type      | Default | Description                                                                                                                                                       |
| ---------------- | --------- | ------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-LayoutConfig`  | array     | -       | The same layout array passed to `Set-WindowLayouts`; each entry has `ProcessName`, `WindowTitle`, `DesktopNumber`, `Zone`, `Monitor`, `Layout`, etc. (mandatory). |
| `-MonitorInfo`   | array     | -       | Pre-fetched monitor information from `Get-MonitorInfo`.                                                                                                           |
| `-MonitorConfig` | hashtable | -       | The `Monitors` hashtable from the workspace `.psd1` config, used to resolve layout names per virtual desktop per monitor.                                         |
| `-DesktopOffset` | int       | `0`     | Desktop offset applied to all desktop numbers (for alongside / multi-workspace mode).                                                                             |
| `-Tolerance`     | int       | `50`    | Maximum pixel deviation allowed per dimension before a window is considered mispositioned.                                                                        |

Returns a `[hashtable]` with `Success` (bool - `$true` if all windows passed), `Total` (int - entries checked), `Passed` (int), and `Failures` (array of objects with `WindowTitle`, `Handle`, `Expected`, `Actual`, and per-dimension `DeltaX`/`DeltaY`/`DeltaW`/`DeltaH`).

> The non-zero default tolerance absorbs invisible DWM drop-shadow borders (~7-14px) that `GetWindowRect` includes in its measurements. A tolerance of `0` would cause infinite retry loops because reported positions always differ slightly from the requested zone coordinates.

```powershell
# Verify layout positions after snapping, honoring the workspace desktop offset
$result = Confirm-WorkspaceWindowPositions `
    -LayoutConfig $config.Layout `
    -MonitorInfo $monitorInfo `
    -MonitorConfig $config.Monitors `
    -DesktopOffset $DesktopOffset

# Inspect failures (each carries the live handle for targeted rerun)
if (-not $result.Success) {
    $result.Failures | ForEach-Object { Write-Host $_.WindowTitle }
}
```

## [ConvertTo-InternalDesktopIndex](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/ConvertTo-InternalDesktopIndex.ps1)

- **Description:** Converts a 1-based layout desktop number (Desktop 1, 2, 3...) to the 0-based index used by the VirtualDesktop module, applying the workspace desktop offset via `(DesktopNumber - 1) + DesktopOffset`. Centralizes the conversion so `Snap-AllWindows`, `Confirm-WorkspaceWindowPositions`, and `Apply-FancyZones` all map desktop numbers identically and honor the offset consistently, removing a class of off-by-one races. Returns the resulting 0-based index.
- **Parameters:** -DesktopNumber, -DesktopOffset (default: 0)
- **Usage:** `ConvertTo-InternalDesktopIndex -DesktopNumber 1`, `ConvertTo-InternalDesktopIndex -DesktopNumber 1 -DesktopOffset 2`

Layout files express desktops as 1-based numbers, while the VirtualDesktop module uses 0-based indices. This helper applies the workspace `DesktopOffset` (the number of pre-existing desktops to the left) so that "alongside" workspaces resolve to the correct physical desktop. Centralizing the formula removes off-by-one races where one function applied the offset and another did not.

| Parameter       | Type | Default | Description                                        |
| --------------- | ---- | ------- | -------------------------------------------------- |
| `DesktopNumber` | int  | -       | 1-based desktop number from layout configuration   |
| `DesktopOffset` | int  | `0`     | Offset applied for "alongside" workspace placement |

```powershell
# First layout desktop with no offset -> 0-based index 0
ConvertTo-InternalDesktopIndex -DesktopNumber 1            # 0

# First workspace desktop sitting after two existing desktops -> index 2
ConvertTo-InternalDesktopIndex -DesktopNumber 1 -DesktopOffset 2  # 2
```

## [Ensure-VirtualDesktops](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Ensure-VirtualDesktops.ps1)

- **Description:** Ensures the specified number of virtual desktops exist, creating additional desktops when too few exist and removing the excess when too many exist. Optionally switches to a target desktop afterward. Requires the VirtualDesktop PowerShell module.
- **Recovery:** Runs a live RPC preflight (`Get-RpcRetryPolicy -Probe`, 5 attempts / 250 ms initial delay), wraps every desktop list/create/remove/switch call in RPC-aware retry helpers, and self-heals between attempts: when a call fails with the RPC-unavailable error family (classified via `Test-RpcUnavailableError`), the session's VirtualDesktop COM proxies are reconnected via `Reset-VirtualDesktopState` before the next retry. Verifies the final desktop count before returning success.
- **Parameters:** -Count, -SwitchToDesktop
- **Usage:** `Ensure-VirtualDesktops -Count 3`, `Ensure-VirtualDesktops -Count 3 -SwitchToDesktop 2`

Creates virtual desktops if fewer than `-Count` exist, up to the requested count, and removes extras (then switches to the first desktop) if more exist. After reconciling the count it can switch to a specific desktop via `-SwitchToDesktop` (1-based; `0` means don't switch). Returns `$true` on success and `$false` on failure (module missing or desktop create/remove failed). "The RPC server is unavailable. (0x800706BA)" failures - previously a known issue when Explorer had restarted earlier in the session (wallpaper, taskbar, or icon-cache operations) - now recover in place through the retry hook instead of failing the workspace run.

| Parameter          | Type | Default | Description                                                       |
| ------------------ | ---- | ------- | ----------------------------------------------------------------- |
| `-Count`           | int  | -       | Required. The total number of virtual desktops that should exist. |
| `-SwitchToDesktop` | int  | `0`     | Desktop to switch to (1-based, `0` = don't switch).               |

```powershell
# Ensure 3 virtual desktops exist
Ensure-VirtualDesktops -Count 3

# Ensure 3 desktops, then switch to desktop 2 (1-based)
Ensure-VirtualDesktops -Count 3 -SwitchToDesktop 2

# Verbose diagnostic output
Set-LogLevel Verbose { Ensure-VirtualDesktops -Count 4 }
```

**See also:** [Configuration: Window Layout](../configuration/guides/configure-window-layout.md)

## [Ensure-WindowsFormsLoaded](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Ensure-WindowsFormsLoaded.ps1)

- **Description:** Ensures the `System.Windows.Forms` assembly is loaded, calling `Add-Type` only if it is not already loaded. Uses a module-scoped flag to avoid repeated `Add-Type` calls.
- **Usage:** `Ensure-WindowsFormsLoaded`

## [Focus-VirtualDesktop](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Focus-VirtualDesktop.ps1)

- **Description:** Switches to a virtual desktop and locks keyboard focus onto a window that lives there, used as the final `WorkspaceActions` step so a workspace run reliably lands the user on the first desktop. Workspace setup (`Set-WorkspaceWindowLayout` / `Snap-AllWindows`) hops across every desktop while snapping windows and ends with a single, unverified `Switch-Desktop`; in a long-running shell the VirtualDesktop COM/RPC session can go stale and that switch silently no-ops, and even when it takes, nothing guarantees a foreground window on the target desktop - so focus can revert to a window snapped on a higher desktop and drag the view back with it. This function closes both gaps by reusing the proven `Switch-Desktop` + `Wait-DesktopSwitch` retry loop with a `Reset-VirtualDesktopState` recovery pass, then parking focus on a real window on the target desktop.
- **Parameters:** -DesktopNumber, -DesktopOffset
- **Usage:** `Focus-VirtualDesktop`, `Focus-VirtualDesktop -DesktopNumber 1 -DesktopOffset 2`

Resolves the target desktop via `ConvertTo-InternalDesktopIndex` (combining `DesktopNumber` and `DesktopOffset`), runs the `Switch-Desktop` + `Wait-DesktopSwitch` retry loop (up to 3 attempts) with a `Reset-VirtualDesktopState` recovery pass - the same block `Snap-AllWindows` uses - then refreshes the window cache and parks focus on a real window that lives on the target desktop. The focus-target scan is terminal-first and stops at the first window resolved to the target desktop, instead of resolving every window's desktop. It prefers Windows Terminal via `Focus-TerminalTab` (only when the terminal actually lives on that desktop, since activating one elsewhere would drag the view away), otherwise force-foregrounds the first window found there via `WindowModule.Native::ForceForegroundWindow`. Lazy-loads the VirtualDesktop module if needed and reports the outcome with a `=>` status message (focused, switched-but-no-window, or failure) rather than returning a value.

| Parameter        | Type | Default | Description                                                                       |
| ---------------- | ---- | ------- | --------------------------------------------------------------------------------- |
| `-DesktopNumber` | int  | `1`     | 1-based desktop number to focus (layout-file convention).                         |
| `-DesktopOffset` | int  | `0`     | Workspace offset - pre-existing desktops to the left, for "alongside" workspaces. |

```powershell
# Switch to and focus the first virtual desktop
Focus-VirtualDesktop

# Focus the first desktop of an alongside workspace that starts after two existing desktops
Focus-VirtualDesktop -DesktopNumber 1 -DesktopOffset 2
```

## [Format-ZoneContent](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Format-ZoneContent.ps1)

- **Description:** Formats an array of content items (process names, window titles) to fit within a specified character width. Handles multi-line content and truncates long lines with an ellipsis character. Returns an array of formatted strings suitable for ASCII art visualization.
- **Parameters:** -Content, -Width
- **Usage:** `Format-ZoneContent -Content @("ProcessName", "WindowTitle") -Width 16`

A helper used by the FancyZones layout visualization. Each item in `-Content` is coerced to a string and split on newlines; lines at or under `-Width` are kept as-is, while longer lines are truncated to `Width - 1` characters with a trailing `…`. The result is always returned as an array, even for a single element.

| Parameter  | Description                                                      |
| ---------- | ---------------------------------------------------------------- |
| `-Content` | Array of content items (process names, window titles) to format. |
| `-Width`   | Maximum width in characters for each line.                       |

```powershell
# Fit process name and window title into 16-character-wide cells
Format-ZoneContent -Content @("ProcessName", "WindowTitle") -Width 16
```

**See also:** [Generate-LayoutVisualization](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Generate-LayoutVisualization.ps1)

## [Generate-DynamicVisualization](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Generate-DynamicVisualization.ps1)

- **Description:** Dynamically generates an ASCII visualization for any grid-based layout. Analyzes a FancyZones grid layout definition and renders ASCII art showing zone boundaries and content, dynamically calculating column widths, row heights, and box-drawing characters from the zone boundaries. Used internally by `Generate-LayoutVisualization` and `Visualize-Layouts`.
- **Parameters:** -LayoutInfo, -ZoneContent, -ZoneNames, -TotalWidth
- **Usage:** `$visual = Generate-DynamicVisualization -LayoutInfo $layoutDef.info -ZoneContent $zoneContent -ZoneNames $zoneIndexToName`, `Generate-DynamicVisualization -LayoutInfo $layout.info -ZoneContent @{0 = @("Firefox", "YouTube")} -ZoneNames @{0 = "Top-Left"; 1 = "Top-Right"} -TotalWidth 80`

A rendering helper that turns a FancyZones grid definition into a string of box-drawing characters. It reads the `cell-child-map` to build a zone grid (via `Build-ZoneGridMap`), allocates each column proportionally from `columns-percentage` (falling back to equal widths, with an 8-character minimum per column), computes per-row heights to fit the longest zone content, and draws the appropriate corner, edge, and intersection glyphs based on how adjacent cells share zones. Empty zones display their `-ZoneNames` label (or `Zone N` when unnamed); content is centered with `Center-Text` and wrapped with `Format-ZoneContent`. Returns the assembled visualization as a string.

| Parameter      | Description                                                                                                                   |
| -------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `-LayoutInfo`  | Layout info object containing the `cell-child-map` (and optional `columns-percentage`) from the FancyZones layout definition. |
| `-ZoneContent` | Hashtable mapping zone index to a content array (e.g. process names and window titles).                                       |
| `-ZoneNames`   | Hashtable mapping zone index to a human-readable name (e.g. `0 -> "Top-Left"`); used to label empty zones. Defaults to `@{}`. |
| `-TotalWidth`  | Total width available for the visualization. Defaults to `54`.                                                                |

```powershell
# Render a layout using prepared zone content and index-to-name maps
$visual = Generate-DynamicVisualization -LayoutInfo $layoutDef.info -ZoneContent $zoneContent -ZoneNames $zoneIndexToName

# Render with inline content and a wider canvas
Generate-DynamicVisualization -LayoutInfo $layout.info -ZoneContent @{0 = @("Firefox", "YouTube")} -ZoneNames @{0 = "Top-Left"; 1 = "Top-Right"} -TotalWidth 80
```

**See also:** [Generate-LayoutVisualization](#generate-layoutvisualization), [Visualize-Layouts](#visualize-layouts)

## [Generate-LayoutVisualization](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Generate-LayoutVisualization.ps1)

- **Description:** Generates an ASCII art visualization of a FancyZones layout, showing which processes and windows are assigned to each zone. The visualization is built dynamically from the layout definition in `custom-layouts.json`, so it supports any grid-based layout configuration. Returns the rendered visualization as a string.
- **Parameters:** -LayoutType, -Windows, -DesktopNumber, -MonitorName, -LayoutsJsonPath
- **Usage:** `Generate-LayoutVisualization -LayoutType "One" -Windows $windows -DesktopNumber 1 -MonitorName "Primary"`

A helper used by `Visualize-Layouts` to render one monitor's layout. It maps each window's `Zone` to a zone index via `ZoneNameMappings` from `Configuration.psd1`, loads the matching grid definition through `Get-LayoutDefinition`, and hands the assembled zone content to `Generate-DynamicVisualization` for rendering. Only `grid`-type layouts are supported; unknown or non-grid layouts produce a descriptive message instead. When `-LayoutsJsonPath` is omitted, the path is resolved automatically from `$global:RepoRoot` or by walking up from the module location to `Windows\FancyZones\custom-layouts.json`.

| Parameter          | Description                                                                                                   |
| ------------------ | ------------------------------------------------------------------------------------------------------------- |
| `-LayoutType`      | The FancyZones layout type (`Zero`, `One`, `Two`, etc.).                                                      |
| `-Windows`         | Array of window configurations for this layout (each with `Zone`, `ProcessName`, and optional `WindowTitle`). |
| `-DesktopNumber`   | The virtual desktop number (1-based, e.g. `1` for the first desktop).                                         |
| `-MonitorName`     | The monitor name (`Primary`, `Secondary`, etc.).                                                              |
| `-LayoutsJsonPath` | Optional path to `custom-layouts.json`. Defaults to the standard location under the WinuX root.               |

```powershell
# Render the "One" layout for the primary monitor on the first virtual desktop
Generate-LayoutVisualization -LayoutType "One" -Windows $windows -DesktopNumber 1 -MonitorName "Primary"

# Point at a specific custom-layouts.json instead of auto-resolving the path
Generate-LayoutVisualization -LayoutType "Two" -Windows $windows -DesktopNumber 2 -MonitorName "Secondary" -LayoutsJsonPath "<DevRoot>\WinuX\Windows\FancyZones\custom-layouts.json"
```

## [Get-ActiveWindowInfo](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Get-ActiveWindowInfo.ps1)

- **Description:** Retrieves detailed information about all open windows (or a filtered subset) and writes it to `ActiveWindowInfo.txt` on the desktop, including process name, window title, handle, position, size, and a ready-to-use config template for each window. Useful for determining what values to use in layout configurations. In `-Continuous` mode it instead monitors the focused window in real time and appends each new focus change to the terminal so earlier entries remain visible and copyable.
- **Parameters:** -Window, -Continuous
- **Usage:** `Get-ActiveWindowInfo`, `Get-ActiveWindowInfo -Window "*Firefox*"`, `Get-ActiveWindowInfo -Window "(.*Calendar.*|.*Week.*)"`, `Get-ActiveWindowInfo -Continuous`

The one-shot run (no `-Continuous`) enumerates every open window, applies the optional title filter, and writes a timestamped report to `ActiveWindowInfo.txt` on the desktop. Each window block lists the process name, window title, handle, process ID, position, and size, followed by a `@{ ... }` config template (with `ProcessName`/`WindowTitle` prefilled and placeholder `DesktopNumber`/`Zone`/`Monitor`) that can be pasted directly into a layout configuration. `-Continuous` skips the file and prints each focused window's info to the terminal as you switch focus.

| Parameter     | Description                                                                                                                                                                                    |
| ------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-Window`     | A window title pattern to filter by, using the same wildcard/regex syntax used throughout the workspace setup (e.g. `*YouTube*`, `.*Firefox.*`). Position 0; omit to include all open windows. |
| `-Continuous` | Switch. Continuously monitors the focused window and appends its info to the terminal on each focus change (earlier entries are kept). Press Ctrl+C to stop.                                   |

```powershell
# Write every open window's info (and a config template) to ActiveWindowInfo.txt on the desktop
Get-ActiveWindowInfo

# Filter to windows whose title matches a wildcard pattern
Get-ActiveWindowInfo -Window "*Firefox*"

# Filter with a regex alternation pattern
Get-ActiveWindowInfo -Window "(.*Calendar.*|.*Week.*)"

# Live-monitor the focused window; switch windows to capture each, Ctrl+C to stop
Get-ActiveWindowInfo -Continuous
```

## [Get-AppliedFancyZonesState](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Get-AppliedFancyZonesState.ps1)

- **Description:** Reads (and briefly caches) the FancyZones `applied-layouts.json` file, which records the layout currently applied to each monitor on each virtual desktop. Returns a lookup hashtable keyed by `"{MonitorId}:{VirtualDesktopGUID}"` with layout UUID values, or `$null` if the file is missing or cannot be parsed. Used by `Apply-FancyZones` for idempotency, skipping keyboard-shortcut sends when a monitor already has the correct layout applied.
- **Parameters:** -Force
- **Usage:** `$state = Get-AppliedFancyZonesState`, `$freshState = Get-AppliedFancyZonesState -Force`

`MonitorId` is the FancyZones `monitor` field - either an EDID hardware code (e.g. `LEN8ABC`, `DELA1A8`) or a display path (e.g. `\\.\DISPLAY1`). Both the monitor and virtual-desktop GUID portions of each key are normalized to upper case. When the schema records a per-device `monitor-instance` (newer FancyZones), an additional instance-qualified key `"{MonitorId}|{MonitorInstance}:{VirtualDesktopGUID}"` is stored alongside the legacy EDID-only key, so consumers with instance data can match unambiguously when identical monitors share an EDID (the EDID-only key collides there, last write wins). The `applied-layouts.json` file is written by FancyZones in real time whenever a layout is applied (via keyboard shortcut, drag-drop, or the editor), so the cache TTL is kept short (10s); pass `-Force` to bypass the cache and re-read immediately after applying layouts.

| Parameter | Description                                                    |
| --------- | -------------------------------------------------------------- |
| `-Force`  | Forces a re-read of the file even if valid cached data exists. |

```powershell
# Read the applied-layout state and check whether a specific monitor/desktop
# already has the expected layout (idempotency check)
$state = Get-AppliedFancyZonesState
$key = "LEN8ABC:{CF6C2856-0D59-466D-AA7F-E6DF85C6034C}"
if ($state[$key] -eq "{9D07C01E-877C-4B03-B2D9-3DCC0C1E961F}") { "Already applied" }

# Force a fresh re-read after applying layouts
$freshState = Get-AppliedFancyZonesState -Force
```

**See also:** [Test-FancyZonesLayoutApplied](window.md#test-fancyzoneslayoutapplied)

## [Get-CachedFancyZonesLayouts](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Get-CachedFancyZonesLayouts.ps1)

- **Description:** Gets cached FancyZones layout data. Returns the FancyZones layout configuration from cache if still valid, otherwise reads and parses the `custom-layouts.json` file. This avoids repeated file I/O and JSON parsing. Returns a `PSObject` of parsed layout data, or `$null` if the file is not found or cannot be parsed.
- **Parameters:** -LayoutsJsonPath
- **Usage:** `$layouts = Get-CachedFancyZonesLayouts -LayoutsJsonPath "C:\Users\<User>\...\custom-layouts.json"`

## [Get-CachedMonitors](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Get-CachedMonitors.ps1)

- **Description:** Returns cached monitor information from `System.Windows.Forms.Screen`. Returns the monitor/screen information from cache if still valid, otherwise refreshes it from `System.Windows.Forms.Screen.AllScreens`. This reduces repeated calls to the Windows Forms API.
- **Usage:** `$monitors = Get-CachedMonitors`

Returns an array of `System.Windows.Forms.Screen` objects representing all monitors. The cache is considered stale when no monitors are cached yet or when its age exceeds the configured maximum (`$script:MonitorCache.MaxAgeSec`); on a stale read it ensures Windows Forms is loaded, refreshes `AllScreens`, and stamps the cache timestamp before returning.

## [Get-CachedWindows](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Get-CachedWindows.ps1)

- **Description:** Gets cached window enumeration results. Returns window information from the cache if it is still valid, otherwise refreshes the cache by calling the native `EnumWindows` function. This reduces repeated syscalls when multiple functions need window data.
- **Usage:** `$windows = Get-CachedWindows`

Returns an array of window information from `WindowModule.Native.GetAllWindows()`. On each call it compares the age of the cached snapshot against the configured maximum cache age; if the cache is empty or expired it re-enumerates all visible windows via the native API and refreshes the timestamp, otherwise it returns the existing snapshot unchanged. This shared cache backs the bulk window operations (`Move-Windows`, `Resize-Windows`, `Center-Windows`, `Get-WindowHandle`, `Resolve-PositionedWindowHandle`, and others) so a single layout pass enumerates windows once instead of per function.

```powershell
# Get all visible windows, using the cache when it is still fresh
$windows = Get-CachedWindows
```

**See also:** [Clear-WindowCache](window.md), [Set-WindowCacheMaxAge](window.md)

## [Get-CurrentLayout](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Get-CurrentLayout.ps1)

- **Description:** Reads the persisted `CurrentLayout.txt` snapshot written by `Save-CurrentLayout`. The file is a PowerShell data file (parsed with the same `Import-PowerShellDataFile` used for layout `.psd1` files) recording, per open workspace, the virtual desktop count, the FancyZones layout applied to each monitor on each desktop, and one record per window that was positioned and snapped (handle, process fingerprint, title, layout-relative desktop, monitor, and zone). It is read when a workspace is initialized, reopened, or opened `-Alongside` so identically-named windows (for example several `Browser` entries) can be returned to the same zones. Returns the whole snapshot, or - with `-Workspace` - a single workspace's section. Never throws: a missing, empty, or unparseable file simply returns `$null` so callers fall back to their normal stateless behaviour.
- **Parameters:** -LayoutsDir, -Workspace
- **Usage:** `Get-CurrentLayout -LayoutsDir $layoutsDir`, `Get-CurrentLayout -LayoutsDir $layoutsDir -Workspace "Example_PC"`

| Parameter     | Type   | Required | Description                                                                                        |
| ------------- | ------ | -------- | -------------------------------------------------------------------------------------------------- |
| `-LayoutsDir` | string | Yes      | The Layouts directory holding `CurrentLayout.txt` (`$MachineSpecificPaths.Projects.Self.Layouts`). |
| `-Workspace`  | string | No       | When supplied, returns only that workspace's section (or `$null` if absent).                       |

```powershell
# Pin duplicate-named windows back to their zones on reopen
$section = Get-CurrentLayout -LayoutsDir $layoutsDir -Workspace "Example_PC"
if ($section) { $section.Windows | ForEach-Object { "$($_.Zone) => $($_.Handle)" } }
```

**See also:** [Save-CurrentLayout](window.md), [Set-WorkspaceWindowLayout](window.md)

## [Get-DuplicateMonitorEdid](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Get-DuplicateMonitorEdid.ps1)

- **Description:** Returns the distinct EDID hardware codes that are shared by more than one display in a display-name-to-EDID map. `Apply-FancyZones` uses this helper during idempotency checks: FancyZones' `applied-layouts.json` keys each monitor by its EDID code plus the virtual desktop GUID, so when two or more identical monitor models report the same EDID their keys collide and a key can no longer be mapped back to one physical monitor. Detecting duplicates lets `Apply-FancyZones` disable the "already applied" skip and always reapply every monitor's layout rather than false-skipping one.
- **Parameters:** -DisplayToEdidMap
- **Usage:** `Get-DuplicateMonitorEdid -DisplayToEdidMap @{ '\\.\DISPLAY1' = 'AOCB316'; '\\.\DISPLAY2' = 'AOCB316' }`

Returns a distinct `[string[]]` of duplicated EDID codes. Returns an empty array when the map is `$null`, empty, has fewer than two entries, or no EDID appears more than once. Display names whose EDID value is empty are ignored when counting.

| Parameter           | Type          | Required | Description                                                                                                       |
| ------------------- | ------------- | -------- | ----------------------------------------------------------------------------------------------------------------- |
| `-DisplayToEdidMap` | `IDictionary` | No       | Map of display names (for example `\\.\DISPLAY1`) to EDID codes (for example `AOCB316`). May be `$null` or empty. |

```powershell
# Two displays of the same model share an EDID -> ambiguous identity
$duplicates = Get-DuplicateMonitorEdid -DisplayToEdidMap @{
    '\\.\DISPLAY1' = 'AOCB316'
    '\\.\DISPLAY2' = 'AOCB316'
}
# $duplicates -> @('AOCB316')

# Distinct EDIDs -> unambiguous identity, returns an empty array
Get-DuplicateMonitorEdid -DisplayToEdidMap @{
    '\\.\DISPLAY1' = 'AOCB316'
    '\\.\DISPLAY2' = 'LEN8ABC'
}
```

## [Get-FancyZone](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Get-FancyZone.ps1)

- **Description:** Gets FancyZone coordinates using human-readable zone names. Provides a user-friendly interface to get zone coordinates by using descriptive zone names instead of numeric indices, with the available names depending on the layout type.
- **Parameters:** -LayoutName, -ZoneName, -MonitorX, -MonitorY, -MonitorWidth, -MonitorHeight, -CustomLayoutsPath
- **Usage:** `Get-FancyZone -LayoutName "Seven" -ZoneName "Top-Right"`, `Get-FancyZone -LayoutName "Seven" -ZoneName "Left" -MonitorY -1440`, `Get-FancyZone -LayoutName "One" -ZoneName "Right" -MonitorX 1920`

Resolves a human-readable zone name to its numeric index via `ZoneNameMappings` in `Configuration.psd1`, then delegates to `Get-FancyZoneCoordinates` to compute the actual pixel bounds for that zone. Requires the global configuration to be loaded (`Load-PathConfiguration`); if the layout or zone name is unknown it lists the available layouts or zone names and returns `$null`. Returns a `PSCustomObject` with `ZoneIndex`, `X`, `Y`, `Width`, `Height`, `MonitorX`, `MonitorY`, `LayoutName`, and `ZoneName`.

Available zone names depend on the layout:

- **Zero** (Fullscreen): `Full`
- **One** (50/50 Split): `Left`, `Right`
- **Two** (3 Columns): `Left`, `Middle`, `Right`
- **Three** (4 Columns): `Far-Left`, `Middle-Left`, `Middle-Right`, `Far-Right`
- **Four** (2x2 Grid): `Top-Left`, `Bottom-Left`, `Top-Right`, `Bottom-Right`
- **Five** (67/33 Split): `Large`, `Small`
- **Six** (Left Full, Right Split): `Left`, `Top-Right`, `Bottom-Right`
- **Seven** (3 Columns, Right Split): `Left`, `Middle`, `Top-Right`, `Bottom-Right`
- **Eight** (Left+Right Split, Middle Full): `Top-Left`, `Bottom-Left`, `Middle`, `Top-Right`, `Bottom-Right`
- **Nine** (All Split): `Top-Left`, `Bottom-Left`, `Top-Middle`, `Bottom-Middle`, `Top-Right`, `Bottom-Right`

| Parameter            | Type   | Default | Description                                                  |
| -------------------- | ------ | ------- | ------------------------------------------------------------ |
| `-LayoutName`        | string | -       | FancyZones layout name (e.g., "Zero", "One", "Seven").       |
| `-ZoneName`          | string | -       | Human-readable zone name; valid values depend on the layout. |
| `-MonitorX`          | int    | `0`     | Monitor X offset.                                            |
| `-MonitorY`          | int    | `0`     | Monitor Y offset.                                            |
| `-MonitorWidth`      | int    | `3440`  | Monitor width in pixels.                                     |
| `-MonitorHeight`     | int    | `1440`  | Monitor height in pixels.                                    |
| `-CustomLayoutsPath` | string | -       | Optional path to a `custom-layouts.json` file.               |

```powershell
# Get coordinates for a named zone on the primary monitor
Get-FancyZone -LayoutName "Seven" -ZoneName "Top-Right"

# Account for a monitor stacked above (negative Y offset)
Get-FancyZone -LayoutName "Seven" -ZoneName "Left" -MonitorY -1440

# Use the returned object to position a window
$zone = Get-FancyZone -LayoutName "One" -ZoneName "Right"
Set-WindowPosition -WindowHandle $handle -X $zone.X -Y $zone.Y -Width $zone.Width -Height $zone.Height
```

**See also:** [Get-FancyZoneCoordinates](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Get-FancyZoneCoordinates.ps1)

## [Get-FancyZoneCoordinates](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Get-FancyZoneCoordinates.ps1)

- **Description:** Calculates zone coordinates from FancyZones custom layouts. Parses the FancyZones `custom-layouts.json` file and computes the actual pixel coordinates (X, Y, width, height) for each zone based on monitor dimensions and the layout's grid configuration. Only grid-type layouts are supported.
- **Parameters:** -LayoutName, -MonitorX, -MonitorY, -MonitorWidth, -MonitorHeight, -CustomLayoutsPath
- **Usage:** `Get-FancyZoneCoordinates -LayoutName "Seven" -MonitorX 0 -MonitorY -1440 -MonitorWidth 3440 -MonitorHeight 1440`, `$zones = Get-FancyZoneCoordinates -LayoutName "One"`
- **⚠️ Important:** The `spacing` value in `custom-layouts.json` **must be set to `3`**. FancyZones internally applies spacing asymmetrically (full spacing on outer edges, half on inner), while the zone coordinate calculation uses a uniform approximation. With `spacing: 3` the error is ~2px (well within snap tolerance). Larger values (e.g. 10, 20) cause coordinate mismatches that break `Snap-AllWindows` verification.

Reads the layout grid (rows, columns, row/column percentages, and `cell-child-map`) for the named layout and walks every cell to determine each zone's bounding range. It then converts those ranges into absolute pixel coordinates offset by the monitor position. When the JSON path is omitted it falls back to the machine-specific PowerToys CustomLayouts symlink target. Each zone is returned as a `PSCustomObject` with `ZoneIndex`, `X`, `Y`, `Width`, `Height`, `MonitorX`, `MonitorY`, and `LayoutName`.

| Parameter            | Description                                                                                     |
| -------------------- | ----------------------------------------------------------------------------------------------- |
| `-LayoutName`        | Required. The name of the FancyZones layout (e.g., `"Zero"`, `"One"`, `"Seven"`).               |
| `-MonitorX`          | The X position of the monitor (default: `0`).                                                   |
| `-MonitorY`          | The Y position of the monitor (default: `0`).                                                   |
| `-MonitorWidth`      | The width of the monitor in pixels (default: `3440`).                                           |
| `-MonitorHeight`     | The height of the monitor in pixels (default: `1440`).                                          |
| `-CustomLayoutsPath` | Optional path to `custom-layouts.json`. If not specified, uses the default FancyZones location. |

```powershell
# Calculate zones for a layout on a monitor stacked above the primary (negative Y)
Get-FancyZoneCoordinates -LayoutName "Seven" -MonitorX 0 -MonitorY -1440 -MonitorWidth 3440 -MonitorHeight 1440

# Capture zones and index into a specific one
$zones = Get-FancyZoneCoordinates -LayoutName "One"
$leftZone = $zones[0]  # Get coordinates for zone 0 (left)
```

## [Get-InsetWindowBounds](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Get-InsetWindowBounds.ps1)

- **Description:** Calculates inset window bounds centered within a target zone. Returns the adjusted bounds used before FancyZones snapping so the inset window stays centered inside the target zone, keeping the snap target unambiguous.
- **Parameters:** -TargetX, -TargetY, -TargetWidth, -TargetHeight, -InsetPercent
- **Usage:** `Get-InsetWindowBounds -TargetX 0 -TargetY 0 -TargetWidth 1920 -TargetHeight 1080`, `Get-InsetWindowBounds -TargetX 0 -TargetY 0 -TargetWidth 960 -TargetHeight 1080 -InsetPercent 0.05`

Computes shared inset bounds for pre-snap resizing. The target zone is shrunk by `InsetPercent` on each side and re-centered on the zone center, returning a `[PSCustomObject]` carrying both the original target values and the adjusted geometry: `AdjustedX`, `AdjustedY`, `AdjustedWidth`, `AdjustedHeight`, `AdjustedRight`, `AdjustedBottom`, plus `ZoneCenterX`/`ZoneCenterY`. Adjusted width and height are floored at 1px.

| Parameter       | Type   | Mandatory | Description                                                                     |
| --------------- | ------ | --------- | ------------------------------------------------------------------------------- |
| `-TargetX`      | int    | Yes       | Target zone X coordinate.                                                       |
| `-TargetY`      | int    | Yes       | Target zone Y coordinate.                                                       |
| `-TargetWidth`  | int    | Yes       | Target zone width.                                                              |
| `-TargetHeight` | int    | Yes       | Target zone height.                                                             |
| `-InsetPercent` | double | No        | Inset percentage applied on each side. Range `0.0`-`0.49`. Default `0.05` (5%). |

```powershell
# Inset bounds for a full 1920x1080 zone using the default 5% inset
$bounds = Get-InsetWindowBounds -TargetX 0 -TargetY 0 -TargetWidth 1920 -TargetHeight 1080

# Half-width zone with an explicit inset percentage
$bounds = Get-InsetWindowBounds -TargetX 0 -TargetY 0 -TargetWidth 960 -TargetHeight 1080 -InsetPercent 0.05
```

## [Get-LayoutDefinition](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Get-LayoutDefinition.ps1)

- **Description:** Retrieves a specific FancyZones layout definition from the `custom-layouts.json` configuration file by name. Used internally by the layout visualization system to access grid-based layout configurations (including cell-child-map data). Returns the matching layout definition object, or `$null` if the file is missing or no layout matches.
- **Parameters:** -LayoutsJsonPath, -LayoutName
- **Usage:** `$layout = Get-LayoutDefinition -LayoutsJsonPath "C:\Users\<User>\custom-layouts.json" -LayoutName "Eight"`

Reads the `custom-layouts.json` file (via a cached read through `Get-CachedFancyZonesLayouts` to avoid repeated file I/O), then filters the `custom-layouts` collection for an entry whose `name` matches `-LayoutName`. Writes an error and returns `$null` when the file is not found, the JSON fails to load, or parsing throws.

| Parameter          | Description                                                          |
| ------------------ | -------------------------------------------------------------------- |
| `-LayoutsJsonPath` | Path to the `custom-layouts.json` file to read.                      |
| `-LayoutName`      | Name of the layout to retrieve (e.g., `"Zero"`, `"One"`, `"Eight"`). |

```powershell
# Retrieve the "Eight" layout definition from a custom-layouts.json file
$layout = Get-LayoutDefinition -LayoutsJsonPath "C:\Users\<User>\custom-layouts.json" -LayoutName "Eight"
```

## [Get-MonitorInfo](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Get-MonitorInfo.ps1)

- **Description:** Gets information about all connected monitors, including their dimensions, position, work area, and primary status, which helps in calculating zone positions for FancyZones.
- **Parameters:** -Quiet
- **Usage:** `Get-MonitorInfo`, `Get-MonitorInfo -Quiet`

Returns an array of `PSCustomObject` entries (one per connected display) with `DeviceName`, full bounds (`Left`/`Top`/`Right`/`Bottom`/`Width`/`Height`), work-area bounds (`WorkAreaLeft`/`WorkAreaTop`/`WorkAreaRight`/`WorkAreaBottom`/`WorkAreaWidth`/`WorkAreaHeight`), and `IsPrimary`. Monitor enumeration is cached via `Get-CachedMonitors`. Under `Set-LogLevel Verbose` it prints a per-monitor breakdown (device, resolution, position, work area), unless `-Quiet` is set to suppress all console output.

| Parameter | Type   | Required | Description                                                     |
| --------- | ------ | -------- | --------------------------------------------------------------- |
| `-Quiet`  | switch | No       | Suppresses console output for silent retrieval of monitor info. |

```powershell
# Return monitor info objects (no console output by default)
Get-MonitorInfo

# Retrieve silently, e.g. when piping into another function
$monitors = Get-MonitorInfo -Quiet

# Verbose diagnostic output
Set-LogLevel Verbose { Get-MonitorInfo }
```

**See also:** [Get-MonitorSpecs](window.md#get-monitorspecs)

## [Get-MonitorSpecs](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Get-MonitorSpecs.ps1)

- **Description:** Gets monitor specifications in a format suitable for layout configurations. Returns monitor information with standardized labels (Primary, Secondary, Monitor3, etc.) that can be used directly in layout configuration files, making layouts portable across different display configurations.
- **Parameters:** -AsHashtable, -MonitorInfo
- **Usage:** `Get-MonitorSpecs`, `Get-MonitorSpecs -AsHashtable`, `Get-MonitorSpecs -MonitorInfo $monitorInfo`

Calls `Get-MonitorInfo` (or reuses pre-fetched info via `-MonitorInfo`) and remaps each display to a stable label: the primary monitor becomes `Primary`, the first non-primary becomes `Secondary`, and any further monitors become `Monitor3`, `Monitor4`, etc. Each entry exposes `X`, `Y`, `Width`, `Height`, `DeviceName`, and the work-area fields `WorkX`, `WorkY`, `WorkWidth`, `WorkHeight` (the screen minus the taskbar - what FancyZones lays zones over). By default the result is a `PSCustomObject` for easy property access; with `-AsHashtable` it returns a hashtable suited to layout configuration files. Returns `$null` (with an error) when no monitors are detected.

| Parameter      | Description                                                                                                                            |
| -------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `-AsHashtable` | Returns the result as a hashtable instead of a `PSCustomObject`, for easier use in layout configuration files.                         |
| `-MonitorInfo` | Optional pre-fetched monitor information from `Get-MonitorInfo`. If provided, skips the monitor detection call for better performance. |

```powershell
# Get monitor specs and access the primary display
$monitors = Get-MonitorSpecs
$primary  = $monitors.Primary

# Reuse cached monitor info to avoid a redundant detection call
$monitorInfo = Get-MonitorInfo
$specs       = Get-MonitorSpecs -MonitorInfo $monitorInfo

# Get specs as a hashtable for layout configuration files
$monitors = Get-MonitorSpecs -AsHashtable

# Use the specs to build a FancyZone bound to the primary monitor
$zone = Get-FancyZone -LayoutName "One" -ZoneName "Left" `
    -MonitorX $monitors.Primary.X -MonitorY $monitors.Primary.Y `
    -MonitorWidth $monitors.Primary.Width -MonitorHeight $monitors.Primary.Height
```

## [Get-NextAvailableDesktopIndex](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Get-NextAvailableDesktopIndex.ps1)

- **Description:** Gets the 0-based index of the next available virtual desktop (one to the right of all existing desktops). Returns the first desktop position after all existing desktops, useful when opening a new workspace on a separate set of virtual desktops without disturbing the current workspace. Used by Open-Workspace with its -Alongside flag.
- **Usage:** `Get-NextAvailableDesktopIndex`

Lazy-loads the `VirtualDesktop` module via the cached `Import-VirtualDesktopModule` loader (no `Get-Module -ListAvailable` disk scan per call), then counts the existing desktops via `Get-DesktopList` and returns that count, which is the 0-based index of the next position after all current desktops (e.g. with 2 desktops at indices 0 and 1, it returns `2`). If the `VirtualDesktop` module is unavailable or an error occurs, it returns `$null` - never `0`, because an alongside caller falling back to offset 0 would open the new workspace on top of the current one; callers treat `$null` as "abort the alongside open".

```powershell
# If there are 2 desktops (0 and 1), returns 2
$nextIndex = Get-NextAvailableDesktopIndex

# Verbose diagnostic output
Set-LogLevel Verbose { Get-NextAvailableDesktopIndex }
```

## [Get-PositionedWindowCount](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Get-PositionedWindowCount.ps1)

- **Description:** Gets the count of tracked positioned windows. Returns the number of window handles that have been registered as positioned by `Set-WindowLayouts` (0 if none have been tracked).
- **Usage:** `Get-PositionedWindowCount`

## [Get-VirtualDesktopGuid](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Get-VirtualDesktopGuid.ps1)

- **Description:** Resolves the GUID of a virtual desktop by its 0-based index. Reads the ordered `VirtualDesktopIDs` registry value (16-byte GUID chunks) and returns the requested desktop's GUID as an upper-case braced string (e.g., `{CF6C2856-0D59-466D-AA7F-E6DF85C6034C}`) - the same form FancyZones records per desktop in `applied-layouts.json`. Returns `$null` when the registry value is unavailable or the index is out of range.
- **Parameters:** -DesktopIndex
- **Usage:** `Get-VirtualDesktopGuid -DesktopIndex 0`

Reads `HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VirtualDesktops\VirtualDesktopIDs`, slices the binary value into 16-byte GUID chunks, and returns the GUID at the requested index. Because this is the same GUID FancyZones records per desktop, it can be used to correlate a live virtual desktop with its applied FancyZones layout.

| Parameter       | Type | Default | Description                                               |
| --------------- | ---- | ------- | --------------------------------------------------------- |
| `-DesktopIndex` | int  | -       | The 0-based virtual desktop index to resolve (Mandatory). |

```powershell
# Resolve the GUID of the first virtual desktop
Get-VirtualDesktopGuid -DesktopIndex 0
# {CF6C2856-0D59-466D-AA7F-E6DF85C6034C}

# Pipe the GUID into a FancyZones layout check
$guid = Get-VirtualDesktopGuid -DesktopIndex 0
Test-FancyZonesLayoutApplied -VirtualDesktopGuid $guid
```

**See also:** [Test-FancyZonesLayoutApplied](../modules/window.md)

## [Get-WindowDisplayName](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Get-WindowDisplayName.ps1)

- **Description:** Resolves a friendly display label for a window from its process name, falling back to its window title. Known processes are mapped to a product name (e.g. `WindowsTerminal` => "Windows Terminal", whose live title follows the active tab); any other process uses the supplied title. Used by `Center-Windows` and `Move-Windows` to label the windows they acted on.
- **Parameters:** `-ProcessName` `[-Title]`
- **Usage:** `Get-WindowDisplayName -ProcessName "WindowsTerminal" -Title "PowerShell"`

## [Get-WindowHandle](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Get-WindowHandle.ps1)

- **Description:** Retrieves window handles (HWND) for windows belonging to the specified process name or window title pattern. Both `-ProcessName` and `-WindowTitle` accept exact names, wildcard patterns (`*`, `?`), and full .NET regex, with automatic detection and conversion; plain names without special characters use exact matching for performance. When both parameters are provided, windows matching EITHER criterion are returned (OR logic), giving redundant, more robust window detection.
- **Parameters:** -ProcessName, -WindowTitle, -All
- **Usage:** `Get-WindowHandle -ProcessName "chrome"`, `Get-WindowHandle -ProcessName "(firefox|chrome|msedge|brave)"`, `Get-WindowHandle -WindowTitle "*YouTube*"`, `Get-WindowHandle -WindowTitle "^Chrome.*Google"`, `Get-WindowHandle -WindowTitle "(?i)notepad"`, `Get-WindowHandle -ProcessName "WhatsApp" -WindowTitle ".*WhatsApp.*"`

Resolves windows from a cached native enumeration (no repeated `EnumWindows`/`Get-Process` calls). Each `-ProcessName` and `-WindowTitle` value is first tried as a regex; if that fails, a wildcard pattern (`*`/`?`) is converted to regex, and an invalid pattern raises a `Write-Error`. Process names that are plain (or contain regex metacharacters like `+` but are not valid regex/wildcards) fall back to exact matching. With no parameters, every cached window is returned.

| Parameter      | Description                                                                                             |
| -------------- | ------------------------------------------------------------------------------------------------------- |
| `-ProcessName` | Process name without `.exe`. Exact, wildcard (`*`, `?`), or regex; plain names use fast exact matching. |
| `-WindowTitle` | Pattern matched against window titles. Exact, wildcard (`*`, `?`), or regex.                            |
| `-All`         | Switch on the default `All` parameter set; returns all windows when no filter criterion is supplied.    |

```powershell
# Exact process-name match (fast path)
Get-WindowHandle -ProcessName "chrome"

# Regex alternation across multiple browsers
Get-WindowHandle -ProcessName "(firefox|chrome|msedge|brave)"

# Wildcard title match
Get-WindowHandle -WindowTitle "*YouTube*"

# Case-insensitive regex title match
Get-WindowHandle -WindowTitle "(?i)notepad"

# Combine both: matches EITHER criterion (OR logic) for redundancy
Get-WindowHandle -ProcessName "WhatsApp" -WindowTitle ".*WhatsApp.*"

# Resolve a handle and feed it to positioning
$handle = (Get-WindowHandle -ProcessName "firefox").Handle
Set-WindowPosition -WindowHandle $handle -X 0 -Y 0 -Width 960 -Height 1080
```

## [Get-WindowModuleDelays](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Get-WindowModuleDelays.ps1)

- **Description:** Gets the current Window module timing configuration. Returns a clone of the module-scoped timing configuration hashtable, allowing external tuning of the delay values (in milliseconds) used throughout the module.
- **Usage:** `Get-WindowModuleDelays`

## [Import-VirtualDesktopModule](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Import-VirtualDesktopModule.ps1)

- **Description:** Lazily imports the VirtualDesktop module with caching. Checks whether the module is available and imports it only once, using module-scoped state to avoid repeated `Get-Module` calls. Returns `$true` if the module is loaded and ready, `$false` otherwise.
- **Parameters:** -Silent
- **Usage:** `if (Import-VirtualDesktopModule) { ... }`, `$hasModule = Import-VirtualDesktopModule -Silent`

On first call it queries `Get-Module -ListAvailable` once, caches the result in module-scoped state, and short-circuits on every subsequent call. If the module is unavailable it warns with the install command (`Install-Module -Name VirtualDesktop -Scope CurrentUser`) unless `-Silent` is set; if already loaded by another source it reuses it, otherwise it imports it. Returns a boolean reflecting whether the module is loaded and ready.

| Parameter | Description                                                                |
| --------- | -------------------------------------------------------------------------- |
| `-Silent` | Suppresses warning messages when the module is not found or fails to load. |

```powershell
# Gate VirtualDesktop cmdlet usage behind a successful import
if (Import-VirtualDesktopModule) {
    # Use VirtualDesktop cmdlets
}

# Probe for availability without emitting warnings
$hasModule = Import-VirtualDesktopModule -Silent
```

## [Initialize-PositionedWindowTracking](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Initialize-PositionedWindowTracking.ps1)

- **Description:** Initializes or clears the module-scoped tracking set for positioned windows. Creates a collection that tracks window handles positioned by `Set-WindowLayouts`; if the set already exists it is cleared instead. This lets `Snap-AllWindows` snap only the windows that were intentionally positioned.
- **Usage:** `Initialize-PositionedWindowTracking`

```powershell
# Initialize (or reset) positioned-window tracking quietly
Initialize-PositionedWindowTracking

# Verbose diagnostic output
Set-LogLevel Verbose { Initialize-PositionedWindowTracking }
```

## [Initialize-WorkspaceWindowLayoutRerun](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Initialize-WorkspaceWindowLayoutRerun.ps1)

- **Description:** Prepares workspace window layout state before opening a rerun shell. For every rerun it runs the live RPC preflight through `Get-RpcRetryPolicy -Probe` when available. In window-only retry mode it preserves the existing FancyZones process, applied monitor layouts, virtual desktops, and caches for a targeted failed-window retry. In full cleanup mode it force-restarts FancyZones via `Start-FancyZones` with a settled verification pass, resets virtual desktops, and clears the FancyZones, monitor, and window caches before the caller invokes `ReRun-LastCommand`. The Window module owns this behavior because it knows whether a retry should preserve or reset the current FancyZones/virtual desktop state.
- **Parameters:** -WindowOnlyRetry
- **Usage:** `Initialize-WorkspaceWindowLayoutRerun -WindowOnlyRetry`, `Initialize-WorkspaceWindowLayoutRerun`

Keeps FancyZones and desktop recovery owned by the Window module instead of the generic `ReRun-LastCommand` helper. Returns `$true` when state is ready (always so in window-only mode), or the combined readiness of the FancyZones restart and the desktop/cache reset in full cleanup mode.

| Parameter          | Type   | Default | Description                                                                                 |
| ------------------ | ------ | ------- | ------------------------------------------------------------------------------------------- |
| `-WindowOnlyRetry` | switch | -       | Preserves current FancyZones, virtual desktop, and cache state for a targeted window retry. |

**What happens:**

1. Runs the live RPC preflight through `Get-RpcRetryPolicy -Probe` (when the command is available).
2. In `-WindowOnlyRetry` mode, returns `$true` after preserving the current layout state.
3. In full cleanup mode, force-restarts FancyZones with `Start-FancyZones -ForceRestart`.
4. Runs a settled, non-force FancyZones verification pass to ensure startup has settled.
5. Resets virtual desktops through `Remove-VirtualDesktops`.
6. Clears the FancyZones, monitor, and window caches.

```powershell
# Window-only mode: run RPC preflight and preserve current layout
# state for a targeted failed-window retry.
Initialize-WorkspaceWindowLayoutRerun -WindowOnlyRetry

# Full cleanup: RPC preflight, restart FancyZones, reset virtual
# desktops, and clear layout caches for a clean rerun.
Initialize-WorkspaceWindowLayoutRerun
```

## [Move-Windows](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Move-Windows.ps1)

- **Description:** Enumerates all visible application windows and moves each one to a specified virtual desktop (1-based; desktop 1 is the first). If the target desktop does not exist it is created automatically, and after the move pass focus is switched to the destination desktop. Use `-Current` to target the calling terminal's own desktop without knowing its number. Optional `-Monitor` repositions windows onto a target physical monitor in the same pass, preserving each window's relative placement from its source monitor work area and clamping to the destination work area for safe multi-resolution placement. Filtering by `-ProcessName` and/or `-WindowTitle` supports exact, wildcard, and regex matching (delegated to `Get-WindowHandle`); when both are given, windows matching either criterion are moved (OR logic). Windows already on the target desktop are skipped unless monitor repositioning is requested.
- **Parameters:** -VirtualDesktop, -Current, -ProcessName, -WindowTitle, -Monitor
- **Usage:** `Move-Windows`, `Move-Windows -VirtualDesktop 2`, `Move-Windows -Current`, `Move-Windows -Current -ProcessName "chrome"`, `Move-Windows -WindowTitle "*YouTube*"`, `Move-Windows -ProcessName "chrome" -WindowTitle "*GitHub*"`, `Move-Windows -Current -Monitor Secondary`, `Move-Windows -VirtualDesktop 2 -Monitor 1`

Moves every visible window to a target virtual desktop and, optionally, a target physical monitor. The `-VirtualDesktop` and `-Current` parameters are mutually exclusive (separate parameter sets). Missing desktops are created on demand via `Ensure-VirtualDesktops`. Monitor targeting accepts a 1-based index (`1`, `2`), standardized labels (`Primary`, `Secondary`, `Monitor3`, ...), or an exact device name (for example `\\.\DISPLAY1`). System and shell windows (Program Manager, Start, Search, overlays, zero-size windows, etc.) are excluded. Under `Set-LogLevel Verbose`, a per-window trace plus a summary of moved, already-there, skipped, enumerated, eligible, and exclusion (skip-title / invalid-size) counts is printed. VirtualDesktop calls are wrapped with optional exponential-backoff retries (`Invoke-WithRetry`) to absorb transient RPC failures such as `0x800706BA`.

| Parameter         | Type   | Default | Description                                                                                                       |
| ----------------- | ------ | ------- | ----------------------------------------------------------------------------------------------------------------- |
| `-VirtualDesktop` | int    | `1`     | Target virtual desktop (1-based, range 1-100). Cannot be combined with `-Current`.                                |
| `-Current`        | switch | -       | Target the calling terminal's current virtual desktop (auto-detected). Cannot be combined with `-VirtualDesktop`. |
| `-ProcessName`    | string | -       | Only move windows whose process name (without `.exe`) matches; exact, wildcard, or regex. OR with `-WindowTitle`. |
| `-WindowTitle`    | string | -       | Only move windows whose title matches; wildcard or regex. OR with `-ProcessName`.                                 |
| `-Monitor`        | string | -       | Also reposition windows onto a target monitor by 1-based index, label, or device name.                            |

```powershell
# Move all windows to the first virtual desktop (default)
Move-Windows

# Move all windows to the calling terminal's own desktop
Move-Windows -Current

# Verbose diagnostic output
Set-LogLevel Verbose { Move-Windows -VirtualDesktop 3 -ProcessName "chrome" }

# Move windows whose title starts with "Visual Studio" (regex)
Move-Windows -WindowTitle "^Visual Studio"

# Move Chrome windows OR windows with "GitHub" in the title (OR logic)
Move-Windows -ProcessName "chrome" -WindowTitle "*GitHub*"

# Move all windows to desktop 2 and reposition them onto monitor index 1
Move-Windows -VirtualDesktop 2 -Monitor 1
```

**See also:** [Reset-Windows](window.md), [Move-WindowToVirtualDesktop](window.md)

## [Move-WindowToVirtualDesktop](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Move-WindowToVirtualDesktop.ps1)

- **Description:** Moves a window (identified by its handle) to the specified virtual desktop number. Requires the VirtualDesktop module or falls back to COM automation. Uses 0-based desktop indexing internally; layout files use 1-based indexing, which is converted before this function is called.
- **Parameters:** -WindowHandle, -DesktopNumber
- **Usage:** `Move-WindowToVirtualDesktop -WindowHandle $handle -DesktopNumber 0`, `Move-WindowToVirtualDesktop -WindowHandle $handle -DesktopNumber 1`

A window already on the target desktop returns `$true` immediately (no COM move, no settle delay) - the common case, since workspace windows are desktop-moved from more than one code path. Otherwise it validates the target index against the available desktop count, resolves the destination desktop by its 0-based index, and moves the window there. After a real move the result is verified immediately and then polled briefly (10ms steps, ~100ms budget) instead of a fixed sleep, tolerating the transient `TYPE_E_ELEMENTNOTFOUND` error that the underlying COM interfaces often raise even on success. The script-scoped `$script:LastMoveWindowToVirtualDesktopResult.Moved` reports whether a real move happened, so callers can skip their own settle delays on the fast path. Returns `$true` on confirmed success and `$false` on failure or an out-of-range index. If the VirtualDesktop module is missing it warns with install instructions and returns `$false`.

| Parameter        | Type   | Mandatory | Description                                 |
| ---------------- | ------ | --------- | ------------------------------------------- |
| `-WindowHandle`  | IntPtr | Yes       | The window handle (HWND) to move.           |
| `-DesktopNumber` | int    | Yes       | The target virtual desktop (0-based index). |

```powershell
# Get a window handle and move it to the first desktop (0-based)
$handle = (Get-WindowHandle -ProcessName "chrome")[0].Handle
Move-WindowToVirtualDesktop -WindowHandle $handle -DesktopNumber 0

# Verbose diagnostic output
Set-LogLevel Verbose { Move-WindowToVirtualDesktop -WindowHandle $handle -DesktopNumber 1 }
```

**See also:** [Get-WindowHandle](window.md), [Ensure-VirtualDesktops](window.md)

## [Reset-KeyboardModifiers](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Reset-KeyboardModifiers.ps1)

- **Description:** Releases modifier keys (Shift, Ctrl, Alt, Win - left, right, and neutral variants) that the session reports as logically held down, by injecting the matching key-up events in a single `SendInput` batch. This clears the state an interrupted synthesized-input sequence leaves behind - the "terminal input locks up during workspace orchestration" known issue, where typed letters come out as caps and Enter stops submitting - without signing out. Keys that are not held are never touched, toggle keys (Caps Lock, Num Lock) are never sent, and on a quiescent keyboard the call is a read-only no-op. Called automatically by `Snap-AllWindows` (at pass start, before each snap retry, and on pass failure), by `Set-WorkspaceWindowLayout` and `Rerun-LastCommand` before a rerun respawns the shell, and by `Open-Workspace` when the flow ends.
- **Parameters:** -IncludeMouseButton
- **Usage:** `Reset-KeyboardModifiers`, `Reset-KeyboardModifiers -IncludeMouseButton`

Returns the names of the keys that were released (empty when none were stuck) and logs a warning listing them. If a stuck Shift prevents submitting the command in the first place (Enter inserts a new line instead of executing - PSReadLine reads it as `Shift+Enter`), tap both Shift keys first: a physical press and release also clears the stuck state for that key, after which the command can be run to release any remaining variants.

| Parameter             | Type   | Default | Description                                                                                                                                        |
| --------------------- | ------ | ------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-IncludeMouseButton` | switch | -       | Also release the left mouse button when reported held (an interrupted shift-drag snap strands it pressed). Orchestration failure paths enable it. |

```powershell
# Release any stuck Shift/Ctrl/Alt/Win keys
Reset-KeyboardModifiers

# Post-failure cleanup: additionally release a stuck left mouse button
Reset-KeyboardModifiers -IncludeMouseButton
```

**See also:** [Snap-AllWindows](window.md#snap-allwindows), [Set-WorkspaceWindowLayout](window.md#set-workspacewindowlayout)

## [Reset-Windows](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Reset-Windows.ps1)

- **Description:** Convenience wrapper that resets the window layout to a clean slate for layout testing. Runs four steps in order: `Remove-VirtualDesktops` (collapse down to a single virtual desktop), `Move-Windows` (move every window to the target virtual desktop and, optionally, a target monitor), `Center-Windows` (center every window on its monitor), and finally `Focus-TerminalTab` (focuses Windows Terminal to continue working). Defaults for `-VirtualDesktop` and `-Monitor` are read per machine from configuration.
- **Parameters:** -VirtualDesktop (default: per-machine config), -Monitor (default: per-machine config)
- **Usage:** `Reset-Windows`, `Reset-Windows -VirtualDesktop 2 -Monitor Primary`, `Reset-Windows -Monitor ""`

Reproduces the manual reset sequence in one call. Per-machine defaults are read from `$global:Configuration.ResetAllWindowsDefaults`, keyed by the current machine type (PC, Laptop, Work, Test) as resolved by `DetermineMachineType`, falling back to a `Default` entry and then to virtual desktop 1 with no monitor targeting. On the PC, windows are consolidated onto monitor 2; on the laptop and work machines no monitor targeting is applied. Explicitly passing `-VirtualDesktop` or `-Monitor` overrides the configured default for that run.

This replaces the manual sequences:

```powershell
# PC
Remove-VirtualDesktops; Move-Windows -Monitor 2 -VirtualDesktop 1; Center-Windows

# Laptop / Work
Remove-VirtualDesktops; Move-Windows -VirtualDesktop 1; Center-Windows
```

| Parameter         | Type   | Default            | Description                                                                                                                                                                                                      |
| ----------------- | ------ | ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-VirtualDesktop` | int    | per-machine config | 1-based virtual desktop to consolidate all windows onto. When omitted, the per-machine default from `ResetAllWindowsDefaults` is used.                                                                           |
| `-Monitor`        | string | per-machine config | Target physical monitor by 1-based index (`2`), label (`Primary`, `Secondary`, `Monitor3`), or device name (`\\.\DISPLAY1`). Pass `""` to skip monitor targeting. When omitted, the per-machine default is used. |

```powershell
# Use the current machine's configured defaults
Reset-Windows

# Verbose diagnostic output
Set-LogLevel Verbose { Reset-Windows }

# Override defaults: consolidate onto virtual desktop 2 and monitor Primary
Reset-Windows -VirtualDesktop 2 -Monitor Primary

# Skip monitor targeting for this run, keep the configured virtual desktop
Reset-Windows -Monitor ""
```

## [Reset-VirtualDesktopComProxy](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Reset-VirtualDesktopComProxy.ps1)

- **Description:** Reconnects the `VirtualDesktop` module's cached COM proxies to the current shell via reflection. The module's compiled `DesktopManager` class creates its COM proxies once per process in a static constructor and caches them in static fields; after an Explorer restart those proxies are permanently disconnected and every VirtualDesktop call fails with "The RPC server is unavailable" (`0x800706BA`) - and re-importing the module can never fix it, because the compiled assembly stays loaded and the constructor never runs again. This function replays that constructor: it creates a fresh ImmersiveShell service provider and overwrites the static COM fields with newly connected proxies, recovering the session in place without a new shell.
- **Usage:** `Reset-VirtualDesktopComProxy`, `if (Test-RpcUnavailableError $_) { [void](Reset-VirtualDesktopComProxy) }`

Returns a Boolean: `$true` when the compiled types are not loaded yet (the first real call creates fresh proxies on its own) or when every field was rebuilt; `$false` when the rebuild failed - typically while a restarted Explorer is still re-registering its COM classes, in which case retrying after a short delay succeeds. Used by `Reset-VirtualDesktopState` as the first (and decisive) recovery layer.

**See also:** [Reset-VirtualDesktopState](window.md#reset-virtualdesktopstate), [Test-VirtualDesktopComHealth](window.md#test-virtualdesktopcomhealth), [Test-RpcUnavailableError](helper.md#test-rpcunavailableerror)

## [Reset-VirtualDesktopState](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Reset-VirtualDesktopState.ps1)

- **Description:** Restores a working VirtualDesktop session in place after the COM/RPC state has gone stale (the `0x800706BA` failure family an Explorer restart leaves behind). Two recovery layers: first `Reset-VirtualDesktopComProxy` reconnects the compiled type's cached static COM proxies to the current shell (the step that actually repairs a stale session - re-importing the module alone can never refresh them), then the module is removed, the module-scoped lazy-load cache (`$script:VirtualDesktopState`) is cleared, and the module is re-imported via `Import-VirtualDesktopModule`. When `Test-VirtualDesktopComHealth` is available, a live in-process roundtrip verifies the session actually works before success is reported.
- **Usage:** `Reset-VirtualDesktopState`, `if (Reset-VirtualDesktopState) { Switch-Desktop -Desktop 0 }`

Returns a Boolean: `$true` only when the VirtualDesktop session is verified ready after the reset, otherwise `$false` (safe to retry after a delay - a restarted Explorer needs a moment to re-register its COM classes). Module removal failures are ignored (the module may not currently be loaded). Callers: `Snap-AllWindows` and `Focus-VirtualDesktop` when a desktop switch cannot be verified, the RPC retry hooks in `Ensure-VirtualDesktops` and `Remove-VirtualDesktops`, `Repair-RpcServer` as its primary recovery step, and `Restart-Explorer` proactively right after restarting the shell.

```powershell
# Reconnect the session and only switch when it is verified ready again
if (Reset-VirtualDesktopState) { Switch-Desktop -Desktop 0 }
```

**See also:** [Reset-VirtualDesktopComProxy](window.md#reset-virtualdesktopcomproxy), [Focus-VirtualDesktop](window.md#focus-virtualdesktop)

## [Resize-Windows](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Resize-Windows.ps1)

- **Description:** Resizes open windows either by a percentage (scaling each window's width and height while keeping its center point fixed) or to inset bounds within a target zone. In percentage mode a value of 100 leaves windows unchanged, below 100 shrinks them, and above 100 enlarges them, with results clamped to the monitor work area. When `TargetX`/`TargetY`/`TargetWidth`/`TargetHeight` are supplied it switches to target-bounds mode, using the shared FancyZones pre-snap inset sizing logic (an `-InsetPercent` of 0 places the window at the exact bounds, which is how `Center-Windows` reuses this path). Like `Move-Windows`, it can target all visible windows, a filtered set matching a `-ProcessName` and/or `-WindowTitle` pattern (delegated to `Get-WindowHandle`), or a single window by handle.
- **Parameters:** -Percent (default: 70), -ProcessName, -WindowTitle, -WindowHandle, -TargetX, -TargetY, -TargetWidth, -TargetHeight, -InsetPercent (default: 0.05), -Tolerance, -SkipIfAlreadyPositioned
- **Usage:** `Resize-Windows`, `Resize-Windows -Percent 120`, `Resize-Windows -Percent 50 -ProcessName "chrome"`, `Resize-Windows -WindowTitle "*YouTube*" -Percent 120`, `Resize-Windows -WindowHandle $handle`, `Resize-Windows -WindowHandle $handle -TargetX 0 -TargetY 0 -TargetWidth 1720 -TargetHeight 1440 -SkipIfAlreadyPositioned`

Operates in two modes. **Percentage mode** is the general utility path: it selects windows (all via `Get-CachedWindows`, a filtered set via `Get-WindowHandle`, or a single `-WindowHandle`), scales each window's current dimensions by `Percent`, and re-centers them on their original center point, clamping size and position to the owning monitor's work area (minimum 100px) so nothing extends off-screen. **Target-bounds mode** activates when all four `Target*` parameters are provided; it delegates to `Get-InsetWindowBounds` to compute the shared inset geometry and is the single source of truth for the pre-snap resize used by `Set-WindowLayouts`, `Resize-PositionedWindows`, `Snap-AllWindows` retries, and `Center-Windows`. System/shell windows (Program Manager, Start, Search, etc.) and zero-size windows are skipped. `-ProcessName`/`-WindowTitle` matching is delegated to `Get-WindowHandle` (exact names, wildcard patterns, and regex, with OR logic when both are supplied). Single-handle mode is served from the window cache without forcing a refresh per call (the cache's own 50ms TTL keeps the data fresh enough for the skip-tolerance check) - it runs once per window in tight loops like `Resize-PositionedWindows` and snap retries. Only the user-facing resize-all/matching invocation prints a title and summary in percent mode; single-handle calls no longer print a success line per window (verbose mode still logs each).

| Parameter                        | Description                                                                                                                                             |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-Percent`                       | Percentage to scale each window's current size by. Default `70`. Range 10-500. 100 is a no-op.                                                          |
| `-ProcessName`                   | Only resize windows whose process matches this pattern (without `.exe`). Exact name, wildcard (`*`, `?`), or regex. Omit to resize all visible windows. |
| `-WindowTitle`                   | Only resize windows whose title matches this pattern. Wildcard (`*`, `?`) or regex. Combine with `-ProcessName` (OR logic).                             |
| `-WindowHandle`                  | Only resize the window with this exact handle.                                                                                                          |
| `-TargetX` / `-TargetY`          | Target zone top-left coordinates for target-bounds mode.                                                                                                |
| `-TargetWidth` / `-TargetHeight` | Target zone size for target-bounds mode.                                                                                                                |
| `-InsetPercent`                  | Inset applied per side in target-bounds mode. Default `0.05`. Range 0.0-0.49.                                                                           |
| `-Tolerance`                     | Pixel tolerance used with `-SkipIfAlreadyPositioned`. Defaults to the module's shared position verification tolerance.                                  |
| `-SkipIfAlreadyPositioned`       | In target-bounds mode, skips windows already at the adjusted target bounds within `Tolerance`.                                                          |

```powershell
# Shrink all windows to the default 70% of their current size
Resize-Windows

# Enlarge all windows to 120% of current size
Resize-Windows -Percent 120

# Shrink only Chrome windows to half size
Resize-Windows -Percent 50 -ProcessName "chrome"

# Verbose diagnostic output
Set-LogLevel Verbose { Resize-Windows -Percent 150 -ProcessName "(chrome|firefox|msedge)" }

# Target-bounds mode: move one window to the shared inset pre-snap bounds for a zone
Resize-Windows -WindowHandle $handle -TargetX 0 -TargetY 0 -TargetWidth 1720 -TargetHeight 1440 -SkipIfAlreadyPositioned
```

**See also:** [Window Layout System](../modules/window.md)

## [Resize-PositionedWindows](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Resize-PositionedWindows.ps1)

- **Description:** Reapplies the shared pre-snap inset resize bounds to every tracked positioned window before FancyZones snapping. Uses the same `Resize-Windows` target-bounds path as `Set-WindowLayouts` and `Snap-AllWindows`, so every pre-snap resize comes from one source of truth and the first snap attempt always starts from the same geometry used during initial positioning and snap retries.
- **Parameters:** -InsetPercent, -Tolerance
- **Usage:** `Resize-PositionedWindows`, `Resize-PositionedWindows -Tolerance 0`

Called by `Set-WorkspaceWindowLayout` after the initial positioning pass and immediately before `Snap-AllWindows`. For each tracked window it invokes `Resize-Windows` in target-bounds mode with that window's expected zone bounds, skipping windows already at the adjusted pre-snap position (within `Tolerance`). Returns a result object with `ResizedCount`, `SkippedCount`, and `FailedWindows`.

| Parameter       | Description                                                                                                                                                                                                            |
| --------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-InsetPercent` | Inset percentage applied on each side. Default `0.05` (5 percent), constrained to the range `0.0`-`0.49`.                                                                                                              |
| `-Tolerance`    | Pixel tolerance for deciding whether a window is already at the adjusted pre-snap position. Defaults to the module's shared position verification tolerance (`$script:WindowModuleTolerances.PositionVerificationPx`). |

```powershell
# Reapply the shared pre-snap inset to all tracked windows
Resize-PositionedWindows

# Verbose diagnostic output
Set-LogLevel Verbose { Resize-PositionedWindows -Tolerance 0 }
```

**See also:** [Window module](window.md)

## [Resolve-CenteredWindowPercent](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Resolve-CenteredWindowPercent.ps1)

- **Description:** Resolves `Center-Windows` width/height percentages from a target pixel size. Computes the percentage of a monitor's work area needed to render a window at a fixed on-screen pixel size (`round(targetPx / workArea * 100)`), clamps each to the supplied `[Min, Max]` bounds, and finally hard-clamps to `Center-Windows`' own `[10, 100]` range so a misconfigured Min/Max can never throw at the call site. A non-positive work area or target falls back to the corresponding `Max` percent. Pure and side-effect free; used by `Center-Terminal` to keep the terminal a roughly constant physical size across displays.
- **Parameters:** -WorkAreaWidth, -WorkAreaHeight, -TargetWidthPx, -TargetHeightPx, -MinWidthPercent, -MaxWidthPercent, -MinHeightPercent, -MaxHeightPercent
- **Usage:** `Resolve-CenteredWindowPercent -WorkAreaWidth 3440 -WorkAreaHeight 1400 -TargetWidthPx 1376 -TargetHeightPx 700 -MinWidthPercent 25 -MaxWidthPercent 72 -MinHeightPercent 35 -MaxHeightPercent 75`

The result is DPI-consistent: the target and work-area dimensions come from the same `Get-MonitorInfo` coordinate space, so the computed fraction is correct regardless of the host process's DPI awareness (constancy is in DIPs, i.e. perceived size). On a 3440x1440 ultrawide (work area ~3440x1400) the defaults yield 40% x 50% (unchanged); on a 1920x1080 laptop they yield ~72% x 67%, scaling the window up to hold the same physical size.

| Parameter           | Type | Default | Description                                                                              |
| ------------------- | ---- | ------- | ---------------------------------------------------------------------------------------- |
| `-WorkAreaWidth`    | int  | -       | Target monitor work-area width in px (e.g. `Get-MonitorInfo` WorkAreaWidth). (Mandatory) |
| `-WorkAreaHeight`   | int  | -       | Target monitor work-area height in px. (Mandatory)                                       |
| `-TargetWidthPx`    | int  | -       | Desired on-screen window width in px. (Mandatory)                                        |
| `-TargetHeightPx`   | int  | -       | Desired on-screen window height in px. (Mandatory)                                       |
| `-MinWidthPercent`  | int  | -       | Lower clamp for the resolved width percentage. (Mandatory)                               |
| `-MaxWidthPercent`  | int  | -       | Upper clamp for the resolved width percentage. (Mandatory)                               |
| `-MinHeightPercent` | int  | -       | Lower clamp for the resolved height percentage. (Mandatory)                              |
| `-MaxHeightPercent` | int  | -       | Upper clamp for the resolved height percentage. (Mandatory)                              |

Returns `[PSCustomObject]` with `WidthPercent` and `HeightPercent` (integers, ready to pass to `Center-Windows`).

```powershell
# Ultrawide: target 1376x700 resolves to the legacy 40% x 50%
Resolve-CenteredWindowPercent -WorkAreaWidth 3440 -WorkAreaHeight 1400 `
    -TargetWidthPx 1376 -TargetHeightPx 700 `
    -MinWidthPercent 25 -MaxWidthPercent 72 -MinHeightPercent 35 -MaxHeightPercent 75
# -> @{ WidthPercent = 40; HeightPercent = 50 }

# 1920x1080 laptop panel: scales up to hold the same physical size
Resolve-CenteredWindowPercent -WorkAreaWidth 1920 -WorkAreaHeight 1040 `
    -TargetWidthPx 1376 -TargetHeightPx 700 `
    -MinWidthPercent 25 -MaxWidthPercent 72 -MinHeightPercent 35 -MaxHeightPercent 75
# -> @{ WidthPercent = 72; HeightPercent = 67 }
```

**See also:** [Center-Terminal](window.md#center-terminal), [Center-Windows](window.md#center-windows)

## [Resolve-LayoutTokens](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Resolve-LayoutTokens.ps1)

- **Description:** Expands layout-file tokens to regex patterns at the matching boundary. Layout entries may use the literal token `"Browser"` as a value for `ProcessName` and/or `WindowTitle`; this helper returns a shallow clone of the entry with those tokens expanded to a regex covering every browser declared in `$global:Configuration.Browsers` (Tor excluded - SecureBrowser layouts opt into `tor` explicitly). Other values, including literal alternation regex like `(firefox|chrome|msedge|brave)`, are returned unchanged. Tokens are matched case-sensitively and expanded patterns are cached at module scope so it stays cheap inside the per-entry Set-WindowLayouts / Confirm-WorkspaceWindowPositions loops. The original entry is never mutated, so Visualize-Layouts still renders the raw `Browser` cell.
- **Parameters:** -LayoutEntry
- **Usage:** `Resolve-LayoutTokens -LayoutEntry @{ ProcessName = "Browser"; Zone = "Left" }`, `Resolve-LayoutTokens -LayoutEntry @{ ProcessName = "firefox" }`

Layout files (under `Windows/PowerShell/Modules/Window/Layouts/**`) can stay browser-agnostic by using the literal token `Browser` instead of a specific browser name. At match time the token is expanded to a regex covering every browser declared under `Configuration.Browsers`, so the same layout works whether Firefox, Chrome, Edge, or Brave is the active default. The process side expands to the exe basenames (e.g. `(firefox|chrome|msedge|brave)`) and the title side to an escaped, case-insensitive alternation of the friendly browser names. When `Configuration` is not loaded (e.g. isolated Pester tests), a built-in fallback set is used. Returns a `[hashtable]` shallow clone of the input with the token fields expanded.

| Parameter      | Description                                                                                                                                                                                                                                 |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-LayoutEntry` | A single layout entry hashtable (mandatory). Typical keys: `ProcessName`, `WindowTitle`, `DesktopNumber`, `Zone`, `Monitor`, `Layout`. Only `ProcessName` / `WindowTitle` values equal to the case-sensitive token `Browser` are rewritten. |

```powershell
# Token expansion: "Browser" becomes a process-name regex
$expanded = Resolve-LayoutTokens -LayoutEntry @{ ProcessName = "Browser"; Zone = "Left" }
# $expanded.ProcessName -> "(firefox|chrome|msedge|brave)"

# Non-token values are returned unchanged
$expanded = Resolve-LayoutTokens -LayoutEntry @{ ProcessName = "firefox" }
# $expanded.ProcessName -> "firefox"
```

**See also:** [Window module](window.md)

## [Resolve-PositionedWindowHandle](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Resolve-PositionedWindowHandle.ps1)

- **Description:** Re-resolves a possibly stale tracked window handle to a live window. Given a tracked window state (with `WindowTitle` and an optional process fingerprint), it searches the current windows to find the matching live window, returning the first match or `$null`.
- **Parameters:** -WindowState
- **Usage:** `Resolve-PositionedWindowHandle -WindowState $tracked`

Enumerates the window list once via `Get-CachedWindows` (instead of issuing multiple `Get-WindowHandle` calls during snap recovery loops) and filters in memory: first by the tracked title as an escaped literal substring match, then by exact `ProcessName`, then by the captured `ProcessId` when a fingerprint was recorded. This lets `Snap-AllWindows` recover when a window was recreated or its handle was reassigned during a long-running session - the primary reason snaps fail only in reused shells but succeed from a fresh shell. Returns the first matching live window object from the cached list, or `$null` when no match is found.

| Parameter      | Description                                                                                               |
| -------------- | --------------------------------------------------------------------------------------------------------- |
| `-WindowState` | The tracked window state object (mandatory). Expected members: `WindowTitle`, `ProcessName`, `ProcessId`. |

```powershell
# Recover a live handle for a tracked (possibly stale) window
$fresh = Resolve-PositionedWindowHandle -WindowState $tracked
if ($fresh) { $handle = $fresh.Handle }
```

## [Save-CurrentLayout](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Save-CurrentLayout.ps1)

- **Description:** Writes the most recently applied workspace layout to `Window\Layouts\CurrentLayout.txt` (read back by `Get-CurrentLayout`). Called by `Set-WorkspaceWindowLayout` after a workspace has been applied and verified. Records, per open workspace, the virtual desktop count, the FancyZones layout applied to each monitor on each desktop, and one record per positioned+snapped window with its handle, process fingerprint, title, layout-relative desktop, monitor, and zone - i.e. exactly where each window belongs. Window records come from the positioned-window tracking (`$script:PositionedWindowHandles`) joined with each entry's Monitor/Zone/Layout. A normal open replaces the whole file (normal mode resets the desktops, so only this workspace is on screen); an `-Alongside` open instead merges, updating only this workspace's section and preserving the workspaces already running. Desktop numbers are stored layout-relative (offset-stripped) so the snapshot is reusable regardless of where the workspace is later reopened. Writing is best-effort: any I/O error is logged and swallowed so it can never fail an already-successful layout.
- **Parameters:** -Workspace, -LayoutsDir, -MachineType, -DesktopOffset, -Alongside, -DesktopCount, -LayoutConfig, -MonitorConfig, -WindowStates
- **Usage:** `Save-CurrentLayout -Workspace "Example_PC" -LayoutsDir $layoutsDir -MachineType "PC" -DesktopCount $requiredVirtualDesktops -MonitorConfig $config.Monitors -LayoutConfig $config.Layout`

| Parameter        | Type      | Required | Description                                                                                                                                    |
| ---------------- | --------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `-Workspace`     | string    | Yes      | Workspace/layout name this snapshot belongs to (e.g. "Example_PC").                                                                            |
| `-LayoutsDir`    | string    | Yes      | The Layouts directory holding `CurrentLayout.txt`.                                                                                             |
| `-MachineType`   | string    | No       | Machine type the layout was applied for (PC / Laptop / Work). Recorded for context.                                                            |
| `-DesktopOffset` | int       | No       | Desktop offset applied this run (0 normally, +N for alongside). Default 0.                                                                     |
| `-Alongside`     | switch    | No       | Present for an alongside open; merges with the existing file instead of replacing it.                                                          |
| `-DesktopCount`  | int       | No       | Number of virtual desktops the workspace uses. Default 1.                                                                                      |
| `-LayoutConfig`  | array     | No       | The workspace layout array (`$config.Layout`).                                                                                                 |
| `-MonitorConfig` | hashtable | No       | The `Monitors` section (`$config.Monitors`); used to record the FancyZones layout per monitor/desktop.                                         |
| `-WindowStates`  | object    | No       | Positioned-window records to serialize. Defaults to `$script:PositionedWindowHandles`; pass `@()` for simple layouts with no per-zone windows. |

**See also:** [Get-CurrentLayout](window.md), [Set-WorkspaceWindowLayout](window.md), [Add-PositionedWindow](window.md)

## [Set-WindowCacheMaxAge](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Set-WindowCacheMaxAge.ps1)

- **Description:** Sets the maximum age for the window cache, configuring how long the window enumeration cache remains valid. Lower values provide more accurate data at the cost of more syscalls.
- **Parameters:** -MaxAgeMs
- **Usage:** `Set-WindowCacheMaxAge -MaxAgeMs 100`

## [Set-WindowLayouts](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Set-WindowLayouts.ps1)

- **Description:** Applies a predefined window layout configuration. Moves windows to specific virtual desktops and positions them according to a layout configuration, supporting two positioning modes: direct pixel coordinates (X, Y, Width, Height) and zone-based placement (Layout, Zone, Monitor) that uses FancyZones layouts with human-readable zone names. Distinguishes pre-existing from newly opened windows so windows already at the final target coordinates are skipped (idempotent) while new windows are always positioned and tracked for later snapping. Includes retry logic and handle-based recovery for transient browser title changes, and supports duplicate layout entries where the same (ProcessName, WindowTitle) pair appears multiple times so each entry claims exactly one distinct window handle for its own zone. For those duplicate entries the claim is deterministic instead of using whatever enumeration/Z-order returned first: when an optional `-PinnedHandleMap` (built from `CurrentLayout.txt`) records a specific window for this exact desktop/monitor/zone and that window is still live with a matching process fingerprint, it is reclaimed (the HWND is a unique, stable identifier within a session, so every window returns to its own zone with zero reshuffle). When there is no valid recorded window (first open, after a reboot, or a brand-new window) it falls back to claiming the unclaimed candidate whose **current bounds are closest to that entry's target zone**, mirroring the verifier's scoring.
- **Parameters:** -LayoutConfig, -ConfigPath, -MonitorInfo, -MonitorConfig, -ExistingWindowHandles, -ExpectedWindowState, -DesktopOffset, -SkipExistingWindows, -PinnedHandleMap
- **Usage:** `Set-WindowLayouts -LayoutConfig $layout`, `Set-WindowLayouts -ConfigPath "<DevRoot>\MyLayouts\development.json"`, `Set-WindowLayouts -LayoutConfig $layout -MonitorInfo $monitors -MonitorConfig $config.Monitors`, `Set-WindowLayouts -LayoutConfig $layout -DesktopOffset 2`

Applies the per-window portion of a layout after FancyZones layouts are already in place. It sorts layout entries by desktop and monitor coordinates for deterministic processing, resolves each target zone or direct coordinate block (auto-resolving layout names from `MonitorConfig` based on Monitor and DesktopNumber when not explicitly given), finds matching windows with retries and handle-based recovery, moves each window to the correct virtual desktop, then resizes via the shared target-bounds (inset) path of `Resize-Windows` before tracking each positioned window so `Resize-PositionedWindows` and `Snap-AllWindows` can validate and recover it later. Accepts either a `-LayoutConfig` array/hashtable or a `-ConfigPath` to a `.json` or `.psd1` file (mutually exclusive parameter sets).

| Parameter                | Description                                                                                                                                                                                                                                                                                                                                                                                          |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-LayoutConfig`          | Array of window configuration hashtables (ProcessName, optional WindowTitle, DesktopNumber, and either X/Y/Width/Height or Layout/Zone/Monitor). Mutually exclusive with `-ConfigPath`.                                                                                                                                                                                                              |
| `-ConfigPath`            | Path to a `.json` or `.psd1` file containing the layout configuration. Mutually exclusive with `-LayoutConfig`.                                                                                                                                                                                                                                                                                      |
| `-MonitorInfo`           | Array of monitor specs used to resolve string monitor labels (e.g. "Primary", "Secondary") to coordinates.                                                                                                                                                                                                                                                                                           |
| `-MonitorConfig`         | Hashtable of the `Monitors` configuration section; used to auto-resolve layout names per monitor and desktop.                                                                                                                                                                                                                                                                                        |
| `-ExistingWindowHandles` | HashSet of handles open before the layout run; used to detect pre-existing windows and skip already-correct positioning.                                                                                                                                                                                                                                                                             |
| `-ExpectedWindowState`   | Hashtable of stable window state captured during the wait phase; enables handle-based recovery when titles change transiently.                                                                                                                                                                                                                                                                       |
| `-DesktopOffset`         | Integer shift applied to all 1-based desktop numbers (default 0).                                                                                                                                                                                                                                                                                                                                    |
| `-SkipExistingWindows`   | Switch (alongside mode) that skips windows existing before this workspace opened, since they belong to a previous workspace.                                                                                                                                                                                                                                                                         |
| `-PinnedHandleMap`       | Optional hashtable from `CurrentLayout.txt` keyed by `"<DesktopNumber>\|<Monitor>\|<Zone>"` → recorded window (`@{ Handle; ProcessId; ProcessName }`). The authoritative source for which duplicate-named window claims each zone: a still-live, process-matching recorded window is reclaimed exactly; geometry is the fallback when no valid record exists. A stale/dead/reused handle is ignored. |

```powershell
# Direct pixel coordinates
$layout = @(
    @{
        ProcessName   = "chrome"
        DesktopNumber = 1
        X = 0; Y = 0; Width = 1920; Height = 1080
        ZoneName      = "Browser-Main"
    }
)
Set-WindowLayouts -LayoutConfig $layout

# Zone-based positioning with monitor specs
$layout = @(
    @{ ProcessName = "Code"; DesktopNumber = 1; Layout = "One"; Zone = "Left"; Monitor = "Primary" }
)
Set-WindowLayouts -LayoutConfig $layout -MonitorInfo $monitors -MonitorConfig $config.Monitors

# Load a layout from a file and shift all desktops by an offset
Set-WindowLayouts -ConfigPath "<DevRoot>\MyLayouts\development.json" -DesktopOffset 2
```

**See also:** [Set-WorkspaceWindowLayout](window.md), [Resize-Windows](window.md), [Resize-PositionedWindows](window.md), [Snap-AllWindows](window.md)

## [Set-WindowModuleDelays](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Set-WindowModuleDelays.ps1)

- **Description:** Sets Window module timing configuration values. Updates the module-scoped timing configuration with the provided values; only existing keys are updated and unknown keys are ignored.
- **Parameters:** -Delays
- **Usage:** `Set-WindowModuleDelays -Delays @{ FocusSettleMs = 10; WindowRestoreMs = 10 }`

Accepts a hashtable of timing values and merges them into the module-scoped `$script:WindowModuleDelays` table, leaving any key it does not recognize untouched. These delays govern the small settle pauses the Window module inserts between cursor moves, focus changes, keyboard shortcuts, and window/desktop operations.

| Key                  | Description                                               |
| -------------------- | --------------------------------------------------------- |
| `CursorSettleMs`     | Delay after cursor movement before sending keys.          |
| `FocusSettleMs`      | Delay after `SetForegroundWindow` before sending keys.    |
| `KeyboardShortcutMs` | Delay after a keyboard shortcut is sent.                  |
| `WindowRestoreMs`    | Delay after `ShowWindow` restore operations.              |
| `WindowPositionMs`   | Delay after `SetWindowPos` for the window to settle.      |
| `VirtualDesktopMs`   | Delay after `Move-Window` for virtual desktop operations. |

```powershell
# Tighten focus and restore settle delays to 10ms each
Set-WindowModuleDelays -Delays @{ FocusSettleMs = 10; WindowRestoreMs = 10 }
```

## [Set-WindowPosition](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Set-WindowPosition.ps1)

- **Description:** Sets the position and size of a window by handle and pixel coordinates. Moves and resizes a window to specific coordinates, which can be used to position windows to match FancyZones layouts by calculating the zone coordinates.
- **Parameters:** -WindowHandle, -X, -Y, -Width, -Height
- **Usage:** `Set-WindowPosition -WindowHandle $handle -X 0 -Y 0 -Width 1920 -Height 1080`

Positions a single window by handle and pixel coordinates. Automatically restores maximized or snapped windows to a normal state before repositioning, then applies the new bounds. The restore settle sleep is only paid when the window was not already in the normal show state, and there is no fixed post-`SetWindowPos` delay - callers verify the resulting rect (e.g. via `Wait-WindowRect`) or settle on their own schedule. Returns `$true` on success and `$false` on failure.

| Parameter       | Type   | Mandatory | Description                                 |
| --------------- | ------ | --------- | ------------------------------------------- |
| `-WindowHandle` | IntPtr | Yes       | The window handle (HWND) to move.           |
| `-X`            | int    | Yes       | The X coordinate (left position) in pixels. |
| `-Y`            | int    | Yes       | The Y coordinate (top position) in pixels.  |
| `-Width`        | int    | Yes       | The width of the window in pixels.          |
| `-Height`       | int    | Yes       | The height of the window in pixels.         |

```powershell
# Position a window full-screen by handle
$handle = (Get-WindowHandle -ProcessName "chrome")[0].Handle
Set-WindowPosition -WindowHandle $handle -X 0 -Y 0 -Width 1920 -Height 1080

# Verbose diagnostic output
$handle = (Get-WindowHandle -ProcessName "firefox").Handle
Set-LogLevel Verbose { Set-WindowPosition -WindowHandle $handle -X 0 -Y 0 -Width 960 -Height 1080 }
```

**See also:** [Get-WindowHandle](window.md), [Set-WorkspaceWindowLayout](window.md)

## [Set-WorkspaceWindowLayout](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Set-WorkspaceWindowLayout.ps1)

- **Description:** Loads and applies a predefined, machine-specific window layout for a workspace. Layout files live in machine-type subfolders of the module's `Layouts` directory (e.g. `Layouts/PC/`, `Layouts/Laptop/`, `Layouts/Work/`) and define both FancyZones monitor layouts and per-window placement rules. The function ensures the required virtual desktops exist, waits for workspace windows to appear and stabilize, applies FancyZones, positions and snaps each window into its zone, then verifies every entry. On snap or verification failure it first retries the position → snap → verify pipeline in-process up to 2 times (refreshing the existing-window snapshot so already-correct windows are skipped); only when those retries are exhausted does it escalate by force-starting FancyZones and rerunning in a fresh shell in a window-only retry mode that preserves already-configured desktops and reapplies the full layout config; before every rerun it also releases stuck keyboard modifiers and a stranded mouse button via `Reset-KeyboardModifiers` so the respawned shell takes over a clean input session.
- **Parameters:** -WorkspaceName, -LayoutPath, -TimeoutSeconds, -SnapDelayMs, -DisableAutoWait, -PreCapturedExistingWindows, -DesktopOffset, -Alongside
- **Usage:** `Set-WorkspaceWindowLayout -WorkspaceName MyWorkspace`, `Set-WorkspaceWindowLayout -WorkspaceName OtherProject -DesktopOffset 2 -Alongside`, `Set-WorkspaceWindowLayout -LayoutPath C:\Users\<User>\MyLayouts\custom.psd1 -TimeoutSeconds 30`, `Set-WorkspaceWindowLayout -WorkspaceName MyWorkspace -DisableAutoWait`

This is the final step of the layout system: FancyZones (PowerToys) defines the zones, `.psd1` layout files map windows to those zones, and `Set-WorkspaceWindowLayout` applies the configuration. With `ByWorkspace` it auto-resolves `Layouts/{MachineType}/{WorkspaceName}_{MachineType}.psd1` (and falls back to the `Laptop` layout when a small primary display is detected); with `ByPath` it applies an explicit layout file. Layouts may contain duplicate window entries (same `ProcessName`/`WindowTitle`) to place identical windows in different zones, used together with `Open-Browser`'s `-Override` to position two copies of the same URL group independently. The function does not perform the final virtual-desktop landing itself; switching to and focusing the workspace's first desktop is delegated to `Focus-VirtualDesktop`, the last action in each workspace's `WorkspaceActions` sequence. VS Code entries are matched by process: a `Code` entry with no `WindowTitle` is a catch-all that captures every VS Code window (folder or `.code-workspace`, any number of them) and places them all in its zone, so opening a workspace file with `-VSCodeWorkspace` needs no layout coupling. Give a `Code` entry a `WindowTitle` (a bare project name such as `Dotfiles`) only to split several VS Code windows across different zones; the process-and-title match then pins each editor to its own slot.

On every successful apply the function records the result to `Window\Layouts\CurrentLayout.txt` via `Save-CurrentLayout` (virtual desktop count, FancyZones layout per monitor per desktop, and every configured window with its desktop/monitor/zone - built from the `Set-WindowLayouts` results so the snapshot stays complete even on idempotent re-runs where most windows are already correct and skipped). On entry it reads that snapshot back via `Get-CurrentLayout` for the workspace being applied and passes it to `Set-WindowLayouts` as a `-PinnedHandleMap`, which authoritatively reclaims each recorded window for its zone - so layouts with many identically-named windows (e.g. `Example_PC`'s `Browser` entries) keep each window in the same zone across reopens and `-Alongside` opens, with closest-bounds geometry as the fallback only when there is no valid record. A missing/stale file simply changes nothing. The file is per-machine runtime state and is git-ignored. FancyZones layouts are always reapplied per desktop (the snapshot does not gate that) so the zone grids are unconditionally refreshed; only window-to-zone assignment is driven by the snapshot.

| Parameter                     | Type            | Default | Description                                                                                                                                                                                                                                                |
| ----------------------------- | --------------- | ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-WorkspaceName`              | string          | -       | Workspace layout to apply (parameter set `ByWorkspace`); auto-resolves the machine-specific layout file.                                                                                                                                                   |
| `-LayoutPath`                 | string          | -       | Direct path to a layout `.psd1` file (parameter set `ByPath`, mandatory there).                                                                                                                                                                            |
| `-TimeoutSeconds`             | int             | `60`    | Maximum seconds to wait for windows when using automatic detection.                                                                                                                                                                                        |
| `-SnapDelayMs`                | int             | `10`    | Milliseconds to wait after positioning before snapping. Increase if windows do not snap cleanly.                                                                                                                                                           |
| `-DisableAutoWait`            | switch          | -       | Skips automatic window detection and applies the layout immediately (windows may not be ready).                                                                                                                                                            |
| `-PreCapturedExistingWindows` | HashSet[IntPtr] | -       | Window handles that existed before opening workspace apps; used to distinguish new windows from existing ones. Typically supplied by `Open-Workspace`.                                                                                                     |
| `-DesktopOffset`              | int             | `0`     | Offset added to every virtual desktop number in the layout so a workspace can open to the right of existing ones (e.g. offset `2` places Desktop 1 on Desktop 3).                                                                                          |
| `-Alongside`                  | switch          | -       | Opens the workspace alongside existing desktops (added to the right via `DesktopOffset`) instead of replacing them.                                                                                                                                        |

```powershell
# Apply a workspace layout using automatic window detection
Set-WorkspaceWindowLayout -WorkspaceName MyWorkspace

# Open a second workspace alongside existing desktops, offset two desktops to the right
Set-WorkspaceWindowLayout -WorkspaceName OtherProject -DesktopOffset 2 -Alongside

# Apply an explicit layout file with a custom detection timeout
Set-WorkspaceWindowLayout -LayoutPath C:\Users\<User>\MyLayouts\custom.psd1 -TimeoutSeconds 30

# Apply immediately without waiting for windows (use with caution)
Set-WorkspaceWindowLayout -WorkspaceName MyWorkspace -DisableAutoWait

# Verbose diagnostic output
Set-LogLevel Verbose { Set-WorkspaceWindowLayout -WorkspaceName MyWorkspace }
```

On entry the function runs a live RPC preflight (`Get-RpcRetryPolicy -OperationLabel "applying layout" -Probe`): the probe verifies this session's VirtualDesktop COM state in-process, so a session whose proxies went stale after an Explorer restart is detected and repaired (via `Repair-RpcServer` / `Reset-VirtualDesktopState`) before any desktop reconfiguration begins. On success Windows Terminal is refocused just before the success banner so output is not buried behind workspace windows. On snap or verification failure the position → snap → verify pipeline is first retried in-process up to 2 times (in `-Alongside` mode too): the existing-window snapshot is refreshed so already-correct windows are skipped by the position check (in `-Alongside` mode it stays the original pre-open capture, since there it marks the other workspace's windows), and verification runs against the full layout config so windows an aborted snap pass never reached are covered (verification is skipped in `-Alongside` mode, where shared windows make position checks unreliable). Only when the in-process retries are exhausted does the function record the failed window marker (now informational only), force-start FancyZones, and rerun via `Initialize-WorkspaceWindowLayoutRerun -WindowOnlyRetry` / `ReRun-LastCommand` in a window-only mode that preserves virtual desktops and caches, always reapplies FancyZones monitor layouts, and applies the full layout config - idempotent skips keep it cheap (still capped at 2 auto-reruns). The rerun command is taken from `$env:WORKSPACE_RERUN_COMMAND` (recorded by `Open-Workspace`) when present, instead of scraping PSReadLine history. Auto-rerun is disabled in `-Alongside` mode. `CurrentLayout.txt` is written only on the success paths, so a failed/rerunning attempt never overwrites the last good snapshot.

A few passes between waiting and positioning are kept deliberately narrow. First-open normalization resizes only the windows this open created (pre-existing windows elsewhere on the machine are left untouched). Browser first-tab normalization (Ctrl+1) skips windows already showing a title some browser layout entry wants, and touches pre-existing browser windows only when a browser entry's title currently matches no window; it no longer probes tab counts via a UIA tree walk. The pre-snap resize (`Resize-PositionedWindows`) runs with the module's default 20px tolerance so windows that self-adjust by a pixel (terminal cell rounding, min-size constraints, DPI rounding) converge instead of being re-positioned on every open. And a virtual desktop count mismatch is delta-resized with a single `Ensure-VirtualDesktops` call (it grows and shrinks) instead of removing all desktops and recreating them.

**See also:** [Save-CurrentLayout](window.md), [Get-CurrentLayout](window.md), [Set-WindowLayouts](window.md), [Window module overview](../modules/window.md)

## [Snap-AllWindows](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Snap-AllWindows.ps1)

- **Description:** Intelligently snaps windows to FancyZones by sending `Win+Up` (or `Win+Down` for top-position, vertically split windows) with reliable focus acquisition. Groups windows by virtual desktop and switches desktops as needed, validates positions pre-snap, re-positions when drifted, and falls back to shift-drag snapping if keyboard snap fails. Default mode snaps only windows previously positioned by `Set-WindowLayouts` (the workspace flow); `-All` snaps all visible windows standalone. Stuck keyboard modifiers are cleared via `Reset-KeyboardModifiers` at pass start, before each snap retry, and (mouse button included) when a pass fails, so an interrupted earlier sequence can neither corrupt the injected combos (a held Shift turns `Win+Up` into `Win+Shift+Up`) nor leave terminal input locked up.
- **Parameters:** -All, -CurrentDesktopOnly, -WindowHandles, -SnapDelayMs, -DesktopOffset, -DesktopCount
- **Usage:** `Snap-AllWindows`, `Snap-AllWindows -All`, `Snap-AllWindows -All -CurrentDesktopOnly`, `Snap-AllWindows -All -SnapDelayMs 100`, `Snap-AllWindows -DesktopOffset 2 -DesktopCount 3`

A window is treated as "top and vertically split" (and snapped with `Win+Down` instead of `Win+Up`) when its top is at or near the monitor top, its center is in the top half, and its height is roughly 40-60% of the monitor height.

`GetAllWindows` (`EnumWindows`) enumerates windows across **every** virtual desktop, not just the active one, so `-All` alone snaps system-wide. When a caller switches desktops in a loop and snaps each in turn, it must pass `-CurrentDesktopOnly` so each window is snapped exactly once on its own desktop and forcing a window foreground never drags the active desktop to a window that lives elsewhere. The current and per-window desktops are resolved with `Get-CurrentDesktop` / `Get-DesktopFromWindow` / `Get-DesktopIndex`; an unresolvable window is kept (snapped) rather than dropped, and if the current desktop itself cannot be determined the filter is skipped. Callers that already resolved the window-to-desktop mapping can instead pass `-WindowHandles` with the per-desktop handle list - it takes precedence over `-CurrentDesktopOnly` and avoids the two COM roundtrips per window on every desktop pass.

In the workspace (positioned-windows) flow, windows are grouped by desktop and processed in positioning order. Desktop switches are verified by polling (`Wait-DesktopSwitch`); when a switch cannot be confirmed the `VirtualDesktop` module is reset (`Reset-VirtualDesktopState`). After each transition the monitor/window caches are refreshed, each window is revalidated and realigned to the target desktop, and stale handles are recovered via title + process fingerprint matching (`Resolve-PositionedWindowHandle`). Re-positioning uses the same shared inset resize path as `Set-WindowLayouts` and `Resize-PositionedWindows`, and focus is verified immediately before key injection via `Confirm-WindowForeground`. Keyboard-snap and shift-drag results are verified by polling the window rect via `Wait-WindowRect` (the time budget grows on each retry) instead of a fixed sleep and single check, so a snap that lands quickly returns immediately and the expensive fallbacks only trigger when the budget is genuinely exhausted. Target desktop indices are computed through `ConvertTo-InternalDesktopIndex` so `DesktopOffset` is honored consistently.

At start the function requires a verified FancyZones ready state, and during long snap loops it re-checks FancyZones liveness once per desktop pass (rather than per window) and attempts a restart if the process disappears; if FancyZones cannot be recovered it aborts early. If keyboard and shift-drag retries still cannot verify zone placement, the failed window details are recorded in its return object so `Set-WorkspaceWindowLayout` can rerun the workspace command in window-only retry mode. After processing, the active desktop is left on the last one snapped - returning the user to the first desktop is delegated to `Focus-VirtualDesktop` (the final workspace action), keeping switch-and-focus logic in one place (DRY).

| Parameter             | Type   | Default | Description                                                                                                                                      |
| --------------------- | ------ | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `-All`                | switch | -       | Snap all visible windows without requiring prior positioning by `Set-WindowLayouts`. Useful for standalone usage.                                |
| `-CurrentDesktopOnly` | switch | -       | Only valid with `-All`. Restricts snapping to windows on the currently active virtual desktop, so desktop-switching loops snap each window once. |
| `-WindowHandles`      | IntPtr[] | -     | Only valid with `-All`. Restricts snapping to exactly these window handles; takes precedence over `-CurrentDesktopOnly`. For callers that already resolved the window-to-desktop mapping. |
| `-SnapDelayMs`        | int    | `25`    | Delay in milliseconds between each window snap operation.                                                                                        |
| `-DesktopOffset`      | int    | `0`     | Virtual desktop offset, so alongside workspaces target the correct desktop.                                                                      |
| `-DesktopCount`       | int    | `0`     | Number of desktops to process.                                                                                                                   |

```powershell
# Snap previously positioned windows to FancyZones (workspace flow)
Snap-AllWindows

# Snap all visible windows standalone (keyboard snap + shift-drag fallback)
Snap-AllWindows -All

# Snap only windows on the active desktop (per-desktop snap loop)
Snap-AllWindows -All -CurrentDesktopOnly

# Verbose diagnostic output
Set-LogLevel Verbose { Snap-AllWindows -All -SnapDelayMs 100 }
```

> **Note:** Disable PowerToys' "Move newly created windows to their last known zone" so windows aren't moved to the wrong position. The `spacing` value in `FancyZones/custom-layouts.json` must be `3`, or coordinate mismatches break snap zone verification and shift-drag snapping.

**See also:** [Set-WorkspaceWindowLayout](window.md#set-workspacewindowlayout), [Resize-Windows](window.md#resize-windows), [Get-InsetWindowBounds](window.md#get-insetwindowbounds)

## [Test-FancyZonesLayoutApplied](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Test-FancyZonesLayoutApplied.ps1)

- **Description:** Tests whether FancyZones currently has a layout applied for a given virtual desktop, optionally narrowed to a specific monitor. Queries the applied-layouts state via `Get-AppliedFancyZonesState`; returns `$false` when that state cannot be read, so callers can treat an unknown state as "not confirmed".
- **Parameters:** -VirtualDesktopGuid, -MonitorId
- **Usage:** `Test-FancyZonesLayoutApplied -VirtualDesktopGuid $guid`, `Test-FancyZonesLayoutApplied -VirtualDesktopGuid $guid -MonitorId "LEN8ABC"`

Snapping windows when no layout is applied can drop a window into a stale or wrong zone grid; this check lets callers detect that condition before injecting snap input. With `-MonitorId` it requires a layout applied to that specific monitor on the desktop; without it, any monitor with an applied layout on the desktop satisfies the check. `Snap-AllWindows` uses it (under verbose logging) to warn when no layout is applied for a desktop, since blind snapping into an unapplied zone grid is unreliable.

| Parameter             | Type   | Default | Description                                                                                                                |
| --------------------- | ------ | ------- | -------------------------------------------------------------------------------------------------------------------------- |
| `-VirtualDesktopGuid` | string | -       | Desktop GUID to check (mandatory). Braces and case are optional; normalized to the `{UPPER-CASE}` form used by FancyZones. |
| `-MonitorId`          | string | -       | Optional FancyZones monitor identifier (EDID code or display path) to narrow the check to one monitor.                     |

```powershell
# Check whether any monitor has a layout applied for the desktop
Test-FancyZonesLayoutApplied -VirtualDesktopGuid "{CF6C2856-0D59-466D-AA7F-E6DF85C6034C}"

# Require a layout applied to a specific monitor on that desktop
Test-FancyZonesLayoutApplied -VirtualDesktopGuid $guid -MonitorId "LEN8ABC"
```

## [Test-PositionedWindow](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Test-PositionedWindow.ps1)

- **Description:** Tests whether a window handle is tracked as positioned. Checks if the handle has been registered as positioned by `Set-WindowLayouts`, returning `$true` if the window was positioned and `$false` otherwise.
- **Parameters:** -WindowHandle
- **Usage:** `Test-PositionedWindow -WindowHandle $window.Handle`

## [Test-VirtualDesktopComHealth](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Test-VirtualDesktopComHealth.ps1)

- **Description:** Probes THIS session's VirtualDesktop COM state with a live roundtrip (`[VirtualDesktop.Desktop]::Count`) on a background runspace inside the current process, under a hard timeout. Because the probe shares the session's compiled types and cached COM proxies, it detects the failure modes that matter to this session: stale proxies after an Explorer restart (fails fast with `0x800706BA` / `0x80010108` - a child-process probe creates its own fresh proxies and wrongly reports healthy in that state) and a hung shell endpoint (the call blocks and the timeout flags it). When the VirtualDesktop types are not compiled in this process yet, the runspace imports the module and calls `Get-DesktopCount`, exercising the same COM activation path a first real call would take.
- **Parameters:** -TimeoutMs (default 5000)
- **Usage:** `Test-VirtualDesktopComHealth`, `$probe = Test-VirtualDesktopComHealth -TimeoutMs 2500`

Returns a `PSCustomObject` with `Healthy` (bool), `TimedOut` (bool), and `Error` (innermost failure message plus HRESULT, or `$null`). A healthy warm probe completes in milliseconds. Used by `Test-RpcServerHealth -Probe` as the live endpoint check and by `Reset-VirtualDesktopState` to verify a reset actually produced a working session.

**See also:** [Test-RpcServerHealth](system.md#test-rpcserverhealth), [Reset-VirtualDesktopState](window.md#reset-virtualdesktopstate)

## [Update-LayoutSectionHeaders](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Update-LayoutSectionHeaders.ps1)

- **Description:** Updates the section headers (e.g., `# VIRTUAL DESKTOP 1 - Monitor: Primary - Layout: One`) within the `Layout` array of a layout file to match the actual configuration. Parses the file content, strips the existing headers, sorts the entries by DesktopNumber, Monitor (Primary, then Secondary, then others), and zone order, then regenerates the headers from the real DesktopNumber, Monitor, and Layout type values. Used by `Visualize-Layouts -Update` to keep both the visualization block and the inline section headers synchronized with the configuration.
- **Parameters:** -Content, -Config
- **Usage:** `Update-LayoutSectionHeaders -Content $content -Config $config`

Layout files use 1-based indexing for `DesktopNumber`, which is displayed directly in the regenerated headers. Entries are reordered deterministically (DesktopNumber, then Primary/Secondary/other monitor, then `ZoneNameMappings` zone order from the global configuration, then original index) so the output stays stable across runs. If the `Layout` array cannot be parsed, the original content is returned unchanged.

| Parameter  | Description                                                                                                                             |
| ---------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `-Content` | The layout file content (a `string`) with the visualization block already removed.                                                      |
| `-Config`  | The parsed configuration (`hashtable`) containing the `Layout` array, used to resolve each entry's layout type per monitor and desktop. |

```powershell
# Regenerate the inline section headers for a layout file
$content = Get-Content -Path "layout.psd1" -Raw
$config  = Import-PowerShellDataFile -Path "layout.psd1"
$updated = Update-LayoutSectionHeaders -Content $content -Config $config
```

**See also:** [Window Layout System](window.md#window-layout-system)

## [Validate-Layout](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Validate-Layout.ps1)

- **Description:** Validates a window layout configuration hashtable for consistency. Checks the `VirtualDesktopLayouts` definitions and the actual `Layout` array (both 1-based for `DesktopNumber` and `VirtualDesktopLayouts` keys), verifying virtual desktop counts are consistent across monitors, indices are contiguous starting at 1, `Layout` desktop numbers fall in range, and zone-based entries resolve to defined monitors. Returns a hashtable with `IsValid` (bool), `Errors` (array), and `Warnings` (array).
- **Parameters:** -Config, -LayoutName
- **Usage:** `Validate-Layout -Config $config`, `Validate-Layout -Config $config -LayoutName "MyMachine"`

Calculates the required virtual desktop count from the `Monitors` section and validates it against the `Layout` array. It reports hard errors (which set `IsValid = $false`) for missing or 0-based desktop indices, out-of-range `DesktopNumber` values, and zone-based entries that reference an undefined monitor or a monitor/desktop combination with no defined layout. It emits non-fatal warnings for monitors with mismatched desktop counts, desktops defined in `VirtualDesktopLayouts` but unused in `Layout`, and layouts that still use the legacy hardcoded browser-alternation regex instead of the `Browser` token.

| Parameter     | Type        | Default    | Description                                                          |
| ------------- | ----------- | ---------- | -------------------------------------------------------------------- |
| `-Config`     | `hashtable` | -          | The imported layout configuration hashtable (mandatory).             |
| `-LayoutName` | `string`    | `"Layout"` | Optional name of the layout being validated, used in error messages. |

**Checks performed:**

- `VirtualDesktopLayouts` keys are contiguous and 1-based (1, 2, 3, ...); 0-based indexing is flagged as an error.
- All monitors have consistent desktop counts (mismatch raises a warning).
- `Layout` array `DesktopNumber` values are within the valid range.
- Zone-based entries reference a valid monitor with a defined layout for the monitor/desktop combination.
- Unused desktops and legacy browser-alternation regex raise warnings.

```powershell
# Validate a layout configuration file
$config = Import-PowerShellDataFile -Path "Layout.psd1"
$result = Validate-Layout -Config $config -LayoutName "MyMachine"

if (-not $result.IsValid) {
    $result.Errors | ForEach-Object { Write-Host $_ }
}
```

**See also:** [Configuration: Window Layout](../configuration/guides/configure-window-layout.md)

## [Visualize-Layouts](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Visualize-Layouts.ps1)

- **Description:** Generates ASCII art visualizations of FancyZones layouts and adds them as commented sections at the top of layout files. Each visualization shows which processes are assigned to each zone, organized by Virtual Desktop and then Monitor (Primary, Secondary, etc.). Layout files live in machine-specific subfolders (Laptop, PC, Work) under the Layouts directory and are searched recursively. Configurations are validated before rendering, and with `-DisplayAvailableLayouts` it can instead list all available layout types (Zero, One, Two, etc.) with their zone-name mappings from configuration.
- **Parameters:** -Layout, -All, -DisplayAvailableLayouts, -Update
- **Usage:** `Visualize-Layouts`, `Visualize-Layouts -Layout "MyWorkspace_PC"`, `Visualize-Layouts -All`, `Visualize-Layouts -All -Update`, `Visualize-Layouts -DisplayAvailableLayouts`

Without parameters the function presents an interactive menu (via `Resolve-Selection`) to pick one or more layouts. For each selected file it imports the `.psd1`, validates it with `Validate-Layout`, groups windows by `DesktopNumber` then `Monitor`, resolves each monitor's layout type from the `Monitors` section, and renders the arrangement with `Generate-LayoutVisualization`. By default it only displays the visualizations; with `-Update` it rewrites each layout file, replacing any existing `LAYOUT VISUALIZATION` comment block with a freshly generated one and refreshing the section headers. `-DisplayAvailableLayouts` reads `ZoneNameMappings` and `custom-layouts.json` to show the zone structure of each grid layout type without touching any files.

| Parameter                  | Description                                                                                                                           |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `-Layout`                  | Name of a specific layout to visualize (e.g. `MyWorkspace_PC`); matched against the layout file's base name.                          |
| `-All`                     | Process every layout file found recursively in the Layouts directory and its machine-specific subfolders.                             |
| `-DisplayAvailableLayouts` | List all available layout types (Zero, One, Two, etc.) with their zone names shown in position; does not read or modify layout files. |
| `-Update`                  | Write the generated visualizations back into the layout files as a comment block. Without it, visualizations are only displayed.      |

```powershell
# Interactive selection of one or more layouts (display only)
Visualize-Layouts

# Display the visualization for a single layout
Visualize-Layouts -Layout "MyWorkspace_PC"

# Regenerate and write the comment block into every layout file
Visualize-Layouts -All -Update

# Show all FancyZones layout types and their zone names
Visualize-Layouts -DisplayAvailableLayouts
```

**See also:** [Set-WorkspaceWindowLayout](#set-workspacewindowlayout), [Configure Window Layout](../configuration/guides/configure-window-layout.md)

## [Wait-DesktopSwitch](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Wait-DesktopSwitch.ps1)

- **Description:** Polls the current virtual desktop index (via the `VirtualDesktop` module) until it matches a target index, returning `$true` once the desktop is active or `$false` on timeout. Replaces fixed post-switch sleeps with event-driven verification so callers like `Snap-AllWindows` confirm a `Switch-Desktop` actually took effect before snapping windows.
- **Parameters:** -TargetDesktopIndex, -TimeoutMs (default: 750), -PollIntervalMs (default: 10)
- **Usage:** `Wait-DesktopSwitch -TargetDesktopIndex 1`, `Wait-DesktopSwitch -TargetDesktopIndex 0 -TimeoutMs 1000`

Used by `Snap-AllWindows` to confirm each asynchronous `Switch-Desktop` call has actually taken effect before snapping windows, instead of relying on a fixed sleep that can race with the desktop change. Transient RPC/COM errors raised while a switch is in flight are swallowed so polling continues until the timeout. Returns a Boolean.

| Parameter             | Type | Default | Description                                       |
| --------------------- | ---- | ------- | ------------------------------------------------- |
| `-TargetDesktopIndex` | int  | -       | The 0-based virtual desktop index to wait for.    |
| `-TimeoutMs`          | int  | `750`   | Maximum time to poll before giving up.            |
| `-PollIntervalMs`     | int  | `10`    | Delay between polls. Set to `0` for a tight spin. |

```powershell
# Wait up to the default 750ms for virtual desktop index 1 to become active
Wait-DesktopSwitch -TargetDesktopIndex 1

# Wait up to 1000ms for desktop index 0
Wait-DesktopSwitch -TargetDesktopIndex 0 -TimeoutMs 1000
```

## [Wait-ForWorkspaceWindows](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Wait-ForWorkspaceWindows.ps1)

- **Description:** Waits for all expected windows from a workspace layout to be ready. Polls for windows defined in a layout configuration until all are detected and individually stable, or a timeout is reached. Matches by ProcessName, WindowTitle, or both (OR logic for redundant detection), and treats a window as ready only after it holds a consistent title and dimensions for `MinimumStableDurationSeconds`. Supports duplicate layout entries where the same `(ProcessName, WindowTitle)` pair appears multiple times: each entry independently tracks and claims a distinct window handle with handle affinity across poll iterations to prevent stability resets from handle swapping. Optionally cycles through and focuses found windows to speed up loading (some apps such as Firefox and WhatsApp load faster when focused). The extra sequential collective settle after individual stability is opt-in via `-CollectiveStabilitySeconds` (default 0 - it previously added a guaranteed +1s to every open), and `-ProcessAbsentGraceSeconds` abandons an entry when no window has ever matched it AND no live process matches its process pattern, so a dead or mistyped app does not burn the whole timeout.
- **Parameters:** -LayoutConfig, -TimeoutSeconds, -PollIntervalSeconds, -FocusWindows, -FocusDelayMs, -MinimumStableDurationSeconds, -CollectiveStabilitySeconds, -ProcessAbsentGraceSeconds, -RequireStableDimensions, -OnWindowStable
- **Usage:** `Wait-ForWorkspaceWindows -LayoutConfig $config.Layout`, `Wait-ForWorkspaceWindows -LayoutConfig $layout -TimeoutSeconds 30 -PollIntervalSeconds 0.5`, `Wait-ForWorkspaceWindows -LayoutConfig $layout -FocusWindows:$false`, `Wait-ForWorkspaceWindows -LayoutConfig $layout -MinimumStableDurationSeconds 3 -RequireStableDimensions`

A workspace-orchestration helper (called by `Set-WorkspaceWindowLayout` / `Set-WindowLayouts`) that blocks until the apps for a layout have actually finished initializing, so windows are positioned only once they are stable. While waiting it keeps the Windows Terminal topmost to avoid flicker when browser windows steal focus, then restores normal z-order on exit. Returns a hashtable with `Success` (bool - `$false` when the wait timed out or any entry was abandoned), `WindowStates` (handle → position/size snapshot; on failure it still carries the windows that did stabilize, feeding downstream title-drift fallbacks), and `Abandoned` (descriptions of entries abandoned by the process-absent fail-fast).

| Parameter                       | Type        | Default | Description                                                                                                                                                        |
| ------------------------------- | ----------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `-LayoutConfig`                 | array       | -       | Mandatory layout array of window definitions (ProcessName and/or WindowTitle). When both are given, a window matches if EITHER criterion is satisfied.             |
| `-TimeoutSeconds`               | int         | `15`    | Maximum seconds to wait for all windows.                                                                                                                           |
| `-PollIntervalSeconds`          | double      | `0.1`   | Seconds between polling attempts.                                                                                                                                  |
| `-FocusWindows`                 | switch      | `$true` | Cycles through and focuses found (unstable browser) windows to accelerate loading.                                                                                 |
| `-FocusDelayMs`                 | int         | `5`     | Milliseconds to dwell on each window while focusing. Increase if windows need more focus time.                                                                     |
| `-MinimumStableDurationSeconds` | double      | `1`     | Seconds a window must remain stable before being considered fully loaded.                                                                                          |
| `-CollectiveStabilitySeconds`   | double      | `0`     | Extra settle time AFTER every window is individually stable. Default `0` skips it (individual tracking already resets on any change); set above 0 to restore the previous double-settle behavior. |
| `-ProcessAbsentGraceSeconds`    | int         | `10`    | Abandons an entry when no window has ever matched it AND no live process matches its process pattern after this many seconds. Abandoned entries are reported in `Abandoned` and make `Success` `$false`. `0` disables the fail-fast. |
| `-RequireStableDimensions`      | switch      | `$true` | Also requires window dimensions to stop changing during the stability window.                                                                                      |
| `-OnWindowStable`               | scriptblock | -       | Callback fired once per layout entry as each window first becomes individually stable, receiving the layout entry and the window so callers can relocate it early. |

```powershell
# Wait for a layout's windows with default timeout/stability
$config = Import-PowerShellDataFile -Path "MyWorkspace.psd1"
Wait-ForWorkspaceWindows -LayoutConfig $config.Layout

# Custom timeout and a longer stability requirement
Wait-ForWorkspaceWindows -LayoutConfig $config.Layout -TimeoutSeconds 60 -MinimumStableDurationSeconds 2

# Disable focus-to-load acceleration
Wait-ForWorkspaceWindows -LayoutConfig $config.Layout -FocusWindows:$false

# Verbose diagnostic output
Set-LogLevel Verbose { Wait-ForWorkspaceWindows -LayoutConfig $config.Layout }
```

**See also:** [Window module](window.md)

## [Wait-WindowRect](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Wait-WindowRect.ps1)

- **Description:** Polls a window's rectangle (via the native `GetWindowRect` API) until it matches expected bounds within a tolerance, or a time budget elapses. Replaces the "fixed sleep, check once" verification pattern around FancyZones snapping: a fixed delay both wasted time when the snap landed quickly and produced false failures when FancyZones processed the input slower than the delay, escalating to expensive fallbacks (shift-drag, workspace rerun). The first check runs immediately, so an already-correct window costs a single `GetWindowRect` call.
- **Parameters:** -WindowHandle, -ExpectedX, -ExpectedY, -ExpectedWidth, -ExpectedHeight, -TolerancePx (default: 20), -TimeoutMs (default: 300), -PollIntervalMs (default: 15)
- **Usage:** `Wait-WindowRect -WindowHandle $handle -ExpectedX 0 -ExpectedY 0 -ExpectedWidth 1720 -ExpectedHeight 1440`, `Wait-WindowRect -WindowHandle $handle -ExpectedX 0 -ExpectedY 0 -ExpectedWidth 1720 -ExpectedHeight 1440 -TimeoutMs 500`

Used by `Snap-AllWindows` to verify keyboard-snap and shift-drag results, with a time budget that grows on each retry. Position AND size must both match within `TolerancePx` per edge before the poll succeeds. Polling stops early when the handle becomes unreadable (window closed or recreated), since it can no longer succeed. Returns a `PSCustomObject` with `Verified` (bool - `$true` once the rect matched within the budget), the last observed `X`/`Y`/`Width`/`Height` (`$null` when the rect was never readable), and `ElapsedMs` (how long the poll ran).

| Parameter         | Type   | Default | Description                                                                              |
| ----------------- | ------ | ------- | ---------------------------------------------------------------------------------------- |
| `-WindowHandle`   | IntPtr | -       | Handle of the window to observe. (Mandatory)                                             |
| `-ExpectedX`      | int    | -       | Expected left edge in physical pixels. (Mandatory)                                       |
| `-ExpectedY`      | int    | -       | Expected top edge in physical pixels. (Mandatory)                                        |
| `-ExpectedWidth`  | int    | -       | Expected window width in physical pixels. (Mandatory)                                    |
| `-ExpectedHeight` | int    | -       | Expected window height in physical pixels. (Mandatory)                                   |
| `-TolerancePx`    | int    | `20`    | Per-edge tolerance in pixels. Defaults to the module's shared `PositionVerificationPx`.  |
| `-TimeoutMs`      | int    | `300`   | Maximum time to poll before reporting failure.                                           |
| `-PollIntervalMs` | int    | `15`    | Delay between polls.                                                                     |

```powershell
# Poll until FancyZones moves the window to the zone position (immediate first check)
$result = Wait-WindowRect -WindowHandle $handle -ExpectedX 0 -ExpectedY 0 -ExpectedWidth 1720 -ExpectedHeight 1440
if ($result.Verified) { "snapped in $($result.ElapsedMs)ms" }

# Grow the budget for a retry attempt
Wait-WindowRect -WindowHandle $handle -ExpectedX 0 -ExpectedY 0 -ExpectedWidth 1720 -ExpectedHeight 1440 -TimeoutMs 500
```

**See also:** [Snap-AllWindows](window.md#snap-allwindows), [Set-WindowPosition](window.md#set-windowposition)

## [Write-WindowInfoBlock](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Write-WindowInfoBlock.ps1)

- **Description:** Writes a formatted terminal block for a window info object, printing the process name, window title, handle, process ID, position, and size, followed by a ready-to-copy configuration template. Used by `Get-ActiveWindowInfo -Continuous` to keep each captured focus change readable and copyable.
- **Parameters:** -Info
- **Usage:** `Write-WindowInfoBlock -Info $windowInfo`

The `-Info` object is expected to expose `ProcessName`, `Title`, `Handle`, `ProcessId`, `X`, `Y`, `Width`, and `Height`. The handle is rendered in hexadecimal, position as `(X, Y)`, and size as `WidthxHeight`. The trailing config template is pre-filled with the captured `ProcessName` and `Title` so it can be pasted straight into a window-layout configuration block.

| Parameter | Description                                                                                                                                        |
| --------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-Info`   | Window information object (`PSCustomObject`) containing `ProcessName`, `Title`, `Handle`, `ProcessId`, `X`, `Y`, `Width`, and `Height`. Mandatory. |

```powershell
# Render a formatted info block for a captured window object
Write-WindowInfoBlock -Info $windowInfo
```

## Tested Dependency Versions

The Window module relies on specific external software. The versions below are the **known-working, tested combination** as of **2026-07-07** on **Windows 11 25H2** (build 26200). Pinning these versions ensures reliable operation and makes it immediately obvious when a breaking update occurs.

| Dependency                           | Version      | Install Method                                          | Pinned?                             | Notes                                                                                             |
| ------------------------------------ | ------------ | ------------------------------------------------------- | ----------------------------------- | ------------------------------------------------------------------------------------------------- |
| **Microsoft PowerToys** (FancyZones) | **0.100.2**  | `winget install Microsoft.PowerToys`                    | No (Latest via WinGetApps.csv)      | Core dependency - provides zone layouts, keyboard shortcuts (`Win+Ctrl+Alt+N`), and snap behavior |
| **VirtualDesktop** PS module         | **1.5.11**   | `Install-Module VirtualDesktop -RequiredVersion 1.5.11` | Yes (Install-PowerShellModules.ps1) | Virtual desktop creation, window moving, desktop switching. Author: Markus Scholtes (PSGallery)   |
| **PowerShell**                       | 7.5.4        | `winget install Microsoft.PowerShell`                   | No (Latest)                         | Required for module loading and `Add-Type` compilation                                            |
| **Windows Terminal**                 | 1.23.x       | `winget install Microsoft.WindowsTerminal`              | No (Latest)                         | Not a direct dependency but the expected execution environment                                    |
| **.NET System.Windows.Forms**        | 9.0.0        | Built-in (.NET 9 runtime)                               | N/A                                 | Monitor enumeration via `[System.Windows.Forms.Screen]::AllScreens`                               |
| **Windows 11**                       | 25H2 (26200) | N/A                                                     | N/A                                 | Win32 APIs: `user32.dll`, `kernel32.dll`                                                          |

### Why Pin Versions?

- **PowerToys FancyZones** is the backbone of the layout system. Updates can change keyboard shortcut behavior, zone grid spacing algorithms, `custom-layouts.json` format, or snap mechanics - any of which silently break `Apply-FancyZones`, `Snap-AllWindows`, and `Set-WorkspaceWindowLayout`.
- **VirtualDesktop module** wraps undocumented Windows COM interfaces that change between Windows builds. A module update targeting a newer Windows build can break `Move-WindowToVirtualDesktop`, `Ensure-VirtualDesktops`, and desktop switching on the current OS version.

### Updating Dependency Versions

When you want to upgrade a pinned dependency:

1. Install the new version on a **test machine** first
2. Run the full layout test suite: apply each workspace layout, verify all windows land in correct zones and desktops
3. Specifically test:
    - `Set-WorkspaceWindowLayout -WorkspaceName "MyWorkspace"` - multi-zone, multi-desktop
    - `Snap-AllWindows -All` - keyboard snap and shift-drag fallback
    - `Ensure-VirtualDesktops -Count 3` - create/remove desktops
    - `Visualize-Layouts -Layout "MyWorkspace_PC"` - zone coordinate calculations
4. If all tests pass, update the pinned version in:
    - `Modules/Bootstrap/Data/WinGetApps.csv` - for PowerToys
    - `Modules/Application/Functions/Install-PowerShellModules.ps1` - for VirtualDesktop (`$pinnedModules` hashtable)
    - This documentation section

### Zone Geometry Contract

FancyZones lays its zones over each monitor's **work area** (screen minus taskbar), never the full monitor bounds. The Window module honors the same contract:

- `Get-MonitorSpecs` exposes both geometries per monitor: `X/Y/Width/Height` (full bounds, used to **identify** physical monitors) and `WorkX/WorkY/WorkWidth/WorkHeight` (work area, used for **zone math**).
- `Set-WindowLayouts` and `Confirm-WorkspaceWindowPositions` compute every expected zone rectangle from the `Work*` fields, so positioning and snap verification agree with where FancyZones actually snaps - regardless of taskbar visibility. With taskbar auto-hide enabled the two geometries are identical.
- `Window.psm1` opts the process into **Per-Monitor-V2 DPI awareness** at module load, so all coordinates are physical pixels (the space FancyZones works in) on any display scale, not just 100%.

Breaking either half of this contract reproduces the classic fresh-machine failure: zones apply, windows position, but every snap "fails" verification by the taskbar height (or the DPI scale factor) and the workspace endlessly reruns.

## Window Layout System

The Window module creates a **"tiling window manager"** experience on Windows using:

1. **FancyZones** (PowerToys) - Defines zone layouts
2. **Layout files** (.psd1) - Define window-to-zone mappings
3. **Set-WorkspaceWindowLayout** - Applies the configuration

> **⚠️ Important:** The `spacing` value in `FancyZones/custom-layouts.json` **must be set to `3`**. FancyZones internally uses an asymmetric spacing algorithm (full spacing on outer grid edges, half spacing on inner edges), while the zone coordinate calculation uses a uniform approximation. With `spacing: 3` the approximation error is only ~2px, well within snap tolerance. Larger values cause coordinate mismatches that break `Snap-AllWindows` zone verification and shift-drag snapping.

```
┌─────────────────────────────────────────────────────────────────────┐
│                    LAYOUT APPLICATION FLOW                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Layout File (.psd1)                                                │
│  ├── Monitors.Primary.VirtualDesktopLayouts = @{ 1 = "One" }        │
│  └── Layout = @(window rules...)                                    │
│           │                                                         │
│           ▼                                                         │
│  Set-WorkspaceWindowLayout                                          │
│  ├── 0. Read layout file                                            │
│  ├── 1. Ensure required virtual desktops exist                      │
│  ├── 2. Wait for workspace windows to appear and stabilize          │
│  ├── 3. Focus browser first tabs (unmatched windows only)           │
│  ├── 4. Apply FancyZones layouts to monitors                        │
│  ├── 5. For each window rule (Set-WindowLayouts):                   │
│  │       ├── Find window by ProcessName + WindowTitle               │
│  │       ├── Move to correct virtual desktop                        │
│  │       └── Position using shared inset resize path                │
│  ├── 6. Reapply shared pre-snap resize to tracked windows           │
│  ├── 7. Snap all positioned windows to FancyZones                   │
│  ├── 8. Verify all windows are correctly positioned                 │
│  ├── 9. Visualize layout results                                    │
│  └── 10. In-process retries, then auto-rerun on failed snap/verify  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## Layout File Structure

Layout files are in `Modules/Window/Layouts/{MachineType}/`:

```powershell
# Example: MyWorkspace_PC.psd1
@{
    # FancyZones layout per desktop (1-based indexing)
    Monitors = @{
        Primary = @{
            VirtualDesktopLayouts = @{
                1 = "Seven"    # Desktop 1 uses "Seven" layout
                2 = "One"      # Desktop 2 uses "One" layout
            }
        }
        Secondary = @{
            VirtualDesktopLayouts = @{
                1 = "Two"
            }
        }
    }

    # Window rules (DesktopNumber is 1-based)
    Layout = @(
        @{
            ProcessName   = "devenv"
            WindowTitle   = "*MyProject*- Visual Studio*"
            DesktopNumber = 1
            Zone          = "Left"
            Monitor       = "Primary"
        }
        @{
            ProcessName   = "Code"
            WindowTitle   = "*MyRepo*Visual Studio Code"
            DesktopNumber = 1
            Zone          = "Middle"
            Monitor       = "Primary"
        }
        @{
            ProcessName   = "Browser"     # Matches any configured browser
            WindowTitle   = "*"            # Any title
            DesktopNumber = 1
            Zone          = "Top-Right"
            Monitor       = "Primary"
        }
    )
}
```

## Zone Names Reference

Zone names depend on the FancyZones layout:

| Layout  | Zones                                                                     |
| ------- | ------------------------------------------------------------------------- |
| `Zero`  | Full                                                                      |
| `One`   | Left, Right                                                               |
| `Two`   | Left, Middle, Right                                                       |
| `Three` | Far-Left, Middle-Left, Middle-Right, Far-Right                            |
| `Four`  | Top-Left, Bottom-Left, Top-Right, Bottom-Right                            |
| `Five`  | Left, Right (different proportions)                                       |
| `Six`   | Left, Top-Right, Bottom-Right                                             |
| `Seven` | Left, Middle, Top-Right, Bottom-Right                                     |
| `Eight` | Left, Top-Middle, Bottom-Middle, Top-Right, Bottom-Right                  |
| `Nine`  | Top-Left, Bottom-Left, Top-Middle, Bottom-Middle, Top-Right, Bottom-Right |

## Pattern Matching

Both `ProcessName` and `WindowTitle` support exact names, wildcard patterns, and full .NET regex syntax. Plain names without special characters use exact matching for performance. Patterns containing special characters (`(`, `|`, `*`, `?`, `^`, `$`, etc.) are automatically detected and used as regex, with wildcard-to-regex conversion as a fallback.

### Browser Token

Layout entries can use the literal token `Browser` in `ProcessName` (and optionally `WindowTitle`) instead of a specific browser name. At match time, `Resolve-LayoutTokens` expands it to a regex covering every browser declared under `Configuration.Browsers` (Tor excluded - use `tor` explicitly for secure-browser layouts).

```powershell
@{
    ProcessName   = "Browser"   # Expanded to (firefox|chrome|msedge|brave) at match time
    WindowTitle   = "*"
    DesktopNumber = 1
    Zone          = "Left"
    Monitor       = "Primary"
}
```

This keeps layouts browser-agnostic: the same file works whether Firefox, Chrome, Edge, or Brave is the active default. Layout visualizations render the cell as `Browser` rather than the expanded regex. Legacy hardcoded alternations (e.g. `(firefox|chrome|msedge|brave)`) continue to work, but `Validate-Layout` emits a soft warning recommending the token.

### ProcessName Matching

```powershell
ProcessName = "chrome"                         # Exact match
ProcessName = "(firefox|chrome|msedge|brave)"   # Regex alternation
ProcessName = "*chrome*"                        # Wildcard (converted to regex)
ProcessName = "^fire"                           # Regex starts-with
```

### WindowTitle Matching

```powershell
WindowTitle = "*MyRepo*"             # Contains "MyRepo"
WindowTitle = "*Visual Studio Code"  # Ends with "Visual Studio Code"
WindowTitle = "GitHub*"              # Starts with "GitHub"
WindowTitle = "*"                    # Any title
WindowTitle = "(.*Firefox.*|.*Chrome.*)"  # Regex alternation
```

## Duplicate Window Entries

When the same `ProcessName` and `WindowTitle` appear multiple times in a layout, each entry is placed in a different zone. This is used with `Open-Browser`'s `Override` parameter, which opens the same URL group in a separate browser window.

**Workspace action example:**

```powershell
MyWorkspace = @(
    @{ Action = "Open-Browser"; Parameters = @{ Groups = @("GroupName") } }
    @{ Action = "Open-Browser"; Parameters = @{ Groups = @("GroupName"); Override = $true } }
    @{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = "MyWorkspace" } }
)
```

**Layout file example:**

```powershell
Layout = @(
    @{
        ProcessName   = "Browser"
        WindowTitle   = "Google -"
        DesktopNumber = 1
        Zone          = "Left"
        Monitor       = "Secondary"
    }
    @{
        ProcessName   = "Browser"
        WindowTitle   = "Google -"
        DesktopNumber = 1
        Zone          = "Right"
        Monitor       = "Secondary"
    }
)
```

**How it works:**

1. `Wait-ForWorkspaceWindows` detects duplicate entries and waits for the correct number of distinct windows, tracking each with handle affinity to prevent stability resets from handle swapping between poll iterations
2. `Set-WindowLayouts` pre-scans the layout for duplicate `(ProcessName, WindowTitle)` pairs - each entry claims exactly one distinct window handle so they end up in different zones
3. For unique entries (e.g., a single `Code` entry matching two VS Code windows), all matching windows are still processed together - the original behaviour is preserved

## Troubleshooting

### Dependency Version Mismatch

If the Window module stops working after a system update, check versions first:

```powershell
# Check PowerToys version (tested: 0.100.2)
winget list --id Microsoft.PowerToys

# Check VirtualDesktop module version (should be 1.5.11)
Get-InstalledModule -Name VirtualDesktop | Select-Object Name, Version

# Roll PowerToys back to the last tested version if a newer release misbehaves
winget install Microsoft.PowerToys --version 0.100.2 --force

# Downgrade VirtualDesktop if needed
Install-Module -Name VirtualDesktop -RequiredVersion 1.5.11 -Force -Scope CurrentUser
```

### Window Not Positioned

1. Check process name matches (supports exact, wildcard, and regex patterns)
2. Use `Get-ActiveWindowInfo` to verify window title pattern
3. Ensure window is open before applying layout
4. Run the command under `Set-LogLevel Verbose { ... }` for detailed output

### Layout Not Applied

1. Verify FancyZones is running: `Start-FancyZones`
2. Check layout file exists for your machine type
3. Verify zone names match available zones
4. Run `Validate-Layout` to check configuration

### Virtual Desktop Issues

1. Ensure `VirtualDesktop` module is installed
2. Check that required desktops exist
3. Use `Ensure-VirtualDesktops` to create missing desktops
