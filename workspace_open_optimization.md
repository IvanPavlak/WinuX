# Workspace Open Optimization - Task Tracker

Handoff/tracker file for implementing the performance and reliability improvements to the
`Open-Workspace` / `Set-WorkspaceWindowLayout` flow identified in the 2026-07-24 analysis session.

Source docs:
- Analysis performed against `C:\Users\Ivan\Development\GitHub\WinuX` (Claude Code session, 2026-07-24).
  All touched module files were verified byte-identical to WinuX master, so all file:line
  references transfer directly. Canonical implementation target: THIS repo (`WinuX`),
  branch `feature/workspace-open-optimization`.
- Entry points analyzed: `Windows/PowerShell/Modules/Workflow/Functions/Open-Workspace.ps1`,
  `Windows/PowerShell/Modules/Window/Functions/Set-WorkspaceWindowLayout.ps1` + full call graph.

Workflow: implement ALL points in one pass on this branch (user instruction, verbatim:
"implement everything at once, do not update tests or docs until I say so, but keep the points
in the handoff .md file so that it is not forgotten"). Tests and docs are therefore
**deliberately NOT updated** in this branch until the user says so - see "Deferred by user
decision" section. Line numbers below refer to pre-change state; they shift as points land.

## Status legend
- [ ] pending · [~] in progress · [x] done · [?] awaiting user decision

---

## Points

### Tier 1 - structural

- [ ] **1. In-process retry before terminal-respawn rerun** (analysis Tier 1 #1)
  - Current: any snap/verify failure in `Set-WorkspaceWindowLayout.ps1:857-913,:930-983,:1035-1080`
    writes 4 User-scope env markers, force-restarts PowerToys, and calls `ReRun-LastCommand`
    → kills all other WT tabs via SendKeys, spawns new pwsh WITHOUT `-NoProfile` (2-6s module
    reload), re-runs the whole workspace action list. 15-45s per attempt, ×2 max.
  - Plan: bounded in-process retry first (re-position → re-snap → re-confirm only the failed
    entries, driven by `Confirm-WorkspaceWindowPositions` on the FULL config so never-snapped
    windows are included); escalate to the existing respawn only if in-process attempts fail.
    Also enabled for `-Alongside` (which today has NO retry at all); respawn stays disabled there.
  - Sub-fixes bundled here:
    - a) Window-only retry applies the FULL layout config instead of filtering to the single
      failed entry (`:273-286`) - fixes stranded-at-inset windows after an aborted snap pass
      (Snap-AllWindows aborts the whole pass on first exhausted window) and fixes verification
      only checking the filtered subset. Idempotent skip logic keeps this cheap.
    - b) On window-only retry success, MERGE retried window records into the existing
      CurrentLayout.txt section instead of replacing the file with 1 record (`:1001-1027`,
      `Save-CurrentLayout.ps1:219-229`) - preserves zone pinning. (Full-config retry makes the
      records complete anyway; merge is belt-and-braces.)
    - c) Clear retry markers if the respawn spawn itself fails (today markers are written first;
      a spawn failure leaves stale User-scope retry mode for 10 min affecting ANY workspace).
    - d) `Rerun-LastCommand.ps1:132` calls `[Microsoft.VisualBasic.Interaction]::AppActivate`
      without loading the assembly → terminating error if VB not yet loaded. Load it (or use
      the native helper defined lines above) + try/catch.
    - e) `ReRun-LastCommand` replays the most recent **shared PSReadLine history** line - a
      command typed in another pwsh window meanwhile gets executed instead. Open-Workspace now
      records its exact invocation in a process env var; ReRun prefers it over history.

- [ ] **2. Poll-until-verified instead of fixed-sleep-check-once** (analysis Tier 1 #2)
  - a) Snap verification (`Snap-AllWindows.ps1:594-599,:668-685`): fixed 25ms sleep + single
    rect check after Win+Up / shift-drag → any FancyZones latency >25ms escalates to
    `ShiftDragSnap` (~410ms hardcoded sleeps, `WindowNative.cs:707-808`) → retries → rerun.
    Plan: new `Wait-WindowRect` helper polling GetWindowRect every ~15ms up to ~300ms budget;
    returns as soon as verified (faster happy path, far fewer false escalations).
  - b) `Apply-FancyZones.ps1:566-572,:626-632,:651-653`: `Switch-Desktop` + fixed 10ms sleep +
    hotkey injection races the async desktop switch → layout recorded under the PREVIOUS
    desktop's GUID (silent wrong-desktop layout → snap failures → rerun). Plan: use existing
    `Wait-DesktopSwitch` (as `Snap-AllWindows.ps1:244` already does); skip the desktop with a
    warning if the switch cannot be confirmed.
  - c) `Move-WindowToVirtualDesktop.ps1:39-106`: no "already on target desktop" fast path,
    unconditional 25ms sleep + single verify. Every window is moved TWICE per open (early-move
    callback `Set-WorkspaceWindowLayout.ps1:515-530` + unconditional `Set-WindowLayouts.ps1:1044`;
    dedup dict is local to Set-WindowLayouts). Plan: fast path returns immediately when already
    on target; verify-first-then-poll (~10ms steps, ~100ms budget) instead of blind sleep;
    expose `$script:LastMoveWindowToVirtualDesktopResult.Moved` so `Set-WindowLayouts.ps1:1076-1078`
    sleeps only after a REAL move.

- [ ] **3. Start-FancyZones happy-path probe cost** (analysis Tier 1 #3)
  - Current: `Start-FancyZones.ps1:72-135` readiness test = 4 × Get-Process with 3×250ms sleeps
    (750ms fixed) + 3 × Get-Service + fresh JSON parse of both layout files - runs even when
    PowerToys has been up for hours; called from `Apply-FancyZones` begin AND `Snap-AllWindows`
    begin → ≈1.6s/standard open, ≈3.5s for simple layouts (per-desktop Snap-AllWindows calls).
  - Plan: single sample when the FancyZones PID's StartTime is older than ~5s (PID-stability
    sampling only matters during startup); module-scope "verified ready" cache (~10s TTL),
    cleared by ForceRestart, so repeat calls within one open are free.

- [ ] **4. Wait-phase floor and 60s worst case** (analysis Tier 1 #4)
  - Current: `Wait-ForWorkspaceWindows.ps1:486-531` - after every window is individually stable
    (1s each), an additional COLLECTIVE 1s runs → hard +1s on every open incl. idempotent
    re-runs (~2s total floor). One never-matching entry (dead app / stale title regex) burns the
    full 60s timeout, then `Set-WindowLayouts.ps1:657-669` adds 3 search retries (0.5→1→2s) per
    missing entry.
  - Plan: `CollectiveStabilitySeconds` parameter, default 0 (param preserved for configurability);
    process-absent fail-fast - entry abandoned (warning) when no window AND no matching process
    exists after a grace period (~10s, checked ~1×/s), so the loop can finish early. Title-typo
    with a live process still waits (cannot be distinguished safely).

- [ ] **5. Replace SendKeys tab-cycling probes with focus-free UIA tab reading** (analysis Tier 1 #5)
  - Current: three implementations foreground every WT window and Ctrl+Tab through all tabs with
    per-keystroke sleeps: `Test-TerminalTabsAlreadyOpen.ps1:58-108`,
    `Open-ProjectTerminals.ps1:163-228` (both run back-to-back per open),
    `Terminate-WindowsTerminalTabs.ps1:144-197` (+ always-run verify pass `:271-389`, + CIM
    parent-walk `:45-56` that runs even for `-OnlyCurrent` which never uses it). ~1-2s+/open and
    the biggest input hazard (synthesized Ctrl+W/Ctrl+C land wherever the user's focus is).
  - Plan: shared UIA helper reading WT `TabItem` names without focus/keystrokes; integrate in
    all three call sites; keep the SendKeys path as automatic fallback when UIA yields nothing
    (WT version resilience). Terminate: close via per-tab UIA close button (InvokePattern) with
    SendKeys fallback; CIM walk moved below the `-OnlyCurrent` early exit and replaced with the
    PS7 `Process.Parent` chain; verify pass runs only when the main pass wasn't clean.
  - Bundled: **Environment.Exit seam** (`Invoke-TerminateWindowsTerminalTabsExit.ps1:22`) skips
    all `finally` blocks (Open-Workspace summary + `Reset-KeyboardModifiers` self-heal never run
    when the last action closes its own tab). Plan: Open-Workspace prints the elapsed summary and
    runs Reset-KeyboardModifiers BEFORE executing a process-terminating tab action; the exit seam
    itself also calls Reset-KeyboardModifiers defensively.

### Tier 2 - guaranteed per-open overhead

- [ ] **6. Set-WindowPosition unconditional sleeps** - `Set-WindowPosition.ps1:60-79`: always
  `ShowWindow(SW_SHOWNORMAL)`+25ms even when window is normal, +25ms after SetWindowPos; ×~35
  calls/open ≈ 1-1.8s. Plan: restore (and sleep) only when IsIconic/IsZoomed (add `IsIconic`
  P/Invoke to WindowNative.cs); drop the post-SetWindowPos sleep (callers verify via rect reads).
- [ ] **7. First-open normalization resizes every visible window on the machine** -
  `Set-WorkspaceWindowLayout.ps1:802-804` (non-alongside): shrinks ALL windows to 70% incl.
  non-workspace apps, then repositions workspace ones again. Plan: normalize only NEW windows
  (mirror the alongside branch `:793-801`).
- [ ] **8. `Resize-PositionedWindows -Tolerance 0` never converges** -
  `Set-WorkspaceWindowLayout.ps1:836`: apps that self-adjust by 1px are re-positioned forever;
  per-window Clear-WindowCache + re-enumeration inside `Resize-Windows.ps1:224-232`. Plan: use
  the module's 20px `PositionVerificationPx`; enumerate once per pass.
- [ ] **9. Browser first-tab normalization: UIA descendant walk + machine-wide Ctrl+1** -
  `Set-WorkspaceWindowLayout.ps1:605-629` full-tree UIA probe whose only purpose is skipping a
  harmless Ctrl+1 on single-tab windows; then `:634-686` Ctrl+1's EVERY window of the browser
  process incl. personal windows not in the workspace (real UX damage), and in alongside mode
  touches other workspaces' browsers. Plan: delete the UIA probe; normalize new windows always,
  existing windows ONLY when a browser layout entry's title pattern currently matches no window
  (i.e. matching would otherwise fail); skip windows whose title already matches an entry.
- [ ] **10. RPC probe runspace churn** - `Test-VirtualDesktopComHealth.ps1:65-67` fresh
  [PowerShell] runspace + 3 Get-Service per probe, 2-3×/open seconds apart
  (`Ensure-VirtualDesktops.ps1:51`, `Remove-VirtualDesktops.ps1:60`, alongside `:846`).
  Plan: module-scope TTL cache (~8s) for the probe result; reset paths clear it.
- [ ] **11. Desktop teardown-and-rebuild instead of delta resize** -
  `Set-WorkspaceWindowLayout.ps1:453-467` Remove-all + Ensure on count mismatch;
  `Ensure-VirtualDesktops.ps1:137-157` already grows AND shrinks. Plan: single
  `Ensure-VirtualDesktops -Count` call. (Verify shrink semantics match Remove w.r.t. window
  relocation before relying - record findings here.)
- [ ] **12. Focus-VirtualDesktop full scan** - `Focus-VirtualDesktop.ps1:134-151` iterates ALL
  windows (2 COM calls each) at the end of every open. Plan: WindowsTerminal-first, stop at
  first hit on target desktop.
- [ ] **13. Appx launch AUMID resolution** - `Start-Application.ps1:170-181` wildcard
  Get-AppxPackage + manifest parse per launch (0.5-2s). Plan: script-scope PackageName→AUMID
  cache.
- [ ] **14. Simple-layout snap loop O(desktops×windows) COM + per-window FZ liveness probe** -
  `Set-WorkspaceWindowLayout.ps1:349-366` + `Snap-AllWindows.ps1:101-126` re-enumerate/filter per
  desktop; `Snap-AllWindows.ps1:305` Get-Process per WINDOW in workspace mode. Plan: build
  window→desktop map once, pass explicit handle list into `Snap-AllWindows -All`; hoist liveness
  probe to per-desktop.

### Tier 3 - reliability bugs

- [x] **15. `Resolve-Selection` bare `break` on invalid input** - `Resolve-Selection.ps1:146`:
  `break` propagates across function boundaries to the caller's loop (Open-Workspace action
  loop) - a config typo silently kills all remaining workspace actions, uncatchable by
  try/catch. Fix: return $null after the error message (callers already handle $null).
  - DONE: `break` → `return $null` with explanatory comment
    (`Helper/Functions/Resolve-Selection.ps1`). Finding correction recorded: the non-hierarchical
    branch (~:180) does NOT have the bug - it already warns and continues with valid selections;
    only the hierarchical branch was affected. Behavior choice: abort-this-resolution (return
    $null) preserved over ignore-invalid-and-continue, matching the original abort intent.
- [x] **16. `Get-NextAvailableDesktopIndex` returns 0 on failure** - `:40-45`: stale-RPC blip
  makes `-Alongside` open ON TOP of the current workspace (exactly what the flag prevents);
  also does `Get-Module -ListAvailable` disk scan per call instead of the cached loader.
  Fix: use `Import-VirtualDesktopModule`; return $null on failure; Open-Workspace aborts that
  workspace's alongside open with a clear error when offset is $null.
  - DONE: `Window/Functions/Get-NextAvailableDesktopIndex.ps1` now uses the cached
    `Import-VirtualDesktopModule` loader and returns `$null` on both failure paths (warning now
    always emitted, not verbose-gated). `Workflow/Functions/Open-Workspace.ps1` (alongside
    branch) checks `$null -eq $desktopOffset` → `Write-LogError` + `continue` to the next
    workspace. Only production caller is Open-Workspace (verified via grep; other hits are
    tests/logs). Tests asserting the old `0` fallback will fail until the deferred test pass.
- [ ] **17. Apply-FancyZones results-array scope bug** - `Apply-FancyZones.ps1:250` scriptblock
  does `$resultsArray += ...` (rebinds a local) → all "Shortcut Sent"/"Failed" records lost →
  `$appliedCount` always 0 → applied-layouts cache never invalidated after changes (stale
  idempotency for 10s TTL), return value incomplete. Fix: Generic List + `.Add()`.
- [ ] **18. Browser title drift → guaranteed-futile rerun** - `Confirm-WorkspaceWindowPositions.ps1:256-272,:356-367`:
  title-drift fallback deliberately disabled for browsers; a tab title change between positioning
  and verification yields "not found" → respawn rerun ×2 that cannot fix a title mismatch.
  Fix: before declaring a browser entry missing, consult the tracked positioned handle for that
  entry (matched via expected bounds) and accept it if alive + process-matched.
- [ ] **19. RPC-dead retry storm (no circuit breaker)** - `Remove-VirtualDesktops.ps1:159-172`:
  per-window 5-attempt ladders (3.75s backoff each + full module reset per retry) after the
  preflight repair already failed → minutes. Fix: after the first exhausted ladder classified as
  RPC-unavailable, trip a breaker and fail the operation once.
- [ ] **20. Duplicate-EDID monitors permanently disable FancyZones idempotency** -
  `Apply-FancyZones.ps1:177-183`: same-model monitors → full choreography every open.
  Investigate instance-qualified keys (`GetMonitorDeviceInfo` exposes `MonitorInstance`;
  check the actual applied-layouts.json schema on this machine). Implement if schema supports
  it; otherwise record findings + defer.
- [ ] **21. Batched WT tab creation + explicit window id** - `Open-Terminal.ps1:78-128`,
  `Open-ProjectTerminals.ps1:355`: `wt -w 0` resolves to "most recently used" window right after
  probes foregrounded every WT window (tabs land in wrong window); one `wt.exe` spawn + 25ms
  sleep per tab with no ordering guarantee. Fix: single `wt` invocation chaining `new-tab ...;`
  subcommands (WT processes them in order), explicit window id when known.
- [ ] **22. Localhost error-page false positive** - `Test-BrowserGroupAlreadyOpen.ps1:551-563`:
  ANY "Problem loading page" window counts as "already open" for localhost URLs → project's
  Swagger tab silently never opens. Fix: stop treating generic error titles as a match.

---

## Deferred by user decision (do NOT do until user says so)

> User, verbatim: "do not update tests or docs until I say so, but keep the points in the
> handoff .md file so that it is not forgotten."

- [ ] **T1. Update Pester tests** under `Windows/PowerShell/Modules/Tests/` for all behavior
  changes above (new parameters, changed retry semantics, removed sleeps, UIA helper mocks,
  Resolve-Selection return-instead-of-break, Move result object, etc.). Run-but-don't-edit
  results will be recorded in "Verification status" below.
- [ ] **T2. Update docs/comment-based help** (README/docs/, function .SYNOPSIS/.PARAMETER blocks
  for new params like `CollectiveStabilitySeconds`, changed defaults like Resize tolerance,
  CHANGELOG.md entry). New parameters land with minimal inline help only.

---

## Notes for team discussion (NOT done now - "no need now" / roadmap)

> Extract these to the external note-taking app.

1. **Direct applied-layouts.json write instead of hotkey choreography.** Analysis Tier "architectural
   option": all three keys FancyZones needs (layout UUID, desktop GUID, monitor EDID) are already
   computed in Apply-FancyZones; writing the file while PowerToys is stopped and starting it once
   would remove all desktop switches + synthetic input and the wrong-desktop race class entirely.
   Bigger swing; flag-gated; interacts with point 20.
2. **Opt-in "direct placement" snap mode.** SetWindowPos to the full zone rect, skipping Win+Up
   registration. Removes the focus-dependent snap entirely; tradeoff: FancyZones does not
   register the window in a zone (zone navigation / keep-in-zone features won't track it).
   Worth having for headless/flaky contexts even if not default.
3. **Pipelined per-window position+snap.** The OnWindowStable callback already pipelines desktop
   moves during the wait phase; positioning could also be pipelined (SetWindowPos works
   cross-desktop), leaving only the snap pass desktop-bound. Larger control-flow refactor.
4. **Replace User-scope env-var rerun mirrors with a state file** next to CurrentLayout.txt -
   each User-scope env write broadcasts WM_SETTINGCHANGE (up to ~1s per hung window, fired
   exactly when something is hung). Partially mitigated by point 1 making reruns rare.

---

## Open questions for user
- None currently blocking. Points 20 (EDID schema) and 11 (Ensure shrink semantics) may surface
  decisions; they will be recorded here if so.

---

## Key facts discovered (grounding for implementation)

- `Start-FancyZones` readiness test costs 750ms fixed (3×250ms PID-stability sleeps) ON THE
  ALREADY-RUNNING happy path - verified `Start-FancyZones.ps1:72-135,:151-156`.
- `ShiftDragSnap` has ~410ms of hardcoded `Thread.Sleep`s per invocation - verified
  `WindowNative.cs:707-808` (50+30+20+30+10×10+100+30+50ms).
- PowerShell `break` inside a function with no enclosing loop propagates OUT of the function to
  the nearest caller loop and is NOT caught by try/catch - the Resolve-Selection defect
  mechanism (verified `Resolve-Selection.ps1:143-147` + `Open-Workspace.ps1:347,469`).
- `[Environment]::Exit(0)` does not run `finally` blocks - verified seam at
  `Invoke-TerminateWindowsTerminalTabsExit.ps1:22`; Open-Workspace's summary + keyboard reset
  live in `finally` (`Open-Workspace.ps1:488-498`).
- `$resultsArray +=` inside the Apply-FancyZones scriptblock rebinds a scope-local copy; only
  the outer-scope "Already Applied" `$results +=` entries survive - verified via grep
  (`Apply-FancyZones.ps1:250,:355,:370,:383,:438,:477,:489` vs `:554,:614`).
- Every window is desktop-moved TWICE per open: early-stable callback
  (`Set-WorkspaceWindowLayout.ps1:515-530`) + `Set-WindowLayouts.ps1:1044`; the `$movedWindows`
  dedup dict (`Set-WindowLayouts.ps1:174`) is local and unaware of callback moves - verified.
- `Move-WindowToVirtualDesktop` has NO already-on-target fast path and always sleeps 25ms
  (`VirtualDesktopMs`) before a single verify - verified `:39-106`.
- Wait phase: individual stability (1s) then SEQUENTIAL collective stability (1s) - verified
  `Wait-ForWorkspaceWindows.ps1:78,:486-531`; Set-WorkspaceWindowLayout passes TimeoutSeconds=60.
- Rerun state survives terminal respawn via User-scope env mirrors `value|unix-ts`, one-shot,
  10-min TTL, NOT workspace-scoped - `Set-WorkspaceWindowLayout.ps1:114-153`.
- Windows Terminal windowing: `wt -w 0` = most-recently-used window; alongside mode already
  passes an explicit GUID via `WT_WINDOW_ID` (`Open-Workspace.ps1:97-153`) - reuse that seam.
- `WindowModuleDelays` defaults all 25ms; tolerances: PositionVerificationPx=20,
  PreSnapValidationPx=75 (`Window.psm1:24-50`).
- Snap-AllWindows aborts the WHOLE pass at the first window that exhausts its 3 snap attempts
  (`$snapAborted` breaks retry→window→desktop loops) - remaining windows stay at 95% inset,
  and the current rerun filter verifies only the failed entry - verified `:694-750` + 
  `Set-WorkspaceWindowLayout.ps1:273-286,:918-924`.
- Stale VirtualDesktop COM (0x800706BA) is per-process and now self-healed in-process via
  `Get-RpcRetryPolicy -Probe` / `Reset-VirtualDesktopComProxy` (commit 06941a2) - the original
  justification for respawning a fresh shell on retry no longer holds.

---

## Verification status

- Build/verify: pending (PSScriptAnalyzer with repo `PSScriptAnalyzerSettings.psd1` + existing
  Pester suite run AFTER implementation; failures requiring test edits recorded here, not fixed).

## Change log (updated as points land)

- (empty - implementation not started)
