# Window Module

The Window module provides **window management**, **virtual desktop control**, and **"tiling window manager"** functionality via FancyZones integration.

## [Add-PositionedWindow](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Add-PositionedWindow.ps1)

- **Description:** Adds a window handle to the positioned windows tracking set. Registers a window handle as having been positioned by `Set-WindowLayouts`, storing the expected window state (position, dimensions, title, virtual desktop number, optional process fingerprint, and the `SingleZone` marker) for validation before snapping. `Snap-AllWindows` uses this tracking metadata to verify windows are still in the expected state - detecting stale or reassigned handles in long-running shells and re-resolving windows - and retries positioning if needed. Windows tracked with `-SingleZone` are routed through `Invoke-SingleZoneWindowSnap` - clear any stale FancyZones assignment, center the window in the zone at a deeper inset, `Win+Up`, shift-drag fallback - so they end up registered with FancyZones, not merely positioned.
- **Parameters:** -WindowHandle, -ExpectedX, -ExpectedY, -ExpectedWidth, -ExpectedHeight, -WindowTitle, -DesktopNumber, -ExpectedProcessName, -ExpectedProcessId, -SingleZone
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
| `-SingleZone`          | switch | -       | Marks the window as belonging to a single-zone FancyZones layout (e.g. `Zone = "Fullscreen"` on the `Zero` grid); `Snap-AllWindows` snaps it through `Invoke-SingleZoneWindowSnap`. |

```powershell
# Track a window after positioning it, with optional process fingerprint
Add-PositionedWindow -WindowHandle $window.Handle `
    -ExpectedX 100 -ExpectedY 200 -ExpectedWidth 800 -ExpectedHeight 600 `
    -WindowTitle "MyApp" -DesktopNumber 0 `
    -ExpectedProcessName "myapp" -ExpectedProcessId $window.ProcessId
```

**See also:** [Window module](../modules/window.md)

## [Apply-FancyZones](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Apply-FancyZones.ps1)

- **Description:** Applies the zone layouts a layout file names - per monitor, per virtual desktop - to the workspace's desktops. Reads a `MonitorConfig` hashtable (per-monitor `Layout`, or per-desktop `VirtualDesktopLayouts`), makes sure FancyZones is ready first (`Start-FancyZones`, escalating to a forced restart) and fails fast if readiness cannot be verified. By default (`FancyZonesApplyMethod = "File"`) it writes the entries for every desktop it owns straight into FancyZones' `applied-layouts.json` through `Write-AppliedFancyZonesLayouts`, lets FancyZones reload the file, sends ONE probe shortcut on the current desktop - FancyZones answers a layout shortcut by saving its whole in-memory layout map back to the file - and verifies through `Test-AppliedFancyZonesLayouts` that every written entry survived that save. Desktops that verify need no switch and no shortcut; any desktop that does not, and every desktop under `FancyZonesApplyMethod = "Hotkeys"`, goes through the shortcut pass: switch to it, then `Send-FancyZonesLayoutShortcut` per monitor. The shortcut pass stays idempotent - it reads the applied-layouts state and skips monitors and desktops that are already correct, with instance-qualified keys (`EDID|INSTANCE:GUID`) keeping that safe for identical monitors and the skip disabled only when instance data is missing - and `-Force` bypasses both the idempotency read and the "already applied" skip of the file write, so a retry rewrites and re-proves everything; recovery callers such as `Set-WorkspaceWindowLayout`'s retry pass it for exactly that reason. Supports multi-workspace scenarios via `-DesktopOffset` and `-DesktopCount`.
- **Parameters:** -MonitorConfig, -DesktopNumber, -MonitorInfo, -DesktopOffset, -DesktopCount, -Force
- **Usage:** `Apply-FancyZones -MonitorConfig $config.Monitors`, `Apply-FancyZones -MonitorConfig $config.Monitors -DesktopNumber 2`, `Apply-FancyZones -MonitorConfig $config.Monitors -DesktopOffset 2 -DesktopCount 3`, `Apply-FancyZones -MonitorConfig $config.Monitors -Force`

Only `-MonitorConfig` is mandatory. With no `-DesktopNumber`, it covers every virtual desktop the call owns (using the VirtualDesktop module, when available). In the shortcut pass every desktop switch is confirmed via `Wait-DesktopSwitch` before the layout hotkey is injected - an unconfirmed switch skips that desktop (and the return-desktop re-apply), closing the race where a layout was silently recorded under the previous desktop's GUID - and the pass returns to the starting desktop. Layout names resolve to shortcut numbers (0-9) via `LayoutNumbers` in `Configuration.psd1`, and to layout uuids via `custom-layouts.json` for the file write. Returns a result array (one row per monitor/desktop) with a `Status` such as `Layout Written`, `Shortcut Sent`, `Already Applied`, `Monitor Not Found`, or `Failed`.

**Why the file, and why the probe.** FancyZones keys `applied-layouts.json` by monitor (EDID code, PnP instance path, serial number, monitor number) and virtual desktop GUID, watches the file and reloads it on change, and the work areas it creates when a desktop is first switched to read their entry from the reloaded data (`WorkArea::InitLayout`). Writing the entries therefore replaces one desktop switch, one shortcut and the layout-commit wait per desktop with a single file write - the whole FancyZones phase of a cold open, 3.8 s for 3 desktops and about 7 s for 8 or 10. The probe closes the one gap in that story: whether FancyZones actually reloaded. It never writes the file on a plain reload, but it does save the whole map after a layout shortcut (`ApplyQuickLayout` ends in `SaveData`), so the written entries either survive that save - proving they were loaded - or vanish, in which case those desktops are handed to the shortcut pass. A duplicate entry for the probe desktop means the cloned device block was not FancyZones' own and is treated the same way. The probe lands on the current desktop when this call owns it, otherwise on the first owned desktop, where the shortcut pass would have ended anyway in a `-DesktopOffset` call. Under `Set-LogLevel Verbose` the pass reports `FancyZones took the file update: [n] desktop(s) verified without switching`, or names the reason it fell back.

Monitor handling is **count-agnostic**: the `Monitors` keys are iterated as given, so any number of displays is supported. A key that names a monitor which is not attached (`Monitor6` on a two-monitor machine) is not fatal - the attached monitors are still laid out - but it produces a single warning naming the unresolvable keys and the labels that *are* attached, so a layout/display mismatch is visible instead of passing without a trace. Both passes find the physical monitor the same way: by the layout's own `X`/`Y`/`Width`/`Height` when it carries them, otherwise by the bounds `Get-MonitorSpecs` assigned to the label. A monitor FancyZones has never written an `applied-layouts.json` entry for cannot be written to and stays with the shortcut pass until it has (FancyZones writes one the first time it runs with the monitor attached).

Cost in file mode is one write, one reload settle (`AppliedLayoutsReloadMs`, 150 ms), one shortcut and one verification read, independent of the number of desktops. The shortcut pass scales as **monitors x desktops**: one shortcut send per pair, each carrying the cursor-settle, focus-settle and keyboard-shortcut delays from `Get-WindowModuleDelays` (25 ms each by default) plus one `Switch-Desktop` per desktop; its applied-layouts idempotency skip keeps repeat opens cheap, and `-Force` or a duplicate-EDID collision without instance data disables that skip.

| Parameter        | Description                                                                                                                                                                                                                                                                                       |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-MonitorConfig` | Hashtable of monitor configs keyed by monitor label (`Primary`, `Secondary`, `Monitor3`, ...). Each has a simple `Layout` (e.g. `@{ Layout = "One" }`), an optional legacy `LayoutNumber`, or per-desktop `VirtualDesktopLayouts` (1-based desktop index → layout name or `@{ Layout = ...; LayoutNumber = ... }`). |
| `-DesktopNumber` | Virtual desktop number to apply layouts for; if set and the monitor has `VirtualDesktopLayouts`, uses that desktop's layout.                                                                                                                                                                      |
| `-MonitorInfo`   | Pre-fetched monitor info array to reuse instead of calling `Get-MonitorInfo` (caching optimization).                                                                                                                                                                                              |
| `-DesktopOffset` | Virtual desktop offset for multi-workspace placement; layouts apply to desktops starting from this index.                                                                                                                                                                                         |
| `-DesktopCount`  | Caps how many desktops are processed (from the offset), preventing overwrite of adjacent workspaces' layouts.                                                                                                                                                                                     |
| `-Force`         | Skips the applied-layouts idempotency read; in file mode the entries are rewritten even when the file already holds them and the probe re-proves the reload, in the shortcut pass every layout shortcut is re-sent. Use when the on-disk state cannot be trusted to describe the live zone grid (FancyZones just restarted, or is holding a stale grid) - the case where an ordinary call reports "Already Applied" and changes nothing. |

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

- **Description:** Centers the Windows Terminal on the primary monitor at a physically-constant size. Rather than a fixed percentage, it targets a fixed on-screen pixel size (`CenterTerminalSizing` in `Configuration.psd1`) and derives the width/height percentages from the LIVE primary monitor's work area at run time, then delegates the move/resize to `Center-Windows -OnPrimary`. Because the size is computed from the live monitor (not the hostname-derived `$global:MachineType`), an undocked laptop on its small panel gets a proportionally larger window while a docked laptop or the ultrawide stays at its usual size - so a single target already produces a uniform terminal everywhere, with no per-machine configuration required. The target itself can still be tuned per machine: `CenterTerminalSizing` also accepts a keyed shape resolved by `Resolve-CenterTerminalSizing`. Falls back to `Center-Windows`' default 40% x 50% when the config section resolves to nothing or monitor information is unavailable. Used by `Kill-All` to re-center the surviving terminal after cleanup.
- **Usage:** `Center-Terminal`

Resolves the target size via `Get-MonitorInfo` (live primary monitor work area), `Resolve-CenterTerminalSizing` (which sizing block applies to this display), and `Resolve-CenteredWindowPercent` (target-px to clamped percentages), then calls `Center-Windows -ProcessName "WindowsTerminal" -OnPrimary` with the resolved percentages. The defaults shipped in `CenterTerminalSizing` anchor the target to 1376x700 px - exactly what 40% x 50% yields on a 3440x1440 ultrawide - so the ultrawide is unchanged while smaller panels scale up (e.g. ~72% x 67% on a 1920x1080 laptop).

`CenterTerminalSizing` accepts two shapes. The **keyed** shape holds rows (`SmallDisplay`, machine type, `Default`) and exists to *tune* the pixel target per machine - a physically small panel may want a smaller terminal than the percentages alone would give it. The **legacy flat** shape puts `TargetWidthPx` and friends directly in the section and applies to every machine; it is detected first and wins outright, which keeps a flat local override correct even when it deep-merges on top of a keyed base. The monitor snapshot this function already captured is handed to the resolver, so the rows cost no extra query.

```powershell
# Re-center Windows Terminal on the primary monitor at the adaptive size
Center-Terminal
```

**See also:** [Center-Windows](window.md#center-windows), [Resolve-CenterTerminalSizing](window.md#resolve-centerterminalsizing), [Resolve-CenteredWindowPercent](window.md#resolve-centeredwindowpercent), [Display-Aware Window Sizing](../configuration/configuration-reference.md#display-aware-window-sizing)

## [Center-Text](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Center-Text.ps1)

- **Description:** Centers a string within a specified character width by adding padding on both sides. If the text is longer than the width, it is truncated to fit. Used by Generate-LayoutVisualization to create centered text in ASCII-art layout visualizations.
- **Parameters:** -Text, -Width
- **Usage:** `Center-Text -Text "Hello" -Width 20`

## [Center-Windows](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Center-Windows.ps1)

- **Description:** Centers all open windows on their respective monitors. Enumerates all visible application windows, determines which monitor each window is currently on based on its center point, then moves and resizes every window to a centered position within that monitor's work area. By default windows are resized to 40% of the monitor work area width and 50% of the height (override with `-WidthPercent` / `-HeightPercent`). Off-screen windows are automatically moved to the primary monitor. Pass `-OnPrimary` to force every matched window onto the primary monitor (whichever is currently primary), or `-Monitor` to force them onto a specific monitor by index, label, or device name (resolved by `Resolve-TargetMonitor`, the same path `Move-Windows` uses); the two are mutually exclusive. Forcing a target instead of deriving one per window is what makes a consolidation pass self-correcting - see the note below. Optionally restrict centering to matching windows with `-ProcessName` and/or `-WindowTitle` (exact, wildcard, or regex; OR logic when both are given), delegated to `Get-WindowHandle` - the same filtering path as `Move-Windows`. The actual move/resize is delegated to `Resize-Windows` in target-bounds mode (with `-InsetPercent 0` for exact placement), so all window placement flows through a single shared path (DRY).
- **Parameters:** -WidthPercent, -HeightPercent, -ProcessName, -WindowTitle, -OnPrimary, -Monitor
- **Usage:** `Center-Windows`, `Center-Windows -WidthPercent 60 -HeightPercent 70`, `Center-Windows -ProcessName "chrome"`, `Center-Windows -ProcessName "*chrome*"`, `Center-Windows -ProcessName "(chrome|firefox|msedge)"`, `Center-Windows -WindowTitle "*YouTube*"`, `Center-Windows -ProcessName "WindowsTerminal" -OnPrimary`, `Center-Windows -Monitor 2`

Builds on existing module helpers: `Get-WindowHandle` for pattern filtering when `-ProcessName`/`-WindowTitle` is supplied (otherwise `Get-CachedWindows` enumerates all windows; the cache is cleared first to read fresh positions), `Get-MonitorInfo` for monitor bounds and work areas, `Resize-Windows` (target-bounds mode, `-InsetPercent 0`) for reliable, centralized placement, and `Ensure-WindowsFormsLoaded` for the `System.Windows.Forms` dependency. System and shell windows (Program Manager, Windows Input Experience, search/start surfaces, overlays, etc.) and windows with no meaningful size are skipped. Under `Set-LogLevel Verbose` it prints a per-window trace plus a diagnostics summary with enumerated, eligible, centered, and skipped counts and exclusion counts (skip-title and invalid-size) to explain why some windows were not centered.

| Parameter        | Description                                                                                                                                                                                         |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-WidthPercent`  | Percentage of the monitor work area width per window. Default `40`. Range 10-100.                                                                                                                   |
| `-HeightPercent` | Percentage of the monitor work area height per window. Default `50`. Range 10-100.                                                                                                                  |
| `-ProcessName`   | Only center windows whose process matches this pattern (without `.exe`). Supports exact names, wildcards (`*`, `?`), and regex. Omit to center all visible windows.                                 |
| `-WindowTitle`   | Only center windows whose title matches this pattern. Supports wildcards (`*`, `?`) and regex. Combine with `-ProcessName` (OR logic). Omit (with no `-ProcessName`) to center all visible windows. |
| `-OnPrimary`     | Force every matched window onto the primary monitor (whichever is currently primary), pulling it back from a secondary monitor if needed. Omit to center each window on its current monitor.        |
| `-Monitor`       | Force every matched window onto this monitor: 1-based index (`2`), label (`Primary`, `Secondary`, `Monitor3`), or device name (`\\.\DISPLAY1`). An empty string means no targeting. Excludes `-OnPrimary`. |

Deriving the monitor per window (the default) reads each window's CURRENT position, so it re-homes a window wherever it happens to sit. After a consolidation pass that is the wrong behavior: any window that something else moved in the meantime - notably FancyZones restoring a remembered zone - gets centered on the monitor it drifted to, cementing the stray placement. `-Monitor` re-asserts the intended target instead, which is why `Reset-Windows` passes its configured monitor through.

```powershell
# Center every window at the default 40% x 50% on its current monitor
Center-Windows

# Pull every window onto monitor 2 and center it there
Center-Windows -Monitor 2

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

**See also:** [Reset-Windows](window.md#reset-windows), [Resolve-TargetMonitor](window.md#resolve-targetmonitor)

## [Clear-FancyZonesCache](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Clear-FancyZonesCache.ps1)

- **Description:** Clears the FancyZones layout cache. Invalidates the cached FancyZones layout data (resetting its data, path, and timestamp), forcing the next `Get-CachedFancyZonesLayouts` call to re-read from the JSON file.
- **Usage:** `Clear-FancyZonesCache`

**See also:** [Get-CachedFancyZonesLayouts](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Get-CachedFancyZonesLayouts.ps1)

## [Clear-FancyZonesWindowAssignment](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Clear-FancyZonesWindowAssignment.ps1)

- **Description:** Removes FancyZones' zone-assignment marker (the `FancyZones_zones` window property, see `Get-FancyZonesWindowAssignment`) from a window so a keyboard snap can resolve. FancyZones' position-based `Win+Arrow` only considers zones the window is NOT currently assigned to, so on a one-zone grid a stale assignment is fatal: the only zone is excluded, the snap no-ops on a single monitor and, with `moveWindowAcrossMonitors` enabled, throws the window to the next monitor's zone. Stale assignments are routine because the marker survives every programmatic move - `Reset-Windows` gathers windows with `SetWindowPos` and leaves each one still assigned to the zone it last occupied. Clearing the marker makes the window "new" to FancyZones again, so the next `Win+Up` deterministically snaps it INTO the zone it is sitting in, re-assigning it and rewriting its history entry. Only the live marker is touched; the window's existing `app-zone-history.json` entry is left for FancyZones to rewrite on the next snap. Returns `$true` when a marker was present and removed.
- **Parameters:** -WindowHandle
- **Usage:** `Clear-FancyZonesWindowAssignment -WindowHandle $handle`

**See also:** [Get-FancyZonesWindowAssignment](window.md#get-fancyzoneswindowassignment), [Invoke-SingleZoneWindowSnap](window.md#invoke-singlezonewindowsnap)

## [Clear-MonitorCache](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Clear-MonitorCache.ps1)

- **Description:** Clears the monitor information cache. Invalidates the cached monitor data - including the display-topology fingerprint - forcing the next `Get-CachedMonitors` call to refresh from the Windows Forms API. Useful when the monitor configuration changes. The fingerprint is cleared alongside the data so the next call cannot compare fresh monitors against a signature captured before the change that prompted the clear.
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

- **Description:** Performs a final verification that every window defined in the layout config exists and is at its expected zone position. After `Set-WindowLayouts` positions windows and `Snap-AllWindows` snaps them into FancyZones, it walks the layout config, resolves each entry's expected zone coordinates, finds a matching live window, reads its actual position via the native `GetWindowRect` API, and compares against the expected bounds within `Tolerance`. Called automatically by `Set-WorkspaceWindowLayout` after snapping; returns a result hashtable whose failure objects carry the live window handle so the workspace rerun path can resize only the failing window before retrying. Each failure names the matched window by its real caption (`WindowTitle`), keeping the layout entry's own label under `LayoutEntry` alongside its `ProcessName` - a token-expanded entry's label is a regex such as `(firefox|chrome|msedge|brave)`, which names no window and reads identically for every browser entry in the layout.
- **Parameters:** -LayoutConfig, -MonitorInfo, -MonitorConfig, -DesktopOffset, -ExcludeWindowHandles, -Tolerance (default: 50)
- **Usage:** `Confirm-WorkspaceWindowPositions -LayoutConfig $config.Layout -MonitorInfo $monitorInfo -MonitorConfig $config.Monitors`, `Confirm-WorkspaceWindowPositions -LayoutConfig $config.Layout -MonitorInfo $monitorInfo -MonitorConfig $config.Monitors -DesktopOffset $DesktopOffset`

This is the last verification pass in the workspace layout pipeline. For each layout entry it resolves the expected zone coordinates using the same logic as `Set-WindowLayouts`, locates a live window matching `ProcessName` / `WindowTitle` against a fresh window cache, and compares the actual `GetWindowRect` bounds against the expected zone within `Tolerance` pixels. It catches windows that were never found on the first pass (e.g. an app not yet started), windows whose handles became invalid after positioning, and windows that ended up in the wrong place.

`-ExcludeWindowHandles` narrows what may be matched at all. An alongside open is only allowed to position windows it created, so `Set-WorkspaceWindowLayout` passes the pre-open window snapshot here: windows belonging to whichever workspace is already running are removed from every candidate list, and scoring one into a zone can neither pass an entry no window was ever placed for nor steal the match from an entry's real window. A normal open omits it, and every matching window stays fair game.

When multiple live windows match the same `ProcessName`/`WindowTitle`, candidates are scored by how closely their actual bounds match the expected bounds and the best-matching one is selected; a `$claimedHandles` set guarantees each duplicate-keyed layout entry claims a unique window so identical titles (e.g. two browser windows) are never misassigned. A title-drift fallback handles non-browser apps whose captions change at runtime (e.g. new Outlook / `Olk` titling its window after the selected folder): when strict process-and-title matching finds nothing and exactly one unclaimed process window remains, that window is accepted rather than false-failing. Candidates on the expected virtual desktop are preferred, falling back to cross-desktop candidates only when none exist there. As a last resort before declaring an entry "window not found", the tracked positioned window whose expected bounds and desktop match the entry is accepted, provided its handle is still alive and unclaimed - covering browser windows whose title drifted between positioning and verification (a tab finished loading), which previously escalated to reruns that could never fix a title mismatch.

| Parameter        | Type      | Default | Description                                                                                                                                                       |
| ---------------- | --------- | ------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-LayoutConfig`  | array     | -       | The same layout array passed to `Set-WindowLayouts`; each entry has `ProcessName`, `WindowTitle`, `DesktopNumber`, `Zone`, `Monitor`, `Layout`, etc. (mandatory). |
| `-MonitorInfo`   | array     | -       | Pre-fetched monitor information from `Get-MonitorInfo`.                                                                                                           |
| `-MonitorConfig` | hashtable | -       | The `Monitors` hashtable from the workspace `.psd1` config, used to resolve layout names per virtual desktop per monitor.                                         |
| `-DesktopOffset` | int       | `0`     | Desktop offset applied to all desktop numbers (for alongside / multi-workspace mode).                                                                             |
| `-ExcludeWindowHandles` | HashSet[IntPtr] | - | Handles that may never be matched to a layout entry. `Set-WorkspaceWindowLayout` passes the pre-open snapshot here in alongside mode.                    |
| `-Tolerance`     | int       | `50`    | Maximum pixel deviation allowed per dimension before a window is considered mispositioned.                                                                        |

Returns a `[hashtable]` with `Success` (bool - `$true` if all windows passed), `Total` (int - entries checked), `Passed` (int), and `Failures` (array of objects with `WindowTitle`, `Handle`, `Expected`, `Actual`, and per-dimension `DeltaX`/`DeltaY`/`DeltaW`/`DeltaH`).

Monitor resolution stays in lockstep with `Set-WindowLayouts`, including its refusal to substitute default geometry or fall back to `Primary`: an entry whose monitor has no resolvable geometry is dropped from `Total` rather than counted as a failure. It is the same entry `Set-WindowLayouts` skipped, so verifying it against invented geometry would report a window as misplaced when the real fault is a layout naming a monitor that is not attached.

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

## [Ensure-DesktopVisible](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Ensure-DesktopVisible.ps1)

- **Description:** Brings a virtual desktop on screen - either a given index, or whichever desktop a given window lives on - and returns the index of the desktop that *was* visible so the caller can put the view back. Exists because some window content only exists while its desktop is the visible one: Windows Terminal hosts its tab strip in a XAML island that is not composed off screen, so UI Automation reports such a window as having no descendants at all - no tabs to read, no close buttons to invoke.
- **Parameters:** -WindowHandle, -DesktopIndex
- **Usage:** `Ensure-DesktopVisible -WindowHandle $terminalHandle`, `Ensure-DesktopVisible -DesktopIndex 1`

Unlike [Focus-VirtualDesktop](#focus-virtualdesktop) this does exactly one thing - it makes a desktop visible. No window enumeration, no focus locking, no section title, so a caller can bring a desktop up, do its work, and restore the view without narrating a "focus" step it never intended. `$null` means nothing needs restoring: either the target was already showing, or the switch could not be made. The switch itself is confirmed with `Wait-DesktopSwitch` and retried through a `Reset-VirtualDesktopState` recovery pass (mirroring `Focus-VirtualDesktop`), because a long-running shell can hold a stale VirtualDesktop COM proxy whose `Switch-Desktop` silently no-ops. `Clear-WindowCache` runs after a successful switch, since handles enumerated beforehand describe the previous desktop's composition.

Note that `SetForegroundWindow` and the module's own `ForceForegroundWindow` are both refused by the Windows foreground lock when called from a background process, so activation is not a usable route to the same end - `Switch-Desktop` is not subject to that lock, which is what makes this work. Used by [Get-TerminalTabSnapshot](helper.md#get-terminaltabsnapshot) and [Close-Workspace](workflow.md#close-workspace), both of which read or close terminal tabs on desktops the workspace layout has parked them on.

| Parameter        | Type   | Description                                                                                     |
| ---------------- | ------ | ----------------------------------------------------------------------------------------------- |
| `-WindowHandle`  | IntPtr | Bring up whichever desktop this window lives on. Mandatory in the `Window` parameter set.        |
| `-DesktopIndex`  | int    | Bring up this 0-based desktop index; used to restore a previously returned index. Mandatory in the `Index` parameter set. |

```powershell
# Read a terminal's tabs even though it sits on another desktop, then restore the view
$previous = Ensure-DesktopVisible -WindowHandle $terminalHandle
$tabs = Get-WindowsTerminalTabTitles -WindowHandle $terminalHandle
if ($null -ne $previous) { [void](Ensure-DesktopVisible -DesktopIndex $previous) }
```

**See also:** [Focus-VirtualDesktop](#focus-virtualdesktop), [Wait-DesktopSwitch](#wait-desktopswitch), [Get-TerminalTabSnapshot](helper.md#get-terminaltabsnapshot), [Close-Workspace](workflow.md#close-workspace)

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

**See also:** [Configuration: Window Layout](../configuration/guides/window/configure-window-layout.md)

## [Ensure-WindowsFormsLoaded](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Ensure-WindowsFormsLoaded.ps1)

- **Description:** Ensures the `System.Windows.Forms` assembly is loaded, calling `Add-Type` only if it is not already loaded. Uses a module-scoped flag to avoid repeated `Add-Type` calls.
- **Usage:** `Ensure-WindowsFormsLoaded`

## [Expand-LayoutMonitorCoverage](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Expand-LayoutMonitorCoverage.ps1)

- **Description:** Extends a layout configuration's `Monitors` section to cover every attached monitor, cloning the per-desktop layouts of the first defined monitor as a template. `Apply-FancyZones` iterates the `Monitors` section, so a monitor a layout file does not define is never visited and keeps whatever zone layout it already had. Modifies the passed configuration in place and returns the labels it added. Set `AutoExtendMonitors = $false` at the top level of a layout file to opt that layout out.
- **Parameters:** -Config, -MonitorInfo
- **Usage:** `$added = Expand-LayoutMonitorCoverage -Config $config -MonitorInfo $monitors`

| Parameter      | Description                                                                                                                    |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `-Config`      | The parsed layout configuration (from `Import-PowerShellDataFile`). Its `Monitors` hashtable is modified **in place**.          |
| `-MonitorInfo` | Monitor objects from `Get-MonitorInfo`. When omitted, `Get-MonitorInfo -Quiet` is called. Pass a retrieved set to avoid a second enumeration. |

Called by `Set-WorkspaceWindowLayout` immediately after a layout file is loaded, for **every** workspace. It only extends the `Monitors` section, never the `Layout` array: an auto-added monitor receives a zone layout but no window assignments, so nothing is moved onto it and nothing already targeted elsewhere changes. Monitors the file defines are never modified, and the pass is idempotent.

The template is the first monitor the file defines in label order (`Primary`, `Secondary`, `Monitor3`, ...) rather than hashtable order, so which monitor gets cloned does not depend on the order `Import-PowerShellDataFile` happens to enumerate the keys in. Returns an empty array when the layout already covers every attached monitor, when it opted out, or when the template monitor carries no `VirtualDesktopLayouts` to clone.

**See also:** [Get-MonitorSpecs](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Get-MonitorSpecs.ps1), [Configuration: Window Layout](../configuration/guides/window/configure-window-layout.md)

## [Focus-VirtualDesktop](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Focus-VirtualDesktop.ps1)

- **Description:** Switches to a virtual desktop and locks keyboard focus onto a window that lives there, used as the final `WorkspaceActions` step so a workspace run reliably lands the user on the first desktop. Workspace setup (`Set-WorkspaceWindowLayout` / `Snap-AllWindows`) hops across every desktop while snapping windows and ends with a single, unverified `Switch-Desktop`; in a long-running shell the VirtualDesktop COM/RPC session can go stale and that switch silently no-ops, and even when it takes, nothing guarantees a foreground window on the target desktop - so focus can revert to a window snapped on a higher desktop and drag the view back with it. This function closes both gaps by reusing the proven `Switch-Desktop` + `Wait-DesktopSwitch` retry loop with a `Reset-VirtualDesktopState` recovery pass, then parking focus on a real window on the target desktop.
- **Parameters:** -DesktopNumber, -DesktopOffset
- **Usage:** `Focus-VirtualDesktop`, `Focus-VirtualDesktop -DesktopNumber 1 -DesktopOffset 2`

Resolves the target desktop via `ConvertTo-InternalDesktopIndex` (combining `DesktopNumber` and `DesktopOffset`), runs the `Switch-Desktop` + `Wait-DesktopSwitch` retry loop (up to 3 attempts) with a `Reset-VirtualDesktopState` recovery pass - the same block `Snap-AllWindows` uses - then refreshes the window cache and parks focus on a real window that lives on the target desktop. The focus-target scan is terminal-first and stops at the first window resolved to the target desktop, instead of resolving every window's desktop. It prefers Windows Terminal via `Focus-TerminalTab` (only when the terminal actually lives on that desktop, since activating one elsewhere would drag the view away), handing over the **handle** of the window it verified - left to itself `Focus-TerminalTab` activates the first `WindowsTerminal` *process*, and one process hosts every one of its windows, so the check could clear one window while a sibling on another desktop is the one that actually comes forward. Otherwise it force-foregrounds the first window found there via `WindowModule.Native::ForceForegroundWindow`. Lazy-loads the VirtualDesktop module if needed and reports the outcome with a `=>` status message (focused, switched-but-no-window, or failure) rather than returning a value.

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

## [Format-CanvasZoneListing](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Format-CanvasZoneListing.ps1)

- **Description:** Renders a FancyZones canvas layout as a textual per-zone listing. Canvas zones are free-form rectangles (possibly overlapping), so they cannot be drawn as a proportional ASCII grid the way grid layouts are; this renders one line per zone instead, with the zone's position and size expressed as percentages of the layout's `ref-width`/`ref-height` coordinate space, e.g. `Zone 0 [Left]: x=0% y=0% w=50% h=100%`. Used by `Visualize-Layouts` and `Generate-LayoutVisualization` to render canvas layouts.
- **Parameters:** -LayoutInfo, -ZoneContent, -ZoneNames
- **Usage:** `Format-CanvasZoneListing -LayoutInfo $layoutDef.info -ZoneContent @{} -ZoneNames @{ 0 = "Left" }`

Zone names come from the optional `-ZoneNames` map (zone index to name, shown in brackets after the index); zone content (e.g. process names and window titles) from the optional `-ZoneContent` map, appended after the geometry. A layout with non-positive ref dimensions or no zones returns a descriptive message instead of a listing. Returns the assembled listing as a string with one line per zone.

| Parameter      | Description                                                                                            |
| -------------- | -------------------------------------------------------------------------------------------------------- |
| `-LayoutInfo`  | The canvas layout's `info` object from `custom-layouts.json` (`ref-width`, `ref-height`, `zones`). Mandatory. |
| `-ZoneContent` | Optional hashtable mapping zone index to an array of content labels (e.g. process names). Defaults to `@{}`. |
| `-ZoneNames`   | Optional hashtable mapping zone index to a human-readable zone name. Defaults to `@{}`.                  |

```powershell
# Render a canvas layout with a named first zone
Format-CanvasZoneListing -LayoutInfo $layoutDef.info -ZoneNames @{ 0 = "Left" }

# Include per-zone window content in the listing
Format-CanvasZoneListing -LayoutInfo $layoutDef.info -ZoneContent @{ 0 = @("firefox", "YouTube") }
```

**See also:** [Visualize-Layouts](window.md#visualize-layouts), [Generate-LayoutVisualization](window.md#generate-layoutvisualization)

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

- **Description:** Dynamically generates an ASCII visualization for any grid-based layout. Analyzes a FancyZones grid layout definition and renders ASCII art showing zone boundaries and content, dynamically calculating column widths, row heights, and box-drawing characters from the zone boundaries. Used internally by `Generate-LayoutVisualization` and `Visualize-Layouts`. Grid layouts only - canvas layouts are rendered by `Format-CanvasZoneListing` instead, since free-form rectangles cannot be drawn as a proportional ASCII grid.
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

- **Description:** Generates an ASCII art visualization of a FancyZones layout, showing which processes and windows are assigned to each zone. The visualization is built dynamically from the layout definition in `custom-layouts.json`, so it supports any layout configuration: grid layouts render as a proportional ASCII grid, canvas layouts as a textual per-zone listing. Returns the rendered visualization as a string.
- **Parameters:** -LayoutType, -Windows, -DesktopNumber, -MonitorName, -LayoutsJsonPath
- **Usage:** `Generate-LayoutVisualization -LayoutType "One" -Windows $windows -DesktopNumber 1 -MonitorName "Primary"`

A helper used by `Visualize-Layouts` to render one monitor's layout. It maps each window's `Zone` to a zone index via `ZoneNameMappings` from `Configuration.psd1`, loads the matching layout definition through `Get-LayoutDefinition`, and hands the assembled zone content to `Generate-DynamicVisualization` (grid) or `Format-CanvasZoneListing` (canvas) for rendering; unknown layout types produce a descriptive message instead. When `-LayoutsJsonPath` is omitted, the path is resolved via `Get-FancyZonesLayoutsPath` (anchored on `Configuration.psd1`, no hardcoded parent-folder walking).

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

- **Description:** Returns cached monitor information from `System.Windows.Forms.Screen`. Returns the monitor/screen information from cache if still valid, otherwise refreshes it from `System.Windows.Forms.Screen.AllScreens`. This reduces repeated calls to the Windows Forms API. Two signals invalidate the cache: a change in the display topology, or the TTL expiring.
- **Usage:** `$monitors = Get-CachedMonitors`

Returns an array of `System.Windows.Forms.Screen` objects representing all monitors. The cache is considered stale when no monitors are cached yet, when its age exceeds the configured maximum (`$script:MonitorCache.MaxAgeSec`, 5 s), or when the display-topology fingerprint no longer matches; on a stale read it ensures Windows Forms is loaded, refreshes `AllScreens`, and stamps the cache timestamp and fingerprint before returning.

The fingerprint is the monitor count plus the virtual-screen rectangle - two `GetSystemMetrics` calls, no allocation. It exists because monitor **labels are derived from physical position** (see `Get-MonitorSpecs`): serving a stale cache after the displays change hands out labels for an arrangement that no longer exists, and a TTL alone only bounds how long that wrong answer survives. It catches an attach, a detach, a resolution change and most rearrangements; a swap that leaves both the count and the overall bounds identical still relies on the TTL, which is why the TTL is kept short rather than removed. The fingerprint is skipped until Windows Forms is loaded - which any cached entry already implies - so validating the cache never drags the assembly in on its own.

**See also:** [Clear-MonitorCache](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Clear-MonitorCache.ps1)

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

- **Description:** Gets FancyZone coordinates using human-readable zone names. Provides a user-friendly interface to get zone coordinates by using descriptive zone names instead of numeric indices. The available names per layout are defined in `$Configuration.ZoneNameMappings` (`Configuration.psd1`), which maps each name to a zone index in that layout's `custom-layouts.json` definition.
- **Parameters:** -LayoutName, -ZoneName, -MonitorX, -MonitorY, -MonitorWidth, -MonitorHeight, -CustomLayoutsPath
- **Usage:** `Get-FancyZone -LayoutName "Seven" -ZoneName "Top-Right" -MonitorWidth 3440 -MonitorHeight 1440`, `Get-FancyZone -LayoutName "One" -ZoneName "Right" -MonitorX 1920 -MonitorWidth 1920 -MonitorHeight 1080`

Resolves a human-readable zone name to its numeric index via `ZoneNameMappings` in `Configuration.psd1`, then delegates to `Get-FancyZoneCoordinates` to compute the actual pixel bounds for that zone. Requires the global configuration to be loaded (`Load-PathConfiguration`); if the layout or zone name is unknown it lists the available layouts or zone names and returns `$null`. When a mapped index does not exist in the layout, the error names the layout's zone count and indices and points at `ZoneNameMappings` and `Test-FancyZonesConfiguration` to find the drift. Multiple names may map to the same index (e.g. `Left` and `Far-Left`). Run `Visualize-Layouts -DisplayAvailableLayouts` to see every layout with its zone names in position. Returns a `PSCustomObject` with `ZoneIndex`, `X`, `Y`, `Width`, `Height`, `MonitorX`, `MonitorY`, `LayoutName`, `ZoneName`, and `TotalZoneCount` - how many zones the resolved layout defines, straight from `custom-layouts.json`. A count of `1` is the authoritative single-zone signal the snap pipeline branches on (`Set-WindowLayouts` marks such windows `-SingleZone` so `Snap-AllWindows` snaps them through `Invoke-SingleZoneWindowSnap`); counting `ZoneNameMappings` keys would be wrong because two names (`Full`, `Fullscreen`) map to the same index.

**Monitor geometry is required.** `-MonitorWidth` and `-MonitorHeight` must both be greater than 0; omitting them is an error that returns `$null`, not a cue to assume a display size. They previously defaulted to a `3440x1440` ultrawide, which on a mixed-resolution setup silently computed zones for a display that need not be attached at all. Resolve the real geometry with `Get-MonitorSpecs` and pass the monitor's work area.

| Parameter            | Type   | Default | Description                                                                    |
| -------------------- | ------ | ------- | ------------------------------------------------------------------------------ |
| `-LayoutName`        | string | -       | FancyZones layout name (e.g., "Zero", "One", "Seven").                         |
| `-ZoneName`          | string | -       | Human-readable zone name; valid values depend on the layout.                   |
| `-MonitorX`          | int    | `0`     | Monitor X offset.                                                              |
| `-MonitorY`          | int    | `0`     | Monitor Y offset.                                                              |
| `-MonitorWidth`      | int    | -       | Required. Monitor width in pixels; a non-positive value is an error.           |
| `-MonitorHeight`     | int    | -       | Required. Monitor height in pixels; a non-positive value is an error.          |
| `-CustomLayoutsPath` | string | -       | Optional path to a `custom-layouts.json` file.                                 |

```powershell
# Get coordinates for a named zone on the primary monitor
$primary = (Get-MonitorSpecs).Primary
Get-FancyZone -LayoutName "Seven" -ZoneName "Top-Right" `
    -MonitorX $primary.WorkX -MonitorY $primary.WorkY `
    -MonitorWidth $primary.WorkWidth -MonitorHeight $primary.WorkHeight

# Account for a monitor stacked above (negative Y offset)
Get-FancyZone -LayoutName "Seven" -ZoneName "Left" -MonitorY -1440 -MonitorWidth 3440 -MonitorHeight 1440

# Use the returned object to position a window
$zone = Get-FancyZone -LayoutName "One" -ZoneName "Right" -MonitorWidth 1920 -MonitorHeight 1080
Set-WindowPosition -WindowHandle $handle -X $zone.X -Y $zone.Y -Width $zone.Width -Height $zone.Height
```

**See also:** [Get-FancyZoneCoordinates](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Get-FancyZoneCoordinates.ps1)

## [Get-FancyZoneCoordinates](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Get-FancyZoneCoordinates.ps1)

- **Description:** Calculates zone coordinates from FancyZones custom layouts. Parses the FancyZones `custom-layouts.json` file and computes the actual pixel coordinates (X, Y, width, height) for each zone, replicating the zone math PowerToys FancyZones itself uses so the computed rectangles match what FancyZones snaps windows to. Both `grid` and `canvas` layout types are supported, with arbitrary zone definitions and any `spacing` value.
- **Parameters:** -LayoutName, -MonitorX, -MonitorY, -MonitorWidth, -MonitorHeight, -CustomLayoutsPath
- **Usage:** `Get-FancyZoneCoordinates -LayoutName "Seven" -MonitorX 0 -MonitorY -1440 -MonitorWidth 3440 -MonitorHeight 1440`

For **grid** layouts, row and column edges are computed with cumulative prefix sums and floor division so the cells always add up to exactly the monitor work area, regardless of how the percentages divide (e.g. `3333/3333/3334` loses no pixels). Spacing follows the real FancyZones model: FancyZones insets edges that touch the work-area border by the full spacing value, and interior edges by `Floor(spacing/2)` per zone (two adjacent zones leave `2 * Floor(spacing/2)` px between them); a zone spanning multiple cells absorbs the spacing between them, because only the zone's own outer edges are inset. Any spacing value works. For **canvas** layouts, each zone's explicit X/Y/width/height rectangle (drawn in the layout's `ref-width`/`ref-height` coordinate space) is scaled to the monitor work area; canvas layouts ignore spacing entirely, and the zone index is the zone's position in the layout's `zones` array. Malformed definitions (percentage count mismatches, cell-child-map dimension mismatches, invalid canvas ref dimensions) produce clear errors. When the JSON path is omitted it falls back to the machine-specific PowerToys CustomLayouts symlink target, or the repository file via `Get-FancyZonesLayoutsPath`. Each zone is returned as a `PSCustomObject` with `ZoneIndex`, `X`, `Y`, `Width`, `Height`, `MonitorX`, `MonitorY`, and `LayoutName`.

| Parameter            | Description                                                                                                          |
| -------------------- | --------------------------------------------------------------------------------------------------------------------- |
| `-LayoutName`        | Required. The name of the FancyZones layout (e.g., `"Zero"`, `"One"`, `"Seven"`).                                     |
| `-MonitorX`          | The X position of the monitor work area (default: `0`).                                                               |
| `-MonitorY`          | The Y position of the monitor work area (default: `0`).                                                               |
| `-MonitorWidth`      | Required. The width of the monitor **work area** in pixels, excluding the taskbar; a non-positive value is an error.  |
| `-MonitorHeight`     | Required. The height of the monitor **work area** in pixels, excluding the taskbar; a non-positive value is an error. |
| `-CustomLayoutsPath` | Optional path to `custom-layouts.json`. If not specified, uses the PowerToys symlink target or the repository file. |

**Monitor geometry is required.** `-MonitorWidth` and `-MonitorHeight` must both be greater than 0; omitting them writes an error and returns `$null`. They previously defaulted to a `3440x1440` ultrawide, so a caller that resolved no monitor silently got zones for a display that need not be attached.

```powershell
# Calculate zones for a layout on a monitor stacked above the primary (negative Y)
Get-FancyZoneCoordinates -LayoutName "Seven" -MonitorX 0 -MonitorY -1440 -MonitorWidth 3440 -MonitorHeight 1440

# Capture zones from a resolved monitor and index into a specific one
$primary = (Get-MonitorSpecs).Primary
$zones = Get-FancyZoneCoordinates -LayoutName "One" `
    -MonitorX $primary.WorkX -MonitorY $primary.WorkY `
    -MonitorWidth $primary.WorkWidth -MonitorHeight $primary.WorkHeight
$leftZone = $zones[0]  # Get coordinates for zone 0 (left)
```

**See also:** [Get-FancyZonesLayoutsPath](window.md#get-fancyzoneslayoutspath), [Test-FancyZonesConfiguration](window.md#test-fancyzonesconfiguration)

## [Get-FancyZonesLayoutsPath](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Get-FancyZonesLayoutsPath.ps1)

- **Description:** Resolves the repository path of a FancyZones configuration file. The repository root is resolved through `Get-RepositoryPath`, which anchors on `Configuration.psd1` instead of counting parent folders, so callers are immune to being relocated to a different depth. This is the single place that knows where the FancyZones files live in the repo. Returns the path string; the file is not required to exist - callers decide how to handle a missing file.
- **Parameters:** -File
- **Usage:** `Get-FancyZonesLayoutsPath`, `Get-FancyZonesLayoutsPath -File LayoutHotkeys`

Consumers that need the file FancyZones actually loaded should keep reading the `%LOCALAPPDATA%` copy instead - the repo file is the symlink TARGET, and zone math should always be computed from the repository's source of truth. `Apply-FancyZones` deliberately keeps reading the `%LOCALAPPDATA%` copy for its uuid idempotency check, while `Get-FancyZoneCoordinates`, `Test-FancyZonesConfiguration`, `Visualize-Layouts`, and `Generate-LayoutVisualization` resolve the repository files through this helper.

| Parameter | Type   | Default         | Description                                                                                                                             |
| --------- | ------ | --------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `-File`   | string | `CustomLayouts` | Which file to resolve: `CustomLayouts` => `Windows\FancyZones\custom-layouts.json`; `LayoutHotkeys` => `Windows\FancyZones\layout-hotkeys.json`. |

```powershell
# Resolve the repository custom-layouts.json
$layoutsPath = Get-FancyZonesLayoutsPath

# Resolve the repository layout-hotkeys.json
$hotkeysPath = Get-FancyZonesLayoutsPath -File LayoutHotkeys
```

**See also:** [Test-FancyZonesConfiguration](window.md#test-fancyzonesconfiguration), [Get-FancyZoneCoordinates](window.md#get-fancyzonecoordinates)

## [Get-FancyZonesWindowAssignment](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Get-FancyZonesWindowAssignment.ps1)

- **Description:** Reads FancyZones' own zone-assignment marker for a window: the `FancyZones_zones` window property, a zone-index bitmask (zone 0 => `0x1`, zone 1 => `0x2`, ...) FancyZones stamps on every window IT moved into a zone. The property is how FancyZones itself distinguishes a **snapped** window - one it assigned, wrote into `app-zone-history.json` for, and will relocate on zone-set and display changes - from a window that merely sits at zone-like coordinates. A plain `SetWindowPos` never sets it, and only FancyZones' own operations clear it, so the marker survives every programmatic move (`Reset-Windows` included). Zero therefore means "not registered with FancyZones", the state a direct placement leaves behind and the state `Invoke-SingleZoneWindowSnap` exists to avoid.
- **Parameters:** -WindowHandle
- **Usage:** `Get-FancyZonesWindowAssignment -WindowHandle $handle`

The property name is a PowerToys implementation detail (stable across releases, verified against PowerToys 0.100). If a future release renames it, this function reads `0` for every window and its consumers degrade to snapping without assignment awareness rather than failing.

```powershell
$mask = Get-FancyZonesWindowAssignment -WindowHandle $handle
if ($mask -eq 0) { "window is only positioned, not snapped" }
```

**See also:** [Clear-FancyZonesWindowAssignment](window.md#clear-fancyzoneswindowassignment), [Invoke-SingleZoneWindowSnap](window.md#invoke-singlezonewindowsnap)

## [Get-InsetWindowBounds](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Get-InsetWindowBounds.ps1)

- **Description:** Calculates inset window bounds inside a target zone. Returns the adjusted bounds used before FancyZones snapping, deliberately offset from the zone's exact center by `InsetCenterBiasPx` (2px, defined at the top of the function's own file) so the snap target stays unambiguous. The bias is load-bearing: FancyZones' `Win+Arrow` is a *relative* move that only snaps a window into the zone it is sitting in while it does not already recognise the window as zoned, and a window centered exactly on its zone is recognised - every arrow key then throws it into the neighbouring zone and the slow shift-drag fallback has to recover it. Historically the zone rectangles fed in here were a couple of pixels off the real FancyZones geometry, so "centered on the computed zone" happened to land the window off-center in the *actual* zone; now that the zone math reproduces FancyZones exactly, that accident is gone and the offset has to be deliberate.
- **Parameters:** -TargetX, -TargetY, -TargetWidth, -TargetHeight, -InsetPercent
- **Usage:** `Get-InsetWindowBounds -TargetX 0 -TargetY 0 -TargetWidth 1920 -TargetHeight 1080`, `Get-InsetWindowBounds -TargetX 0 -TargetY 0 -TargetWidth 960 -TargetHeight 1080 -InsetPercent 0.05`

Computes shared inset bounds for pre-snap resizing. The target zone is shrunk by `InsetPercent` on each side and re-centered on the zone center, returning a `[PSCustomObject]` carrying both the original target values and the adjusted geometry: `AdjustedX`, `AdjustedY`, `AdjustedWidth`, `AdjustedHeight`, `AdjustedRight`, `AdjustedBottom`, plus `ZoneCenterX`/`ZoneCenterY`. Adjusted width and height are floored at 1px.

The default inset comes from `Get-WindowInsetPercent` (the `SnapInsetPercent` configuration value, `0.05` when unset) - one value shared by every placement path. Passing `-InsetPercent` explicitly bypasses it entirely, since a bound parameter never evaluates its default expression.

| Parameter       | Type   | Mandatory | Description                                                                     |
| --------------- | ------ | --------- | ------------------------------------------------------------------------------- |
| `-TargetX`      | int    | Yes       | Target zone X coordinate.                                                       |
| `-TargetY`      | int    | Yes       | Target zone Y coordinate.                                                       |
| `-TargetWidth`  | int    | Yes       | Target zone width.                                                              |
| `-TargetHeight` | int    | Yes       | Target zone height.                                                             |
| `-InsetPercent` | double | No        | Inset percentage applied on each side. Range `0.0`-`0.49`. Defaults to `Get-WindowInsetPercent` (`SnapInsetPercent`, `0.05` when unset). |

```powershell
# Inset bounds for a full 1920x1080 zone using the default 5% inset
$bounds = Get-InsetWindowBounds -TargetX 0 -TargetY 0 -TargetWidth 1920 -TargetHeight 1080

# Half-width zone with an explicit inset percentage
$bounds = Get-InsetWindowBounds -TargetX 0 -TargetY 0 -TargetWidth 960 -TargetHeight 1080 -InsetPercent 0.05
```

## [Get-LayoutDefinition](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Get-LayoutDefinition.ps1)

- **Description:** Retrieves a specific FancyZones layout definition from the `custom-layouts.json` configuration file by name. Used internally by the layout visualization system to access layout configurations (grid definitions including cell-child-map data, and canvas zone rectangles). Returns the matching layout definition object, or `$null` if the file is missing or no layout matches.
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

## [Get-LayoutMachineType](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Get-LayoutMachineType.ps1)

- **Description:** Resolves the machine type whose window-arrangement settings apply to the current display setup, in order: a non-empty `LayoutMachineTypeOverrides` entry for the detected machine type, else `SmallDisplayMachineType` when `Test-SmallPrimaryDisplay` reports a laptop-class primary display, else the detected type from `DetermineMachineType`. Shared by `Set-WorkspaceWindowLayout` (which `Layouts/<Type>/` folder and `<Workspace>_<Type>.psd1` file to load), `Reset-Windows` (which `ResetAllWindowsDefaults` profile to apply), and `Resolve-DisplayAwareProfile` (which row of `CenterTerminalSizing` / `ResizeWindowsPercent` applies), so every answer to "which monitor setup am I on?" comes from one resolution instead of drifting apart. Only display-shaped settings resolve through it - base paths, symbolic links, wallpapers, themes, and the taskbar keep using `DetermineMachineType`, so a redirect never relocates a path or repaints a desktop.
- **Parameters:** -MonitorInfo
- **Usage:** `Get-LayoutMachineType`, `Get-LayoutMachineType -MonitorInfo $cachedMonitorInfo`

Window layouts and the reset defaults describe a machine's **monitors**, not its identity, and monitors change: a desktop moved away from its multi-monitor rig, a temporary single screen, a laptop-class display. The manual override is checked before the display-size rule on purpose - an explicit choice must not be overruled by a monitor-width guess, which is exactly what a temporary single screen would trigger.

Monitors are measured only when the small-display rule is actually reachable (no override matched **and** `SmallDisplayMachineType` is configured), so the common path costs nothing beyond the machine-type lookup. The measurement itself lives in `Test-SmallPrimaryDisplay`, shared with `Resolve-DisplayAwareProfile` so the two can never disagree about what counts as a small display. Callers that already hold a snapshot pass it via `-MonitorInfo` to avoid a second query; an empty or unavailable snapshot simply leaves the detected machine type in place. The redirect it picks is logged at verbose level by whichever rule fired.

| Parameter      | Type     | Default | Description                                                                                                                                          |
| -------------- | -------- | ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-MonitorInfo` | object[] | -       | Monitor records from `Get-MonitorInfo`. Pass a snapshot the caller already holds to avoid re-querying; when omitted, monitors are fetched on demand. |

```powershell
# "PC" normally; "Temp" when LayoutMachineTypeOverrides.PC = "Temp"
Get-LayoutMachineType

# Reuse a monitor snapshot the caller already captured
Get-LayoutMachineType -MonitorInfo $cachedMonitorInfo
```

**See also:** [Set-WorkspaceWindowLayout](window.md#set-workspacewindowlayout), [Reset-Windows](window.md#reset-windows), [Test-SmallPrimaryDisplay](window.md#test-smallprimarydisplay), [Resolve-DisplayAwareProfile](window.md#resolve-displayawareprofile), [Layout Set Overrides](../configuration/configuration-reference.md#layout-set-overrides)

## [Get-MonitorDeviceIdentityMap](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Get-MonitorDeviceIdentityMap.ps1)

- **Description:** Maps display device names (`\\.\DISPLAY1`) to the identity FancyZones keys its files by: the monitor's EDID code (`DELA1A8`) and its PnP instance path (`4&1CFDC60E&0&UID8262`), both upper-cased, read through `EnumDisplayDevices` with `EDD_GET_DEVICE_INTERFACE_NAME` (`GetMonitorDeviceInfo` in `WindowNative.cs`). These are the `monitor` and `monitor-instance` fields of `applied-layouts.json`, so `Apply-FancyZones` builds both its idempotency keys and the targets of the file-based layout application from them. Returns empty maps when the native type is not loaded or the enumeration fails, and callers fall back to matching by display name.
- **Parameters:** none
- **Usage:** `$identity = Get-MonitorDeviceIdentityMap`, `$identity.Edid['\\.\DISPLAY1']`, `$identity.Instance['\\.\DISPLAY1']`

Returns a `PSCustomObject` with two hashtables, `Edid` and `Instance`, both keyed by display device name. The instance path only exists in the interface-name form of the device ID; a display whose enumeration yields the device-class form keeps its `Edid` entry and gets no `Instance` entry.

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

Calls `Get-MonitorInfo` (or reuses pre-fetched info via `-MonitorInfo`) and remaps each display to a label: the primary monitor becomes `Primary`, and the remaining displays become `Secondary`, `Monitor3`, `Monitor4`, ... Each entry exposes `X`, `Y`, `Width`, `Height`, `DeviceName`, and the work-area fields `WorkX`, `WorkY`, `WorkWidth`, `WorkHeight` (the screen minus the taskbar - what FancyZones lays zones over). By default the result is a `PSCustomObject` for easy property access; with `-AsHashtable` it returns a hashtable suited to layout configuration files. Returns `$null` (with an error) when no monitors are detected.

### Label ordering

The non-primary displays are ordered by **physical position** - sorted by `Left`, then `Top`, then `DeviceName` - never by `Get-MonitorInfo` / `Screen.AllScreens` enumeration order. That enumeration order is neither spatial nor stable: the non-primary display can sort first, and the order can change on monitor sleep/wake, a DisplayPort link drop, a GPU driver reload or a dock/undock.

With two displays there is exactly one non-primary monitor, so `Secondary` was correct whatever the order and the instability was invisible. With three or more, which physical panel became `Secondary` versus `Monitor3` was arbitrary and could swap between runs, silently retargeting every layout entry that named them.

The consequence to keep in mind: **a label identifies a position in the current arrangement, not a specific panel.** It survives a display re-enumeration but not an actual rearrangement - move your displays around in Windows display settings and the labels follow the new arrangement, as do the layout files naming them. Use a device name (`\\.\DISPLAY1`) where a target must be pinned to one physical panel; `Move-Windows`, `Center-Windows` and `Reset-Windows` all accept one. `DeviceName` breaks the remaining sort tie so mirrored displays, which report identical bounds, still get a fixed order.

Use [Resolve-MonitorLabel](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Resolve-MonitorLabel.ps1) to convert between a label and its 0-based ordinal. Any monitor count is supported - the labels continue `Monitor4`, `Monitor5`, ... for as many displays as are attached.

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

## [Get-WindowDesktopIndex](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Get-WindowDesktopIndex.ps1)

- **Description:** Resolves which virtual desktop a window lives on, as a 0-based index, returning `-1` for every "cannot tell" case rather than `$null` or an exception. Wraps the `Get-DesktopIndex (Get-DesktopFromWindow -Hwnd ...)` pair with the guards each caller of it needs: the VirtualDesktop module may not be loaded, and the lookup throws for windows that cannot be resolved at all.
- **Parameters:** -WindowHandle
- **Usage:** `Get-WindowDesktopIndex -WindowHandle $window.Handle`

Shell windows are why the `-1` contract matters in practice: "Windows Input Experience" (`TextInputHost`) always answers `TYPE_E_ELEMENTNOTFOUND`, and a window that closed mid-scan answers nothing at all. Neither is an error worth propagating - the window simply has no known desktop - so callers can compare the result without null checks and never wrap the call in a `try`. Note that `0` is a real answer and a falsy one: the first desktop is where a plain workspace lands, so callers must test the value, not its truthiness.

Failures are **not** retried. A window that cannot be resolved on its own merits cannot succeed on a second attempt, and burning an RPC backoff ladder per window is exactly the cost [Remove-VirtualDesktops](system.md#remove-virtualdesktops) was fixed to stop paying; a caller doing a whole-set scan that must tolerate genuine RPC failure should retry the scan, not the window. Used by [Close-Workspace](workflow.md#close-workspace) to decide which windows sit on a workspace's own desktops and which desktops to remove with it.

| Parameter       | Description                                              |
| --------------- | -------------------------------------------------------- |
| `-WindowHandle` | `IntPtr` handle of the window to locate. Mandatory.      |

```powershell
# Where is this window?
$index = Get-WindowDesktopIndex -WindowHandle $window.Handle
if ($index -ge 0) { "window is on desktop $index" }

# Group every visible window by the desktop it sits on
Get-WindowHandle | Group-Object { Get-WindowDesktopIndex -WindowHandle $_.Handle }
```

**See also:** [Ensure-DesktopVisible](#ensure-desktopvisible), [Remove-VirtualDesktops](system.md#remove-virtualdesktops), [Close-Workspace](workflow.md#close-workspace)

## [Get-WindowDisplayName](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Get-WindowDisplayName.ps1)

- **Description:** Resolves a friendly display label for a window from its process name, falling back to its window title. Known processes are mapped to a product name (e.g. `WindowsTerminal` => "Windows Terminal", whose live title follows the active tab); any other process uses the supplied title. Used by `Center-Windows` and `Move-Windows` to label the windows they acted on.
- **Parameters:** `-ProcessName` `[-Title]`
- **Usage:** `Get-WindowDisplayName -ProcessName "WindowsTerminal" -Title "PowerShell"`

## [Get-WindowFrameMargin](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Get-WindowFrameMargin.ps1)

- **Description:** Measures the per-edge gap between a window's frame rectangle and the frame the user actually sees. `SetWindowPos` and `GetWindowRect` both work on the frame rectangle, which on a standard desktop window extends past the visible window by the DWM invisible resize border - about 7px on the left, right and bottom at 100% scaling, growing with the monitor's DPI. FancyZones sizes a snapped window against the **visible** frame instead (`DWMWA_EXTENDED_FRAME_BOUNDS`), which is why a keyboard-snapped window's `GetWindowRect` overhangs its zone while the window itself sits flush inside it. The zone rectangle grown by this per-edge difference is therefore the exact frame rect a FancyZones snap produces: `Invoke-SingleZoneWindowSnap` verifies its snaps against that compensated rectangle, and `Invoke-SingleZoneWindowPlacement` places directly at it.
- **Parameters:** -WindowHandle
- **Usage:** `Get-WindowFrameMargin -WindowHandle $handle`

The margin is measured on the actual window at call time, because it is a property of that window's style and its monitor's DPI rather than a constant: standard windows report 7/0/7/7 (left/top/right/bottom), UWP hosts report a margin on all four edges, and console and borderless windows report none at all. Every failure path returns all-zero margins rather than throwing - a failed native read, a negative edge (clamped), any edge past the 50px sanity cap (the whole reading is discarded, since the real border stays under 40px even at the 500% scaling ceiling, so a larger value means the window was cloaked or mid-transition and the reading does not describe a border), and a session whose in-memory `WindowNative` type was compiled before `GetExtendedFrameBounds` existed, since `Add-Type` cannot recompile it. A caller's arithmetic then degrades to the uncompensated rectangle instead of chasing a target nothing will match.

```powershell
$margin = Get-WindowFrameMargin -WindowHandle $handle
$placeWidth = $zone.Width + $margin.Left + $margin.Right
```

**See also:** [Invoke-SingleZoneWindowSnap](window.md#invoke-singlezonewindowsnap), [Invoke-SingleZoneWindowPlacement](window.md#invoke-singlezonewindowplacement), [Set-WindowPosition](window.md#set-windowposition)

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

## [Get-WindowInsetPercent](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Get-WindowInsetPercent.ps1)

- **Description:** Returns the pre-snap inset fraction every FancyZones placement path trims off each side of a target zone. The single source of truth for `SnapInsetPercent` in `Configuration.psd1`, falling back to the built-in `0.05` when it is unset or invalid. Read by `Resize-Windows`, `Get-InsetWindowBounds`, and `Resize-PositionedWindows` as a parameter default, and by `Set-WindowLayouts` and `Snap-AllWindows` directly - five places that each used to hardcode the same `0.05`.
- **Usage:** `Get-WindowInsetPercent`

A getter rather than a module variable, because parameter defaults are evaluated at call time and the configuration is not loaded when the module is imported. Reading `$global:Configuration` on every call also means a reloaded profile takes effect immediately.

Anything non-numeric, or outside the `0.0`-`0.49` range that every consuming parameter's `ValidateRange` accepts, falls back to `0.05` - a config typo must not abort a workspace open mid-loop. `0.49` is the ceiling because two insets of `0.5` would leave a zero-width window. Explicitly passing `-InsetPercent` still wins everywhere, which is how `Center-Windows` keeps its deliberate `-InsetPercent 0` (exact placement, no inset).

```powershell
# 0.05 by default; whatever SnapInsetPercent is set to otherwise
Get-WindowInsetPercent
```

**See also:** [Get-InsetWindowBounds](window.md#get-insetwindowbounds), [Resize-Windows](window.md#resize-windows), [Display-Aware Window Sizing](../configuration/configuration-reference.md#display-aware-window-sizing)

## [Get-WindowModuleDelays](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Get-WindowModuleDelays.ps1)

- **Description:** Gets the current Window module timing configuration. Returns a clone of the module-scoped timing configuration hashtable, allowing external tuning of the delay values (in milliseconds) used throughout the module.
- **Usage:** `Get-WindowModuleDelays`

## [Get-WorkspaceLayoutTimings](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Get-WorkspaceLayoutTimings.ps1)

- **Description:** Returns the phase timings recorded by the most recent `Set-WorkspaceWindowLayout` run in this session, or `$null` when none has run. The record names the workspace and layout file, the attempt count, how the run ended (`Applied`, `Escalated`, `Error` or `Aborted`), the total seconds, and the seconds spent per phase - `Preamble` (RPC probe, layout file, validation, snapshot read), `Desktops` (virtual desktop resize), `FancyZones` (zone layouts applied per desktop), `Wait` (`Wait-ForWorkspaceWindows`), `Normalize` (browser first-tab and first-open resize passes), `Position` (`Set-WindowLayouts` and the pre-snap resize), `Snap` (`Snap-AllWindows`), `Verify` (`Confirm-WorkspaceWindowPositions`), `Retry` (the FancyZones reset between in-process attempts), `Save` (snapshot write, empty-desktop cleanup, visualization) and `Other` (whatever ran after the last mark) - accumulated across the in-process retry loop, so a run that snapped twice reports the sum. It is the read side of the phase clock `Set-WorkspaceWindowLayout` keeps, and exists so `Open-Workspace` (Workflow module) can attach the layout breakdown to the benchmark row it writes through [Write-WorkspaceBenchmark](workflow.md#write-workspacebenchmark) without reaching into this module's private state. The value is replaced by every run; `RecordedAt` tells a caller whether it belongs to the run it just made.
- **Usage:** `Get-WorkspaceLayoutTimings`, `(Get-WorkspaceLayoutTimings).Phases`

```powershell
# Which phases dominated the last layout pass
$timings = Get-WorkspaceLayoutTimings
$timings.Phases.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 3
```

**See also:** [Set-WorkspaceWindowLayout](#set-workspacewindowlayout), [Write-WorkspaceBenchmark](workflow.md#write-workspacebenchmark), [Get-WorkspaceBenchmark](workflow.md#get-workspacebenchmark)

## [Get-WorkspaceRerunMirror](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Get-WorkspaceRerunMirror.ps1)

- **Description:** Reads and consumes the persisted mirror of a workspace rerun marker written by [Set-WorkspaceRerunMirror](#set-workspacererunmirror). One-shot: a value found is cleared as it is read, so a marker can influence exactly the run it was written for. Values older than the TTL, timestamped in the future, or not in `value|unix-timestamp` form are discarded.
- **Parameters:** -Name, -TtlMinutes, -Scope
- **Usage:** `Get-WorkspaceRerunMirror -Name 'WORKSPACE_RERUN_COUNT'`, `Get-WorkspaceRerunMirror -Name 'WORKSPACE_RERUN_COUNT' -TtlMinutes 1`

`Set-WorkspaceWindowLayout` keeps its auto-rerun state in process-scoped environment variables, which do not survive the terminal respawn: Windows Terminal generates a new environment block for every session it starts (its `reloadEnvironmentVariables` setting, on by default), built from the registry rather than inherited from the shell that ran `wt`, so the respawned shell never sees the escalating run's process copies - every marker reset and the rerun loop was uncapped, hence the out-of-process mirror. That same registry-built block is how the mirror reaches the new shell: verbatim, stamp included, as the process copy of the same variable. `Set-WorkspaceWindowLayout` therefore uses a process copy only when it is a plain value the running shell wrote itself, skips one carrying the `|unix-timestamp` stamp (a snapshot of the mirror taken when the shell started - never newer than the mirror, and possibly far older in a long-lived `"useAnyExisting"` host) and falls back to this function, whose TTL and one-shot consume make it the only authoritative copy. Returns `$null` when there is nothing valid to report, which is the normal case.

| Parameter      | Description                                                                                              |
| -------------- | -------------------------------------------------------------------------------------------------------- |
| `-Name`        | Environment variable to read, e.g. `WORKSPACE_WINDOW_ONLY_RETRY`.                                        |
| `-TtlMinutes`  | Maximum age at which a mirrored value is still honored. Defaults to 10.                                  |
| `-Scope`       | `User` (default) or `Process`. `Process` exists for tests - see the note under Set-WorkspaceRerunMirror.  |

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

## [Invoke-SingleZoneWindowPlacement](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Invoke-SingleZoneWindowPlacement.ps1)

- **Description:** Places a window directly at a single-zone layout's zone rectangle, with verification. This is the deterministic DIRECT-placement primitive for windows assigned to a single-zone FancyZones layout (e.g. `Zone = "Fullscreen"` on the one-zone `Zero` grid): it calls `Set-WindowPosition` straight to the zone rectangle - grown by the window's frame margins, see below - and verifies the result with `Wait-WindowRect`, the same geometry check the snap path and `Confirm-WorkspaceWindowPositions` use. Because it bypasses FancyZones entirely, the window it places is NOT registered as zoned (see `Get-FancyZonesWindowAssignment`), which is why it serves exactly one caller: `Set-WorkspaceWindowLayout`'s simple-layout path, where windows sit on **invisible** desktops that FancyZones' own keyboard and drag paths cannot reach without desktop switching.
- **Parameters:** -WindowHandle, -TargetX, -TargetY, -TargetWidth, -TargetHeight, -WindowTitle, -MaxAttempts
- **Usage:** `Invoke-SingleZoneWindowPlacement -WindowHandle $handle -TargetX 0 -TargetY 0 -TargetWidth 3434 -TargetHeight 1384`

`Set-WindowPosition` is used directly (not `Resize-Windows -InsetPercent 0`) because `Get-InsetWindowBounds` applies an unconditional center bias even at zero inset - the bias exists to keep the *relative* snap deterministic, which is exactly what this placement does not do. Retries re-issue the placement with a growing verification budget; failures a `SetWindowPos` cannot fix (an app enforcing a minimum/maximum size smaller than the zone) will not be fixed by more attempts either - the caller reports expected vs actual bounds and hands the window to the workspace retry loop.

The rectangle that reaches `SetWindowPos` is the zone grown by the window's frame margins (`Get-WindowFrameMargin`), because the two are not in the same coordinate space: `SetWindowPos` positions the window **frame**, which includes the DWM invisible resize border, while FancyZones fills a zone with the window's **visible** frame. Placing the frame at the zone rectangle therefore leaves the visible window inset by the border on every edge that has one - a thin strip of desktop down the left, right and bottom of a fullscreen window, which a manual `Win+Arrow` then corrects. Compensating here reproduces the snap path's result exactly: on a 3440x1440 work area, the fullscreen zone `(3, 3) 3434x1434` is placed at `(-4, 3) 3448x1441` for a standard 7px-border window, which is precisely where `Win+Up` puts a window snapped into that zone. Margins are measured once per placement rather than per attempt, since neither the window's style nor its monitor changes between retries, and a window with no border (console, borderless) measures zero and is placed at the zone rectangle unchanged. `Verified` therefore means the window matched the compensated target, and the small frame-vs-zone difference stays well inside `Confirm-WorkspaceWindowPositions`' tolerance - the same difference every keyboard-snapped window already reports.

A plainly positioned window is not registered in FancyZones' app-zone-history. That is harmless here: workspace verification is geometry-only, and later manual `Win+Arrow` moves still work because the required `fancyzones_moveWindowsBasedOnPosition` setting resolves zones from the window's position, not its history.

Called by `Set-WorkspaceWindowLayout`'s simple-layout path (the `Fullscreen` workspace), which places every window at its own monitor's fullscreen zone without any desktop switching - direct placement works on windows parked on invisible desktops. The workspace flow (`Snap-AllWindows`) snaps single-zone windows through `Invoke-SingleZoneWindowSnap` instead, so they end up registered with FancyZones.

| Parameter       | Type   | Default | Description                                                                    |
| --------------- | ------ | ------- | ------------------------------------------------------------------------------ |
| `-WindowHandle` | IntPtr | -       | Handle of the window to place. (Mandatory)                                     |
| `-TargetX`      | int    | -       | Zone left edge in physical pixels. (Mandatory)                                 |
| `-TargetY`      | int    | -       | Zone top edge in physical pixels. (Mandatory)                                  |
| `-TargetWidth`  | int    | -       | Zone width in physical pixels. (Mandatory)                                     |
| `-TargetHeight` | int    | -       | Zone height in physical pixels. (Mandatory)                                    |
| `-WindowTitle`  | string | `''`    | Window title used only for log messages.                                       |
| `-MaxAttempts`  | int    | `3`     | Maximum placement attempts before reporting failure (matches the snap path).   |

Returns a `PSCustomObject` with `Verified` (`$true` once the rect matched the frame-compensated target within tolerance), `Attempts`, and the last observed `X`/`Y`/`Width`/`Height` (`$null` when the rect was never readable).

```powershell
# Place a window into a monitor's single fullscreen zone and verify it landed
$zone = Get-FancyZone -LayoutName "Zero" -ZoneName "Fullscreen" -MonitorWidth 3440 -MonitorHeight 1440
$result = Invoke-SingleZoneWindowPlacement -WindowHandle $handle `
    -TargetX $zone.X -TargetY $zone.Y -TargetWidth $zone.Width -TargetHeight $zone.Height
if ($result.Verified) { "placed in $($result.Attempts) attempt(s)" }
```

**See also:** [Invoke-SingleZoneWindowSnap](window.md#invoke-singlezonewindowsnap), [Snap-AllWindows](window.md#snap-allwindows), [Add-PositionedWindow](window.md#add-positionedwindow), [Get-WindowFrameMargin](window.md#get-windowframemargin), [Set-WindowPosition](window.md#set-windowposition), [Wait-WindowRect](window.md#wait-windowrect)

## [Invoke-SingleZoneWindowSnap](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Invoke-SingleZoneWindowSnap.ps1)

- **Description:** Snaps a window into a single-zone FancyZones layout so it ends up **registered**, not just positioned. A direct `SetWindowPos` can reproduce a snap's geometry exactly, but FancyZones never learns about it: the window gets no zone assignment (`Get-FancyZonesWindowAssignment`), so relocation on zone-set and display changes skips it. This function drives FancyZones' own mechanisms instead, kept deliberately simple: a stale assignment - the routine `Reset-Windows` leftover, which would make the position-based `Win+Up` a no-op or a cross-monitor throw on a one-zone grid - is cleared first (`Clear-FancyZonesWindowAssignment`); the window is moved to the **middle of the zone at double the shared inset** (capped at 20% per side), so the position-based move has exactly one clearly-containing zone to resolve to; then `Win+Up` with verified foreground focus (the ~50-150ms fast path that assigns the window and writes its history entry), with shift-drag as the fallback - slower (~1s) but running FancyZones' real drag path, which registers just as well. An exhausted window is reported unverified for the caller's retry, exactly like the multi-zone path.
- **Parameters:** -WindowHandle, -TargetX, -TargetY, -TargetWidth, -TargetHeight, -WindowTitle, -MaxAttempts, -InsetPercent
- **Usage:** `Invoke-SingleZoneWindowSnap -WindowHandle $handle -TargetX 3 -TargetY 3 -TargetWidth 3434 -TargetHeight 1434`

Verification compares the DWM frame-compensated rectangle (`Get-WindowFrameMargin`) - the frame rect a successful FancyZones snap actually produces - rather than the zone rect plus tolerance, and registration is re-read after a verified snap and surfaced on the result, so "snapped" can no longer silently mean "merely positioned". The window's virtual desktop must be the **active** one and the window focusable: keyboard and drag snaps act on the visible desktop. Callers that place windows on invisible desktops (`Set-WorkspaceWindowLayout`'s simple-layout path) keep using `Invoke-SingleZoneWindowPlacement`, which trades registration for that ability.

One limitation is FancyZones' own and no snap method avoids it: **`app-zone-history.json` has no per-window identity.** The durable store FancyZones re-reads when it rebuilds a work area on a desktop switch is keyed by **app path** plus monitor plus virtual desktop and holds one zone entry per key, and every virtual-desktop sync re-stamps the whole file onto the desktop that is current at that moment - so a workspace open, which creates and destroys desktops, keeps moving which single desktop owns a given application's row. For a process with windows on several desktops (Firefox) at most one of those desktops keeps the row; the rebuild re-seeds its window-to-zone map by app path, and a miss leaves the window untracked, so FancyZones' relocation on a later zone-set or display change moves nothing on that desktop. A single-window process (VS Code) is uncontested and behaves. The assignment marker and the live tracking are correct either way, so `Win+Arrow` and the current session's layout behavior are unaffected, and a manual `Win+Arrow` once the desktops have settled rewrites the row for that desktop. See [Troubleshooting](../reference/troubleshooting.md#changing-the-fancyzones-layout-re-tiles-some-desktops-but-not-others) for how to recognise it in FancyZones' own log.

| Parameter       | Type   | Default                      | Description                                                                          |
| --------------- | ------ | ---------------------------- | ------------------------------------------------------------------------------------ |
| `-WindowHandle` | IntPtr | -                            | Handle of the window to snap. (Mandatory)                                            |
| `-TargetX`      | int    | -                            | Zone left edge in physical pixels. (Mandatory)                                       |
| `-TargetY`      | int    | -                            | Zone top edge in physical pixels. (Mandatory)                                        |
| `-TargetWidth`  | int    | -                            | Zone width in physical pixels. (Mandatory)                                           |
| `-TargetHeight` | int    | -                            | Zone height in physical pixels. (Mandatory)                                          |
| `-WindowTitle`  | string | `''`                         | Window title used only for log messages.                                             |
| `-MaxAttempts`  | int    | `3`                          | Keyboard-plus-drag attempts before reporting failure (matches the multi-zone path).  |
| `-InsetPercent` | double | `Get-WindowInsetPercent`     | Inset used when re-positioning the window between attempts (the snap-steering inset). |

Returns a `PSCustomObject` with `Verified` (rect matched the frame-compensated zone rectangle), `Registered` (window carries FancyZones' zone assignment afterwards), `Method` (`KeyboardSnap` \| `ShiftDrag` \| `None`), `Attempts`, and the last observed `X`/`Y`/`Width`/`Height`.

```powershell
# Snap a window into a monitor's single fullscreen zone and prove it is registered
$zone = Get-FancyZone -LayoutName "Zero" -ZoneName "Fullscreen" -MonitorWidth 3440 -MonitorHeight 1440
$result = Invoke-SingleZoneWindowSnap -WindowHandle $handle `
    -TargetX $zone.X -TargetY $zone.Y -TargetWidth $zone.Width -TargetHeight $zone.Height
if ($result.Verified -and $result.Registered) { "snapped for real via $($result.Method)" }
```

**See also:** [Snap-AllWindows](window.md#snap-allwindows), [Invoke-SingleZoneWindowPlacement](window.md#invoke-singlezonewindowplacement), [Get-FancyZonesWindowAssignment](window.md#get-fancyzoneswindowassignment), [Clear-FancyZonesWindowAssignment](window.md#clear-fancyzoneswindowassignment), [Get-WindowFrameMargin](window.md#get-windowframemargin), [Wait-WindowRect](window.md#wait-windowrect)

## [Move-Windows](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Move-Windows.ps1)

- **Description:** Enumerates all visible application windows and moves each one to a specified virtual desktop (1-based; desktop 1 is the first). If the target desktop does not exist it is created automatically, and after the move pass focus is switched to the destination desktop. Use `-Current` to target the calling terminal's own desktop without knowing its number. Optional `-Monitor` repositions windows onto a target physical monitor in the same pass (resolved by `Resolve-TargetMonitor`), preserving each window's relative placement from its source monitor work area and clamping to the destination work area for safe multi-resolution placement. Each monitor placement is verified with `Wait-WindowRect` and re-applied once if the window did not hold its position, because `SetWindowPos` reports success for the call even when an external window manager moves the window straight back. Filtering by `-ProcessName` and/or `-WindowTitle` supports exact, wildcard, and regex matching (delegated to `Get-WindowHandle`); when both are given, windows matching either criterion are moved (OR logic). Windows already on the target desktop are skipped unless monitor repositioning is requested. Windows that could not be moved, or that would not stay on the target monitor, are reported in normal mode as well as under verbose logging. After the per-window pass, a verification sweep re-checks every window counted as on the target desktop (via `Get-WindowDesktopIndex`) and retries stragglers once: a stale already-on-desktop read taken while a desktop collapse was still settling, or the upstream `Move-Window` moving a sibling window of the same multi-window process (its fallback when the requested view cannot be moved), leaves a window elsewhere while the counters say otherwise. A window the sweep cannot recover is reclassified as a failure so the summary reports it.
- **Parameters:** -VirtualDesktop, -Current, -ProcessName, -WindowTitle, -Monitor
- **Usage:** `Move-Windows`, `Move-Windows -VirtualDesktop 2`, `Move-Windows -Current`, `Move-Windows -Current -ProcessName "chrome"`, `Move-Windows -WindowTitle "*YouTube*"`, `Move-Windows -ProcessName "chrome" -WindowTitle "*GitHub*"`, `Move-Windows -Current -Monitor Secondary`, `Move-Windows -VirtualDesktop 2 -Monitor 1`

Moves every visible window to a target virtual desktop and, optionally, a target physical monitor. The `-VirtualDesktop` and `-Current` parameters are mutually exclusive (separate parameter sets). Missing desktops are created on demand via `Ensure-VirtualDesktops`. Monitor targeting accepts a 1-based index (`1`, `2`), standardized labels (`Primary`, `Secondary`, `Monitor3`, ...), or an exact device name (for example `\\.\DISPLAY1`). System and shell windows (Program Manager, Start, Search, overlays, zero-size windows, etc.) are excluded. Under `Set-LogLevel Verbose`, a per-window trace plus a summary of moved, already-there, skipped, enumerated, eligible, and exclusion (skip-title / invalid-size) counts is printed. VirtualDesktop calls are wrapped with optional exponential-backoff retries (`Invoke-WithRetry`) to absorb transient RPC failures such as `0x800706BA`.

Note that a numeric `-Monitor` index is POSITIONAL: it follows `Get-MonitorInfo` / `Screen.AllScreens` enumeration order, which is not guaranteed to match the numbering in Windows display settings and can change when displays are re-enumerated. Prefer a label or device name when the target must survive a display reconfiguration.

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

**See also:** [Reset-Windows](window.md#reset-windows), [Move-WindowToVirtualDesktop](window.md#move-windowtovirtualdesktop), [Resolve-TargetMonitor](window.md#resolve-targetmonitor), [Wait-WindowRect](window.md#wait-windowrect)

## [Move-WindowToVirtualDesktop](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Move-WindowToVirtualDesktop.ps1)

- **Description:** Moves a window (identified by its handle) to the specified virtual desktop number. Requires the VirtualDesktop module or falls back to COM automation. Uses 0-based desktop indexing internally; layout files use 1-based indexing, which is converted before this function is called.
- **Parameters:** -WindowHandle, -DesktopNumber
- **Usage:** `Move-WindowToVirtualDesktop -WindowHandle $handle -DesktopNumber 0`, `Move-WindowToVirtualDesktop -WindowHandle $handle -DesktopNumber 1`

A window already on the target desktop returns `$true` immediately (no COM move, no settle delay) - the common case, since workspace windows are desktop-moved from more than one code path. Otherwise it validates the target index against the available desktop count, resolves the destination desktop by its 0-based index, and moves the window there. After a real move the result is verified immediately and then polled briefly (10ms steps, ~100ms budget) instead of a fixed sleep, tolerating the transient `TYPE_E_ELEMENTNOTFOUND` error that the underlying COM interfaces often raise even on success. The script-scoped `$script:LastMoveWindowToVirtualDesktopResult.Moved` reports whether a real move happened, so callers can skip their own settle delays on the fast path. Returns `$true` on confirmed success and `$false` on failure or an out-of-range index - always exactly one boolean: the upstream `Move-Window` cmdlet returns the Desktop object, which is discarded rather than leaked into the output, where it made every failed move truthy to callers (a two-element array is `$true` regardless of contents). If the VirtualDesktop module is missing it warns with install instructions and returns `$false`.

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

- **Description:** Releases modifier keys (Shift, Ctrl, Alt, Win - left, right, and neutral variants) that the session reports as logically held down, by injecting the matching key-up events in a single `SendInput` batch. This clears the state an interrupted synthesized-input sequence leaves behind - the "terminal input locks up during workspace orchestration" known issue, where typed letters come out as caps and Enter stops submitting - without signing out. Keys that are not held are never touched, toggle keys (Caps Lock, Num Lock) are never sent, and on a quiescent keyboard the call is a read-only no-op. Called automatically by `Snap-AllWindows` (at pass start, before each snap retry, and on pass failure), by `Set-WorkspaceWindowLayout` and `Rerun-LastCommand` before a rerun respawns the shell, by `Rerun-LastCommand` again as its last act before the process exits (`[Environment]::Exit` skips every `finally`, so nothing later could release what the tab-close passes stranded), and by `Open-Workspace` when the flow ends.
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

## [Reset-Windows](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Reset-Windows.ps1)

- **Description:** Convenience wrapper that resets the window layout to a clean slate for layout testing. Runs four steps in order: `Remove-VirtualDesktops` (collapse down to a single virtual desktop), `Move-Windows` (move every window to the target virtual desktop and, optionally, a target monitor), `Center-Windows` (center every window on the configured monitor, or on its current monitor when none is configured), and finally `Focus-TerminalTab` (focuses Windows Terminal to continue working). The configured monitor is passed on to `Center-Windows` so the last pass re-asserts the intended target rather than re-deriving one per window, which makes the reset self-correcting when something moves a window mid-run. A `Remove-VirtualDesktops` failure is surfaced as a warning instead of being ignored. Defaults for `-VirtualDesktop` and `-Monitor` are read per machine from configuration, keyed by the machine type `Get-LayoutMachineType` resolves - the same one the window layouts are read under, so a `LayoutMachineTypeOverrides` entry (or a small primary display) selects the matching reset profile too.
- **Parameters:** -VirtualDesktop (default: per-machine config), -Monitor (default: per-machine config)
- **Usage:** `Reset-Windows`, `Reset-Windows -VirtualDesktop 2 -Monitor Primary`, `Reset-Windows -Monitor ""`

Reproduces the manual reset sequence in one call. Per-machine defaults are read from `$global:Configuration.ResetAllWindowsDefaults`, keyed by the machine type `Get-LayoutMachineType` resolves (PC, Laptop, Work, Test, or a redirected layout set), falling back to a `Default` entry and then to virtual desktop 1 with no monitor targeting. Sharing that resolution with the layouts is what keeps a machine on a borrowed monitor setup from consolidating windows onto a monitor it no longer has: "move everything to monitor 2" is a statement about a monitor setup, so it has to follow the same switch the layouts do. On the PC, windows are consolidated onto monitor 2; on the laptop and work machines no monitor targeting is applied. Explicitly passing `-VirtualDesktop` or `-Monitor` overrides the configured default for that run.

This replaces the manual sequences:

```powershell
# PC
Remove-VirtualDesktops; Move-Windows -Monitor 2 -VirtualDesktop 1; Center-Windows -Monitor 2

# Laptop / Work
Remove-VirtualDesktops; Move-Windows -VirtualDesktop 1; Center-Windows
```

Collapsing the virtual desktops makes Windows migrate the windows off the removed desktops, and FancyZones reacts to those arrivals by restoring each window to its remembered zone - which can be on a different monitor. Passing the configured monitor to `Center-Windows` (the last pass) is what corrects that: without it, `Center-Windows` derives each window's monitor from its current position and centers strays where they landed. See [Windows Land On The Wrong Monitor After Reset-Windows](../reference/troubleshooting.md) in troubleshooting.

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

## [Resize-PositionedWindows](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Resize-PositionedWindows.ps1)

- **Description:** Reapplies the shared pre-snap inset resize bounds to every tracked positioned window before FancyZones snapping. Uses the same `Resize-Windows` target-bounds path as `Set-WindowLayouts` and `Snap-AllWindows`, so every pre-snap resize comes from one source of truth and the first snap attempt always starts from the same geometry used during initial positioning and snap retries.
- **Parameters:** -InsetPercent, -Tolerance
- **Usage:** `Resize-PositionedWindows`, `Resize-PositionedWindows -Tolerance 0`

Called by `Set-WorkspaceWindowLayout` after the initial positioning pass and immediately before `Snap-AllWindows`. For each tracked window it invokes `Resize-Windows` in target-bounds mode with that window's expected zone bounds, skipping windows already at the adjusted pre-snap position (within `Tolerance`). Returns a result object with `ResizedCount`, `SkippedCount`, and `FailedWindows`.

| Parameter       | Description                                                                                                                                                                                                            |
| --------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-InsetPercent` | Inset percentage applied on each side. Defaults to `Get-WindowInsetPercent` (`SnapInsetPercent`, `0.05` when unset), constrained to the range `0.0`-`0.49`.                                                            |
| `-Tolerance`    | Pixel tolerance for deciding whether a window is already at the adjusted pre-snap position. Defaults to the module's shared position verification tolerance (`$script:WindowModuleTolerances.PositionVerificationPx`). |

```powershell
# Reapply the shared pre-snap inset to all tracked windows
Resize-PositionedWindows

# Verbose diagnostic output
Set-LogLevel Verbose { Resize-PositionedWindows -Tolerance 0 }
```

**See also:** [Window module](window.md)

## [Resize-Windows](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Resize-Windows.ps1)

- **Description:** Resizes open windows either by a percentage (scaling each window's width and height while keeping its center point fixed) or to inset bounds within a target zone. In percentage mode a value of 100 leaves windows unchanged, below 100 shrinks them, and above 100 enlarges them, with results clamped to the monitor work area. When `TargetX`/`TargetY`/`TargetWidth`/`TargetHeight` are supplied it switches to target-bounds mode, using the shared FancyZones pre-snap inset sizing logic (an `-InsetPercent` of 0 places the window at the exact bounds, which is how `Center-Windows` reuses this path). Like `Move-Windows`, it can target all visible windows, a filtered set matching a `-ProcessName` and/or `-WindowTitle` pattern (delegated to `Get-WindowHandle`), or a single window by handle.
- **Parameters:** -Percent (default: ResizeWindowsPercent, else 70), -ProcessName, -WindowTitle, -WindowHandle, -TargetX, -TargetY, -TargetWidth, -TargetHeight, -InsetPercent (default: SnapInsetPercent, else 0.05), -Tolerance, -SkipIfAlreadyPositioned
- **Usage:** `Resize-Windows`, `Resize-Windows -Percent 120`, `Resize-Windows -Percent 50 -ProcessName "chrome"`, `Resize-Windows -WindowTitle "*YouTube*" -Percent 120`, `Resize-Windows -WindowHandle $handle`, `Resize-Windows -WindowHandle $handle -TargetX 0 -TargetY 0 -TargetWidth 1720 -TargetHeight 1440 -SkipIfAlreadyPositioned`

Operates in two modes. **Percentage mode** is the general utility path: it selects windows (all via `Get-CachedWindows`, a filtered set via `Get-WindowHandle`, or a single `-WindowHandle`), scales each window's current dimensions by `Percent`, and re-centers them on their original center point, clamping size and position to the owning monitor's work area (minimum 100px) so nothing extends off-screen. **Target-bounds mode** activates when all four `Target*` parameters are provided; it delegates to `Get-InsetWindowBounds` to compute the shared inset geometry and is the single source of truth for the pre-snap resize used by `Set-WindowLayouts`, `Resize-PositionedWindows`, `Snap-AllWindows` retries, and `Center-Windows`. System/shell windows (Program Manager, Start, Search, etc.) and zero-size windows are skipped. `-ProcessName`/`-WindowTitle` matching is delegated to `Get-WindowHandle` (exact names, wildcard patterns, and regex, with OR logic when both are supplied). Single-handle mode is served from the window cache without forcing a refresh per call (the cache's own 50ms TTL keeps the data fresh enough for the skip-tolerance check) - it runs once per window in tight loops like `Resize-PositionedWindows` and snap retries. Only the user-facing resize-all/matching invocation prints a title and summary in percent mode; single-handle calls no longer print a success line per window (verbose mode still logs each).

| Parameter                        | Description                                                                                                                                             |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-Percent`                       | Percentage to scale each window's current size by. Defaults to `Resolve-ResizeWindowsPercent` (`ResizeWindowsPercent`, `70` when unset). Range 10-500. 100 is a no-op. |
| `-ProcessName`                   | Only resize windows whose process matches this pattern (without `.exe`). Exact name, wildcard (`*`, `?`), or regex. Omit to resize all visible windows. |
| `-WindowTitle`                   | Only resize windows whose title matches this pattern. Wildcard (`*`, `?`) or regex. Combine with `-ProcessName` (OR logic).                             |
| `-WindowHandle`                  | Only resize the window with this exact handle.                                                                                                          |
| `-TargetX` / `-TargetY`          | Target zone top-left coordinates for target-bounds mode.                                                                                                |
| `-TargetWidth` / `-TargetHeight` | Target zone size for target-bounds mode.                                                                                                                |
| `-InsetPercent`                  | Inset applied per side in target-bounds mode. Defaults to `Get-WindowInsetPercent` (`SnapInsetPercent`, `0.05` when unset). Range 0.0-0.49.             |
| `-Tolerance`                     | Pixel tolerance used with `-SkipIfAlreadyPositioned`. Defaults to the module's shared position verification tolerance.                                  |
| `-SkipIfAlreadyPositioned`       | In target-bounds mode, skips windows already at the adjusted target bounds within `Tolerance`.                                                          |

Neither default is a constant. **The percentage** is resolved in the `begin` block by `Resolve-ResizeWindowsPercent`, but only in percentage mode and only when the caller passed no `-Percent` - so target-bounds callers never pay for the monitor query, and the `"to <n>%"` log reports the value actually applied. This is what makes the workspace flow behave the same everywhere: `Set-WorkspaceWindowLayout`'s first-open normalization and its retry passes all call `Resize-Windows` with no percentage, and a single hardcoded `70` had to be a compromise between a mild shrink on a wide monitor and an aggressive one on a laptop panel. **The inset** is a parameter default reading `Get-WindowInsetPercent`, so `Center-Windows`' deliberate `-InsetPercent 0` still overrides it (a bound parameter never evaluates its default expression). Both fall back to their historical values (`70`, `0.05`) when nothing is configured, and an invalid configured value falls back rather than throwing mid-loop.

```powershell
# Shrink all windows to the configured default (70% unless ResizeWindowsPercent says otherwise)
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

**See also:** [Window Layout System](../modules/window.md), [Resolve-ResizeWindowsPercent](window.md#resolve-resizewindowspercent), [Get-WindowInsetPercent](window.md#get-windowinsetpercent), [Display-Aware Window Sizing](../configuration/configuration-reference.md#display-aware-window-sizing)

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

## [Resolve-CenterTerminalSizing](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Resolve-CenterTerminalSizing.ps1)

- **Description:** Resolves the `CenterTerminalSizing` block that applies to the current display. The section accepts two shapes: the **legacy flat** shape holds `TargetWidthPx` and friends directly and is returned as-is, while the **keyed** shape holds `SmallDisplay` / machine type / `Default` rows resolved through `Resolve-DisplayAwareProfile`. Only a hashtable row carrying `TargetWidthPx` is accepted; anything else resolves to `$null` so `Center-Terminal` falls back to its own 40% x 50% defaults rather than handing junk to `Resolve-CenteredWindowPercent`, whose parameters are all mandatory ints.
- **Parameters:** -Section, -MonitorInfo
- **Usage:** `Resolve-CenterTerminalSizing -Section $global:Configuration.CenterTerminalSizing -MonitorInfo $monitors`

The flat check runs first and wins outright. That is what makes the hybrid case correct: `Configuration.local.psd1` deep-merges over the base, so a user who keeps the old flat override on top of a keyed base ends up with `TargetWidthPx` and rows in the same hashtable - and the flat keys are the ones they actually edited.

The keyed shape exists to *tune* the target per machine, not to make the terminal size uniform. Uniformity already comes from `Center-Terminal` converting one pixel target into per-monitor percentages at run time; the rows are for when a particular display wants a different physical size.

| Parameter      | Type      | Default | Description                                                                                                          |
| -------------- | --------- | ------- | -------------------------------------------------------------------------------------------------------------------- |
| `-Section`     | hashtable | -       | The `CenterTerminalSizing` section, in either shape. Null or empty resolves to `$null`.                              |
| `-MonitorInfo` | object[]  | -       | Monitor records from `Get-MonitorInfo`, forwarded to the row resolver so the caller's snapshot is reused.            |

```powershell
# The Default row's block on the ultrawide, the SmallDisplay row's block on a laptop panel
Resolve-CenterTerminalSizing -Section $global:Configuration.CenterTerminalSizing -MonitorInfo $monitors

# Legacy flat section, returned unchanged
Resolve-CenterTerminalSizing -Section @{ TargetWidthPx = 1376; TargetHeightPx = 700 }
```

**See also:** [Center-Terminal](window.md#center-terminal), [Resolve-DisplayAwareProfile](window.md#resolve-displayawareprofile), [Display-Aware Window Sizing](../configuration/configuration-reference.md#display-aware-window-sizing)

## [Resolve-DisplayAwareProfile](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Resolve-DisplayAwareProfile.ps1)

- **Description:** The shared row resolver for configuration sections whose value depends on the display the windows will land on (`CenterTerminalSizing`, `ResizeWindowsPercent`). Returns the value of the row that applies, in order: `SmallDisplay` when present **and** `Test-SmallPrimaryDisplay` reports a laptop-class primary display, else the row named after the machine type `Get-LayoutMachineType` resolves, else `Default`, else `$null` for the caller's own built-in fallback.
- **Parameters:** -Section, -MonitorInfo
- **Usage:** `Resolve-DisplayAwareProfile -Section $global:Configuration.ResizeWindowsPercent`, `Resolve-DisplayAwareProfile -Section $sizing -MonitorInfo $monitors`

`SmallDisplay` is checked **first** because the machine type cannot express it. A laptop reports the machine type `Laptop` both on its own panel and docked to a large external monitor, so a `Laptop` row alone can only be right in one of those two states. The `SmallDisplay` row is the state-dependent one: it wins while the small panel is primary and disappears the moment a big display takes over, at which point the ordinary type row (or `Default`) applies. A machine that never uses a laptop-class display simply omits the row and pays nothing - monitors are only measured when the row exists.

Note the asymmetry with `Get-LayoutMachineType`, which deliberately checks its manual override **before** its display-size rule. There the override is an explicit human choice that a display-width guess must not overrule. Here there is no competing explicit choice: both candidate rows are configuration, and the more specific one - the one naming the actual display class - wins.

Because the machine type comes from `Get-LayoutMachineType`, `LayoutMachineTypeOverrides` and `SmallDisplayMachineType` steer these sections exactly as they steer the layout files and the `Reset-Windows` defaults.

| Parameter      | Type      | Default | Description                                                                                                                                          |
| -------------- | --------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `-Section`     | hashtable | -       | Section to resolve: rows keyed by machine type, plus the optional `SmallDisplay` and `Default` rows. Null or empty resolves to `$null`.              |
| `-MonitorInfo` | object[]  | -       | Monitor records from `Get-MonitorInfo`, forwarded to both helpers. Passed on only when bound, so an unbound call leaves each free to skip the query. |

```powershell
# 80 from the SmallDisplay row on the laptop panel; 70 from Default once docked
Resolve-DisplayAwareProfile -Section $global:Configuration.ResizeWindowsPercent
```

**See also:** [Test-SmallPrimaryDisplay](window.md#test-smallprimarydisplay), [Get-LayoutMachineType](window.md#get-layoutmachinetype), [Display-Aware Window Sizing](../configuration/configuration-reference.md#display-aware-window-sizing)

## [Resolve-LayoutTokens](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Resolve-LayoutTokens.ps1)

- **Description:** Expands layout-file tokens to regex patterns at the matching boundary. Layout entries may use the literal token `"Browser"` as a value for `ProcessName` and/or `WindowTitle`; this helper returns a shallow clone of the entry with those tokens expanded to a regex covering every browser declared in `Configuration.Universal.Browsers` - the same map `Open-Browser` reads - with a legacy top-level `Configuration.Browsers` map honoured as a fallback (Tor excluded - SecureBrowser layouts opt into `tor` explicitly). Other values, including literal alternation regex like `(firefox|chrome|msedge|brave)`, are returned unchanged. Tokens are matched case-sensitively and expanded patterns are cached at module scope so it stays cheap inside the per-entry Set-WindowLayouts / Confirm-WorkspaceWindowPositions loops. The original entry is never mutated, so Visualize-Layouts still renders the raw `Browser` cell.
- **Parameters:** -LayoutEntry
- **Usage:** `Resolve-LayoutTokens -LayoutEntry @{ ProcessName = "Browser"; Zone = "Left" }`, `Resolve-LayoutTokens -LayoutEntry @{ ProcessName = "firefox" }`

Layout files (under `Windows/PowerShell/Modules/Window/Layouts/**`) can stay browser-agnostic by using the literal token `Browser` instead of a specific browser name. At match time the token is expanded to a regex covering every browser declared under `Configuration.Universal.Browsers`, so the same layout works whether Firefox, Chrome, Edge, or Brave is the active default - and a browser a fork adds to that map joins the token automatically. A top-level `Configuration.Browsers` map is honoured as a legacy fallback (it was the only location an earlier version of this function read). The process side expands to the exe basenames (e.g. `(firefox|chrome|msedge|brave)`) and the title side to an escaped, case-insensitive alternation of the friendly browser names. When `Configuration` is not loaded (e.g. isolated Pester tests), a built-in fallback set is used. Returns a `[hashtable]` shallow clone of the input with the token fields expanded.

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

## [Resolve-MonitorLabel](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Resolve-MonitorLabel.ps1)

- **Description:** Converts between a monitor's 0-based ordinal and its standardized label, in either direction. Single source of truth for the `Primary` / `Secondary` / `Monitor3` / `Monitor4` / ... scheme that `Get-MonitorSpecs` emits and that layout files, `Apply-FancyZones` and `Resolve-TargetMonitor` all key on. With `-Index` it returns the label; with `-Label` it returns the ordinal, which doubles as the sort key that orders monitors `Primary`, `Secondary`, `Monitor3`, ... Unrecognized labels return `[int]::MaxValue` so they sort last instead of tying with each other.
- **Parameters:** -Index, -Label
- **Usage:** `Resolve-MonitorLabel -Index 2`, `Resolve-MonitorLabel -Label "Monitor3"`, `$entries | Sort-Object { Resolve-MonitorLabel -Label $_.Monitor }`

| Parameter | Description                                                                                                                                    |
| --------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `-Index`  | 0-based monitor ordinal to convert into a label. Must be 0 or greater; a negative ordinal is an error rather than an invented label.            |
| `-Label`  | Monitor label to convert into its ordinal. Matched case-insensitively and trimmed. Empty, whitespace-only and unrecognized labels give `[int]::MaxValue`. |

Ordinal 0 is `Primary`, ordinal 1 is `Secondary`, and every ordinal past that is `Monitor<Index + 1>` - so ordinal 2 is `Monitor3`. `Monitor1` and `Monitor2` resolve back to ordinals 0 and 1, the same slots as `Primary` and `Secondary`, so a hand-written layout file using them still sorts sensibly; `Get-MonitorSpecs` never emits those two forms itself.

Both directions live in one place because the ordering used to be duplicated as a three-way `Primary`=0 / `Secondary`=1 / everything-else=2 mapping in `Update-LayoutSectionHeaders` and `Visualize-Layouts`. Under that mapping `Monitor3`, `Monitor4` and `Monitor5` all tied at 2 and fell back to input order, which made generated section headers and ASCII visualizations look randomly ordered past `Secondary`.

The scheme is **positional, not a hardware identity** - see `Get-MonitorSpecs` for how the ordinals are assigned.

```powershell
Resolve-MonitorLabel -Index 0        # -> Primary
Resolve-MonitorLabel -Index 1        # -> Secondary
Resolve-MonitorLabel -Index 2        # -> Monitor3

Resolve-MonitorLabel -Label "Monitor3"   # -> 2
Resolve-MonitorLabel -Label "Bogus"      # -> [int]::MaxValue (sorts last)
```

**See also:** [Get-MonitorSpecs](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Get-MonitorSpecs.ps1), [Resolve-TargetMonitor](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Resolve-TargetMonitor.ps1)

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

## [Resolve-ResizeWindowsPercent](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Resolve-ResizeWindowsPercent.ps1)

- **Description:** Resolves the percentage `Resize-Windows` shrinks windows by when no `-Percent` is given. Reads `ResizeWindowsPercent` from `Configuration.psd1` through `Resolve-DisplayAwareProfile`, so the default follows the display in use: the `SmallDisplay` row while a laptop-class panel is primary, otherwise the machine type's row, otherwise `Default`. Anything non-numeric or outside the 10-500 range `Resize-Windows`' own `ValidateRange` accepts falls back to the built-in `70`.
- **Parameters:** -MonitorInfo
- **Usage:** `Resolve-ResizeWindowsPercent`, `Resolve-ResizeWindowsPercent -MonitorInfo $monitors`

This is what makes the workspace flow behave the same everywhere. `Resize-Windows`' percent mode is the first-open normalization and retry step of `Set-WorkspaceWindowLayout`, and those call sites pass no `-Percent` at all. A single hardcoded `70` has to be a compromise: a mild shrink on a wide monitor, an aggressive one on a laptop panel where the window has far less room to give up.

Invalid configuration never throws - a typo in a config file must not abort a workspace open mid-loop.

| Parameter      | Type     | Default | Description                                                                                                    |
| -------------- | -------- | ------- | ---------------------------------------------------------------------------------------------------------------- |
| `-MonitorInfo` | object[] | -       | Monitor records from `Get-MonitorInfo`, forwarded to the row resolver so a caller with a snapshot reuses it.   |

```powershell
# 80 on the laptop panel (SmallDisplay row), 70 docked or on the PC (Default row)
Resolve-ResizeWindowsPercent
```

**See also:** [Resize-Windows](window.md#resize-windows), [Resolve-DisplayAwareProfile](window.md#resolve-displayawareprofile), [Display-Aware Window Sizing](../configuration/configuration-reference.md#display-aware-window-sizing)

## [Resolve-TargetMonitor](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Resolve-TargetMonitor.ps1)

- **Description:** Resolves a monitor specifier to a monitor object for the placement functions. Accepts a 1-based index following `Get-MonitorInfo` order (`1`, `2`), a standardized label from `Get-MonitorSpecs` (`Primary`, `Secondary`, `Monitor3`, ...), or an exact device name (`\\.\DISPLAY1`). Shared by `Move-Windows` and `Center-Windows` so both resolve `-Monitor` through one set of rules. Writes no console output: it returns the resolved monitor together with a ready-to-log `ErrorMessage`, leaving logging and control flow (abort, return, or fall back) to the caller. An empty or whitespace-only specifier resolves to "no targeting requested" rather than an error.
- **Parameters:** -Monitor, -MonitorInfo
- **Usage:** `Resolve-TargetMonitor -Monitor "2" -MonitorInfo $monitors`, `Resolve-TargetMonitor -Monitor "Primary"`

| Parameter       | Type     | Default | Description                                                                                                     |
| --------------- | -------- | ------- | --------------------------------------------------------------------------------------------------------------- |
| `-Monitor`      | string   | -       | Monitor specifier: 1-based index, label, or device name. Empty/whitespace means no targeting requested.          |
| `-MonitorInfo`  | object[] | -       | Monitor objects from `Get-MonitorInfo`. Omit to enumerate on demand; pass a set to avoid a second enumeration.   |

Returns a `PSCustomObject` with:

| Member         | Description                                                                       |
| -------------- | --------------------------------------------------------------------------------- |
| `Monitor`      | The resolved monitor object, or `$null` when unresolved or not requested.          |
| `Label`        | Standardized label of the resolved monitor (`Primary`, `Secondary`, `Monitor3`, ...), or its device name when no label matches. |
| `ErrorMessage` | Why resolution failed, or `$null` on success / no request.                         |
| `Requested`    | `$true` when a non-empty specifier was supplied.                                   |

Whichever form resolves, `Label` is always the standardized label of the monitor that was **resolved** - not a restatement of the input - so a log line naming it agrees with what a layout file would call that panel. Reporting the input instead meant `-Monitor 3` logged `Monitor3` even when the third *enumerated* display is not the panel the label `Monitor3` refers to; the two orderings are unrelated.

The three forms are not equally stable, and the difference matters most with three or more displays:

| Form                              | Follows                                     | Survives                                                                 |
| --------------------------------- | ------------------------------------------- | ------------------------------------------------------------------------ |
| Index (`1`, `2`)                  | `Screen.AllScreens` **enumeration** order    | Least stable - can change on sleep/wake, DisplayPort drop, driver reload, dock/undock. Avoid in configuration. |
| Label (`Primary`, `Monitor3`)     | **Physical** arrangement (`Get-MonitorSpecs`) | A re-enumeration, but *not* an actual rearrangement of the displays.      |
| Device name (`\\.\DISPLAY1`)      | The device itself                            | Closest to a fixed identity. Prefer it when the target must survive a display reconfiguration. |

```powershell
# Resolve and act on the caller's own terms
$resolved = Resolve-TargetMonitor -Monitor "2" -MonitorInfo $monitors
if (-not $resolved.Monitor) {
    Write-LogError $resolved.ErrorMessage
    return
}
"Targeting $($resolved.Label) ($($resolved.Monitor.DeviceName))"

# Empty specifier means "no monitor targeting", not a failure
(Resolve-TargetMonitor -Monitor "").Requested   # => False
```

**See also:** [Move-Windows](window.md#move-windows), [Center-Windows](window.md#center-windows), [Get-MonitorSpecs](window.md#get-monitorspecs)

## [Save-CurrentLayout](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Save-CurrentLayout.ps1)

- **Description:** Writes the most recently applied workspace layout to `Window\Layouts\CurrentLayout.txt` (read back by `Get-CurrentLayout`). Called by `Set-WorkspaceWindowLayout` after a workspace has been applied and verified. Records, per open workspace, the virtual desktop count, the FancyZones layout applied to each monitor on each desktop, and one record per positioned+snapped window with its handle, process fingerprint, title, layout-relative desktop, monitor, and zone - i.e. exactly where each window belongs. Window records come from the positioned-window tracking (`$script:PositionedWindowHandles`) joined with each entry's Monitor/Zone/Layout. A normal open replaces the whole file (normal mode resets the desktops, so only this workspace is on screen); an `-Alongside` open instead merges, updating only this workspace's section and preserving the workspaces already running - and `-PreserveOtherSections` extends the same merge to a plain open that is preserving live alongside workspaces (see [Get-WorkspaceOpenProtection](workflow.md#get-workspaceopenprotection)), whose sections carry the zone pinning their next reopen depends on. Desktop numbers are stored layout-relative (offset-stripped) so the snapshot is reusable regardless of where the workspace is later reopened. Writing is best-effort: any I/O error is logged and swallowed so it can never fail an already-successful layout.
- **Parameters:** -Workspace, -LayoutsDir, -MachineType, -DesktopOffset, -Alongside, -DesktopCount, -LayoutConfig, -MonitorConfig, -WindowStates, -PreserveOtherSections
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
| `-PreserveOtherSections` | switch | No | Merge with the existing snapshot instead of replacing it, exactly as an `-Alongside` save does. Passed by a plain `Set-WorkspaceWindowLayout` run that is preserving live alongside workspaces. |

**See also:** [Get-CurrentLayout](window.md), [Set-WorkspaceWindowLayout](window.md), [Add-PositionedWindow](window.md)

## [Send-FancyZonesLayoutShortcut](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Send-FancyZonesLayoutShortcut.ps1)

- **Description:** Sends the FancyZones quick-layout shortcut `Win+Ctrl+Alt+[Number]` for the monitor at a given rectangle, on the active virtual desktop: moves the cursor to the monitor's center (FancyZones targets the monitor under the cursor), gives the desktop window the foreground so no application swallows the chord, and injects the keys through the batched `SendInput` helper in `WindowNative.cs`, with the `CursorSettleMs`, `FocusSettleMs` and `KeyboardShortcutMs` delays from `Get-WindowModuleDelays` between the steps. `Apply-FancyZones` uses it for every monitor/desktop pair of its shortcut pass and for the single probe shortcut that confirms FancyZones reloaded `applied-layouts.json`. It sends real input and must never be called from a test.
- **Parameters:** -LayoutNumber, -MonitorX, -MonitorY, -MonitorWidth, -MonitorHeight
- **Usage:** `Send-FancyZonesLayoutShortcut -LayoutNumber 5 -MonitorX 0 -MonitorY 0 -MonitorWidth 3440 -MonitorHeight 1440`

| Parameter        | Type | Description                                                        |
| ---------------- | ---- | ------------------------------------------------------------------ |
| `-LayoutNumber`  | int  | Hotkey slot 0-9 (`Configuration.LayoutNumbers` maps names to it). |
| `-MonitorX`      | int  | Left edge of the monitor in virtual-screen pixels.                 |
| `-MonitorY`      | int  | Top edge of the monitor in virtual-screen pixels.                  |
| `-MonitorWidth`  | int  | Width of the monitor in pixels.                                    |
| `-MonitorHeight` | int  | Height of the monitor in pixels.                                   |

## [Set-WindowCacheMaxAge](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Set-WindowCacheMaxAge.ps1)

- **Description:** Sets the maximum age for the window cache, configuring how long the window enumeration cache remains valid. Lower values provide more accurate data at the cost of more syscalls.
- **Parameters:** -MaxAgeMs
- **Usage:** `Set-WindowCacheMaxAge -MaxAgeMs 100`

## [Set-WindowLayouts](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Set-WindowLayouts.ps1)

- **Description:** Applies a predefined window layout configuration. Moves windows to specific virtual desktops and positions them according to a layout configuration, supporting two positioning modes: direct pixel coordinates (X, Y, Width, Height) and zone-based placement (Layout, Zone, Monitor) that uses FancyZones layouts with human-readable zone names. Distinguishes pre-existing from newly opened windows so windows already at the final target coordinates are skipped (idempotent) while new windows are always positioned and tracked for later snapping. Includes retry logic and handle-based recovery for transient browser title changes, and supports duplicate layout entries where the same (ProcessName, WindowTitle) pair appears multiple times so each entry claims exactly one distinct window handle for its own zone. For those duplicate entries the claim is deterministic instead of using whatever enumeration/Z-order returned first: when an optional `-PinnedHandleMap` (built from `CurrentLayout.txt`) records a specific window for this exact desktop/monitor/zone and that window is still live with a matching process fingerprint, it is reclaimed (the HWND is a unique, stable identifier within a session, so every window returns to its own zone with zero reshuffle). When there is no valid recorded window (first open, after a reboot, or a brand-new window) it falls back to claiming the unclaimed candidate whose **current bounds are closest to that entry's target zone**, mirroring the verifier's scoring.
- **Parameters:** -LayoutConfig, -ConfigPath, -MonitorInfo, -MonitorConfig, -ExistingWindowHandles, -ExpectedWindowState, -DesktopOffset, -SkipExistingWindows, -PinnedHandleMap, -ProtectedWindowHandles
- **Usage:** `Set-WindowLayouts -LayoutConfig $layout`, `Set-WindowLayouts -ConfigPath "<DevRoot>\MyLayouts\development.json"`, `Set-WindowLayouts -LayoutConfig $layout -MonitorInfo $monitors -MonitorConfig $config.Monitors`, `Set-WindowLayouts -LayoutConfig $layout -DesktopOffset 2`

Applies the per-window portion of a layout after FancyZones layouts are already in place. It sorts layout entries by desktop and monitor coordinates for deterministic processing, resolves each target zone or direct coordinate block (auto-resolving layout names from `MonitorConfig` based on Monitor and DesktopNumber when not explicitly given), finds matching windows with retries and handle-based recovery, moves each window to the correct virtual desktop, then resizes via the shared target-bounds (inset) path of `Resize-Windows` before tracking each positioned window so `Resize-PositionedWindows` and `Snap-AllWindows` can validate and recover it later. When the resolved zone's layout defines exactly one zone (`TotalZoneCount` from `Get-FancyZone`, e.g. `Zone = "Fullscreen"` on the `Zero` grid), the window is tracked with `Add-PositionedWindow -SingleZone` so the snap pass routes it through `Invoke-SingleZoneWindowSnap` - which clears stale FancyZones assignments so the relative `Win+Up` resolves, and registers the window rather than only positioning it; direct-coordinate entries never carry the flag. Accepts either a `-LayoutConfig` array/hashtable or a `-ConfigPath` to a `.json` or `.psd1` file (mutually exclusive parameter sets).

Every layout entry produces exactly one result row, `Configured` or `Not Found`, so the caller's tallies always add up to the layout. An entry that finds no window it may use - no match at all, everything filtered out by `-SkipExistingWindows` or `-ProtectedWindowHandles`, or (for a duplicate key) every candidate already claimed by an earlier entry - reports `Not Found` rather than falling through silently. `-ProtectedWindowHandles` is the plain-open counterpart of `-SkipExistingWindows`: a preserved alongside workspace's window matches layout regexes like any other (`Browser` matches any browser window), so protected handles are dropped from every entry's candidate list before claiming, refused again by a backstop in the move loop, and filtered out of every recreated-window / verify-by-title recovery lookup so a mid-positioning recovery can never pick one up either. Each `Configured` row also carries the token-resolved `LayoutEntry` it came from, which lets a caller rebuild the exact subset of the layout this pass actually placed; `Set-WorkspaceWindowLayout` uses it to scope alongside verification.

**Unresolvable monitor geometry skips the entry.** A zone-based entry whose `Monitor` cannot be resolved to real geometry is skipped with a warning naming the requested monitor and the attached labels. There is no default geometry and no fall back to `Primary`: substituting a hardcoded `3440x1440` placed the window using geometry that can belong to no attached display, and retargeting `Primary` silently stacked a third monitor's windows on top of the primary monitor's. Both were effectively unreachable with two known monitors and became reachable as soon as a layout named a monitor that is not attached. Losing one window to a warning is easier to notice, and to diagnose, than finding it in the wrong place.

| Parameter                | Description                                                                                                                                                                                                                                                                                                                                                                                          |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-LayoutConfig`          | Array of window configuration hashtables (ProcessName, optional WindowTitle, DesktopNumber, and either X/Y/Width/Height or Layout/Zone/Monitor). Mutually exclusive with `-ConfigPath`.                                                                                                                                                                                                              |
| `-ConfigPath`            | Path to a `.json` or `.psd1` file containing the layout configuration. Mutually exclusive with `-LayoutConfig`.                                                                                                                                                                                                                                                                                      |
| `-MonitorInfo`           | Array of monitor specs used to resolve string monitor labels (`Primary`, `Secondary`, `Monitor3`, ...) to coordinates. An entry naming a monitor with no resolvable geometry is skipped with a warning.                                                                                                                                                                                                |
| `-MonitorConfig`         | Hashtable of the `Monitors` configuration section; used to auto-resolve layout names per monitor and desktop.                                                                                                                                                                                                                                                                                        |
| `-ExistingWindowHandles` | HashSet of handles open before the layout run; used to detect pre-existing windows and skip already-correct positioning.                                                                                                                                                                                                                                                                             |
| `-ExpectedWindowState`   | Hashtable of stable window state captured during the wait phase; enables handle-based recovery when titles change transiently.                                                                                                                                                                                                                                                                       |
| `-DesktopOffset`         | Integer shift applied to all 1-based desktop numbers (default 0).                                                                                                                                                                                                                                                                                                                                    |
| `-SkipExistingWindows`   | Switch (alongside mode) that skips windows existing before this workspace opened, since they belong to a previous workspace. Ineligible windows are dropped from an entry's candidate list *before* any claiming happens, so an entry left with none reports `Not Found` (a countable shortfall) rather than silently placing nothing.                                                              |
| `-PinnedHandleMap`       | Optional hashtable from `CurrentLayout.txt` keyed by `"<DesktopNumber>\|<Monitor>\|<Zone>"` → recorded window (`@{ Handle; ProcessId; ProcessName }`). The authoritative source for which duplicate-named window claims each zone: a still-live, process-matching recorded window is reclaimed exactly; geometry is the fallback when no valid record exists. A stale/dead/reused handle is ignored. |
| `-ProtectedWindowHandles` | HashSet of live handles a plain open must preserve (they belong to a live alongside workspace - see [Get-WorkspaceOpenProtection](workflow.md#get-workspaceopenprotection)). No layout entry can claim, move, or recover one; an entry whose only matches are protected reports `Not Found`. |

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

Accepts a hashtable of timing values and merges them into the module-scoped `$script:WindowModuleDelays` table, leaving any key it does not recognize untouched. These delays govern the small settle pauses the Window module inserts between cursor moves, focus changes, keyboard shortcuts, and window/desktop operations. The input-facing delays default to 25 ms rather than 10: on a fast machine 10 ms is short enough that a chord occasionally reaches the wrong monitor or a window that has not finished taking focus, and 25 ms holds full reliability while adding only milliseconds per send.

| Key                  | Default | Description                                               |
| -------------------- | ------- | --------------------------------------------------------- |
| `CursorSettleMs`     | 25      | Delay after cursor movement before sending keys.          |
| `FocusSettleMs`      | 25      | Delay after `SetForegroundWindow` before sending keys.    |
| `KeyboardShortcutMs` | 25      | Delay after a keyboard shortcut is sent.                  |
| `LayoutCommitMs`     | 25      | Delay letting FancyZones commit a layout switch to disk before a virtual-desktop switch fires. |
| `WindowRestoreMs`    | 25      | Delay after `ShowWindow` restore operations.              |
| `WindowPositionMs`   | 25      | Delay after `SetWindowPos` for the window to settle.      |
| `VirtualDesktopMs`   | 25      | Delay after `Move-Window` for virtual desktop operations. |
| `AppliedLayoutsReloadMs` | 150 | Delay after writing `applied-layouts.json` before the probe shortcut that confirms FancyZones reloaded it (FancyZones' own log shows the reload landing 40 to 60 ms after a change). |

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

## [Set-WorkspaceRerunMirror](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Set-WorkspaceRerunMirror.ps1)

- **Description:** Writes or clears the persisted mirror of a workspace rerun marker, stamped as `value|unix-timestamp` for [Get-WorkspaceRerunMirror](#get-workspacererunmirror) to age out. An empty or `$null` value clears the mirror instead of writing one.
- **Parameters:** -Name, -Value, -Scope
- **Usage:** `Set-WorkspaceRerunMirror -Name 'WORKSPACE_RERUN_COUNT' -Value '1'`, `Set-WorkspaceRerunMirror -Name 'WORKSPACE_RERUN_COUNT' -Value $null`

Clearing is read-guarded, and that guard matters more than it looks. A User-scope environment write does not just touch the registry - it broadcasts `WM_SETTINGCHANGE` to every top-level window and blocks on the slowest one to answer, measured at ~700ms on an idle desktop and several seconds on a busy one, while the matching read is a plain registry lookup at ~2ms. `Set-WorkspaceWindowLayout` clears these markers on the success path of every single workspace open, where the mirror is almost always already absent, so writing unconditionally spent most of a second to achieve nothing.

Clearing empties the value rather than removing the variable: passing `$null` from PowerShell to `[Environment]::SetEnvironmentVariable` binds it as an empty string, so the entry survives with no content. Every reader treats empty and absent alike, and removing it outright would cost an extra broadcast.

| Parameter | Description                                                                                                                                                               |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-Name`   | Environment variable to mirror, e.g. `WORKSPACE_WINDOW_ONLY_RETRY`.                                                                                                       |
| `-Value`  | Value to persist. Empty or `$null` clears the mirror.                                                                                                                     |
| `-Scope`  | `User` (default) or `Process`. `Process` is for tests: identical logic without the broadcast, and per-process, so a parallel test worker cannot disturb the real machine.   |

## [Set-WorkspaceWindowLayout](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Set-WorkspaceWindowLayout.ps1)

- **Description:** Loads and applies a predefined, machine-specific window layout for a workspace. Layout files live in machine-type subfolders of the module's `Layouts` directory (e.g. `Layouts/PC/`, `Layouts/Laptop/`, `Layouts/Work/`) and define both FancyZones monitor layouts and per-window placement rules. Which subfolder is read can be redirected per machine with `LayoutMachineTypeOverrides` (see below), and that manual choice takes precedence over the `SmallDisplayMachineType` display-size detection. After loading the workspace layout file, the function validates the FancyZones configuration with `Test-FancyZonesConfiguration` before any desktop or window work: errors touching a layout the workspace references (or global errors) abort the open, while all other findings warn and the open proceeds. It then ensures the required virtual desktops exist, waits for workspace windows to appear and stabilize, applies FancyZones, positions and snaps each window into its zone, then verifies every entry. On snap or verification failure it first retries the position → snap → verify pipeline in-process up to 2 times (refreshing the existing-window snapshot so already-correct windows are skipped). Each retry starts by resetting FancyZones, since a window that will not land in its zone usually means the zone grid is wrong rather than the window being stubborn: PowerToys/FancyZones is force-restarted and the workspace's zone layouts are re-sent with `Apply-FancyZones -Force`, which is what keeps the retry from snapping into the same broken grid. Only when those retries are exhausted does it escalate by force-starting FancyZones and rerunning in a fresh shell in a window-only retry mode that preserves already-configured desktops, force-reapplies the FancyZones layouts, and reapplies the full layout config; before every rerun it also releases stuck keyboard modifiers and a stranded mouse button via `Reset-KeyboardModifiers` so the respawned shell takes over a clean input session. The rerun counter and the retry markers travel to that shell through the User-scope mirror ([Get-WorkspaceRerunMirror](#get-workspacererunmirror) / [Set-WorkspaceRerunMirror](#set-workspacererunmirror)) rather than through the process environment, which Windows Terminal rebuilds from the registry for every new session - so the two-rerun cap holds across respawns and the respawned run really is a window-only retry. Every run also keeps a phase clock and publishes it on exit - seconds spent in `Preamble`, `Desktops`, `FancyZones`, `Wait`, `Normalize`, `Position`, `Snap`, `Verify`, `Retry` and `Save`, accumulated across the in-process retries, plus the attempt count and the outcome - readable through [Get-WorkspaceLayoutTimings](#get-workspacelayouttimings), which `Open-Workspace` folds into the workspace benchmark row.
- **Parameters:** -WorkspaceName, -LayoutPath, -TimeoutSeconds, -SnapDelayMs, -DisableAutoWait, -PreCapturedExistingWindows, -DesktopOffset, -Alongside, -ProtectedWindowHandles
- **Usage:** `Set-WorkspaceWindowLayout -WorkspaceName MyWorkspace`, `Set-WorkspaceWindowLayout -WorkspaceName OtherProject -DesktopOffset 2 -Alongside`, `Set-WorkspaceWindowLayout -LayoutPath C:\Users\<User>\MyLayouts\custom.psd1 -TimeoutSeconds 30`, `Set-WorkspaceWindowLayout -WorkspaceName MyWorkspace -DisableAutoWait`

This is the final step of the layout system: FancyZones (PowerToys) defines the zones, `.psd1` layout files map windows to those zones, and `Set-WorkspaceWindowLayout` applies the configuration. With `ByWorkspace` it auto-resolves `Layouts/{MachineType}/{WorkspaceName}_{MachineType}.psd1`; with `ByPath` it applies an explicit layout file. Layouts may contain duplicate window entries (same `ProcessName`/`WindowTitle`) to place identical windows in different zones, used together with `Open-Browser`'s `-Override` to position two copies of the same URL group independently. The function does not perform the final virtual-desktop landing itself; switching to and focusing the workspace's first desktop is delegated to `Focus-VirtualDesktop`, the last action in each workspace's `WorkspaceActions` sequence. VS Code entries are matched by process: a `Code` entry with no `WindowTitle` is a catch-all that captures every VS Code window (folder or `.code-workspace`, any number of them) and places them all in its zone, so opening a workspace file with `-VSCodeWorkspace` needs no layout coupling. Give a `Code` entry a `WindowTitle` (a bare project name such as `Dotfiles`) only to split several VS Code windows across different zones; the process-and-title match then pins each editor to its own slot.

**The `Fullscreen` simple layout places windows directly, wherever they are.** For `SimpleLayoutWorkspaces` (the `Fullscreen` workspace), the zone grids are applied to every monitor on every desktop, then each window is placed straight at its own monitor's single fullscreen zone via `Invoke-SingleZoneWindowPlacement` - no `Win+Up`, no desktop switching, no focus stealing: direct `SetWindowPos` placement works on windows parked on invisible desktops and is verified per window with `Wait-WindowRect`. Which monitor a window belongs to is resolved from a snapshot taken **before** `Apply-FancyZones` runs, because applying a changed zone set can make FancyZones itself relocate remembered windows across monitors (its zone-set-change move consults `app-zone-history`) - typically right after `Reset-Windows` gathered everything onto one monitor while the history still records zones on another. A minimized window (off-screen rect) is restored once and its live position re-read. Placement failures are reported with expected vs actual bounds; windows whose monitor cannot be resolved are skipped with a debug note. The old per-desktop keyboard-snap loop remains only as a fallback for a simple layout whose grid is not single-zone (none ship today). The trade-off of the no-switching design is that these windows are **not registered** with FancyZones (no zone assignment, no `app-zone-history` entry - see `Get-FancyZonesWindowAssignment`): registering requires FancyZones' own keyboard or drag path, which only works on the visible desktop. The workspace flow (`Snap-AllWindows`) uses `Invoke-SingleZoneWindowSnap` for exactly that; this path keeps the speed by design.

**Every attached monitor is covered, not just the ones the layout file defines.** Immediately after the layout file is loaded - for **every** workspace, not only the `SimpleLayoutWorkspaces` ones - [Expand-LayoutMonitorCoverage](window.md#expand-layoutmonitorcoverage) fills in any attached monitor the file omits, cloning the first defined monitor's per-desktop layouts as a template and logging which labels it added. Without it, `Apply-FancyZones` never visits an undefined monitor, so a newly attached display keeps whatever zone layout it happened to have. This used to run inside the simple-layout branch alone, which made `Fullscreen` and `Empty` the only two workspaces that adapted to a third monitor; attach one and open any normal workspace and it was silently under-served.

Only zone layouts are cloned, never the `Layout` array, so an auto-added monitor receives a FancyZones layout but no window assignments - nothing is moved onto it and nothing already targeted elsewhere changes. Set `AutoExtendMonitors = $false` at the top level of a layout file to opt that layout out and leave undefined monitors alone.

**Which layout set is used** (parameter set `ByWorkspace` only - `-LayoutPath` is always taken as given) comes from [Get-LayoutMachineType](window.md#get-layoutmachinetype): a non-empty `LayoutMachineTypeOverrides` entry for the detected machine type, else `SmallDisplayMachineType` on a laptop-class display, else the detected type. The resolved value fills both halves of the path - the folder becomes `Layouts/<value>/` and the file `<WorkspaceName>_<value>.psd1` - and the captured monitor snapshot is handed over so the display-size rule does not re-query it. `Reset-Windows` resolves its own per-machine defaults through the same helper, so the layouts and the reset target can never disagree about which monitor setup is attached.

The override exists so a machine can be driven on a monitor setup its layouts were never authored for (a desktop moved away from its multi-monitor rig, a temporary single screen) without editing or losing that layout set: author the new geometry in its own folder, point the override at it, clear the entry to switch back. When the resolved set has no file for the workspace, the "No layout configuration found" warning also names that set and the exact path it expected - the set searched is not always the machine's own, which makes an unexplained missing file baffling. There is no silent fallback to the machine's own layouts, because those describe a monitor setup that is not currently attached.

On every successful apply the function records the result to `Window\Layouts\CurrentLayout.txt` via `Save-CurrentLayout` (virtual desktop count, FancyZones layout per monitor per desktop, and every configured window with its desktop/monitor/zone - built from the `Set-WindowLayouts` results so the snapshot stays complete even on idempotent re-runs where most windows are already correct and skipped). On entry it reads that snapshot back via `Get-CurrentLayout` for the workspace being applied and passes it to `Set-WindowLayouts` as a `-PinnedHandleMap`, which authoritatively reclaims each recorded window for its zone - so layouts with many identically-named windows (e.g. `Example_PC`'s `Browser` entries) keep each window in the same zone across reopens and `-Alongside` opens, with closest-bounds geometry as the fallback only when there is no valid record. A missing/stale file simply changes nothing. The file is per-machine runtime state and is git-ignored. FancyZones layouts are always reapplied per desktop (the snapshot does not gate that) so the zone grids are unconditionally refreshed; only window-to-zone assignment is driven by the snapshot.

| Parameter                     | Type            | Default | Description                                                                                                                                                                                                                                                |
| ----------------------------- | --------------- | ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-WorkspaceName`              | string          | -       | Workspace layout to apply (parameter set `ByWorkspace`); auto-resolves the machine-specific layout file.                                                                                                                                                   |
| `-LayoutPath`                 | string          | -       | Direct path to a layout `.psd1` file (parameter set `ByPath`, mandatory there).                                                                                                                                                                            |
| `-TimeoutSeconds`             | int             | `60`    | Maximum seconds to wait for windows when using automatic detection.                                                                                                                                                                                        |
| `-SnapDelayMs`                | int             | `10`    | Milliseconds to wait between positioning and the snap pass, and the per-window delay on the simple-layout path (`Snap-AllWindows -All`). Not a per-window delay in the workspace flow - the positioned-window path verifies with `Wait-WindowRect` instead.  |
| `-DisableAutoWait`            | switch          | -       | Skips automatic window detection and applies the layout immediately (windows may not be ready).                                                                                                                                                            |
| `-PreCapturedExistingWindows` | HashSet[IntPtr] | -       | Window handles that existed before opening workspace apps; used to distinguish new windows from existing ones. Typically supplied by `Open-Workspace`.                                                                                                     |
| `-DesktopOffset`              | int             | `0`     | Offset added to every virtual desktop number in the layout so a workspace can open to the right of existing ones (e.g. offset `2` places Desktop 1 on Desktop 3).                                                                                          |
| `-Alongside`                  | switch          | -       | Opens the workspace alongside existing desktops (added to the right via `DesktopOffset`) instead of replacing them. Also narrows the layout pass to windows this open created - see the alongside notes below.                                             |
| `-ProtectedWindowHandles`     | HashSet[IntPtr] | -       | Live handles of alongside workspaces a plain open preserves. Threaded in by `Open-Workspace`; a standalone plain call derives the set itself via [Get-WorkspaceOpenProtection](workflow.md#get-workspaceopenprotection) when that function is available. See the plain-open preservation notes below. |

**A plain open preserves live alongside workspaces.** When `-ProtectedWindowHandles` is set (or self-derived), the desktop resize target is raised to the highest desktop a protected window stands on - resolved live via `Get-WindowDesktopIndex`, never from a stored index, and never shrinking when occupancy cannot be resolved - so `Ensure-VirtualDesktops` (which removes desktops from the right, exactly where alongside lives) cannot delete a preserved workspace's desktops; a protected window inside the plain layout's own desktop range is reported as an overlap warning. Protected windows are skipped by the early-move callback and by browser first-tab normalization (in both the unresolved-entry scan and the normalization loop), passed to `Set-WindowLayouts` so no layout entry can claim them, excluded from plain-mode verification via `Confirm-WorkspaceWindowPositions -ExcludeWindowHandles`, and the success-path `Save-CurrentLayout` runs with `-PreserveOtherSections` so the preserved workspaces keep their snapshot sections. Simple layouts (`Fullscreen`/`Empty`) deliberately ignore protection: they are global-by-design gestures.

**Alongside narrows what the layout may touch**, not only where it lands: `Set-WindowLayouts` runs with `-SkipExistingWindows`, so every window captured before the open belongs to whichever workspace is already running and is refused. Two things follow from that rule.

Count-based openers have to be told. `Open-Browser -Instances N` means "ensure N windows exist", which is correct for a normal open but starves an alongside one: with N already open it launches nothing, and the layout is handed zero usable windows. `Open-Workspace` therefore forwards `-Alongside` to every action that declares the parameter, and `Open-Browser` switches to "open N NEW windows" when it sees it. Before that, `w example -Alongside` (33 identical `Browser` entries) lost exactly as many zones as there were Chrome windows already open, and degraded further on each rerun.

A shortfall is now reported rather than inferred. When the eligible windows do not go round, each unfillable entry produces a `Not Found` result and the pass warns once with both counts (`Layout short by N window(s) - placed X of Y entries!`). Previously the shortfall was a verbose-only per-entry line, so a run that filled 12 of 33 zones printed the same success banner as a clean one.

Empty-desktop cleanup (`Remove-VirtualDesktops -EmptyOnly`) runs once at the very end, after `CurrentLayout.txt` is written. Removing a desktop to the *left* of the workspace shifts every later desktop down by one, which would silently invalidate `DesktopOffset` for any remaining retry attempt and for the snapshot's `actual = record Desktop + section DesktopOffset` contract.

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

On entry the function runs a live RPC preflight (`Get-RpcRetryPolicy -OperationLabel "applying layout" -Probe`): the probe verifies this session's VirtualDesktop COM state in-process, so a session whose proxies went stale after an Explorer restart is detected and repaired (via `Repair-RpcServer` / `Reset-VirtualDesktopState`) before any desktop reconfiguration begins. On success Windows Terminal is refocused just before the success banner so output is not buried behind workspace windows. On snap or verification failure the position → snap → verify pipeline is first retried in-process up to 2 times (in `-Alongside` mode too): the existing-window snapshot is refreshed so already-correct windows are skipped by the position check (in `-Alongside` mode it stays the original pre-open capture, since there it marks the other workspace's windows), and verification runs against the full layout config so windows an aborted snap pass never reached are covered. `-Alongside` is verified too, but scoped twice over: only the entries this pass actually placed a window for (rebuilt from the `LayoutEntry` field on the `Set-WindowLayouts` results), matched only against windows this open created (the pre-open snapshot is passed as `-ExcludeWindowHandles`). Another workspace's windows can therefore neither be checked nor mistaken for this workspace's, which is what the earlier blanket skip was avoiding - at the cost of reporting unconditional success, so a starved or mispositioned alongside pass was never retried and was persisted by `Save-CurrentLayout` as the truth, pinning the next open to those wrong zones. When nothing at all was placed, verification is skipped: no retry can conjure windows, and the shortfall warning below is the report. Only when the in-process retries are exhausted does the function record the failed window marker (now informational only), force-start FancyZones, and rerun via `Initialize-WorkspaceWindowLayoutRerun -WindowOnlyRetry` / `ReRun-LastCommand` in a window-only mode that preserves virtual desktops and caches, always reapplies FancyZones monitor layouts, and applies the full layout config - idempotent skips keep it cheap (still capped at 2 auto-reruns). The counter behind that cap and the window-only markers reach the respawned shell through the User-scope mirror (`Get-WorkspaceRerunMirror` / `Set-WorkspaceRerunMirror`), never through the process environment: Windows Terminal generates a new environment block for every session, so the new shell's process copies are the stamped mirror values themselves and are skipped in favour of the mirror (reading them as plain used to throw on the `[int]` cast of the counter and to leave the respawned run unaware it was a retry). The rerun command is taken from `$env:WORKSPACE_RERUN_COMMAND` (recorded by `Open-Workspace`) when present, instead of scraping PSReadLine history. Auto-rerun is disabled in `-Alongside` mode. `CurrentLayout.txt` is written only on the success paths, so a failed/rerunning attempt never overwrites the last good snapshot.

A few passes between waiting and positioning are kept deliberately narrow. First-open normalization resizes only the windows this open created (pre-existing windows elsewhere on the machine are left untouched). Browser first-tab normalization (Ctrl+1) skips windows already showing a title some browser layout entry wants, and touches pre-existing browser windows only when a browser entry's title currently matches no window; it no longer probes tab counts via a UIA tree walk. The pre-snap resize (`Resize-PositionedWindows`) runs with the module's default 20px tolerance so windows that self-adjust by a pixel (terminal cell rounding, min-size constraints, DPI rounding) converge instead of being re-positioned on every open. And a virtual desktop count mismatch is delta-resized with a single `Ensure-VirtualDesktops` call (it grows and shrinks) instead of removing all desktops and recreating them.

**See also:** [Save-CurrentLayout](window.md), [Get-CurrentLayout](window.md), [Set-WindowLayouts](window.md), [Window module overview](../modules/window.md)

## [Snap-AllWindows](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Snap-AllWindows.ps1)

- **Description:** Snaps positioned windows into their FancyZones zones, desktop by desktop. Multi-zone windows get `Win+Up` with reliable focus acquisition (validated pre-snap, re-positioned when drifted, shift-drag fallback when the keyboard snap fails); windows tracked with `-SingleZone` (see `Add-PositionedWindow`) snap through `Invoke-SingleZoneWindowSnap` so they end up **registered** with FancyZones, not merely positioned: a stale zone assignment is cleared first (it is what made single-zone `Win+Up` a no-op or a cross-monitor throw - FancyZones' position-based move excludes zones the window is already assigned to, and the marker survives every programmatic move, so `Reset-Windows` leaves it behind routinely), the window is centered in its zone at a deeper inset, then `Win+Up` with a shift-drag fallback. Default mode snaps only windows previously positioned by `Set-WindowLayouts` (the workspace flow); `-All` snaps all visible windows standalone. A window that exhausts its attempts is recorded as failed and the pass **continues** with the remaining windows and desktops (a circuit breaker aborts once 3 windows have failed - that pattern means something systemic the caller's retry must reset first), and a post-pass sweep re-checks that every tracked window is still on its assigned desktop, retrying stragglers once. Stuck keyboard modifiers are cleared via `Reset-KeyboardModifiers` before each window's first snap attempt (the `Win+Ctrl+Alt+N` injection from `Apply-FancyZones` moments earlier can strand a modifier whose key-up was eaten by a focus change), before each snap retry, and (mouse button included) when a pass fails, so an interrupted earlier sequence can neither corrupt the injected combos (a held Shift turns `Win+Up` into `Win+Shift+Up`) nor leave terminal input locked up.
- **Parameters:** -All, -CurrentDesktopOnly, -WindowHandles, -SnapDelayMs, -DesktopOffset, -DesktopCount
- **Usage:** `Snap-AllWindows`, `Snap-AllWindows -All`, `Snap-AllWindows -All -CurrentDesktopOnly`, `Snap-AllWindows -All -SnapDelayMs 100`, `Snap-AllWindows -DesktopOffset 2 -DesktopCount 3`

Every multi-zone window is snapped with `Win+Up`. The window arrives already inset *inside* its target zone, and the two arrow directions are not symmetric for that state: `Win+Up` snaps the window into the zone it is sitting in, while `Win+Down` hands it to the zone **below**. A "top half of a vertically split monitor" special case used to send `Win+Down` for exactly those windows, which made every top-half zone (Seven's Top-Right, Four's top row, ...) land one zone too low, fail verification, and get recovered by the slow shift-drag fallback. Single-zone windows skip all of it - the inset pre-position and foreground focus exist only to steer the relative keyboard snap, so direct placement needs neither and fullscreen-heavy workspaces stop churning focus across their desktops.

The post-pass desktop verification sweep exists because the per-window alignment check answers "was this window on its desktop right before *its* turn", not "is every window still there after the whole pass": the upstream `Move-Window` falls back to moving a process's **main** window when the requested view cannot be moved, so positioning a later sibling of a multi-window process (Firefox, Windows Terminal, VS Code) can silently displace an already-placed window. Same pattern as the `Move-Windows` sweep - one cheap desktop read per tracked window (`Get-WindowDesktopIndex`), one `Move-WindowToVirtualDesktop` recovery attempt, unrecoverable becomes a reported failure. Cross-desktop moves do not need the target desktop visible, so the sweep never switches desktops, and it runs even after an abort.

`GetAllWindows` (`EnumWindows`) enumerates windows across **every** virtual desktop, not just the active one, so `-All` alone snaps system-wide. When a caller switches desktops in a loop and snaps each in turn, it must pass `-CurrentDesktopOnly` so each window is snapped exactly once on its own desktop and forcing a window foreground never drags the active desktop to a window that lives elsewhere. The current and per-window desktops are resolved with `Get-CurrentDesktop` / `Get-DesktopFromWindow` / `Get-DesktopIndex`; an unresolvable window is kept (snapped) rather than dropped, and if the current desktop itself cannot be determined the filter is skipped. Callers that already resolved the window-to-desktop mapping can instead pass `-WindowHandles` with the per-desktop handle list - it takes precedence over `-CurrentDesktopOnly` and avoids the two COM roundtrips per window on every desktop pass.

In the workspace (positioned-windows) flow, windows are grouped by desktop and processed in positioning order. Desktop switches are verified by polling (`Wait-DesktopSwitch`); when a switch cannot be confirmed the `VirtualDesktop` module is reset (`Reset-VirtualDesktopState`). After each transition the monitor/window caches are refreshed, each window is revalidated and realigned to the target desktop, and stale handles are recovered via title + process fingerprint matching (`Resolve-PositionedWindowHandle`). Re-positioning uses the same shared inset resize path as `Set-WindowLayouts` and `Resize-PositionedWindows`, and focus is verified immediately before key injection via `Confirm-WindowForeground`. Keyboard-snap and shift-drag results are verified by polling the window rect via `Wait-WindowRect` (the time budget grows on each retry) instead of a fixed sleep and single check, so a snap that lands quickly returns immediately and the expensive fallbacks only trigger when the budget is genuinely exhausted. Target desktop indices are computed through `ConvertTo-InternalDesktopIndex` so `DesktopOffset` is honored consistently.

At start the function requires a verified FancyZones ready state, and during long snap loops it re-checks FancyZones liveness once per desktop pass (rather than per window) and attempts a restart if the process disappears; if FancyZones cannot be recovered it aborts early. If keyboard and shift-drag retries (or a single-zone snap) still cannot verify zone placement, the failed window is recorded in the return object and the pass moves on to the remaining windows - one stubborn window no longer strands every later desktop at its inset size - so `Set-WorkspaceWindowLayout` can retry the full layout for the recorded stragglers. After processing, the active desktop is left on the last one snapped - returning the user to the first desktop is delegated to `Focus-VirtualDesktop` (the final workspace action), keeping switch-and-focus logic in one place (DRY).

| Parameter             | Type   | Default | Description                                                                                                                                      |
| --------------------- | ------ | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `-All`                | switch | -       | Snap all visible windows without requiring prior positioning by `Set-WindowLayouts`. Useful for standalone usage.                                |
| `-CurrentDesktopOnly` | switch | -       | Only valid with `-All`. Restricts snapping to windows on the currently active virtual desktop, so desktop-switching loops snap each window once. |
| `-WindowHandles`      | IntPtr[] | -     | Only valid with `-All`. Restricts snapping to exactly these window handles; takes precedence over `-CurrentDesktopOnly`. For callers that already resolved the window-to-desktop mapping. |
| `-SnapDelayMs`        | int    | `25`    | Delay in milliseconds between each window snap in `-All` mode. The positioned-window path verifies with `Wait-WindowRect` instead of fixed delays, so it has no effect there. |
| `-DesktopOffset`      | int    | `0`     | Virtual desktop offset for the `-All` flow. Leave at `0` in the workspace flow - see the note below.                                             |
| `-DesktopCount`       | int    | `0`     | Number of desktops to process.                                                                                                                   |

> `Set-WorkspaceWindowLayout` always passes `-DesktopOffset 0`, in every mode. The desktop numbers recorded by `Add-PositionedWindow` already have the workspace offset folded in (`Set-WindowLayouts` stores `DesktopNumber + DesktopOffset`), and this function runs them back through `ConvertTo-InternalDesktopIndex`, which adds the offset a second time. Forwarding the real offset therefore double-applied it: with `-DesktopOffset 2` a window tracked as desktop 3 resolved to internal index `(3-1)+2 = 4` while the window actually sat on `(1-1)+2 = 2`, so the pass switched to a desktop nothing was on and could not snap anything.

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

> **Note:** Disable PowerToys' "Move newly created windows to their last known zone" so windows aren't moved to the wrong position. Any `spacing` value in `FancyZones/custom-layouts.json` works: `Get-FancyZoneCoordinates` replicates the exact FancyZones spacing model (full inset on work-area border edges, `Floor(spacing/2)` per zone on interior edges), so snap verification and shift-drag snapping agree with the live zone grid.

**See also:** [Set-WorkspaceWindowLayout](window.md#set-workspacewindowlayout), [Invoke-SingleZoneWindowSnap](window.md#invoke-singlezonewindowsnap), [Invoke-SingleZoneWindowPlacement](window.md#invoke-singlezonewindowplacement), [Resize-Windows](window.md#resize-windows), [Get-InsetWindowBounds](window.md#get-insetwindowbounds)

## [Test-AppliedFancyZonesLayouts](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Test-AppliedFancyZonesLayouts.ps1)

- **Description:** Verifies that `applied-layouts.json` holds the wanted layout for each monitor/desktop target, optionally after waiting for FancyZones to rewrite the file. Per target it requires exactly one entry for the monitor (EDID code and PnP instance path) on the virtual desktop, carrying the expected layout uuid: `Verified` on a match, `Missing` when no entry exists, `Mismatch` when the entry names another layout, `Duplicate` when more than one entry claims the same monitor and desktop (the sign that an externally written entry carried a device block FancyZones did not recognize as its own, so it added a second one), `Unreadable` when the file cannot be parsed. With `-WaitForWriteAfterUtc` it first polls the file's last-write time until it is later than the given stamp or `-TimeoutMs` (750 ms) runs out, reported as `SaveObserved`. That is the confirmation step of the file-based layout application: after `Write-AppliedFancyZonesLayouts` stamps the file, one layout shortcut makes FancyZones save its whole in-memory layout map back to the file, and only entries FancyZones had loaded survive that save.
- **Parameters:** -Targets, -WaitForWriteAfterUtc, -TimeoutMs, -PollIntervalMs, -AppliedLayoutsPath
- **Usage:** `Test-AppliedFancyZonesLayouts -Targets $written.Targets -WaitForWriteAfterUtc $written.WrittenAtUtc`, `Test-AppliedFancyZonesLayouts -Targets $targets -AppliedLayoutsPath $path`

Returns a `PSCustomObject` with `SaveObserved` (`$true`/`$false` when waiting, else `$null`), `Readable`, `AllVerified`, `VerifiedCount` and one `Targets` record per input (`Status`, `ActualUuid`). Targets are objects with `Monitor`, `MonitorInstance`, `VirtualDesktop` (GUID, braces optional) and `Uuid`; the records `Write-AppliedFancyZonesLayouts` returns fit directly. Matching is case-insensitive, since FancyZones writes the instance path in lower-case hex.

| Parameter               | Type     | Default | Description                                                                   |
| ----------------------- | -------- | ------- | ----------------------------------------------------------------------------- |
| `-Targets`              | array    | -       | Monitor, MonitorInstance, VirtualDesktop and Uuid per target (Mandatory).      |
| `-WaitForWriteAfterUtc` | datetime | -       | Wait until the file's last-write time is later than this before reading.       |
| `-TimeoutMs`            | int      | 750     | How long to wait for that later write.                                         |
| `-PollIntervalMs`       | int      | 25      | Delay between last-write-time polls; 0 spins (tests).                          |
| `-AppliedLayoutsPath`   | string   | -       | Alternative `applied-layouts.json`; defaults to the FancyZones data directory. |

## [Test-FancyZonesConfiguration](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Test-FancyZonesConfiguration.ps1)

- **Description:** Validates the FancyZones configuration quartet against each other: `custom-layouts.json` internal consistency, `$Configuration.ZoneNameMappings`, `$Configuration.LayoutNumbers`, and `layout-hotkeys.json`. Arbitrary layouts, zones, and spacing are supported in `custom-layouts.json`, which makes drift between the four places that must agree the main way a workspace open can misplace windows or apply the wrong layout. Runs automatically near the start of `Set-WorkspaceWindowLayout`: errors touching a layout the workspace references (or global errors) abort the open; everything else warns and the open proceeds.
- **Parameters:** -CustomLayoutsPath, -LayoutHotkeysPath, -Silent
- **Usage:** `Test-FancyZonesConfiguration`, `$result = Test-FancyZonesConfiguration -Silent`

**Checks performed:**

- Every layout in `custom-layouts.json` is internally consistent. Grid: rows/columns match their percentage arrays, each percentage axis sums to exactly 10000, `cell-child-map` is rows x columns and its zone indices form a contiguous `0..N-1` set, spacing is not negative. Canvas: `ref-width`/`ref-height` are positive and every zone has positive width/height (zones extending beyond the ref rect only warn).
- `ZoneNameMappings` agrees with `custom-layouts.json`: every mapped layout exists, and every mapped zone index is within the layout's derived zone count. Layouts without a mappings entry (and zone indices without a name) are warnings, not errors - they only matter once a layout `.psd1` references them.
- `LayoutNumbers` is applyable: values 0-9, unique, and every name exists in `custom-layouts.json`.
- `layout-hotkeys.json` agrees with both: every hotkey uuid exists in `custom-layouts.json`, and for each `LayoutNumbers` entry the hotkey with that number points at that layout's uuid - otherwise `Apply-FancyZones` would apply the WRONG layout via its `Win+Ctrl+Alt+[Number]` shortcut.

| Parameter            | Type   | Default | Description                                                                                          |
| -------------------- | ------ | ------- | ------------------------------------------------------------------------------------------------------ |
| `-CustomLayoutsPath` | string | -       | Optional path to `custom-layouts.json`. Defaults to the repository file (`Get-FancyZonesLayoutsPath`).  |
| `-LayoutHotkeysPath` | string | -       | Optional path to `layout-hotkeys.json`. Defaults to the repository file (`Get-FancyZonesLayoutsPath -File LayoutHotkeys`). |
| `-Silent`            | switch | -       | Suppresses per-finding logging; the result object is returned either way.                              |

Returns an object with `Valid` (`$true` when no errors were found - warnings do not affect validity), `Errors`, and `Warnings`, where each finding is an object with `Layout` and `Message` (`Layout` is `$null` for global/cross-file problems such as hotkey mismatches), so callers can scope their reaction per layout.

```powershell
# Validate the repository FancyZones configuration and log every finding
Test-FancyZonesConfiguration

# Validate silently and inspect the findings programmatically
$result = Test-FancyZonesConfiguration -Silent
if (-not $result.Valid) { $result.Errors | ForEach-Object { $_.Message } }
```

**See also:** [Get-FancyZonesLayoutsPath](window.md#get-fancyzoneslayoutspath), [Set-WorkspaceWindowLayout](window.md#set-workspacewindowlayout), [Apply-FancyZones](window.md#apply-fancyzones)

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

## [Test-SmallPrimaryDisplay](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Test-SmallPrimaryDisplay.ps1)

- **Description:** Tests whether the display that is currently primary is laptop-class - at most `MaxWidthPx` wide (3000px by default), which puts 1920x1080 and 2560x1440 panels in and a 3440x1440 ultrawide or a 4K desktop monitor out. The primary display is the one measured, because that is where the window actually lands; when no display reports itself primary the first enumerated one is used, and with no displays at all the answer is `$false` (never assume small). Shared by `Get-LayoutMachineType` (the `SmallDisplayMachineType` rule) and `Resolve-DisplayAwareProfile` (the `SmallDisplay` row).
- **Parameters:** -MonitorInfo, -MaxWidthPx
- **Usage:** `Test-SmallPrimaryDisplay`, `Test-SmallPrimaryDisplay -MonitorInfo $cachedMonitorInfo`, `Test-SmallPrimaryDisplay -MaxWidthPx 2000`

One shared answer to "am I on the small screen right now?" - the question every display-shaped setting has to ask before it can pick a sensible size. The machine type cannot answer it: a laptop reports the same machine type whether it is sitting on its own panel or docked to a large external monitor, so a per-machine value that is right undocked is wrong docked. Measuring the live primary display is what separates the two. Both consumers used to inline this check; sharing it keeps the threshold in one place, so the laptop cannot start behaving as small for one of them and large for the other.

| Parameter      | Type     | Default | Description                                                                                                            |
| -------------- | -------- | ------- | ------------------------------------------------------------------------------------------------------------------------ |
| `-MonitorInfo` | object[] | -       | Monitor records from `Get-MonitorInfo`. Pass a snapshot the caller already holds to avoid re-querying.                 |
| `-MaxWidthPx`  | int      | `3000`  | Inclusive upper bound, in pixels, for a display to count as laptop-class.                                              |

```powershell
# True on a 1920x1080 laptop panel, False on a 3440x1440 ultrawide
Test-SmallPrimaryDisplay

# Reuse a monitor snapshot the caller already captured
Test-SmallPrimaryDisplay -MonitorInfo $cachedMonitorInfo
```

**See also:** [Get-LayoutMachineType](window.md#get-layoutmachinetype), [Resolve-DisplayAwareProfile](window.md#resolve-displayawareprofile), [Get-MonitorInfo](window.md#get-monitorinfo)

## [Test-VirtualDesktopComHealth](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Test-VirtualDesktopComHealth.ps1)

- **Description:** Probes THIS session's VirtualDesktop COM state with a live roundtrip (`[VirtualDesktop.Desktop]::Count`) on a background runspace inside the current process, under a hard timeout. Because the probe shares the session's compiled types and cached COM proxies, it detects the failure modes that matter to this session: stale proxies after an Explorer restart (fails fast with `0x800706BA` / `0x80010108` - a child-process probe creates its own fresh proxies and wrongly reports healthy in that state) and a hung shell endpoint (the call blocks and the timeout flags it). When the VirtualDesktop types are not compiled in this process yet, the runspace imports the module and calls `Get-DesktopCount`, exercising the same COM activation path a first real call would take.
- **Parameters:** -TimeoutMs (default 5000)
- **Usage:** `Test-VirtualDesktopComHealth`, `$probe = Test-VirtualDesktopComHealth -TimeoutMs 2500`

Returns a `PSCustomObject` with `Healthy` (bool), `TimedOut` (bool), and `Error` (innermost failure message plus HRESULT, or `$null`). A healthy warm probe completes in milliseconds. Used by `Test-RpcServerHealth -Probe` as the live endpoint check and by `Reset-VirtualDesktopState` to verify a reset actually produced a working session.

**See also:** [Test-RpcServerHealth](system.md#test-rpcserverhealth), [Reset-VirtualDesktopState](window.md#reset-virtualdesktopstate)

## [Update-LayoutSectionHeaders](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Update-LayoutSectionHeaders.ps1)

- **Description:** Updates the section headers (e.g., `# VIRTUAL DESKTOP 1 - Monitor: Primary - Layout: One`) within the `Layout` array of a layout file to match the actual configuration. Parses the file content, strips the existing headers, sorts the entries by DesktopNumber, Monitor (`Primary`, `Secondary`, `Monitor3`, `Monitor4`, ...), and zone order, then regenerates the headers from the real DesktopNumber, Monitor, and Layout type values. Used by `Visualize-Layouts -Update` to keep both the visualization block and the inline section headers synchronized with the configuration.
- **Parameters:** -Content, -Config
- **Usage:** `Update-LayoutSectionHeaders -Content $content -Config $config`

Layout files use 1-based indexing for `DesktopNumber`, which is displayed directly in the regenerated headers. Entries are reordered deterministically (DesktopNumber, then monitor order via `Resolve-MonitorLabel`, then `ZoneNameMappings` zone order from the global configuration, then original index) so the output stays stable across runs. If the `Layout` array cannot be parsed, the original content is returned unchanged.

Monitor order comes from [Resolve-MonitorLabel](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Resolve-MonitorLabel.ps1), so it is correct for any monitor count. The local three-way `Primary`=0 / `Secondary`=1 / everything-else=2 mapping it replaced left `Monitor3`, `Monitor4` and `Monitor5` tied at 2, falling back to input order and making generated headers look randomly ordered past `Secondary`. Unrecognized labels sort last and are then broken alphabetically by name.

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

**See also:** [Configuration: Window Layout](../configuration/guides/window/configure-window-layout.md)

## [Visualize-Layouts](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Visualize-Layouts.ps1)

- **Description:** Generates ASCII art visualizations of FancyZones layouts and adds them as commented sections at the top of layout files. Each visualization shows which processes are assigned to each zone, organized by Virtual Desktop and then Monitor (`Primary`, `Secondary`, `Monitor3`, ... - ordered via `Resolve-MonitorLabel`, so any monitor count renders in a stable order). Layout files live in machine-specific subfolders (Laptop, PC, Work) under the Layouts directory and are searched recursively. Configurations are validated before rendering, and with `-DisplayAvailableLayouts` it can instead list all available layout types with their zone-name mappings from configuration.
- **Parameters:** -Layout, -All, -DisplayAvailableLayouts, -Update
- **Usage:** `Visualize-Layouts`, `Visualize-Layouts -Layout "MyWorkspace_PC"`, `Visualize-Layouts -All`, `Visualize-Layouts -All -Update`, `Visualize-Layouts -DisplayAvailableLayouts`

Without parameters the function presents an interactive menu (via `Resolve-Selection`) to pick one or more layouts. For each selected file it imports the `.psd1`, validates it with `Validate-Layout`, groups windows by `DesktopNumber` then `Monitor`, resolves each monitor's layout type from the `Monitors` section, and renders the arrangement with `Generate-LayoutVisualization`. By default it only displays the visualizations; with `-Update` it rewrites each layout file, replacing any existing `LAYOUT VISUALIZATION` comment block with a freshly generated one and refreshing the section headers. `-DisplayAvailableLayouts` reads `ZoneNameMappings` and `custom-layouts.json` (resolved via `Get-FancyZonesLayoutsPath`) to show the zone structure of every layout without touching any files: layouts are ordered by their `LayoutNumbers` hotkey slot, followed by any `custom-layouts.json` layouts absent from `LayoutNumbers` in file order; layouts without a `ZoneNameMappings` entry are still displayed (with unnamed zones); grid layouts render as ASCII grids and canvas layouts as textual per-zone listings via `Format-CanvasZoneListing`.

| Parameter                  | Description                                                                                                                           |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `-Layout`                  | Name of a specific layout to visualize (e.g. `MyWorkspace_PC`); matched against the layout file's base name.                          |
| `-All`                     | Process every layout file found recursively in the Layouts directory and its machine-specific subfolders.                             |
| `-DisplayAvailableLayouts` | List all available layout types with their zone names shown in position, in `LayoutNumbers` hotkey order; does not read or modify layout files. |
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

**See also:** [Set-WorkspaceWindowLayout](#set-workspacewindowlayout), [Configure Window Layout](../configuration/guides/window/configure-window-layout.md)

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

## [Wait-WindowsClosed](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Wait-WindowsClosed.ps1)

- **Description:** Polls the live window list until every window handed to it has gone, or a timeout expires, and returns the ones still open. `WM_CLOSE` is *posted*, not sent: it asks a window to close and returns immediately, so the window may go away in a few milliseconds or put up a save prompt and stay. A caller that checks straight away reports windows as refused when they were merely still closing; one that never checks cannot report a refusal at all.
- **Parameters:** -Window, -TimeoutMilliseconds (default: 1500), -PollIntervalMilliseconds (default: 250)
- **Usage:** `Wait-WindowsClosed -Window $postedWindows`, `Wait-WindowsClosed -Window $postedWindows -TimeoutMilliseconds 3000`

An empty result means they all closed. `Clear-WindowCache` runs before each poll - without it the check keeps reading the same pre-close snapshot and every window looks like it refused. Matching is by handle only: a window that closed and was replaced by a new window of the same application is a different window, and this deliberately does not wait for that one. An empty input collection returns immediately without enumerating anything. Used by [Close-Workspace](workflow.md#close-workspace) to tell "closed" from "refused" before it sweeps empty virtual desktops.

| Parameter                   | Type     | Default | Description                                                                                    |
| --------------------------- | -------- | ------- | ---------------------------------------------------------------------------------------------- |
| `-Window`                   | object[] | -       | Windows to wait on; any object exposing `.Handle` works, including `Get-WindowHandle` records. Mandatory (may be empty). |
| `-TimeoutMilliseconds`      | int      | `1500`  | How long to keep polling before giving up and reporting what is left.                          |
| `-PollIntervalMilliseconds` | int      | `250`   | Delay between polls.                                                                           |

```powershell
# Ask windows to close, then find out which ones actually did
foreach ($w in $targets) { [void][CloseWorkspaceWin32]::PostMessage($w.Handle, 0x0010, 0, 0) }
$refused = Wait-WindowsClosed -Window $targets
if ($refused) { "still open: $($refused.Title -join ', ')" }
```

**See also:** [Get-WindowHandle](#get-windowhandle), [Clear-WindowCache](#clear-windowcache), [Close-Workspace](workflow.md#close-workspace)

## [Write-AppliedFancyZonesLayouts](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Window/Functions/Write-AppliedFancyZonesLayouts.ps1)

- **Description:** Writes zone layouts for virtual desktops straight into FancyZones' `applied-layouts.json`. FancyZones records the layout applied to every (monitor, virtual desktop) pair in that file and watches it: an external write makes it reload the file and re-initialize the current desktop's work areas, and the work areas it creates when a desktop is switched to read their entry from the reloaded data, so writing a workspace's entries applies its layouts to every desktop at once, without switching to each one and injecting `Win+Ctrl+Alt+[Number]`. Each target names a monitor (EDID code and PnP instance path), a desktop GUID and a layout name from `custom-layouts.json`. The entry's device block is cloned from an entry FancyZones itself wrote for that monitor (serial number and monitor number are what FancyZones matches its work areas against), and the applied-layout block is derived exactly as FancyZones derives it from a custom layout: type `custom`, the grid's spacing settings, highest cell index + 1 as the zone count; a canvas contributes its zone count and sensitivity radius and takes the defaults for the rest. Entries that already hold the wanted layout are reported `AlreadyApplied` and leave the file alone unless `-Force`, which rewrites it so FancyZones reloads; every other entry in the file is preserved in place.
- **Parameters:** -Targets, -Force, -AppliedLayoutsPath, -CustomLayoutsPath
- **Usage:** `Write-AppliedFancyZonesLayouts -Targets @(@{ Monitor = 'DELA1A8'; MonitorInstance = '4&1cfdc60e&0&UID8262'; VirtualDesktop = '{413742B8-DC0B-4412-9D80-A2EAD2DE3829}'; LayoutName = 'Five' })`, `Write-AppliedFancyZonesLayouts -Targets $targets -Force`

The write is atomic: the content goes to a temporary file in the same directory that then replaces `applied-layouts.json` through `ReplaceFile`, and the file's last-write time is bumped afterwards, because FancyZones' watcher (a WIL folder change reader on `LastWriteTime`) compares that time with the one it saw last and a rename alone changes nothing it looks at. A file that does not parse is never overwritten: FancyZones treats a malformed file as empty, so a broken write would wipe every layout it knows about. A monitor FancyZones has never written an entry for is reported `NoDeviceEntry`, an unknown layout name `UnknownLayout`; both fall back to the shortcut pass in `Apply-FancyZones`. Returns `Written`, `WrittenAtUtc` (the stamp `Test-AppliedFancyZonesLayouts` waits past), the counts and one `Targets` record per input. The function does not confirm that FancyZones picked the change up; `Apply-FancyZones` does that with a probe shortcut and `Test-AppliedFancyZonesLayouts`.

| Parameter             | Type   | Default | Description                                                                                                  |
| --------------------- | ------ | ------- | ------------------------------------------------------------------------------------------------------------ |
| `-Targets`            | array  | -       | Monitor, MonitorInstance, VirtualDesktop (braces optional), LayoutName and an optional Label per target (Mandatory). |
| `-Force`              | switch | off     | Rewrite the file even when every target is already applied, so FancyZones reloads it.                        |
| `-AppliedLayoutsPath` | string | -       | Alternative `applied-layouts.json`; defaults to the FancyZones data directory under `%LOCALAPPDATA%`.        |
| `-CustomLayoutsPath`  | string | -       | Alternative `custom-layouts.json`; defaults to the FancyZones data directory under `%LOCALAPPDATA%`.         |

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

The Window module relies on specific external software. The **single source of truth** for the known-working, tested combination is the `TESTED VERSIONS` comment block in `Windows/PowerShell/Modules/Bootstrap/Data/WinGetApps.csv` - the table below mirrors it. Tested on **Windows 11 25H2** (build 26200). Pinning these versions ensures reliable operation and makes it immediately obvious when a breaking update occurs.

| Dependency                           | Version      | Install Method                                          | Pinned?                                              | Notes                                                                                             |
| ------------------------------------ | ------------ | ------------------------------------------------------- | ---------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| **Microsoft PowerToys** (FancyZones) | **0.100.2**  | `winget install Microsoft.PowerToys --version 0.100.2`  | Yes (0.100.2 via WinGetApps.csv)                     | Core dependency - provides zone layouts, keyboard shortcuts (`Win+Ctrl+Alt+N`), and snap behavior |
| **VirtualDesktop** PS module         | **1.5.11**   | `Install-Module VirtualDesktop -RequiredVersion 1.5.11` | Yes (`$pinnedModules`, Install-PowerShellModules.ps1) | Virtual desktop creation, window moving, desktop switching. Author: Markus Scholtes (PSGallery)   |
| **PowerShell**                       | 7.6.4        | `winget install Microsoft.PowerShell`                   | No (Latest)                         | Required for module loading and `Add-Type` compilation                                            |
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
4. If all tests pass, update every enforcement point in lockstep:
    - `Modules/Bootstrap/Data/WinGetApps.csv` - the `TESTED VERSIONS` comment block (the single
      source of truth) **and** the pinned `Microsoft.PowerToys` row below it
    - `Modules/Application/Functions/Install-PowerShellModules.ps1` - the `$pinnedModules`
      hashtable, for VirtualDesktop
    - `Modules/Tests/RequiredPesterVersion.txt` - the repo-wide Pester pin (the test harness,
      `Install-PowerShellModules`, and CI all read this one file)
    - This documentation section (it mirrors the CSV block)

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

> **Note:** Arbitrary spacing and arbitrary zone definitions (grid and canvas) are supported in `FancyZones/custom-layouts.json`. FancyZones insets edges that touch the work-area border by the full spacing value, and interior edges by `Floor(spacing/2)` per zone; a zone spanning multiple cells absorbs the spacing between them. `Get-FancyZoneCoordinates` replicates this exactly, so any spacing value works. `Test-FancyZonesConfiguration` validates the configuration (layouts, `ZoneNameMappings`, `LayoutNumbers`, `layout-hotkeys.json`) automatically at the start of every workspace open.

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

Zone names come from `ZoneNameMappings` in `Configuration.psd1`, which maps each human-readable name to a zone index per layout - layouts and their zone names are freely definable, and `Test-FancyZonesConfiguration` verifies the mappings agree with `custom-layouts.json`. The layouts shipped in this repo:

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

Layout entries can use the literal token `Browser` in `ProcessName` (and optionally `WindowTitle`) instead of a specific browser name. At match time, `Resolve-LayoutTokens` expands it to a regex covering every browser declared under `Configuration.Universal.Browsers` (Tor excluded - use `tor` explicitly for secure-browser layouts).

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

If the Window module stops working after a system update, check versions first. The tested
combination is tracked in the `TESTED VERSIONS` block in
`Windows/PowerShell/Modules/Bootstrap/Data/WinGetApps.csv`:

```powershell
# Check PowerToys version (pinned: 0.100.2 via WinGetApps.csv)
winget list --id Microsoft.PowerToys

# Check VirtualDesktop module version (should be 1.5.11)
Get-InstalledModule -Name VirtualDesktop | Select-Object Name, Version

# Roll PowerToys back to the pinned version if a manually installed newer release misbehaves
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
4. Run `Validate-Layout` to check the layout file
5. Run `Test-FancyZonesConfiguration` to check the FancyZones configuration (layouts, `ZoneNameMappings`, `LayoutNumbers`, `layout-hotkeys.json`)

### Virtual Desktop Issues

1. Ensure `VirtualDesktop` module is installed
2. Check that required desktops exist
3. Use `Ensure-VirtualDesktops` to create missing desktops
