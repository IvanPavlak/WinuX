# Troubleshooting

Common issues and their solutions.

## Installation Issues

### "Cannot find script" during Bootstrap

**Problem:** PowerShell can't find the bootstrap script.

**Solution:**

```powershell
# Run with explicit path
iex (irm "https://raw.githubusercontent.com/IvanPavlak/WinuX/master/Windows/WinuX/WinuX.ps1")

# Or if locally:
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
. .\Windows\WinuX\WinuX.ps1
```

### Execution Policy Error

**Problem:** "Running scripts is disabled on this system"

**Solution:**

```powershell
# For current session only (safe)
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# Or permanently (run as admin)
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

### Git Not Found

**Problem:** Bootstrap fails because Git isn't installed.

**Solution:**

```powershell
# Install Git first
winget install Git.Git

# Restart terminal, then run Bootstrap
Bootstrap -WithInitialSetup
```

### WinGet Not Found

**Problem:** WinGet is not available on the system.

**Solution:**

```powershell
# Bootstrap auto-installs WinGet via Install-WinGetPackageManager
# Or manually from Microsoft Store: "App Installer"
```

### WinGet Install Hangs During Unattended / VM Bootstrap

**Problem:** On a fresh machine - most often a VM or the elevated bootstrap console - `Install-WingetApps` appears to hang and installs nothing, even though `winget` is present.

**Cause:** The `msstore` source shows a hard, one-time agreement (including a geographic-region consent) the first time that source is **queried**. Only `--accept-source-agreements` clears it - `--disable-interactivity` does not suppress this legal gate. In an unattended, non-interactive console nobody can answer the prompt, so the first call that engages msstore blocks forever. The `-s winget` installs never accept the msstore agreement, and a bare `winget list` does not engage msstore on a fresh machine, so the acceptance is never recorded.

**Solution:** This is handled automatically - before installing anything, `Install-WingetApps` queries each source (`winget` and `msstore`) directly with `--accept-source-agreements`, which forces the agreement to surface and records the acceptance for every later install. If a hang persists, your WinGet predates 1.6 (which introduced `--disable-interactivity`); update **App Installer** from the Microsoft Store, then re-run:

```powershell
# One-time manual acceptance of the msstore agreement (querying the source is what triggers it)
winget search example --source msstore --accept-source-agreements --disable-interactivity
Install-WingetApps
```

## Configuration Issues

### Machine Type Not Detected

**Problem:** `$MachineType` is empty or wrong.

**Solution:**

1. Check hostname mapping in `Configuration.psd1`:

```powershell
HostnameToMachineType = @{
    "YourHostname" = "PC"  # Add your mapping
}
```

2. Verify hostname:

```powershell
hostname
```

3. Set hostname if needed:

```powershell
Rename-Machine -NewName "DESKTOP-GAMING"
# Requires restart
```

### Path Not Expanding

**Problem:** Paths show `{Dev}` instead of actual path.

**Solution:**

1. Check `BasePaths` has your machine type:

```powershell
BasePaths = @{
    PC = @{ Dev = "C:\Users\You\Development\GitHub"; User = "C:\Users\You" }
    # Add your machine type if missing
}
```

2. Reload profile:

```powershell
Reload-PowerShellProfile
```

### Invalid Configuration Syntax

**Problem:** PowerShell errors when loading profile.

**Solution:**

```powershell
# Run Pester tests to validate
Run-Tests

# Common issues:
# - Missing closing brace }
# - Missing comma between array items
# - Invalid escape sequences
```

## Symbolic Link Issues

### WinuX Replaced My PowerShell Profile Or FancyZones Settings

**Problem:** A file you already had - typically your PowerShell 7 profile
(`Documents\PowerShell\Microsoft.PowerShell_profile.ps1`) or your PowerToys FancyZones
settings - was replaced by a symlink into the repository during Bootstrap. The base
configuration ships those links active, so a first run on a machine that was already set up
hits them.

**Solution:** Nothing was thrown away. The original was copied aside before the link replaced
it. Look under the repository root:

```powershell
# Everything ever replaced, newest last
Get-ChildItem "$env:USERPROFILE\Development\GitHub\WinuX\Backups\Windows\SymbolicLinks" -Recurse -File

# Just the PowerShell profile entry
Get-ChildItem "$env:USERPROFILE\Development\GitHub\WinuX\Backups\Windows\SymbolicLinks\PowerShell.Profile" -Recurse
```

Backups are filed as `Backups\Windows\SymbolicLinks\<entry key>\<yyyy-MM-dd_HH-mm-ss>\<file>` -
one folder per link entry, one timestamped folder per replacement (see [Backups](backups.md) for
the full policy). To restore one, delete the symlink and copy the backup back:

```powershell
Remove-Item $PROFILE -Force
Copy-Item "<backup folder>\Microsoft.PowerShell_profile.ps1" $PROFILE
```

To keep your own profile permanently, drop the `PowerShell.Profile` entry from the
`SymbolicLinks` section in `Configuration.local.psd1` - but note that link is what loads WinuX
into every new shell, so removing it makes the install session-only. The usual answer is to move
your own customizations into the repository's profile instead.

> [!NOTE]
> An existing **symlink** is replaced without a backup (it has no content of its own), and if a
> backup cannot be written the link is skipped and your file is left untouched.

### "A required privilege is not held"

**Problem:** Can't create symbolic links.

**Solution:**

```powershell
# Enable Developer Mode
Enable-DeveloperMode

# Or manually: Settings → Privacy & security → For developers → Developer Mode
```

### Symlink Points to Wrong Target

**Problem:** Symlink exists but points to old location.

**Solution:**

```powershell
# Remove and recreate
Remove-Item "C:\Path\To\Symlink" -Force
SymbolicLinkMaker
```

### WSL Symlink Fails

**Problem:** WSL symlinks not created.

**Solution:**

1. Ensure WSL is installed:

```powershell
wsl --list
```

2. Check target exists in WinuX:

```powershell
Test-Path "WinuX\Server\.ssh\config"
```

3. Create target path in WSL:

```bash
wsl mkdir -p /home/you/.ssh
```

## Application Launch Issues

### "WhatsApp is already running!" With No WhatsApp Window

**Problem:** `Open-WhatsApp` (directly, or as a workspace action) reports `WhatsApp is already running!` and opens nothing, even though no WhatsApp window is on screen. It happens intermittently - sometimes the same workspace opens WhatsApp fine.

**Why it happens:** When a WhatsApp notification arrives while the app is closed, Windows COM-activates a background push notification host: `WhatsApp.Root.exe -RegisterForBGTaskServer /nowindow /pushnotification -Embedding`. That host owns no visible window, but it runs under the same `WhatsApp.Root` process name the UI does, so a process-name-only check treats it as a running app. It is intermittent because the host only exists once Windows has activated it, and `Kill-All` only clears it until the next notification.

**Solution:** This is handled - `Open-WhatsApp` passes `-RequireMainWindow` to `Start-Application`, so only a process owning a visible main window counts as running. To inspect the state yourself:

```powershell
# A background-only host shows MainWindowHandle 0; a real UI shows a non-zero handle
Get-Process WhatsApp.Root | Select-Object Id, MainWindowHandle, MainWindowTitle

# Confirm it is the push notification host
Get-CimInstance Win32_Process -Filter "Name = 'WhatsApp.Root.exe'" | Select-Object CommandLine
```

The same `-RequireMainWindow` switch applies to any app that keeps a windowless helper alive under its own process name.

## Window Layout Issues

### Windows Not Positioning

**Problem:** `Set-WorkspaceWindowLayout` doesn't move windows.

**Solutions:**

1. Check process name is correct:

```powershell
Get-ActiveWindowInfo  # Focus the window, see actual process name
```

2. Check window title pattern:

```powershell
# Use wildcards for flexibility
WindowTitle = "*Visual Studio Code"  # Ends with
WindowTitle = "*Mozilla Firefox*"    # Contains
```

3. Ensure window is open before applying layout:

```powershell
# Layout actions should come last in workspace actions
```

4. Run with verbose/debug output:

```powershell
Set-LogLevel Verbose { Set-WorkspaceWindowLayout -WorkspaceName "MyOrg" }
```

### "The RPC server is unavailable. (0x800706BA)" During Workspace Setup

**Problem:** Virtual desktop operations (`Ensure-VirtualDesktops`, `Remove-VirtualDesktops`, `Switch-Desktop`) fail with `The RPC server is unavailable. (0x800706BA)` - typically after Explorer restarted earlier in the session (taskbar configuration, icon-cache rebuild, theme changes), and re-importing the `VirtualDesktop` module doesn't help.

**Why it happens:** The `VirtualDesktop` module creates its COM connections to Explorer once per PowerShell process (in a compiled static constructor) and caches them. When Explorer restarts, those cached connections are permanently severed for that session; because the compiled assembly stays loaded, `Remove-Module` + `Import-Module` never re-creates them.

**Solution:** This now self-heals. Workspace commands probe the session's live COM state before desktop work and reconnect it in place (`Reset-VirtualDesktopState` rebuilds the cached COM proxies via `Reset-VirtualDesktopComProxy`); `Restart-Explorer` reconnects proactively after restarting the shell. If a session still reports RPC errors, reconnect manually:

```powershell
# Reconnect this session's VirtualDesktop COM state in place
Reset-VirtualDesktopState

# Inspect the live state directly
Test-VirtualDesktopComHealth
```

Opening a new shell also works (a fresh process builds fresh COM connections), but is no longer necessary.

### Windows Land On The Wrong Monitor After Reset-Windows

**Problem:** `Reset-Windows` consolidates onto the configured monitor, but a handful of windows end up centered on a different monitor. The verbose log shows every window moved successfully (`monitor moved [35]`), yet `Center-Windows` then reports target zones on the other monitor.

**Why it happens:** Collapsing the virtual desktops makes Windows migrate the windows off the removed desktops onto the surviving one. FancyZones reacts to those arrivals by restoring each window to its remembered zone from `app-zone-history.json` - and that record includes a monitor. Running the move pass WITHOUT the desktop collapse does not reproduce it; adding the collapse does.

Which monitor FancyZones picks is unreliable when two displays are the same model: identical panels report the same EDID code and can report the same serial number, so `applied-layouts.json` accumulates several device identities for the same physical monitor. `Get-DuplicateMonitorEdid` detects the EDID collision (`Apply-FancyZones` uses it to stop false "already applied" skips), but the zone history has no such guard.

**Solution:** This now self-corrects. `Reset-Windows` passes its configured monitor to `Center-Windows`, which runs last, so any window pulled onto another monitor mid-run is brought back to the intended one. `Move-Windows` also verifies each placement with `Wait-WindowRect` and re-applies it once, and reports windows that would not stay put instead of counting them as moved.

To confirm what happened on a specific run:

```powershell
# Per-window trace plus moved / skipped / monitor-failed counts
Set-LogLevel Verbose { Reset-Windows }

# Re-assert the target monitor on its own
Center-Windows -Monitor 2
```

If windows still drift, the FancyZones re-apply behaviors are the trigger - `fancyzones_displayOrWorkAreaChange_moveWindows` and `fancyzones_zoneSetChange_moveWindows` in `FancyZones/settings.json`. Turning them off stops the drift at the source, but they are load-bearing for workspace layouts, so prefer the self-correcting path above.

### Fullscreen Windows Jumbled Or On The Wrong Monitor

**Problem:** Layout entries with `Zone = "Fullscreen"`, or the `Fullscreen` workspace itself, leave windows jumbled: thrown to the other monitor, stuck at ~90% of the zone size, or (after `Reset-Windows` then `w Fullscreen`) fullscreened on a monitor the window was not sitting on.

**Why it happened:** Fullscreen is a single-zone FancyZones layout (`Zero`), and the snap primitive was a synthesized `Win+Up` - a **relative** move. With only one zone per monitor there is no neighbouring zone to resolve to, so with `fancyzones_moveWindowAcrossMonitors` enabled FancyZones threw an already-recognised window to the *other* monitor's zone, and on a single monitor the key no-op'd until every retry and the shift-drag fallback were burned. One exhausted window also aborted the whole snap pass, stranding every later desktop at the pre-snap inset size. The wrong-monitor-after-`Reset-Windows` variant has a different trigger: applying the zone grids (`Apply-FancyZones`) can make FancyZones relocate remembered windows across monitors from `app-zone-history.json` *before* placement runs, so the pass fullscreened the window wherever the history had dragged it.

**Solution:** This now self-corrects. 0.1.44 replaced the ambiguous `Win+Up` with direct placement (`Invoke-SingleZoneWindowPlacement` via `SetWindowPos`) verified by `Wait-WindowRect`; 0.1.49 refined the workspace flow to `Invoke-SingleZoneWindowSnap`, which makes `Win+Up` deterministic again by clearing the stale FancyZones assignment that caused the ambiguity in the first place (see the next two sections), so those windows are also registered as zoned. The `Fullscreen` workspace resolves each window's monitor from a snapshot taken *before* the zone grids are applied, so a window is fullscreened wherever it sat when the workspace was invoked, and the snap pass records failures and continues instead of aborting on the first stubborn window. The `Fullscreen` simple layout still places directly (its windows sit on invisible desktops FancyZones' own paths cannot reach), so those windows are not registered in FancyZones' zone history; manual `Win+Arrow` on them still works because `fancyzones_moveWindowsBasedOnPosition` resolves zones from position, not history.

```powershell
# Per-window trace: look for "direct single-zone placement (verified at zone position)"
Set-LogLevel Verbose { Set-WorkspaceWindowLayout -WorkspaceName Fullscreen }
```

### Fullscreen Window Slightly Smaller Than Its Zone

**Problem:** A window with `Zone = "Fullscreen"` (or every window in the `Fullscreen` workspace) ends the pass *almost* right: correct monitor, correct desktop, but a thin strip of desktop shows down its left, right and bottom edges, and it looks a few pixels smaller than the neighbouring windows that snapped normally. Pressing `Win+Arrow` on it afterwards visibly finishes the job. The run reports a clean pass with every window verified.

**Why it happened:** Placing a window directly (the 0.1.44 fix above) put the window's **frame** rectangle at the zone rectangle. `SetWindowPos` and `GetWindowRect` both work on the frame, which extends past the window you see by the DWM invisible resize border - about 7px on the left, right and bottom at 100% scaling. FancyZones sizes a snapped window against the **visible** frame instead, so a keyboard-snapped window's `GetWindowRect` deliberately overhangs its zone by that border while the window itself sits flush. Directly placed windows got no such compensation and were inset by the border instead. Nothing caught it because the geometry checks are looser than the error: `Wait-WindowRect` allows 20px and the final workspace verification allows 50px, both deliberately, so applications that enforce their own size constraints do not false-fail.

**Solution:** This now self-corrects. The workspace flow snaps single-zone windows through FancyZones again (`Invoke-SingleZoneWindowSnap` - see the next section), which produces FancyZones' own compensated geometry by construction, and verification compares the frame rect a snap actually produces: the zone grown by `Get-WindowFrameMargin` (`DWMWA_EXTENDED_FRAME_BOUNDS` against `GetWindowRect`) - on a 3440x1440 work area, the fullscreen zone `(3, 3) 3434x1434` lands at `(-4, 3) 3448x1441`, exactly where a manual `Win+Up` puts the same window. Where direct placement still runs (the `Fullscreen` simple layout), `Invoke-SingleZoneWindowPlacement` grows its target by the same margins, so its geometry matches too. Borderless and console windows measure zero margins and use the zone rectangle unchanged; an unreadable measurement falls back to zero margins, which is simply the previous behaviour. **The native layer is compiled once per PowerShell session and cannot be recompiled in place**, so a session started before this release keeps the old geometry until you open a new one.

```powershell
# Per-window trace: look for "Frame compensation for [...]" before each placement
Set-LogLevel Verbose { Set-WorkspaceWindowLayout -WorkspaceName Fullscreen }
```

### Fullscreen Window Not Registered With FancyZones

**Problem:** A fullscreen window opened by a workspace looks perfectly placed, but FancyZones does not treat it as zoned: it is skipped when FancyZones relocates windows on a zone-set or display/resolution change, and it has no entry behind "move newly created windows to their last known zone". A window you snapped by hand with `Win+Arrow` does not have the problem.

**Why it happened:** Between 0.1.44 and 0.1.48, single-zone windows were placed with a plain `SetWindowPos`. That reproduces a snap's geometry but never tells FancyZones anything: FancyZones only registers a window it moved through its own paths - a `Win+Arrow`, a shift-drag, or its own relocation - stamping it with the `FancyZones_zones` window property and writing `app-zone-history.json`. Direct placement sets neither. And the reason 0.1.44 stopped using `Win+Up` was itself a registration effect: the marker survives every programmatic move, so a window `Reset-Windows` had gathered was still assigned to its old zone, and FancyZones' position-based `Win+Arrow` excludes assigned zones - on a one-zone grid that leaves nothing to move to, so the key no-op'd (one monitor) or threw the window to the other monitor's zone (`moveWindowAcrossMonitors`).

**Solution:** This now self-corrects in the workspace flow. `Invoke-SingleZoneWindowSnap` clears a stale assignment (`Clear-FancyZonesWindowAssignment`) so `Win+Up` resolves deterministically into the single zone, centers the window in the zone at double the shared inset so the position-based move has one clearly-containing zone to pick, sends `Win+Up`, and falls back to shift-drag (FancyZones' real drag path, which registers just as well). The `Fullscreen` simple layout deliberately keeps direct placement: its windows sit on invisible desktops, and registering requires FancyZones' own keyboard or drag path, which only works on the visible desktop.

One caveat is FancyZones' own and no snap method avoids it: `app-zone-history.json` has no per-window identity, so several windows of one process spread across several desktops contend for a single entry and only one of those desktops keeps FancyZones' tracking once a desktop switch rebuilds the work area. The snap itself is correct on every desktop - see [Changing The FancyZones Layout Re-Tiles Some Desktops But Not Others](#changing-the-fancyzones-layout-re-tiles-some-desktops-but-not-others) below.

```powershell
# Per-window trace: "Snapped [...] => Win+Up (registered, verified at zone position)"
Set-LogLevel Verbose { w <workspace> }
```

### Changing The FancyZones Layout Re-Tiles Some Desktops But Not Others

**Problem:** After a workspace open, the FancyZones layout hotkey (`Win+Ctrl+Alt+<n>`) re-tiles the windows on one desktop as expected, while on another the zone grid changes but the windows do not move at all. The desktops that work usually hold a window of an application that appears only ONCE in the workspace (VS Code); the ones that do not hold windows of an application that appears on several desktops (Firefox).

**Why it happens:** FancyZones relocates only the windows it currently tracks in that work area's live window-to-zone map, and it rebuilds that map from `app-zone-history.json` every time a desktop switch recreates the work area. That store has no per-window identity: it is keyed by **app path** plus monitor plus virtual desktop and holds exactly one zone entry per key, and every virtual-desktop sync re-stamps the whole file onto whichever desktop is current at that moment. A workspace open creates and destroys desktops, so the sync fires repeatedly and keeps moving which single desktop owns a given application's row. Eight Firefox windows spread over seven desktops therefore contend for one row: at most one of those desktops re-seeds and the rest are left untracked. Nothing else about those windows is wrong - they are placed flush in their zone and still carry the `FancyZones_zones` assignment marker, so the workspace's `(registered, verified at zone position)` report is accurate. The tracking is lost afterwards, at the work-area rebuild, which is why no amount of care in the snap prevents it.

**Solution:** None from this side; it is FancyZones' own per-application bookkeeping. Re-running the workspace open puts everything back, and a manual `Win+Arrow` on an affected window once the desktops have settled rewrites the row for that desktop (taking it from whichever desktop held it before). Confirm the diagnosis in FancyZones' own log under `%LOCALAPPDATA%\Microsoft\PowerToys\FancyZones\Logs`: a desktop that re-seeds logs the lookup AND a hit, a desktop that does not logs only the lookup.

```text
# Re-seeded - this desktop follows a layout change
Get Code.exe zone history on work area: <device>_<desktop-guid>
App zone history found on the work area <device>_<desktop-guid>
Add app zone history, device: <device>_<desktop-guid>, layout: {...}

# Not re-seeded - this desktop ignores a layout change
Get firefox.exe zone history on work area: <device>_<desktop-guid>
Get firefox.exe zone history on work area: <device>_<desktop-guid>
```

The `registry:` list in FancyZones' `Synced virtual desktops` lines is in desktop order, which is how a GUID above maps back to a desktop number.

### Windows Left On Other Desktops After Reset-Windows

**Problem:** `Reset-Windows` reports a clean pass, but a window is still sitting on another virtual desktop. The left-behind window is typically one of several from the same process - one Firefox window while its siblings moved, or one Windows Terminal window.

**Why it happens:** The upstream `Move-Window` cmdlet (MScholtes VirtualDesktop) has a silent fallback: when the requested window's view cannot be moved, it moves the process's MAIN window instead - a different window of the same process - and does not throw. Multi-window processes are therefore the usual victims. `Move-WindowToVirtualDesktop` verifies each move and returns `$false` when the window did not land, but that result used to be swallowed: the cmdlet's own output (the Desktop object) leaked into the function's pipeline output, and a two-element array is truthy in PowerShell, so `Move-Windows` counted the failure as moved and never retried.

**Solution:** This now self-corrects. The leaked output is discarded, so failed moves engage the retry ladder in `Move-Windows` (and `Set-WindowLayouts` / `Snap-AllWindows`), and a verification sweep after the move pass re-checks every window against the target desktop, retries stragglers once, and reports anything it cannot recover as a failure instead of a clean pass:

```powershell
# Per-window trace: look for "Recovered" (sweep fixed it) or
# "could not be brought to Virtual Desktop" (reported failure)
Set-LogLevel Verbose { Reset-Windows }
```

### FancyZones Not Running

**Problem:** Zone snapping doesn't work.

**Solution:**

```powershell
Start-FancyZones

# Stronger recovery path (recommended for stubborn snap failures)
Start-FancyZones -ForceRestart -MaxWaitSeconds 20

# Or restart PowerToys
Stop-Process -Name "PowerToys" -Force
Start-Process "C:\Program Files\PowerToys\PowerToys.exe"
```

`Set-WorkspaceWindowLayout` performs this forced restart path automatically before every retry, and follows it with `Apply-FancyZones -Force`.

**Why both steps:** a restart alone does not fix a wrong layout. FancyZones reloads `applied-layouts.json` on startup but does not re-assert the live zone grid, and that same file is what the idempotency check reads - so an ordinary re-apply reports "Already Applied" for every monitor and sends nothing. If the live grid is stale or was never applied (FancyZones was down, crash-looping, or missed the hotkey), every retry snaps into the same wrong grid and cannot converge. `-Force` skips the check and re-sends the shortcuts.

To reset the zone grid by hand after FancyZones has been misbehaving:

```powershell
Start-FancyZones -ForceRestart -MaxWaitSeconds 20
$config = Import-PowerShellDataFile -Path "<layout>.psd1"
Apply-FancyZones -MonitorConfig $config.Monitors -Force
```

### FancyZones Snap Fails After Editing custom-layouts.json

**Problem:** `Snap-AllWindows` fails to verify snap positions or snaps windows to wrong zones after editing layouts in `custom-layouts.json`.

**Solution:** Run the configuration validator to find drift between the FancyZones files and `Configuration.psd1`:

```powershell
Test-FancyZonesConfiguration
```

It reports unknown layouts, `ZoneNameMappings` indices out of range, `LayoutNumbers` names that no longer exist, `layout-hotkeys.json` uuid mismatches (which make `Apply-FancyZones` apply the WRONG layout), and grid percentage axes that do not sum to exactly 10000. `Set-WorkspaceWindowLayout` runs the same validation automatically at the start of every workspace open.

**Why spacing is not the culprit anymore:** any `spacing` value and any zone definition (grid or canvas) is supported. FancyZones insets edges that touch the work-area border by the full spacing value, and interior edges by `Floor(spacing/2)` per zone; a zone spanning multiple cells absorbs the spacing between them. `Get-FancyZoneCoordinates` replicates this exactly, so the computed rectangles match what FancyZones snaps to regardless of spacing. If verification still fails, the mismatch is configuration drift - which is what `Test-FancyZonesConfiguration` pinpoints.

If a workspace layout reruns after a snap failure, the recovery path now resizes only the failed window handle before retrying. Other open windows are left untouched.

### Alongside Workspace Opens With Windows Missing Or In The Wrong Zones

**Problem:** `w <workspace> -Alongside` fills only some of the layout's zones, and the arrangement looks progressively more scrambled each time it is rerun. A normal (non-alongside) open of the same workspace is fine.

**Solution:** Update to a build where `Open-Workspace` forwards `-Alongside` to the workspace's actions. Then confirm the shortfall is gone - a starved pass now says so explicitly:

```powershell
Set-LogLevel Verbose { w <workspace> -Alongside }
```

Look for `Layout short by N window(s) - placed X of Y entries!`. If it still appears, the workspace genuinely does not open enough windows for its layout: compare the layout's entry count against what its `Open-*` actions launch.

**Why:** An alongside open may only position the windows it created - every window captured before it belongs to whichever workspace is already running and is deliberately refused. A count-based opener such as `Open-Browser -Instances 33` used to read that as "ensure 33 exist", so with Chrome already open it launched fewer than 33 (or none) and the layout was handed too few usable windows. The pass then reported success anyway (alongside skipped verification entirely), `CurrentLayout.txt` recorded the partial arrangement as the truth, and the next open pinned windows to those wrong zones - which is why it compounded rather than merely repeating.

Three changes fix it: `-Alongside` is forwarded to every action that declares it (so `-Instances N` opens N **new** windows), alongside verification is scoped rather than skipped (only the entries this pass placed, matched only against this open's windows), and a genuine shortfall is reported once with both counts instead of a verbose-only per-entry line.

### Workspace Rerun Fails With `Cannot convert value "1|<timestamp>" to type "System.Int32"`

**Problem:** A workspace open fails verification, escalates to a fresh shell as announced (`Rerunning workspace setup in a fresh shell ... (attempt 1/2)`), and the respawned run then aborts the moment it needs the rerun counter - twice, because the `catch` block reads the same counter:

```text
=> Error applying workspace layout: Cannot convert value "1|1788349256" to type "System.Int32". Error: "The input string '1|1788349256' was not in a correct format."
=>    Stack trace => at Set-WorkspaceWindowLayout, ...\Modules\Window\Functions\Set-WorkspaceWindowLayout.ps1: line 1334
=> Error executing action [Set-WorkspaceWindowLayout] for workspace [MyWorkspace]: Cannot convert value "1|1788349256" to type "System.Int32". ...
```

The same respawned run also never behaves as a window-only retry - no forced FancyZones re-apply, and no `Window-Only Retry Mode` line under `Set-LogLevel Verbose` - even though the run that escalated announced one.

**Why it happened:** The rerun state (`WORKSPACE_RERUN_COUNT`, `WORKSPACE_WINDOW_ONLY_RETRY` and the two informational marker variables) is written twice: plain into the process environment, and stamped as `value|unix-timestamp` into the User-scope environment - the mirror that outlives the respawn (see `Get-WorkspaceRerunMirror`). Windows Terminal generates a new environment block for every session it starts (its `reloadEnvironmentVariables` setting, on by default), built from the registry rather than inherited from the shell that ran `wt`, so the respawned shell's process copy of each variable **is** the stamped mirror value. `Set-WorkspaceWindowLayout` preferred the process copy whenever one existed and read it as plain: `[int]"1|1788349256"` threw, and `"1|..." -eq '1'` was false, so the window-only marker was ignored. The count mirror had already been consumed on the way to the error, so nothing was left behind afterwards - the rerun chain simply ended with the layout unverified.

**Solution:** This now self-corrects (0.1.51): a process copy carrying the stamp is skipped and the mirror is used instead, so the counter counts, the two-rerun cap holds across respawns, and the respawned run really is a window-only retry. The shell a rerun respawns into is a fresh session and loads the fix automatically; only the shell you are typing in keeps the old code until you restart it. Nothing needs cleaning up after an interrupted rerun chain - a stale mirror ages out after 10 minutes and is consumed on the next open regardless - but both copies can be inspected, and the mirror cleared, by hand:

```powershell
# What this shell inherited (stamped) versus what the mirror currently holds
$env:WORKSPACE_RERUN_COUNT
[Environment]::GetEnvironmentVariable('WORKSPACE_RERUN_COUNT', 'User')

# Clear a mirror by hand (one User-scope broadcast each)
Set-WorkspaceRerunMirror -Name 'WORKSPACE_RERUN_COUNT' -Value $null
Set-WorkspaceRerunMirror -Name 'WORKSPACE_WINDOW_ONLY_RETRY' -Value $null
```

### Layout File Not Found

**Problem:** "Cannot find layout file" error.

**Solution:**

1. Check file exists for your machine type:

```
Modules/Window/Layouts/PC/WorkspaceName_PC.psd1
```

2. Check machine type:

```powershell
$MachineType  # Should match folder name
```

## fastfetch Logo Issues

Setting `Universal.FastFetchImageLogo` makes fastfetch render that image instead of the text logo,
in the two terminals that can display one - WezTerm and Windows Terminal. Every other host keeps the
text logo declared in the fastfetch configuration. The feature is gated twice: the
`PathTemplates.SymbolicLinks.PowerShell.AllHostsProfile` link has to exist, and the configuration
key has to be set. See [`Get-FastfetchLogoArgument`](../modules/system.md#get-fastfetchlogoargument)
and its [configuration guide](../configuration/guides/system/Get-FastfetchLogoArgument.md).

### Logo Is A Block Of Slashes Instead Of An Image

**Problem:** The logo renders as colored `/////` blocks, and `fastfetch --show-errors` prints
`Logo: getCharacterPixelDimensions() failed`.

This is fastfetch calling its own image path rather than going through the override. fastfetch
cannot measure a character cell in pixels on Windows - its `getCharacterPixelDimensions()` calls
`GetCurrentConsoleFontEx()`, which only works for ConHost - so `--logo-type sixel`, `chafa`,
`kitty` and `iterm` all fail under Windows Terminal and fall back to that placeholder.

**Solution:**

1. Confirm the override is loaded. The global function must exist, and it must be a `Function`, not
   the `Application`:

```powershell
(Get-Command fastfetch).CommandType   # Function
```

2. If it is `Application`, the all-hosts profile did not load. Check the symlink exists and points
   into the repository:

```powershell
Get-Item $PROFILE.CurrentUserAllHosts -Force | Select-Object Target
```

3. Recreate it if missing, then open a new tab. Requires an elevated shell:

```powershell
SymbolicLinkMaker -Name "PowerShell"
```

4. Never set `type` to `sixel` or `chafa` in the fastfetch configuration file. The config keeps the
   TEXT logo on purpose; the image is applied by command-line arguments, which is what makes the
   fallback in other hosts work.

### Image Logo Missing, Text Logo Shown Instead

**Problem:** The panel renders with the text logo in a terminal you expected an image in.

**Solution:** This is the designed fallback and it never reports an error. Turn on verbose logging
to see which check declined:

```powershell
Set-LogLevel Verbose { c }
```

The reasons, all of them deliberate:

| Debug line | Meaning |
| ---------- | ------- |
| `Universal.FastFetchImageLogo is not set` | The feature is off. This is the base configuration's state; set the key in `Configuration.local.psd1`. |
| `output redirected` | Output is being captured, not displayed. |
| `terminal has no supported image protocol` | Not WezTerm, and `$env:WT_SESSION` is unset - VS Code, ConHost, SSH, CI. |
| `terminal did not report its cell size` | The terminal ignored `CSI 16 t`. Windows Terminal answers only from 1.22.2362.0; check `(Get-AppxPackage Microsoft.WindowsTerminal*).Version`. |
| `sixel encoding unavailable` | ImageMagick is not on PATH and the sixel cache is cold. Install it with `winget install ImageMagick.ImageMagick`. |
| `logo image not found` | The configured path does not exist. |

Note that [`Invoke-ClearAndFastfetch`](../modules/system.md#invoke-clearandfastfetch) measures the
panel by running the fastfetch binary directly, bypassing the wrapper - so the text logo appearing
in a captured measurement is correct and expected, not the bug it looks like.

### Image Logo Overlaps The Info Panel

**Problem:** The image spills into the module list, or leaves a large gap before it.

The image is encoded to fit a block of character cells measured from the text logo it replaces, so
the two occupy identical space. A mismatch means the encoded size no longer matches the cell size in
use - most often a stale sixel cache after a font change that did not alter the reported cell size.

**Solution:**

1. Clear the cache and let the next call re-encode:

```powershell
Remove-Item "$env:LOCALAPPDATA\WinuX\SixelCache" -Recurse
```

2. Reset the font to the profile default, which is the size the block is judged against:

```
Ctrl+0
```

3. A wide, short text logo (a banner rather than a square block) gives the image a wide, short box
   to fit inside, so the image comes out small. Pass `-CellWidth` / `-CellHeight` explicitly, or
   point `-ReferenceLogoPath` at a logo with the proportions you want.

### Sixel Artifacts Or A Cleared Image After Resizing

**Problem:** The image vanishes, smears, or leaves fragments after resizing the window, scrolling
back, or switching tabs.

Windows Terminal's sixel implementation is young and does not always survive reflow. Nothing in
this repository can fix it.

**Solution:** Redraw the panel with `c`. WezTerm's inline-image path does not have this problem, so
prefer WezTerm if it bothers you.

## Browser Issues

### URLs Not Opening

**Problem:** `Open-Browser` does nothing.

**Solutions:**

1. Check browser is installed:

```powershell
Get-Command firefox -ErrorAction SilentlyContinue
```

2. Check browser groups exist:

```powershell
$Configuration.BrowserGroups
```

3. Try with explicit browser:

```powershell
Open-Browser AI -Browser Chrome
```

### Duplicate Group Names

**Problem:** Wrong URL opens.

**Solution:**
All names must be unique across all groups:

```powershell
# Bad - "Profile" used twice
@{ Personal = @( @{ Name = "Profile"; Url = "..." } )}
@{ Work = @( @{ Name = "Profile"; Url = "..." } )}

# Good - Unique names
@{ Personal = @( @{ Name = "PersonalProfile"; Url = "..." } )}
@{ Work = @( @{ Name = "WorkProfile"; Url = "..." } )}
```

## Git Issues

### Authentication Failed

**Problem:** `Update-Repositories` fails with auth error.

**Solution:**

```powershell
# Configure credential manager
git config --global credential.helper manager

# Or re-authenticate
gh auth login
```

### Repository Not Found

**Problem:** "Repository not found" error.

**Solution:**

1. Check URL is correct in `Universal.GitHub`:

```powershell
Private = @{
    WinuX = "/YourUsername/WinuX.git"  # Check username
}
```

2. For private repos, ensure you have access.

## Performance Issues

### Slow Profile Load

**Problem:** New terminal takes long to start.

**Solutions:**

1. Check for slow modules:

```powershell
Measure-Command { . $PROFILE }
```

2. Lazy load non-essential functions.

3. Check for slow network operations during load.

### High Memory Usage

**Problem:** PowerShell using too much RAM.

**Solution:**

```powershell
# Start fresh session
exit
# Open new terminal
```

## Debugging Commands

### Validate Everything

```powershell
# Run the Pester test suite
Run-Tests

# Check specific function tests
Run-Tests Validate-Layout
Run-Tests Test-BrowserGroupAlreadyOpen
```

### Check Current State

```powershell
$MachineType                        # Current machine
$MachineSpecificPaths              # All expanded paths
$Configuration                     # All config
Get-ActiveWindowInfo               # Current window details
```

### Verbose Output

```powershell
Bootstrap -Verbose
Update-Repositories -Verbose
Set-LogLevel Verbose { Set-WorkspaceWindowLayout -WorkspaceName "X" }
```

## Getting Help

1. Run the test suite: `Run-Tests`
2. Check this troubleshooting guide
3. Review function documentation
4. Check GitHub issues
5. Enable verbose/debug mode for details

## See Also

- [Tests Module](../modules/tests.md)
- [Getting Started: Prerequisites](../getting-started/prerequisites.md)
