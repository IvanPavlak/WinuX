# Changelog

All notable changes to **WinuX** are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). See [VERSIONING.md](VERSIONING.md) for how we version and release.

<!-- Sections, in order (omit any that are empty in a tagged release): Added · Changed · Breaking · Deprecated · Removed · Fixed · Security -->

## [Unreleased]

## [0.1.19] - 2026-08-01

### Fixed

- `Start-Win11Debloat` (Application module) ran the vendored `Win11Debloat.ps1` in the current session, which is PowerShell 7 - the one interpreter Win11Debloat cannot work under. Its app removal and system restore points depend on Windows PowerShell 5.1-only modules: the `Appx` module's `Get-AppxPackage` / `Remove-AppxPackage`, which upstream documents as failing there with "Operation is not supported on this platform" (`0x80131539`), and `Get-ComputerRestorePoint`, which PowerShell 7 does not ship at all. Upstream's note behind that guard (issue #675) is that a run under pwsh continues and silently fails to remove any apps while still reporting success - the behaviour of the currently vendored 2026.06.24 release. Release 2026.07.11 turns it into an explicit refusal instead: it detects `Core` edition, prints the interpreter to re-run under, and exits 1. Neither shape was visible from WinuX, because the exit code was never inspected and `Debloating with saved settings completed!` was printed unconditionally - under the red error, in the newer release's case. The script is now launched through `powershell.exe` with `-NoProfile -ExecutionPolicy Bypass -File`, the same interpreter and flags its own `Run.bat` uses, and a non-zero exit code is reported as an error instead of success. The child process inherits the console, so the interactive menu is unchanged, and inherits the elevated token from the session `Test-AdminPrivileges` has already verified, so no second UAC prompt appears; a `powershell.exe` that cannot be found skips the step with an error rather than attempting the run.

## [0.1.18] - 2026-07-30

### Fixed

- `Remove-VirtualDesktops -EmptyOnly` (System module) spent about four seconds doing roughly a hundred milliseconds of work, and the cost was a fixed tax rather than anything to do with how many desktops or windows were in play. The occupancy scan wrapped EVERY per-window `Get-DesktopFromWindow` / `Get-DesktopIndex` pair in the RPC retry ladder, so any window the desktop manager refuses to place burned all five attempts and their 250/500/1000/2000 ms backoff sleeps before being skipped - and Windows 11 always has at least one: `TextInputHost` ("Windows Input Experience") answers `TYPE_E_ELEMENTNOTFOUND` (`0x8002802B`) for its own window, forever. Retrying that is pointless by construction; the error is a property of the window, not of the RPC endpoint. The ladder now wraps the scan as a whole - window-level failures are skipped on the spot, and only a genuine RPC-unavailable error restarts the scan after `Reset-VirtualDesktopState` has reconnected the session's COM proxies. The abort-rather-than-guess behaviour is unchanged: an RPC failure that survives the ladder still returns `$false` instead of treating unknowable occupancy as "empty". Measured end to end against three empty desktops: 4098 ms before, 115 ms after; a run with nothing to clean up is now 15 ms.

### Changed

- `Remove-VirtualDesktops` (System module) reads desktop counts with `Get-DesktopCount` instead of `Get-DesktopList`. Only the count was ever used, but the list builds a row per desktop - a registry name lookup, a wallpaper-path query, and a current-desktop index walk, each re-enumerating every desktop over COM - which measured 8.1 ms per call at six desktops against 0.13 ms for the count. Default mode calls it once per removal, so the saving scales with the number of desktops being cleaned up. Two further reductions in `-EmptyOnly` mode: each distinct desktop's index is resolved once and reused for every other window sitting on it (`Get-DesktopIndex` re-enumerates the desktop list on each call, so this was previously paid per window), and the scan stops early once every desktop is known to hold a window. Behaviour is unchanged - same desktops removed, same messages, same summary.

## [0.1.17] - 2026-07-28

### Added

- `Set-TaskbarSettings` (System module): applies the whole Settings > Personalisation > Taskbar page from the new `TaskbarSettings` configuration section - one human-readable key per control on that page, in page order, with `$true`/`$false` for the checkboxes and toggles and a named PascalCase token for each dropdown (`Search = "Hide"`, `TaskbarAlignment = "Centre"`, `CombineTaskbarButtonsAndHideLabels = "WhenTaskbarIsFull"`, ...). Every control is a per-user `HKCU` registry value applied in one pass followed by a single `Restart-Explorer`, the same shape the vendored Win11Debloat uses for its own taskbar tweaks. Config-gated: the base configuration ships the section fully commented so a vanilla bootstrap changes nothing; forks opt in via `Configuration.local.psd1`. Runs during Bootstrap right after `Configure-Taskbar`, which owns a different surface entirely (which apps are *pinned*). Every managed control is reported on its own row: green = toggle on, red = toggle off, white = the selected dropdown token, yellow `[skipped]` = already at the configured value. Because most of these controls have no registry value at all until you change them in the Settings app, a missing value counts as a mismatch and is written explicitly, so the first run makes the state deterministic instead of "whatever this Windows build ships"; unknown keys, non-booleans on a toggle, and unrecognised dropdown tokens are each skipped with a warning naming the key rather than silently doing nothing.
- `TaskbarSettings` (configuration): the per-control section consumed by `Set-TaskbarSettings`, with every accepted dropdown token listed inline next to its key. Ships fully commented, so a vanilla bootstrap still leaves the taskbar page alone - but the commented lines are not placeholders. They are the taskbar WinuX recommends and its author runs on every machine (search hidden, task view off, buttons combined, bar auto-hidden), so the window layouts do the work instead of the shell chrome. Uncomment the lot to get exactly that, or cherry-pick individual controls.

### Changed

- Bootstrap phase 7 runs `Set-TaskbarSettings` where it previously ran `Set-TaskbarAutoHide -Auto`. Auto-hide is now one control among the rest of the page rather than its own provisioning step.

### Breaking

- `Set-TaskbarAutoHide` (System module) and the top-level `TaskbarAutoHide` configuration key are **removed**, folded into `Set-TaskbarSettings` and its `TaskbarSettings` section. Auto-hide was never a separate concern - it is the "Automatically hide the taskbar" checkbox on the very page `Set-TaskbarSettings` already drove, and keeping it apart meant two functions, two config keys, and a docs note in each explaining why the other one owned that checkbox. **Migration:** replace `TaskbarAutoHide = $true` with `AutomaticallyHideTheTaskbar = $true` inside the `TaskbarSettings` hashtable, and replace any `Set-TaskbarAutoHide -Auto` / `-Enabled` call with `Set-TaskbarSettings`. The base configuration shipped `TaskbarAutoHide = $false`, so a setup that never opted in is unaffected.

  The mechanism changed with it, which is what makes the setting durable. `Set-TaskbarAutoHide` used `SHAppBarMessage` (`ABM_SETSTATE`), the call the settings page makes, and its docs claimed Explorer persists the result to `StuckRects3` on exit. It does - but only on a GRACEFUL exit, and `Restart-Explorer` is a `Stop-Process`. So the moment auto-hide was applied in the same pass as any registry-backed taskbar control, the restart that pass performs discarded it: the fresh Explorer read the old bit back and the setting silently reverted, needing a second run to stick. Auto-hide is now written as what it actually is - bit `0x01` of byte 8 in `HKCU:\...\Explorer\StuckRects3\Settings`, read-modify-written so Explorer's surrounding bytes are preserved - and picked up by the same single Explorer restart as every other control. One run now applies the whole page. The trade is that a run changing ONLY auto-hide restarts Explorer where the old function did not; every other control on the page already required that restart. An unreadable `StuckRects3` skips the control with a warning rather than fabricating a blob Explorer owns.

## [0.1.16] - 2026-07-26

### Added

- `Invoke-RerunLastCommandExit` (Helper module): the scriptable process-exit seam for `Rerun-LastCommand`, mirroring `Invoke-TerminateWindowsTerminalTabsExit`. It runs `$script:RerunLastCommandExitAction` when a test seam is configured and otherwise calls `[Environment]::Exit(0)`. This is what makes the close-and-respawn tail of the rerun testable at all: without a seam, exercising that path terminates the Pester session.

### Fixed

- `Rerun-LastCommand` (Helper module) stranded Ctrl and Shift for the rest of the desktop session, deterministically, every time it ran. It closed the original window with a synthesized `Ctrl+Shift+W` - and that window hosts the very process doing the injecting, so Windows Terminal tore the process down INSIDE `SendWait`, before the Ctrl and Shift key-ups were injected. Both modifiers then stayed logically held: the fresh shell typed uppercase and PSReadLine read Enter as `Shift+Enter` so commands stopped submitting, and only locking and unlocking the session recovered it. This is the concrete cause behind the "terminal input locks up during workspace orchestration" known issue - not an orchestration race, and the one shape the existing self-heal architecture could never cover, because nothing runs after a process closes its own host window: the `Reset-KeyboardModifiers` call in this function sits BEFORE the injection, and no `finally` executes. The window is now closed by posting `WM_CLOSE` straight to its handle, which needs no focus and synthesizes no input - the pattern `Close-Project` and `Close-BrowserWindows` already use - so the `SetForegroundWindow` + 250 ms sleep dance is gone too, along with the risk of the hotkey landing on the wrong window if focus were stolen mid-flow. Independently of that root cause, the modifier heal now also runs as the last act before the process exits, so anything stranded by `Terminate-WindowsTerminalTabs`' legacy `Ctrl+Tab` / `Ctrl+C` / `Ctrl+W` fallback is released as well; nothing healed after those passes before. Reproduced 2 times out of 2 with a harness whose injecting shell was hosted by the window being closed (a variant where it was not did NOT reproduce, which is what pins the mechanism), and verified clean under the same harness with `WM_CLOSE`. One behavioral difference remains: when a tab survived `Terminate-WindowsTerminalTabs`, closing the window may now raise Windows Terminal's own close-all-tabs confirmation, which its `confirmCloseAllTabs` setting governs.

## [0.1.15] - 2026-07-26

### Fixed

- `Open-Terminal` (Application module) named every tab it opened without a `-TabTitles` entry `C:\Program Files\PowerShell\7\pwsh.exe`, most visibly the first tab of the window `Open-Workspace -Alongside` relaunches itself into. Given no `--title`, Windows Terminal falls back to the command line it was handed as the tab's starting title AND passes that same string to the spawned shell as its console title, so the path was both displayed and readable back as `$Host.UI.RawUI.WindowTitle` - which is why `Open-Workspace`'s alongside window probe, having flashed a marker into the title to identify its own hosting window, restored the path rather than a name. Untitled tabs are now titled `PowerShell`, exactly like a tab opened by hand from the default profile. The fallback is a STARTING title only, deliberately without the `--suppressApplicationTitle` that explicitly titled tabs still get: pinning the title would break both that alongside probe and `Terminate-WindowsTerminalTabs`' tab marker, which identify their own window by writing `$Host.UI.RawUI.WindowTitle` and reading it back. Cosmetic only; no other behaviour changes.

## [0.1.14] - 2026-07-26

### Added

- `Apply-FancyZones -Force` (Window module): skips the applied-layouts idempotency read and re-sends every layout shortcut. That state records what FancyZones was last TOLD to apply, not what its live zone grid actually is, so recovery paths cannot trust it - and without a way to bypass it, a re-apply aimed at repairing a stale grid reports "Already Applied" for every monitor and sends nothing.

### Fixed

- `Set-WorkspaceWindowLayout` (Window module) retries could not recover from a broken FancyZones, which is the failure they exist for. A window that will not land in its zone almost never means the window is stubborn - it means the zone grid the snap targeted was wrong: FancyZones down, crash-looping, or holding a stale in-memory grid. The retry only re-ran position -> snap -> verify against that same grid, so all three passes failed identically and the run escalated to a terminal respawn that could not fix it either. Two defects compounded: the retry's FancyZones check was a bare `Start-FancyZones`, which caches a successful readiness pass for 10 s - so back-to-back retries got a cached `$true` and did literally nothing, and even a real pass only proves the PROCESS is healthy, never that the workspace's zone grid is applied; and the window-only rerun's `Apply-FancyZones` was idempotent, so the applied-layouts state (still claiming the correct layout) skipped every monitor and the fresh shell snapped into the very same broken grid. Every retry now force-restarts PowerToys/FancyZones and re-sends the zone layouts with `Apply-FancyZones -Force`, and the window-only rerun forces its re-apply too. Covered by a reproduction harness in the Pester suite that models FancyZones liveness and live-grid state separately: both a stale grid hidden behind idempotency and a FancyZones that dies mid-pass now converge on the first in-process retry instead of escalating.
- `Confirm-WorkspaceWindowPositions` (Window module) named the wrong thing in its failure report. The label came from the LAYOUT ENTRY, whose `ProcessName` is a token-expanded regex for browser entries - so a mispositioned window was reported as `[(firefox|chrome|msedge|brave)]`, which names no window and reads identically for every browser entry in the layout. Failures now carry the matched window's real caption in `WindowTitle` (matching how snap failures already report), with the layout entry's own label preserved under the new `LayoutEntry` field. Failure objects also carry `ProcessName` now, which the workspace escalation path already read and always found empty.
- `Start-FancyZones` (Application module) announced work it did not do. The loading spinner was created before the readiness cache was consulted, so every cached no-op still printed a "Starting FancyZones" line - three in a row after a single retry reset (the reset's restart, then `Apply-FancyZones` and `Snap-AllWindows` each re-checking readiness). The cache is now resolved first and a cached call is silent.

## [0.1.13] - 2026-07-25

### Added

- `Resolve-TargetMonitor` (Window module): shared resolver that turns a monitor specifier into a monitor object. Accepts a 1-based index following `Get-MonitorInfo` order, a standardized label from `Get-MonitorSpecs` (`Primary`, `Secondary`, `Monitor3`, ...), or an exact device name. Extracted from `Move-Windows` so it and `Center-Windows` resolve `-Monitor` through one set of rules. It writes no console output, returning the resolved monitor alongside a ready-to-log `ErrorMessage` so each caller keeps its own logging and control flow; an empty specifier resolves to "no targeting requested" rather than an error.
- `Center-Windows -Monitor` (Window module): centers every matched window on one explicit monitor instead of deriving a monitor per window from its current position. `-OnPrimary` remains the shorthand for the primary monitor; the two are mutually exclusive parameter sets.

### Fixed

- `Reset-Windows` (Window module) no longer leaves a subset of windows centered on the wrong monitor. Collapsing the virtual desktops makes Windows migrate windows off the removed desktops, and FancyZones reacts to those arrivals by restoring each window to its remembered zone from `app-zone-history.json` - which records a monitor. `Center-Windows` then ran last and re-derived each window's monitor from its CURRENT position, so it centered the strays where they had drifted to, cementing the placement. Verified with an A/B on the same 35 windows: the move pass alone misplaced 0, and prefixing it with `Remove-VirtualDesktops` misplaced 8. `Reset-Windows` now passes its configured monitor through to `Center-Windows`, so the last pass re-asserts the intended target and the reset self-corrects regardless of what moved a window mid-run. Monitor identity is unreliable to begin with when two displays are the same model: identical panels can report the same EDID code and serial number, which is why `applied-layouts.json` accumulates several device identities for one physical monitor (`Get-DuplicateMonitorEdid` already detects the EDID collision for `Apply-FancyZones`, but the zone history has no such guard).
- `Move-Windows -Monitor` (Window module) now preserves each window's relative placement instead of slamming every window into a corner of the destination work area. The clamp read `[math]::Max(0, [math]::Min(1, $relativeX))`, and because the literals were integers PowerShell bound the `(int, int)` overloads and rounded the relative fraction to 0 or 1. Every coordinate the pass produced was therefore `0` or the work-area maximum, on every window, which the "preserve relative placement" logic was written specifically to avoid. The clamp now uses double literals.
- `Move-Windows` (Window module) verifies each monitor placement with `Wait-WindowRect` and re-applies it once when the window did not hold its position. `SetWindowPos` reports success for the CALL, so a window moved straight back by another window manager was still counted as repositioned.
- `Move-Windows` and `Reset-Windows` (Window module) no longer hide failures in normal mode. `Move-Windows` reported only moved / already-there / monitor-moved counts outside `Set-LogLevel Verbose`, so windows that failed to move or would not stay on the target monitor were silently dropped from the summary and a partial pass looked identical to a complete one; both are now reported with the affected windows listed. `Reset-Windows` also ignored `Remove-VirtualDesktops`' return value, so a failed desktop collapse - which changes how much work the move pass has to do - passed unnoticed; it now warns and continues.

## [0.1.12] - 2026-07-25

### Added

- `DefaultWorkspace` (configuration): names the workspace `Open-Workspace` opens when `[Enter]` is pressed with no input at the selection menu. Mirrors `DefaultWakeOnLanMachine` - the prompt names the configured default (`press [Enter] to open default workspace => Default`) instead of an anonymous "default workspace", so the offer cannot drift from the behaviour again. It is only honoured, and only advertised, when the named workspace actually has a `WorkspaceActions` entry; set it to `""` (or point it at a workspace with no actions) and the prompt becomes `press [Enter] to cancel`.

### Fixed

- `Open-Workspace` (Workflow module) now opens the default workspace when `[Enter]` is pressed at the selection menu, as its prompt and the docs have always claimed. The `Resolve-Selection` splat set `AllowEmptyPromptResponse` but no `DefaultOptionIndex`, so an empty response returned `$null`, and the only fallback - a hardcoded `@("Default")` - had shipped commented out since the initial release. Pressing Enter therefore fell straight into "No valid workspaces selected! Exiting..." and opened nothing. The fallback is now driven by the new `DefaultWorkspace` config key rather than a hardcoded name, so forks that rename their workspaces are not silently broken, and it applies to the genuinely interactive Enter only: a mistyped `-Workspace` argument still exits instead of silently opening the default.

## [0.1.11] - 2026-07-24

### Added

- `Start-Application -RequireMainWindow` (Application module): scopes the "already running" check to processes that own a visible main window, for apps that keep a windowless helper alive under their own process name. Sibling to `-ProcessPathFilter`, which solves the same class of false positive for apps that share a process name with something else.

### Fixed

- `Open-WhatsApp` (Application module) no longer reports "WhatsApp is already running!" and opens nothing when no WhatsApp window exists. When a notification arrives while WhatsApp is closed, Windows COM-activates a background push notification host (`WhatsApp.Root.exe -RegisterForBGTaskServer /nowindow /pushnotification -Embedding`) that owns no window but runs under the same `WhatsApp.Root` process name as the UI, so the process-name check matched it. That made the failure intermittent (it depended on whether Windows had activated the host) and unfixable via `Kill-All`, which only clears the host until the next notification. `Open-WhatsApp` now passes `-RequireMainWindow`.

## [0.1.10] - 2026-07-24

### Added

- `Wait-WindowRect` (Window module): polls a window's rectangle until it matches expected bounds within a tolerance or a time budget elapses, with an immediate first check. Replaces the "fixed sleep, check once" pattern around FancyZones snap verification, which both wasted time when a snap landed quickly and false-failed when FancyZones processed the input slower than the delay - escalating into the ~410 ms shift-drag fallback and, at worst, full workspace reruns.
- `Get-WindowsTerminalTabTitles` (Helper module): reads a Windows Terminal window's tab titles through UI Automation - no focus changes, no keystrokes. Returns `$null` (never an empty array) when the tabs cannot be read, so callers can fall back to the legacy Ctrl+Tab cycling.
- `Close-WindowsTerminalTab` (Helper module): closes one Windows Terminal tab by exact title by invoking its UIA close button. Returns `$false` when the tab or its close button cannot be found, so callers can fall back to the legacy path.
- `Wait-ForWorkspaceWindows -CollectiveStabilitySeconds` (Window module): the old always-on collective settle after every window is individually stable is now opt-in (default 0). Individual stability tracking already resets on any change, so the sequential collective phase added a guaranteed +1 s to every workspace open, including idempotent re-runs.
- `Wait-ForWorkspaceWindows -ProcessAbsentGraceSeconds` (Window module): abandons a layout entry when no window has ever matched it AND no live process matches its process pattern after the grace period (default 10 s; 0 disables). A dead or mistyped app previously burned the entire wait timeout (60 s in the workspace flow). Abandoned entries are reported in the result's new `Abandoned` list, and partial window-state snapshots are now returned on failure so title-drift fallbacks keep working for the windows that did stabilize.
- `Snap-AllWindows -WindowHandles` (Window module): `-All` mode can now be restricted to an explicit handle list. The simple-layout flow resolves each window's desktop once up front and passes per-desktop lists, replacing the per-pass `-CurrentDesktopOnly` filtering that paid two COM roundtrips per window on every desktop pass (and desktops with no windows skip the switch entirely).
- `ReRun-LastCommand -Command` (Helper module): reruns exactly the given command instead of scraping PSReadLine history. The shared history file is written incrementally by every open pwsh session, so "most recent line" could be a command typed in another window - which the respawned shell would then blindly execute. `Open-Workspace` records its resolved invocation (post-menu workspace names, project, flags) in `$env:WORKSPACE_RERUN_COMMAND` and the escalation paths pass it through.

### Changed

- `Set-WorkspaceWindowLayout` (Window module) retries failed window layouts IN-PROCESS before respawning the shell: the position -> snap -> verify pipeline runs up to two extra passes (refreshing the existing-window snapshot so already-correct windows are skipped by the position check), for `-Alongside` mode too, which previously had no retry at all. The terminal respawn - which kills every other WT tab, pays a full profile/module reload in a fresh shell, and re-runs the whole action list (15-45 s per attempt) - is now the last resort instead of the first response. Verification (in-loop and in the respawned run) always covers the FULL layout config.
- `Terminate-WindowsTerminalTabs` (System module) closes tabs via UI Automation first - each tab's close button is invoked directly, with no focus changes and no synthesized keystrokes (the old focus-then-Ctrl+W pattern typed into whatever window actually had focus, closing the user's browser tab if they clicked mid-flow). The legacy cycling pass remains as automatic fallback, the SendKeys retry-verification pass only runs when something actually survived, the current tab is identified from UIA tab titles even when it is not the active tab, and the hosting-WT parent chain is resolved via PS7's `Process.Parent` (the `Get-CimInstance` WMI walk cost 0.2-0.8 s and ran even for `-OnlyCurrent`, which never used it).
- `Test-TerminalTabsAlreadyOpen` and `Open-ProjectTerminals`'s InSameShell auto-detect (Workflow module) read tab titles via `Get-WindowsTerminalTabTitles` instead of foregrounding every WT window and Ctrl+Tab-cycling through its tabs (~1-2 s per open and a focus-stealing hazard); the cycling passes remain as fallback.
- `Open-Terminal` (Application module) chains all tabs of one call into a single `wt` invocation (`new-tab ... ; new-tab ...`) - Windows Terminal processes the subcommands of one command line strictly in order, guaranteeing tab order without one process spawn + 25 ms settle per tab. `Open-ProjectTerminals` (Workflow module) queues consecutive pwsh tabs per project and flushes them as one such call; WSL tabs flush the queue first so on-screen order matches the configured order.
- `Start-FancyZones` (Application module) skips the PID-stability sampling (4 samples, 750 ms of fixed sleeps) when the FancyZones process has been alive for more than ~5 s - a long-lived process cannot be mid-crash-loop - and caches a successful readiness verification for 10 s (cleared by `-ForceRestart` and failed checks). One workspace open calls this 2-4 times; previously each call paid the full ~800 ms dance even with PowerToys up for hours. Also fixes the startup progress line printing nonsense ("40s / 10s") due to dividing by 50 instead of 1000.
- `Test-RpcServerHealth` (System module) caches successful `-Probe` results for 8 s; failures are never cached, so recovery paths always re-verify. Each probe spins up a fresh runspace plus service checks, and one workspace open runs the preflight several times seconds apart.
- `Move-WindowToVirtualDesktop` (Window module) returns immediately when the window is already on the target desktop (every workspace window is desktop-moved from two code paths per open, so this is the common case) and verifies a real move immediately-then-polls instead of a blind 25 ms sleep with a single check. The new `$script:LastMoveWindowToVirtualDesktopResult.Moved` lets `Set-WindowLayouts` pay its settle delay only after real moves.
- `Set-WindowPosition` (Window module) pays the restore settle only when the window was not already in the normal show state, and the fixed post-`SetWindowPos` delay is gone (every caller verifies the rect or settles on its own schedule). The unconditional 2×25 ms cost ~35 calls per open across the positioning pipeline. `Resize-Windows` single-handle mode serves from the window cache's own 50 ms TTL instead of forcing a cache clear + full re-enumeration per call, and no longer prints a per-window success line in percent mode (first-open normalization spammed one line per window).
- `Set-WorkspaceWindowLayout` (Window module) first-open normalization resizes only the windows that this open actually created - the non-alongside branch previously shrank EVERY visible window on the machine to 70%, including unrelated apps, only for the layout pass to reposition the workspace ones again. The pre-snap resize uses the module's shared 20 px tolerance instead of 0 (apps that self-adjust by a pixel were re-positioned forever and never converged), and the desktop-count mismatch case delta-resizes via one `Ensure-VirtualDesktops` call instead of remove-all-then-recreate.
- Browser first-tab normalization (`Set-WorkspaceWindowLayout`, Window module) no longer probes tab counts with a full UIA tree walk per browser window (routinely hundreds of ms whose only purpose was skipping a harmless Ctrl+1), no longer resets the active tab of every browser window on the machine, and skips windows already showing a wanted title (re-runs previously Ctrl+1'd a correctly-matched window off its matching tab). Pre-existing windows are only touched when some browser entry's title currently matches no window at all.
- `Start-Application` (Application module) caches the resolved AppUserModelID per package name for the session - the wildcard `Get-AppxPackage` + manifest parse cost 0.5-2 s on every launch of a Store app; a stale cached AUMID (package updated) is evicted and the error rethrown.
- `Focus-VirtualDesktop` (Window module) checks Windows Terminal windows first and stops at the first window on the target desktop - only one focus target is ever used, so resolving every window's desktop (two COM calls each) wasted 0.2-0.6 s at the end of every open.
- `Get-NextAvailableDesktopIndex` (Window module) uses the cached VirtualDesktop module loader instead of a `Get-Module -ListAvailable` disk scan per call, and returns `$null` instead of `0` when the desktop count cannot be determined; `Open-Workspace` skips that workspace's `-Alongside` open with a clear error. The `0` fallback silently opened the new workspace on top of the current one - the exact thing `-Alongside` exists to prevent.

### Fixed

- `Resolve-Selection` (Helper module) returned from an invalid hierarchical selection with a bare `break`, which propagates out of the function into the nearest loop in the CALLER - one typo'd browser-group or workspace name silently killed every remaining action of `Open-Workspace`'s action loop, uncatchable by try/catch. It now returns `$null`, which every caller already handles.
- `Apply-FancyZones` (Window module) lost every "Shortcut Sent"/"Failed" record appended inside its apply scriptblock (`+=` on a scriptblock parameter rebinds a scope-local copy), which kept the applied count at 0, made the applied-layouts cache invalidation dead code, and returned an incomplete result set. The results are a `List` with reference semantics now.
- `Apply-FancyZones` (Window module) injected the layout hotkey a fixed 10 ms after `Switch-Desktop` - the switch is asynchronous, so a slow switch recorded the layout under the PREVIOUS desktop's GUID (silent wrong-desktop layout that later failed snapping into the rerun path). Every switch is now confirmed via `Wait-DesktopSwitch` before injecting; unconfirmed switches skip that desktop loudly, including the return-desktop re-apply.
- Duplicate-EDID monitors (two identical models) no longer disable FancyZones idempotency permanently: newer FancyZones schemas record a per-device `monitor-instance`, `Get-AppliedFancyZonesState` stores instance-qualified keys alongside the EDID-only ones, and `Apply-FancyZones` prefers them - the skip is only disabled when instance data is genuinely missing (old schema).
- Window-only workspace reruns applied a single filtered layout entry: `Snap-AllWindows` aborts its pass at the first exhausted window, so entries after it were never snapped, stranded at their 95% inset size, and never verified - and the success-path `CurrentLayout.txt` snapshot shrank to one window, breaking zone pinning for identically-titled windows on the next open. Reruns now apply the full config (idempotent skips keep it cheap), verification covers every entry, and the snapshot stays complete.
- Workspace rerun markers (10-minute User-scope mirrors, not workspace-scoped) leaked when the respawn failed to spawn: `Rerun-LastCommand` called `[Microsoft.VisualBasic.Interaction]::AppActivate` without loading the assembly, aborting AFTER the markers were persisted - the next `Open-Workspace` of ANY workspace then silently ran in window-only retry mode with a stale filter. The assembly is loaded in a try/catch now, and both escalation sites clear the one-shot markers whenever `ReRun-LastCommand` returns without ending the process.
- `Terminate-WindowsTerminalTabs -OnlyCurrent` ends the flow via `[Environment]::Exit(0)`, which skips every `finally` block - `Open-Workspace`'s elapsed summary never printed and the `Reset-KeyboardModifiers` self-heal (stuck-modifier state is OS-global and survives the process) never ran when the last action closed its own tab. `Open-Workspace` now prints the summary and releases modifiers before executing a terminating tab action, and the exit seam itself releases modifiers as its last act.
- `Confirm-WorkspaceWindowPositions` (Window module) declared a browser entry "window not found" when its tab title changed between positioning and verification (page finished loading) - escalating into terminal-respawn reruns that can never fix a title mismatch. Before failing an entry, the verifier now accepts the tracked positioned window whose expected bounds and desktop match, provided its handle is still alive and unclaimed.
- `Remove-VirtualDesktops -EmptyOnly` (System module) ground through a 5-attempt retry ladder (~4 s of backoff plus a module reset per retry) for EVERY window when the RPC endpoint was genuinely dead - minutes of retry storm after the preflight repair had already failed. The first exhausted RPC-classified ladder now trips a circuit breaker and the cleanup aborts with `$false`, since window occupancy cannot be trusted without RPC.
- `Test-BrowserGroupAlreadyOpen` (Application module) counted ANY "Problem loading page" window as an already-open localhost group - an unrelated failed page anywhere suppressed opening the group (e.g. the project's Swagger tab never opened). The failed-load heuristic now requires the error window's title to carry host/port evidence from the group's own localhost URLs.

## [0.1.9] - 2026-07-24

### Added

- `Reset-VirtualDesktopComProxy` (Window module): reconnects the `VirtualDesktop` module's cached COM proxies to the current shell via reflection. The module compiles a `DesktopManager` class whose static constructor creates the COM connections once per process and caches them in static fields; after an Explorer restart those connections are permanently severed and every VirtualDesktop call fails with "The RPC server is unavailable" (`0x800706BA`) - re-importing the module can never fix it because the compiled assembly stays loaded and the constructor never runs again. This function replays that constructor (fresh ImmersiveShell service provider, all static COM fields rebuilt, including the Windows 10-only `VirtualDesktopManagerInternal2`), recovering the session in place without a new shell.
- `Test-VirtualDesktopComHealth` (Window module): probes THIS session's VirtualDesktop COM state with a live `[VirtualDesktop.Desktop]::Count` roundtrip on a background runspace in the current process, under a hard timeout. Detects stale session proxies (fail fast with `0x800706BA` / `0x80010108`) and hung endpoints (timeout); a healthy warm probe completes in milliseconds. Returns `Healthy` / `TimedOut` / `Error`.
- `Test-RpcUnavailableError` (Helper module): classifies an ErrorRecord, exception, or message string as an RPC availability failure (`0x800706BA`, `0x800706BE`, `0x80010108`, `0x800401FD` and their message texts). Walks the full `InnerException` chain and compares HRESULTs numerically, so wrapped failures (e.g. a `TypeInitializationException` around the COM error) and localized Windows error text classify correctly.

### Fixed

- Workspace orchestration no longer dies with "The RPC server is unavailable. (0x800706BA)" when Explorer restarted earlier in the session (taskbar configuration, icon-cache rebuild, theme changes) - the failure that aborted `Open-Workspace` at the `Ensure-VirtualDesktops` step and forced a new shell:
  - `Reset-VirtualDesktopState` (Window module) previously only did `Remove-Module` + `Import-Module`, which is a no-op for the actual stale state (verified: the re-imported module reuses the same cached COM proxies). It now reconnects the compiled type's static COM proxies via `Reset-VirtualDesktopComProxy` first, then reloads the cmdlet layer, and reports success only after a live in-process roundtrip verifies the session works. Every existing caller (`Snap-AllWindows`, `Focus-VirtualDesktop`, `Remove-VirtualDesktops` retry hooks, rerun flows) inherits the working recovery.
  - `Test-RpcServerHealth -Probe` (System module) probed in a `Start-Job` child process, which builds its own fresh COM connections - after an Explorer restart it reported "healthy" while the current session stayed broken, so recovery never engaged for the state that mattered. The probe now runs in-process via `Test-VirtualDesktopComHealth` with the same timeout semantics, and is ~100x faster when healthy (no child `pwsh` spawn or module import).
  - `Ensure-VirtualDesktops` (Window module) had no RPC recovery hook at all (unlike `Remove-VirtualDesktops`), so its retries reused the same dead proxies and always failed. It now uses the shared live-probe preflight (5 attempts / 250 ms, matching `Remove-VirtualDesktops`) and reconnects the session between retries when the failure is RPC-classified. The "known issue" comment about failing near `Set-Wallpaper` is gone - that interaction self-heals now.
  - `Repair-RpcServer` (System module) runs `Reset-VirtualDesktopState` as its primary per-attempt recovery step (its old `Remove-Module` step could not repair anything), keeps the elevated best-effort service restarts, and only terminates PowerToys from the second attempt on - a session whose own proxies were stale recovers without collateral damage.
  - `Restart-Explorer` (System module) proactively reconnects the session's VirtualDesktop COM state after restarting the shell (bounded retries while the new Explorer instance re-registers its COM classes), so the next workspace command starts healthy instead of tripping over severed proxies. Sessions that never loaded the VirtualDesktop types skip this entirely.
  - `Set-WorkspaceWindowLayout` (Window module) upgrades its RPC preflight to the live probe (`Get-RpcRetryPolicy -Probe`) - previously reserved for rerun branches because the child-process probe was too slow - so a stale session is repaired before any desktop reconfiguration begins.
  - `Remove-VirtualDesktops` (System module) classifies retry errors via `Test-RpcUnavailableError`, so RPC failures wrapped in other exception types (or localized) still trigger the reconnect instead of exhausting retries.

## [0.1.8] - 2026-07-20

### Added

- `Reset-KeyboardModifiers` (Window module): releases modifier keys (Shift/Ctrl/Alt/Win, left/right/neutral variants) that the session reports as logically held down, plus optionally a stranded left mouse button (`-IncludeMouseButton`). This clears the stuck-modifier state an interrupted synthesized-input sequence leaves behind - the "terminal input locks up during workspace orchestration" known issue - in place, without signing out. No-op when nothing is stuck; toggle keys (Caps Lock, Num Lock) are never touched.

### Fixed

- Workspace orchestration no longer requires a sign-out when a synthesized-input sequence is interrupted and a modifier key stays logically held (typed letters arrive as caps, Enter stops submitting commands):
  - `ShiftDragSnap` (Window module, `WindowNative.cs`) - the ~400 ms window where Shift and the left mouse button are held for the FancyZones drag now releases both in a `finally` block, and the Shift press/release event flags are symmetric (the press previously carried `KEYEVENTF_EXTENDEDKEY`, the release did not), so a failure mid-drag cannot strand them.
  - `SendKeyCombination` (Window module, `WindowNative.cs`) - the `SendInput` result is now checked; a partially inserted batch (key-downs in, key-ups cut off) is immediately compensated with explicit key-ups for every key in the combination.
  - The orchestration flow self-heals at its checkpoints: `Snap-AllWindows` clears stuck modifiers at pass start, before each snap retry, and (mouse button included) when a pass fails; `Set-WorkspaceWindowLayout` and `Rerun-LastCommand` clear them before a rerun respawns the shell; `Open-Workspace` clears them when the flow ends. A stuck modifier previously also corrupted the snap combos themselves (a held Shift turns `Win+Up` into `Win+Shift+Up`), so snap retries now converge instead of repeatedly failing into the rerun loop.

## [0.1.7] - 2026-07-20

### Changed

- `Terminate-AllProcessesByName` (System module) reads its target list from the new `Universal.TerminateProcessNames` configuration key instead of a hardcoded list. The base configuration ships a minimal example (`Code`); keep your real cleanup targets in `Configuration.local.psd1` (the override replaces the array wholesale on merge). When the list is absent or empty the function warns and terminates nothing.
- `Terminate-AllProcessesWithVisibleWindows` (System module) reads its always-excluded process names from the new `Universal.VisibleWindowExclusions` configuration key instead of a hardcoded list; browser processes from `Universal.Browsers` are still excluded automatically. The base configuration ships the full previous default list (`Rainmeter`, `WindowsTerminal`, `Docker Desktop`, `obs64`, and the three PowerToys processes - those are load-bearing, never remove them). When the list is absent or empty the function warns and terminates nothing, since running without exclusions would force-kill `WindowsTerminal` - the very shell executing the cleanup.

### Removed

- `Start-Application -ExecutableName`: the `AppxPackage` start method no longer launches an executable out of the package's install folder, so the parameter is gone. Callers migrate by dropping `-ExecutableName` from `AppxPackage` invocations - the app to activate is resolved from the package manifest automatically (see Fixed).

### Fixed

- `Start-Application` (Application module): the `AppxPackage` method failed with "Access is denied" for packaged UWP/Store apps - their executables live under the ACL-locked `WindowsApps` folder and cannot be started directly with `Start-Process`. The method now resolves the app's AppUserModelID (`PackageFamilyName!AppId`) from the package manifest and activates it through `shell:AppsFolder`, the supported launch path for packaged apps. `Open-WhatsApp`, the method's only shipped caller, works again.
- WhatsApp Desktop actually runs as `WhatsApp.Root`, not `WhatsApp`, so `Open-WhatsApp`'s already-running guard never detected a running instance and `Clear-WhatsAppLocalStorage` never stopped the app before clearing its storage. Both now target `WhatsApp.Root` (the default `Terminate-AllProcessesByName` cleanup target moved into configuration - see Changed).

## [0.1.6] - 2026-07-15

### Changed

- `Configure-Taskbar` (System module) now machine-scopes the taskbar pin list: each `TaskbarConfiguration` row may carry a `Machine` field (`All`, `Test`, `PC/Laptop`, ...) matched against the current machine type through `Test-MachineTypeScope` — the same gate the app CSVs use — so one list drives every machine. A row that omits `Machine` (or leaves it blank) defaults to `All`, preserving the previous "pin everywhere" behavior for untagged rows. The shipped `Configuration.psd1` list is a tagged example; keep your real, machine-specific list in `Configuration.local.psd1` (it replaces the base array wholesale on merge).
- `Configure-Taskbar` and `Unpin-TaskbarApps` (System module) now write the generated `taskbar_layout.xml` directly to a machine-local path (`PathTemplates.TaskbarLayoutFile`, default `C:\ProgramData\provisioning\taskbar_layout.xml`) that the `StartLayoutFile` policy points at, instead of writing it into the repository and symlinking the provisioning path to it. The layout is produced entirely from configuration, so nothing needs to be versioned and no symlink is created; each machine keeps its own copy. On a machine provisioned by the old design, a pre-existing symlink at that path (live or dangling) is removed before writing, so the first run migrates cleanly to a real file instead of writing back through the link into the repo.

### Removed

- The versioned `Windows/TaskbarConfiguration/taskbar_layout.xml` file and the `SymbolicLinks.TaskbarConfiguration` / `PathTemplates.TaskbarConfigurationDir` configuration keys. The taskbar layout is now generated straight to its machine-local path (see Changed), so the committed copy — which had drifted out of sync with `TaskbarConfiguration` — and its symlink are no longer needed.

### Fixed

- `Rebuild-IconCache` (System module) no longer surfaces a `Remove-Item: … cannot find the file specified` error while clearing the icon cache. With Explorer stopped, a file enumerated in the cache folder can vanish before it is deleted; the cleanup now checks the folder exists, re-checks each file immediately before removing it, and ignores per-file failures — so nothing is removed when there is nothing to remove.

## [0.1.5] - 2026-07-15

### Added

- `Test-MachineTypeScope` (Bootstrap module): the single gate behind every machine-scoped data source - the `Machine` column of the WinGet/Scoop/Chocolatey CSVs and `BootstrapConfig.PersonalSteps`. Splits a scope like `PC/Laptop` on `/`, matches case-insensitively, treats `All` as the wildcard, and validates every token against `ValidMachineTypes`: an unknown token (e.g. the typo `Labtop`) is reported via `Write-LogError` together with its data source and the list of valid values, and contributes nothing to the match - a misspelled scope can no longer silently install or skip anything.
- `Invoke-PersonalSteps` (Bootstrap module): runs the fork-defined `BootstrapConfig.PersonalSteps`, extracted out of `Bootstrap` into its own exported function. Entries are now machine-gated: a plain function name runs on every machine type (exactly as before), while `@{ Function = "Install-MyTool"; Machine = "PC/Laptop" }` runs only where its `Machine` scope matches - mirroring the app CSVs' `Machine` column.

### Changed

- `Install-WingetApps`, `Install-ScoopApps`, and `Install-ChocolateyApps` (Application module) route their `Machine`-column filtering through `Test-MachineTypeScope`, so CSV rows gain the same unknown-token validation instead of three copies of a silent inline filter.

### Fixed

- `Test-AdminPrivileges` (Helper module): the elevate-and-rerun offer replayed the immediate caller's source line, which at call depth two or more is an engine line such as `& $stepName` - the fresh elevated shell has no such variable, so the rerun died with "The expression after '&' in a pipeline element produced an object that was not valid". It now replays the outermost call-stack frame that recorded a line - the command the user actually typed - with unchanged behavior for every existing depth-one caller.

## [0.1.4] - 2026-07-11

### Added

- The **Custom area** (`Modules/Custom` + `docs/custom`): a fork-owned half of the module tree, laid out as a mirror of `Modules/`, where a fork keeps the functions and whole modules that are not (yet) part of upstream WinuX. Upstream ships only the aggregator (`Custom.psd1` + `Custom.psm1`) and a README/landing page; a fork adds function files under `Custom/<Module>/Functions/`, their tests under `Custom/<Module>/Tests/`, and man-style docs under `docs/custom/<module>.md`. Because upstream never writes inside those payload paths, an upstream pull never conflicts with a fork's own code, and promoting something into WinuX later is a mechanical `git mv`. The `Custom` module autoloads lazily like every engine module - its `FunctionsToExport` ships empty and each fork lists its own functions there - and the loader skips, with a warning, any payload file whose name would shadow an existing engine function, so the Custom area only ever adds behavior. `Load-PathConfiguration` registers `Modules\Custom` as an additional module root so whole fork-owned modules (`Custom/<Name>` with their own manifest) autoload too. See the [Fork Model](docs/contributing/fork-model.md) and `Modules/Custom/README.md`.
- `Reload-WinuXModules` (System module): removes and re-imports every WinuX module, additionally scanning `Modules/Custom` for whole fork modules. Replaces `Reload-CustomModules` (see Changed).

### Changed

- Renamed `Reload-CustomModules` to `Reload-WinuXModules` (System module) to remove the ambiguity the Custom area introduces ("custom modules" previously meant the project's own modules). No compatibility alias is kept: update any call sites or aliases to the new name. `Reload-PowerShellProfile` calls it internally and is otherwise unchanged.
- `Run-Tests` (Tests module) now also discovers Pester tests under the Custom area (`Modules/Custom/<Module>/Tests`), so fork functions meet the same test bar as engine functions.
- `Test-ManifestCompleteness` (Helper module) and the "Manifest Completeness" Pester test now also verify the Custom area: every `Custom/<Module>/Functions/*.ps1` must be listed in `Custom.psd1`, and a whole fork module is checked against its own manifest. Both pass unchanged on a pure-upstream setup, where the Custom area is empty.
- `List-Functions` (Helper module) now parses `docs/custom/*.md` alongside `docs/modules/*.md`, so `-ListDiscrepancies` checks fork functions against the loaded `Custom` module exactly as it does engine functions.

## [0.1.3] - 2026-07-10

### Added

- `Open-Project -InSameShell` (Workflow module): when explicitly passed, overrides the configured `InSameShell` value of the `Open-ProjectTerminals-Or-RunProject` action so the project's terminal tabs open in the caller's Windows Terminal window. Used by `Open-Workspace -Alongside` to gather all tabs in the relaunched shell window.

### Changed

- `Open-Workspace -Alongside` (Workflow module) now always runs in a completely new shell: the invocation relaunches itself in a fresh Windows Terminal window and hands the calling shell its prompt back immediately. The new window is created under an explicit window ID that is passed to the relaunched shell via `WT_WINDOW_ID`, terminal-opening actions inside it are forced to `-InSameShell` so the workspace's terminal tabs join that exact window (never the most-recently-used one), the window layout places the new window on the workspace's virtual desktops like any other workspace window, and a configured `Terminate-WindowsTerminalTabs -OnlyCurrent` closes the now-redundant bootstrap tab as its final step.
- `Open-Terminal -InSameShell` (Application module) targets the exact caller window via `$env:WT_WINDOW_ID` when the calling shell knows its own window ID, falling back to window ID 0 as before. Windows Terminal resolves `-w 0` to the *most recently used* window, so with multiple terminal windows open the fallback can land tabs in a different window than the caller's - setting `WT_WINDOW_ID` removes that ambiguity.

### Fixed

- `Open-Workspace -Alongside` (Workflow module) is far less prone to failing partway through with virtual-desktop "RPC server may be unavailable" errors (or a silently ignored `Switch-Desktop`). The Windows `VirtualDesktop` COM/RPC session that creating, switching, and removing desktops relies on tends to go stale in a long-running shell, and `-Alongside` is the heaviest user of those calls (it creates desktops to the right of existing ones, moves the new windows onto them, and prunes empties). Because the whole flow now runs in a brand-new shell (see Changed), those calls execute against a fresh RPC session from the start, which circumvents the stale-session failures in practice - it does not fix a session wedged outside the WinuX process, hence "far less prone" rather than "never".

## [0.1.2] - 2026-07-09

### Changed

- `Configure-NerdFont` installs far fewer files, so the bootstrap font step finishes in a fraction of the time. `JetBrainsMonoNerdFont/` now ships only the four faces the shipped configuration actually renders - Regular, Bold, Italic, and Bold Italic of `JetBrainsMono Nerd Font` - instead of the full file family. Windows Terminal, Oh My Posh, and FastFetch are visually unchanged: they only ever request that one face at normal and bold weight, and the full Nerd Font glyph/icon set is present in every face.

### Removed

- Unused files from `JetBrainsMonoNerdFont/`: the `Mono` and `Propo` spacing variants, the ligature-free `NL` family, and every weight other than Regular and Bold (Thin, ExtraLight, Light, Medium, SemiBold, ExtraBold, and all their italics). Nothing in the shipped configuration referenced them. Forks that point a terminal or editor at one of these faces should install that variant themselves.

## [0.1.1] - 2026-07-09

### Added

- `Set-VisualEffects` (System module): applies the Performance Options "Visual Effects" settings programmatically from the new `VisualEffects` configuration section - one human-readable boolean per dialog checkbox, written via the registry and `SystemParametersInfo`. Config-gated: the base configuration ships the section fully commented so a vanilla bootstrap changes nothing; forks opt in via `Configuration.local.psd1`. Runs during Bootstrap right after `Set-TaskbarAutoHide`. Every managed effect is reported on its own colored row: green = enabled, red = disabled, yellow `[skipped]` = already at the configured value.
- `Write-LogStep -Style` (Logging module): render a step row in another level's color (e.g. a green/red outcome row) while keeping the plain Step layout, visibility, and STEP file-log tag.

### Changed

- Versioning policy (`VERSIONING.md`): below 1.0, `0.x.0` releases are reserved for milestone-ladder gates, and backward-compatible additions that land between milestones ship as `0.1.x` patch releases. The strict SemVer split (new function/config option = MINOR) resumes at 1.0.0.

## [0.1.0] - 2026-07-08

The first public release of WinuX.

### Added

- The whole system, in its first public form: a one-command PowerShell bootstrap that takes a fresh Windows 11 install to a fully configured machine - system settings, package managers (WinGet/Scoop/Chocolatey), dotfile symlinks, repositories, themes, and workspace automation - all driven by a single `Configuration.psd1` plus a personal `Configuration.local.psd1` override.
- Multi-machine support via hostname-detected machine types; ships the minimal, VM-ready `Test` profile - add your own types by configuration alone.
- The fork model: a personal config override that never conflicts with upstream pulls, and `merge=ours` protection for fork-owned files.
- A docsify documentation site (GitHub Pages) with a man-style reference for every function.
- Governance and licensing: MIT license, contributor guide, code of conduct, security policy, and third-party notices.
- CI: the full Pester suite on every pull request, and a release workflow that builds `WinuX.exe` from every version tag and attaches it - with a SHA-256 checksum - to the GitHub release.

[Unreleased]: https://github.com/IvanPavlak/WinuX/compare/v0.1.19...HEAD
[0.1.19]: https://github.com/IvanPavlak/WinuX/compare/v0.1.18...v0.1.19
[0.1.18]: https://github.com/IvanPavlak/WinuX/compare/v0.1.17...v0.1.18
[0.1.17]: https://github.com/IvanPavlak/WinuX/compare/v0.1.16...v0.1.17
[0.1.16]: https://github.com/IvanPavlak/WinuX/compare/v0.1.15...v0.1.16
[0.1.15]: https://github.com/IvanPavlak/WinuX/compare/v0.1.14...v0.1.15
[0.1.14]: https://github.com/IvanPavlak/WinuX/compare/v0.1.13...v0.1.14
[0.1.13]: https://github.com/IvanPavlak/WinuX/compare/v0.1.12...v0.1.13
[0.1.12]: https://github.com/IvanPavlak/WinuX/compare/v0.1.11...v0.1.12
[0.1.11]: https://github.com/IvanPavlak/WinuX/compare/v0.1.10...v0.1.11
[0.1.10]: https://github.com/IvanPavlak/WinuX/compare/v0.1.9...v0.1.10
[0.1.9]: https://github.com/IvanPavlak/WinuX/compare/v0.1.8...v0.1.9
[0.1.8]: https://github.com/IvanPavlak/WinuX/compare/v0.1.7...v0.1.8
[0.1.7]: https://github.com/IvanPavlak/WinuX/compare/v0.1.6...v0.1.7
[0.1.6]: https://github.com/IvanPavlak/WinuX/compare/v0.1.5...v0.1.6
[0.1.5]: https://github.com/IvanPavlak/WinuX/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/IvanPavlak/WinuX/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/IvanPavlak/WinuX/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/IvanPavlak/WinuX/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/IvanPavlak/WinuX/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/IvanPavlak/WinuX/releases/tag/v0.1.0
