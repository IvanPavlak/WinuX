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

- [x] **1. In-process retry before terminal-respawn rerun** (analysis Tier 1 #1)
  - DONE (`Set-WorkspaceWindowLayout.ps1` restructure + `Rerun-LastCommand.ps1` + `Open-Workspace.ps1`):
    - Position→snap→verify now runs in a bounded loop (1 initial + 2 in-process retries).
      Retries reset keyboard state, re-check FancyZones (cheap - cached), refresh the
      existing-window snapshot (non-alongside) so already-correct windows are skipped by the
      position check, and re-run the FULL pipeline. Alongside gets in-process retries too
      (previously had NO retry); the terminal respawn stays disabled there.
    - Verification (in-loop and final) always runs against the FULL `$config.Layout` -
      previously the rerun verified only the single filtered entry.
    - Sub-fix a) DONE: the `$targetedLayoutConfig` single-entry filter is REMOVED - a
      window-only retry applies the full layout config (idempotent skips keep it cheap);
      markers are informational/diagnostic only now.
    - Sub-fix b) RESOLVED VIA a): with full-config retries, `$results` covers every configured
      entry, so the success-path Save-CurrentLayout snapshot is complete again - no merge
      needed (design decision: simpler than a merge path in Save-CurrentLayout).
    - Sub-fix c) DONE: both ReRun-LastCommand call sites are wrapped in try/finally that clears
      the three one-shot markers - reaching that code at all means the respawn did NOT happen
      ([Environment]::Exit skips finally blocks), so stale 10-min retry mode can no longer leak
      into the next open.
    - Sub-fix d) DONE: Rerun-LastCommand loads Microsoft.VisualBasic before AppActivate inside
      try/catch (warning instead of aborting the respawn). Also removed a duplicated
      `-notmatch '^\s*ReRun-LastCommand'` condition while in the block.
    - Sub-fix e) DONE: `ReRun-LastCommand -Command <exact>` bypasses history entirely;
      Open-Workspace records its resolved invocation (post-menu workspace names, Project,
      Alongside, ExtraArgs) in process-scoped `$env:WORKSPACE_RERUN_COMMAND` (cleared in
      finally), and both escalation sites in Set-WorkspaceWindowLayout pass it when present.
      Standalone Set-WorkspaceWindowLayout calls keep the history fallback (the typed command
      IS the most recent history line there).
  - Escalation-path behavior notes: max terminal respawns still 2 (`WORKSPACE_RERUN_COUNT`
    semantics unchanged); snap-failure and verification-failure report blocks preserved
    verbatim, now printed per attempt.
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

- [x] **2. Poll-until-verified instead of fixed-sleep-check-once** (analysis Tier 1 #2)
  - DONE:
    - New `Window/Functions/Wait-WindowRect.ps1` (exported in Window.psd1): polls GetWindowRect
      until bounds match within tolerance (default PositionVerificationPx=20), first check
      immediate, default budget 300ms / 15ms interval. Returns Verified + last observed bounds
      + ElapsedMs.
    - `Snap-AllWindows.ps1`: keyboard-snap and shift-drag verification now use Wait-WindowRect
      (budgets 200ms/250ms + 150ms per retry attempt); removed fixed `$retryDelayMs` sleeps and
      its calculation (log line adjusted). Misplaced-window recovery loop simplified - the extra
      25ms sleep + duplicate Get-DesktopFromWindow verify removed (Move verifies internally now).
    - `Apply-FancyZones.ps1`: all 3 Switch-Desktop sites now confirm via Wait-DesktopSwitch.
      Sites 1-2 (per-desktop hotkey passes): unconfirmed switch → warning + `continue` (skip
      desktop; snapping surfaces it; safer than stamping the previous desktop's GUID). Site 3
      (return-desktop re-apply): unconfirmed switch-back → skip the re-apply with warning.
      `$switchedDesktop = $true` is set before the confirmation so the switch-back logic still
      runs after an attempted-but-unconfirmed switch.
    - `Move-WindowToVirtualDesktop.ps1`: already-on-target fast path (returns $true, no COM
      move, no sleep); verify-immediately-then-poll (10ms steps, 100ms budget) replaces the
      fixed 25ms sleep + single check; new `$script:LastMoveWindowToVirtualDesktopResult.Moved`
      (follows the existing LastResizeWindowsResult pattern) distinguishes real moves.
    - `Set-WindowLayouts.ps1`: the unconditional 25ms pre-position sleep now fires only when a
      real move happened this iteration.
  - All files parse clean (AST check).
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

- [x] **3. Start-FancyZones happy-path probe cost** (analysis Tier 1 #3)
  - Current: `Start-FancyZones.ps1:72-135` readiness test = 4 × Get-Process with 3×250ms sleeps
    (750ms fixed) + 3 × Get-Service + fresh JSON parse of both layout files - runs even when
    PowerToys has been up for hours; called from `Apply-FancyZones` begin AND `Snap-AllWindows`
    begin → ≈1.6s/standard open, ≈3.5s for simple layouts (per-desktop Snap-AllWindows calls).
  - Plan: single sample when the FancyZones PID's StartTime is older than ~5s (PID-stability
    sampling only matters during startup); module-scope "verified ready" cache (~10s TTL),
    cleared by ForceRestart, so repeat calls within one open are free.
  - DONE (`Application/Functions/Start-FancyZones.ps1`):
    - `$testFancyZonesReady` now takes ONE process sample when the PID's StartTime is ≥5s old
      (crash-loop sampling can't apply to a long-lived process); full 4-sample/750ms path kept
      for young processes and when StartTime is unreadable (elevation mismatch throws - caught).
    - `$script:FancyZonesReadyCache` (module scope, 10s TTL): happy path returns instantly on a
      recent verification; set on both success paths (already-running + post-start wait loop);
      invalidated on ForceRestart entry and on a failed readiness check.
    - Bundled cosmetic fix (agent-flagged minor): startup progress line divided by 50 instead
      of 1000, printing nonsense like "40s / 10s" - corrected in the touched line.

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
  - DONE (`Window/Functions/Wait-ForWorkspaceWindows.ps1` + caller):
    - New `CollectiveStabilitySeconds` param (default 0 - removes the guaranteed +1s; >0
      restores old double-settle) and `ProcessAbsentGraceSeconds` param (default 10, 0 disables).
    - Fail-fast: entries that never matched any window and whose `SearchProcessName` matches no
      live process (regex-aware, single Get-Process snapshot, checked ≤1×/s) are abandoned with
      a debug-error line; loop exits early when all remaining entries are abandoned.
    - Return shape gained `Abandoned = @(descriptions)`; `Success` is $false when anything was
      abandoned; the state snapshot is now returned in that case too, and
      `Set-WorkspaceWindowLayout` consumes `WindowStates` whenever non-empty (previously only on
      full success) so title-drift fallbacks still work for the windows that did stabilize.
    - Success snapshot skips history placeholders without a Handle (defensive; generic-title
      records are created handle-less).
    - Behavior note: comment-based help for the new params deferred with the docs pass (T2).

- [x] **5. Replace SendKeys tab-cycling probes with focus-free UIA tab reading** (analysis Tier 1 #5)
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
  - DONE:
    - New Helper functions (exported in Helper.psd1): `Get-WindowsTerminalTabTitles`
      (UIA TabItem scan per WT window - returns $null, never empty, when UIA can't read, so
      callers can distinguish "fall back" from a real answer) and `Close-WindowsTerminalTab`
      (invokes the tab's close-button InvokePattern by exact title, returns $false to trigger
      fallback).
    - `Test-TerminalTabsAlreadyOpen`: UIA-first per window; the full SendKeys cycling pass is
      preserved verbatim as automatic fallback when UIA returns $null.
    - `Open-ProjectTerminals` InSameShell auto-detect: UIA-first; legacy cycling + the
      navigate-back pass preserved as fallback.
    - `Terminate-WindowsTerminalTabs`: (1) CIM parent-walk moved below the -OnlyCurrent early
      exit (which never used it) and replaced with the PS7 `Process.Parent` chain; (2) marker
      detection prefers UIA tab titles - identifies OUR tab even when it is not the active tab
      (the window title only mirrors the active tab; old behavior kept as fallback);
      (3) UIA-first close pass for the current window and for other WT windows (close-button
      invoke, no focus/keystrokes), legacy Ctrl+Tab/^c/^w passes preserved as fallback, shared
      `$isOurTabTitle` predicate; (4) the SendKeys retry-verification pass now only runs when a
      failure was recorded or something survived (gated via fresh enumeration + UIA re-read).
    - Exit seam: `Invoke-TerminateWindowsTerminalTabsExit` runs Reset-KeyboardModifiers before
      `[Environment]::Exit(0)`; `Open-Workspace` prints the elapsed summary, clears its env
      vars, and resets modifiers BEFORE executing a Terminate action with -OnlyCurrent or
      -IncludeCurrent (guarded by `$summaryPrinted` so the normal path doesn't double-print).

### Tier 2 - guaranteed per-open overhead

- [x] **6. Set-WindowPosition unconditional sleeps** - `Set-WindowPosition.ps1:60-79`: always
  `ShowWindow(SW_SHOWNORMAL)`+25ms even when window is normal, +25ms after SetWindowPos; ×~35
  calls/open ≈ 1-1.8s.
  - DONE: `ShowWindow(SW_SHOWNORMAL)` still always issued (preserves aero-snap/restore-rect
    normalization), but the 25ms settle is paid only when `GetWindowPlacement.showCmd` was not
    already SW_SHOWNORMAL (design decision: placement check instead of the planned IsIconic
    P/Invoke - no WindowNative.cs change needed; GetWindowPlacement was already imported).
    Post-SetWindowPos sleep removed (all callers verify or sleep themselves).
- [x] **7. First-open normalization resizes every visible window on the machine**
  - DONE: unified both branches to normalize ONLY windows not in the pre-open capture (the
    workspace's own new windows); the alongside-only branch is now the general behavior.
    Dead commented-out "skip if already positioned" block left untouched.
- [x] **8. `Resize-PositionedWindows -Tolerance 0` never converges**
  - DONE: call site now uses the module default (PositionVerificationPx = 20). Additionally
    `Resize-Windows` single-handle mode no longer does Clear-WindowCache + full enumeration
    per call - it reads the target rect/title directly via GetWindowRect/GetWindowText
    (multi-window modes keep the cache-clear). This removes a per-window enumeration from
    Resize-PositionedWindows, snap retries, and Set-WindowLayouts positioning.
    Behavior note: a single-handle target with an EMPTY title is now skipped by the
    skip-titles list instead of warned as not-found (net effect identical: no resize).
- [x] **9. Browser first-tab normalization: UIA descendant walk + machine-wide Ctrl+1**
  - DONE: full-tree UIA tab-count probe deleted. New scoping: windows opened by this flow are
    always normalized; PRE-EXISTING windows only when at least one browser entry's resolved
    title pattern currently matches NO window; any window already showing a wanted title is
    skipped (also fixes a latent self-sabotage where re-runs Ctrl+1'd a correctly-matched
    window off its matching tab). Entry title patterns resolved via Resolve-LayoutTokens and
    matched with Test-WindowTitleMatch.
- [x] **10. RPC probe runspace churn**
  - DONE: `Test-RpcServerHealth` caches SUCCESSFUL -Probe results for 8s (System module
    scope); failures are never cached so recovery always re-verifies. Design decision: cache
    placed in Test-RpcServerHealth (not Get-RpcRetryPolicy) so all probe callers benefit and
    the recovery path needs no cross-module cache invalidation.
- [x] **11. Desktop teardown-and-rebuild instead of delta resize**
  - DONE: the non-alongside count-mismatch branch now calls `Ensure-VirtualDesktops -Count`
    once (grows AND shrinks - verified `Ensure-VirtualDesktops.ps1:116-157`; shrink removes
    highest-index desktops via Remove-Desktop, native behavior relocates their windows, and
    Set-WindowLayouts moves every window to its configured desktop right after, so the end
    state matches the old Remove-all+recreate path). Also fixes latent quirk: old path never
    recreated desktops when requiredVirtualDesktops == 1 after collapsing.
- [x] **12. Focus-VirtualDesktop full scan**
  - DONE: candidates ordered WindowsTerminal-first, loop breaks at the first window on the
    target desktop (only one focus target is ever used).
- [x] **13. Appx launch AUMID resolution**
  - DONE: session-scoped `$script:AppxAumidCache` (PackageName → AUMID); cache entry evicted
    and error rethrown when shell activation of a cached AUMID fails (stale after package
    update).
- [x] **14. Simple-layout snap loop O(desktops×windows) COM + per-window FZ liveness probe**
  - DONE: `Snap-AllWindows -All` gained `-WindowHandles IntPtr[]` (explicit filter, takes
    precedence over -CurrentDesktopOnly); the simple-layout loop resolves each window's
    desktop ONCE, buckets unresolvable windows into a "-1" bucket offered on every pass
    (matching old filter behavior), skips desktops with no windows (saves the switch), and
    passes per-desktop handle lists. In positioned mode the FancyZones liveness Get-Process
    probe moved from per-window to per-desktop (failure records a desktop-level entry and
    aborts, feeding the normal retry path).

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
- [x] **17. Apply-FancyZones results-array scope bug**
  - DONE: `$results` is a Generic List; all 6 scriptblock `$resultsArray +=` sites and both
    outer `$results +=` sites converted to `.Add(...)`. `$appliedCount` and the
    applied-layouts cache invalidation now see real data; return value complete.
- [x] **18. Browser title drift → guaranteed-futile rerun**
  - DONE (`Confirm-WorkspaceWindowPositions.ps1`): new last-resort recovery before the
    "window not found" verdict - accepts the tracked positioned window whose expected bounds
    (and display desktop - zone coords repeat across desktops) match this entry, provided its
    handle is still alive (GetWindowRect) and unclaimed. Works for all entry types; browsers
    are the main beneficiary since their sole-process-window fallback is deliberately off.
- [x] **19. RPC-dead retry storm (no circuit breaker)**
  - DONE (`Remove-VirtualDesktops.ps1` -EmptyOnly occupancy loop): an RPC-unavailable error
    that survived the FULL per-window retry ladder trips a breaker → the cleanup ABORTS with
    $false (correctness: with occupancy unknowable, "empty" desktops can't be trusted) instead
    of grinding multi-second ladders through every remaining window. Non-EmptyOnly path was
    already bounded by its outer catch (first exhausted ladder → $false).
- [x] **20. Duplicate-EDID monitors permanently disable FancyZones idempotency**
  - INVESTIGATED + DONE: this machine's applied-layouts.json (PowerToys current) records
    `monitor-instance` (PnP path, unique per device) alongside the EDID - verified live
    ("SNYBEF3" / "4&1cfdc60e&0&UID4145"). `Get-AppliedFancyZonesState` now stores an
    additional instance-qualified key `"{EDID}|{INSTANCE}:{GUID}"` (legacy EDID-only key kept
    for instance-less callers/schemas); `Apply-FancyZones` builds a display→instance map from
    `GetMonitorDeviceInfo` (already exposed `MonitorInstance`), prefers qualified keys at both
    idempotency sites, and the duplicate-EDID guard now disables idempotency ONLY when a
    duplicated display lacks instance data (old PowerToys schema).
- [x] **21. Batched WT tab creation + explicit window id**
  - DONE: `Open-Terminal` chains all tabs of one call into a single `wt` invocation
    (`new-tab ... ; new-tab ...` - WT processes subcommands in order), with defensive batch
    splitting near the command-line length limit (follow-up batches reuse the same window ID);
    dead `$StartWT` flag removed. `Open-ProjectTerminals` queues consecutive pwsh tabs
    (DEFAULT/custom/regular) per project and flushes them as ONE Open-Terminal call; WSL tabs
    (different WT profile) flush the queue first to preserve on-screen order; without a shared
    project window each tab still gets its own window GUID (flush-per-tab). Per-tab 25ms
    sleeps replaced by one 25ms settle per batch.
- [x] **22. Localhost error-page false positive**
  - DONE (`Test-BrowserGroupAlreadyOpen.ps1`): failed-load windows only count for the
    localhost heuristic when their title carries host/port evidence from THIS group's
    localhost URLs (Chromium error tabs are titled with the host; Firefox's generic
    "Problem loading page" no longer suppresses opening the group). Anti-duplicate intent
    preserved for evidence-bearing titles.

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
