# Changelog

All notable changes to **WinuX** are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). See [VERSIONING.md](VERSIONING.md) for how we version and release.

<!-- Sections, in order (omit any that are empty in a tagged release): Added · Changed · Breaking · Deprecated · Removed · Fixed · Security -->

## [Unreleased]

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

[Unreleased]: https://github.com/IvanPavlak/WinuX/compare/v0.1.11...HEAD
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
