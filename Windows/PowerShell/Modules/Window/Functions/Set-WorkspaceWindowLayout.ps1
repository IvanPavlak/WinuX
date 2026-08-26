function Set-WorkspaceWindowLayout {
	<#
	.SYNOPSIS
		Applies a workspace-specific window layout configuration.

	.DESCRIPTION
		Loads and applies a predefined window layout for a specific workspace.
		Layout files are stored in machine-specific subfolders within the Window module's
		Layouts directory (e.g., Layouts/PC/, Layouts/Laptop/, Layouts/Work/).

		Which subfolder is used is resolved by Get-LayoutMachineType: a non-empty
		$Configuration.LayoutMachineTypeOverrides entry for the detected machine type replaces that
		machine type for layout resolution only (both the Layouts/<Type>/ folder and the
		<Workspace>_<Type>.psd1 file suffix), otherwise SmallDisplayMachineType applies on a
		laptop-class display, otherwise the detected type is used. This is how a machine runs a
		different monitor setup than usual without editing or losing its real layout set - clearing
		the entry restores it. The override takes precedence over the small-display detection, and
		Reset-Windows resolves its own per-machine defaults through the same helper.

		Supports layouts with duplicate window entries where the same ProcessName and
		WindowTitle appear multiple times to place identical windows in different zones.
		This is used with Open-Browser's Override parameter which opens the same URL
		group in a separate browser window, allowing both to be positioned independently.

		On snap failure or final layout verification failure, the position -> snap -> verify
		pipeline is retried IN-PROCESS up to two times first (refreshing the existing-window
		snapshot so already-correct windows are skipped, and verifying against the FULL
		layout config so windows an aborted snap pass never reached are covered).

		Every retry begins by resetting FancyZones, because a window that will not land in
		its zone usually means the zone grid itself is wrong rather than the window being
		stubborn: PowerToys/FancyZones is force-restarted, and the workspace's zone layouts
		are re-applied with Apply-FancyZones -Force so the re-send is not skipped by the
		applied-layouts idempotency check (that state claims the layout is applied even when
		the live grid is stale, which is the condition being recovered from).

		Only when the in-process retries are exhausted does it escalate to a workspace rerun
		in a fresh shell (window-only retry mode) that:
		- Preserves already configured virtual desktops
		- Force-re-applies FancyZones monitor layouts (same reason as above)
		- Re-applies the full layout config (idempotent skips keep it cheap)
		This avoids disturbing windows/layouts that were already configured correctly.

		The final virtual desktop landing is not handled here. Switching to and focusing the
		workspace's first virtual desktop is delegated to Focus-VirtualDesktop, the last action
		in each workspace's WorkspaceActions sequence, so the switch-and-focus logic is not
		duplicated across functions.

	.PARAMETER WorkspaceName
		The name of the workspace layout to apply (e.g., "WinuX", "Server").

	.PARAMETER LayoutPath
		Optional custom path to a layout configuration file.

	.PARAMETER TimeoutSeconds
		Maximum number of seconds to wait for windows when using automatic detection.
		Default is 60 seconds.

	.PARAMETER SnapDelayMs
		Milliseconds to wait between positioning and the snap pass, and the per-window delay
		on the simple-layout path (forwarded to Snap-AllWindows -All). Default is 10. It is
		NOT a per-window delay in the workspace flow - the positioned-window snap path
		verifies every snap with Wait-WindowRect instead of fixed delays.

	.PARAMETER DisableAutoWait
		Disables automatic window detection and applies layout immediately.
		Use with caution as windows may not be ready.

	.PARAMETER PreCapturedExistingWindows
		HashSet of window handles that existed before opening workspace applications.
		Used to properly detect first run and distinguish new windows from existing ones.
		Typically provided by Open-Workspace function.

	.PARAMETER DesktopOffset
		Offset to add to all virtual desktop numbers in the layout. This allows opening
		a workspace on virtual desktops to the right of existing ones, enabling multiple
		workspaces to run simultaneously without interfering with each other.
		For example, if DesktopOffset=2 and a window is configured for Desktop 1,
		it will be placed on Desktop 3 (1 + 2).

	.PARAMETER Alongside
		When specified, opens the workspace alongside existing desktops without removing them.
		New workspace desktops are added to the right of existing ones (uses DesktopOffset).
		When not specified, the workspace replaces existing desktops (normal mode).

		Alongside also narrows what the layout pass may touch: only windows created by this
		open are eligible (Set-WindowLayouts -SkipExistingWindows), everything that was
		already on screen belongs to whichever workspace is already running. Two consequences
		follow. Count-based openers must be told, or they top up to a total that includes
		windows the layout cannot use and leave the layout short - hence Open-Workspace
		forwarding -Alongside to Open-Browser. And verification is scoped rather than skipped:
		the entries this pass placed a window for, checked only against this open's windows,
		so the retry loop still catches real drift without ever judging a stranger's window.

	.PARAMETER ProtectedWindowHandles
		Live window handles belonging to alongside workspaces a plain open preserves. These
		windows are never moved, normalized, counted or verified, the virtual desktop resize
		never shrinks below the highest desktop they stand on, and the CurrentLayout write
		merges instead of replacing so their sections survive. Threaded in by Open-Workspace
		(from Get-WorkspaceOpenProtection); a standalone plain call derives the set itself when
		that function is available. Simple layouts (Fullscreen/Empty) stay global gestures and
		ignore protection by design.

	.EXAMPLE
		Set-WorkspaceWindowLayout -WorkspaceName "WinuX"
		# Uses automatic window detection

	.EXAMPLE
		Set-WorkspaceWindowLayout -WorkspaceName "Server" -DesktopOffset 2
		# Opens Server workspace starting at virtual desktop 3 (offset of 2)

	.EXAMPLE
		Set-WorkspaceWindowLayout -LayoutPath "C:\MyLayouts\custom.psd1" -TimeoutSeconds 30
		# Uses automatic detection with 30 second timeout

	.EXAMPLE
		Set-WorkspaceWindowLayout -WorkspaceName "Server" -DisableAutoWait
		# Applies layout immediately without waiting
	#>
	[CmdletBinding(DefaultParameterSetName = 'ByWorkspace')]
	param (
		[Parameter(ParameterSetName = 'ByWorkspace')]
		[string]$WorkspaceName,

		[Parameter(ParameterSetName = 'ByPath', Mandatory = $true)]
		[string]$LayoutPath,

		[Parameter()]
		[int]$TimeoutSeconds = 60,

		[Parameter()]
		[int]$SnapDelayMs = 10,

		[Parameter()]
		[switch]$DisableAutoWait,

		[Parameter()]
		[System.Collections.Generic.HashSet[IntPtr]]$PreCapturedExistingWindows,

		[Parameter()]
		[int]$DesktopOffset = 0,

		[Parameter()]
		[switch]$Alongside,

		[Parameter()]
		[System.Collections.Generic.HashSet[IntPtr]]$ProtectedWindowHandles
	)

	$offsetLabel = if ($Alongside) { " (alongside" + $(if ($DesktopOffset -gt 0) { ", offset: +$DesktopOffset" }) + ")" } else { "" }
	Write-LogTitle "Applying $WorkspaceName Workspace Layout$offsetLabel"

	if (-not (Test-LogVerbose)) {
		$spinner = Loading-Spinner -Start -Label "Applying layout"
	}

	$windowOnlyRetryEnvVar = 'WORKSPACE_WINDOW_ONLY_RETRY'
	$windowOnlyRetryTitleEnvVar = 'WORKSPACE_WINDOW_ONLY_RETRY_TITLE'
	$windowOnlyRetryProcessEnvVar = 'WORKSPACE_WINDOW_ONLY_RETRY_PROCESS'

	# Rerun state must survive the terminal respawn performed by ReRun-LastCommand. The
	# process-scoped env vars survive only when Windows Terminal spawns a fresh host per
	# `wt` call (windowingBehavior "useNew"); under "useAnyExisting" the new tab inherits
	# the WT host's stale environment, resetting every marker/counter and uncapping the
	# rerun loop. Each value is therefore mirrored outside the process, by
	# Set-WorkspaceRerunMirror / Get-WorkspaceRerunMirror, which own the stamping, the
	# one-shot consume, the TTL and the read-before-clear guard - see those two for why the
	# mirror is shaped the way it is. Reads here prefer the process copy (identical behavior
	# to the plain env vars when it propagates) and fall back to the mirror.
	$rerunStateTtlMinutes = 10
	$readRerunState = {
		param([string]$Name)
		$processValue = [Environment]::GetEnvironmentVariable($Name, 'Process')
		$persisted = Get-WorkspaceRerunMirror -Name $Name -TtlMinutes $rerunStateTtlMinutes
		if (-not [string]::IsNullOrEmpty($processValue)) { return $processValue }
		return $persisted
	}
	$writeRerunState = {
		param([string]$Name, [string]$Value)
		[Environment]::SetEnvironmentVariable($Name, $Value, 'Process')
		Set-WorkspaceRerunMirror -Name $Name -Value $Value
	}

	$windowOnlyRetryActive = (& $readRerunState $windowOnlyRetryEnvVar) -eq '1'
	$windowOnlyRetryTitle = & $readRerunState $windowOnlyRetryTitleEnvVar
	$windowOnlyRetryProcess = & $readRerunState $windowOnlyRetryProcessEnvVar
	# Restart-only on purpose: this runs microseconds before the process is replaced by the
	# respawned shell, and that shell force-re-applies the zone layouts as its first FancyZones
	# action (see the -Force:$windowOnlyRetryActive apply below). Re-applying here as well would
	# pay for a second desktop-switching layout pass that the respawn immediately redoes. The
	# in-process retries do both halves themselves - see $resetFancyZonesState.
	$ensureFancyZonesBeforeRerun = {
		try {
			$null = Start-FancyZones -ForceRestart -ErrorAction Stop
		}
		catch {
			Write-LogWarning "Warning: Failed to force-start FancyZones before rerun: $($_.Exception.Message)"
		}
	}

	# The rerun respawns the shell. A modifier (or the shift-drag's mouse button)
	# left logically held by the failed run would lock terminal input up for the
	# whole session and corrupt the rerun's own synthesized input - release everything before handing off.
	$resetKeyboardStateBeforeRerun = {
		if (Get-Command Reset-KeyboardModifiers -ErrorAction SilentlyContinue) {
			$null = Reset-KeyboardModifiers -IncludeMouseButton
		}
	}

	# Consume one-shot retry markers up front so they only affect the immediate rerun.
	if ($windowOnlyRetryActive) {
		[Environment]::SetEnvironmentVariable($windowOnlyRetryEnvVar, $null, 'Process')
		[Environment]::SetEnvironmentVariable($windowOnlyRetryTitleEnvVar, $null, 'Process')
		[Environment]::SetEnvironmentVariable($windowOnlyRetryProcessEnvVar, $null, 'Process')
	}

	try {
		$snapResult = $null

		# A standalone plain call (no Open-Workspace threading the set in) must still not
		# destroy a live alongside workspace - derive the protection itself. Guarded by
		# Get-Command because the Workflow module owns the function and this module can run
		# without it (and tests blanket-mock Get-Command to $null, keeping this hermetic).
		# Alongside opens add without destroying and need no protection.
		if (-not $PSBoundParameters.ContainsKey('ProtectedWindowHandles') -and -not $Alongside) {
			if (Get-Command Get-WorkspaceOpenProtection -ErrorAction SilentlyContinue) {
				$selfProtection = Get-WorkspaceOpenProtection
				if ($selfProtection) {
					$ProtectedWindowHandles = $selfProtection.WindowHandles
					Write-LogDebug " Self-derived protection for $($ProtectedWindowHandles.Count) alongside window(s)" -Style Success
				}
			}
		}
		$hasProtectedWindows = ($null -ne $ProtectedWindowHandles -and $ProtectedWindowHandles.Count -gt 0)

		# Pre-flight RPC health check using the shared helper. The live probe runs
		# in-process against this session's VirtualDesktop COM state (cheap when
		# healthy), so a stale session - Explorer restarted since the module loaded -
		# is detected and repaired here, before any desktop reconfiguration begins.
		if (Get-Command Get-RpcRetryPolicy -ErrorAction SilentlyContinue) {
			[void](Get-RpcRetryPolicy -OperationLabel "applying layout" -Probe)
		}

		$cachedMonitorInfo = Get-MonitorInfo

		$layoutNameToUse = $null

		if ($PSCmdlet.ParameterSetName -eq 'ByWorkspace') {
			$layoutsDir = $MachineSpecificPaths.Projects.Self.Layouts

			$layoutNameToUse = $WorkspaceName
			if (-not $WorkspaceName -or $WorkspaceName -eq 'Fullscreen') {
				$layoutNameToUse = 'Fullscreen'
			}

			# Which layout SET to read from: a configured LayoutMachineTypeOverrides entry, else the
			# SmallDisplayMachineType set, else this machine's own. Resolved (and logged) by
			# Get-LayoutMachineType, which Reset-Windows shares so both display-shaped settings
			# follow one switch instead of drifting apart. The monitor snapshot is handed over so the
			# small-display rule does not re-query it.
			$machineType = Get-LayoutMachineType -MonitorInfo $cachedMonitorInfo

			$machineSpecificLayoutFileName = "${layoutNameToUse}_${machineType}.psd1"

			$machineSpecificLayoutPath = Join-Path $layoutsDir $machineType $machineSpecificLayoutFileName

			if (Test-Path $machineSpecificLayoutPath) {
				$LayoutPath = $machineSpecificLayoutPath
				Write-LogDebug "Using machine-specific layout => [$machineSpecificLayoutFileName]" -Style Success
			}
			else {
				if ($spinner) { [void](Loading-Spinner -Stop -Spinner $spinner -Discard); $spinner = $null }
				Write-LogWarning "No layout configuration found for workspace => [$WorkspaceName]"
				# The set searched is not always this machine's own - LayoutMachineTypeOverrides and
				# SmallDisplayMachineType redirect it - which makes a missing file baffling unless the
				# set and path actually looked for are named.
				Write-LogWarning " Layout set [$machineType] - expected => [$machineSpecificLayoutPath]" -NoLeadingNewline
				return
			}
		}
		elseif (-not (Test-Path $LayoutPath)) {
			if ($spinner) { [void](Loading-Spinner -Stop -Spinner $spinner -Discard); $spinner = $null }
			Write-LogError "Layout configuration file not found at => [$LayoutPath]"
			return
		}

		$config = Import-PowerShellDataFile -Path $LayoutPath
		$layoutConfigToApply = $config.Layout

		# Cover every attached monitor, not just the ones this layout file defines. Apply-FancyZones
		# iterates the Monitors section, so a monitor the file omits is never visited and keeps
		# whatever zone layout it already had. This runs for EVERY workspace: it used to sit inside
		# the SimpleLayoutWorkspaces branch below, which made Fullscreen and Empty the only
		# workspaces that adapted to a newly attached display. Only zone layouts are cloned - an
		# auto-added monitor gets no window assignments, so nothing moves onto it.
		$autoExtendedMonitors = @(Expand-LayoutMonitorCoverage -Config $config -MonitorInfo $cachedMonitorInfo)
		if ($autoExtendedMonitors.Count -gt 0) {
			Write-LogDebug "  Auto-added monitor(s) [$($autoExtendedMonitors -join ', ')] to layout config" -Style Warning
		}

		# Validate the FancyZones configuration quartet (custom-layouts.json,
		# ZoneNameMappings, LayoutNumbers, layout-hotkeys.json) before any desktop or
		# window work. Arbitrary layouts/zones/spacing are supported, so drift between
		# those files is now the main way an open can misplace windows or apply the
		# wrong layout. Errors touching a layout THIS workspace references - or global
		# errors such as a hotkey/uuid mismatch, which make Apply-FancyZones apply the
		# wrong layout everywhere - abort the open; everything else already logged as
		# a warning by the validator and the open proceeds.
		$fancyZonesValidation = Test-FancyZonesConfiguration
		if (-not $fancyZonesValidation.Valid) {
			$workspaceLayoutNames = @()
			if ($config.Monitors) {
				foreach ($monitorConfig in $config.Monitors.Values) {
					if ($monitorConfig.VirtualDesktopLayouts) {
						$workspaceLayoutNames += @($monitorConfig.VirtualDesktopLayouts.Values)
					}
				}
			}
			if ($config.Layout) {
				$workspaceLayoutNames += @($config.Layout | ForEach-Object { $_.Layout } | Where-Object { $_ })
			}
			$workspaceLayoutNames = @($workspaceLayoutNames | Select-Object -Unique)

			$blockingErrors = @($fancyZonesValidation.Errors | Where-Object {
					(-not $_.Layout) -or ($workspaceLayoutNames -contains $_.Layout)
				})

			if ($blockingErrors.Count -gt 0) {
				if ($spinner) { [void](Loading-Spinner -Stop -Spinner $spinner -Discard); $spinner = $null }
				Write-LogError "FancyZones configuration has $($blockingErrors.Count) error(s) affecting this workspace (see above) - aborting layout. Run Test-FancyZonesConfiguration after fixing."
				return
			}
		}

		# Read the persisted snapshot (CurrentLayout.txt) for this workspace, if any, and turn
		# its window records into a desktop|monitor|zone => recorded-window map. Set-WindowLayouts
		# uses it only as a tiebreaker so identically-named windows (e.g. several "Browser"
		# entries) return to the same zones across reopens. A missing/stale snapshot yields no
		# map and changes nothing.
		$pinnedHandleMap = $null
		if ($layoutNameToUse -and $layoutsDir) {
			$persistedSection = Get-CurrentLayout -LayoutsDir $layoutsDir -Workspace $layoutNameToUse
			if ($persistedSection -and $persistedSection.Windows) {
				$pinnedHandleMap = @{}
				foreach ($recordedWindow in $persistedSection.Windows) {
					if ($null -eq $recordedWindow) { continue }
					$zoneKey = "$($recordedWindow.Desktop)|$($recordedWindow.Monitor)|$($recordedWindow.Zone)"
					$pinnedHandleMap[$zoneKey] = @{
						Handle      = $recordedWindow.Handle
						ProcessId   = $recordedWindow.ProcessId
						ProcessName = $recordedWindow.ProcessName
					}
				}
			}
		}

		if ($windowOnlyRetryActive -and (Test-LogVerbose)) {
			Write-LogDebug "Window-Only Retry Mode: preserving virtual desktops, reapplying FancyZones"
		}

		# Window-only retry applies the FULL layout config: a snap pass records EVERY window
		# that exhausted its attempts (and its circuit breaker can still abort a systemically
		# failing pass mid-way), so filtering the retry to a single recorded failure would
		# strand the other failures at their inset size and verify only the filtered subset.
		# Idempotent skips keep the full pass cheap (already-correct windows are
		# position-checked and left alone). The recorded markers are diagnostics.
		if ($windowOnlyRetryActive -and ($windowOnlyRetryTitle -or $windowOnlyRetryProcess)) {
			Write-LogDebug " Window-only retry trigger => [$(@($windowOnlyRetryProcess, $windowOnlyRetryTitle) | Where-Object { $_ } | Select-Object -First 1)] (applying full layout config)" -Style Warning
		}

		$simpleLayoutWorkspaces = $global:Configuration.SimpleLayoutWorkspaces

		# Documented boundary: simple layouts (Fullscreen/Empty) deliberately ignore
		# ProtectedWindowHandles. They are global-by-design gestures - fullscreen every window
		# on every desktop, replace CurrentLayout.txt whole - and scoping them would change
		# what the gesture means.
		if ($simpleLayoutWorkspaces -contains $layoutNameToUse) {
			# Capture where every window sits BEFORE the zone grids are (re)applied. Applying a
			# changed zone set can make FancyZones itself relocate remembered windows across
			# monitors (its "move windows on zone-set change" behavior consults
			# app-zone-history) - seen after Reset-Windows gathers everything onto one monitor
			# while the history still records zones on another. "Fullscreen wherever the window
			# is" means wherever it was when the workspace was INVOKED, so the placement pass
			# below resolves each window's monitor from this snapshot, not from wherever the
			# layout application left it.
			$preApplyWindowRects = @{}
			if ($layoutNameToUse -ne 'Empty') {
				foreach ($preWin in @(Get-WindowHandle -ErrorAction SilentlyContinue)) {
					$preApplyWindowRects[$preWin.Handle] = [PSCustomObject]@{
						Left   = $preWin.Left
						Top    = $preWin.Top
						Width  = $preWin.Width
						Height = $preWin.Height
					}
				}
			}

			if ($config.Monitors) {
				# Monitor coverage was already extended for every workspace right after the layout
				# file was loaded (Expand-LayoutMonitorCoverage), so all attached monitors are
				# present in $config.Monitors by this point.
				#
				# Simple layouts typically only define VirtualDesktopLayouts for desktop 1.
				# Expand VirtualDesktopLayouts to cover ALL existing virtual desktops so
				# Apply-FancyZones applies the layout everywhere, not just on desktop 1.
				$existingDesktops = Get-DesktopList
				$existingDesktopCount = ($existingDesktops | Measure-Object).Count

				if ($existingDesktopCount -gt 1) {
					foreach ($monitorKey in @($config.Monitors.Keys)) {
						$monitor = $config.Monitors[$monitorKey]
						if ($monitor.VirtualDesktopLayouts -and $monitor.VirtualDesktopLayouts.ContainsKey(1)) {
							$baseLayout = $monitor.VirtualDesktopLayouts[1]
							for ($d = 2; $d -le $existingDesktopCount; $d++) {
								if (-not $monitor.VirtualDesktopLayouts.ContainsKey($d)) {
									$monitor.VirtualDesktopLayouts[$d] = $baseLayout
								}
							}
						}
					}

					Write-LogDebug " Expanded simple layout to all $existingDesktopCount virtual desktop(s)"
				}

				$null = Apply-FancyZones -MonitorConfig $config.Monitors -MonitorInfo $cachedMonitorInfo
				Write-LogDebug "=> $layoutNameToUse layout applied successfully!" -Style Success
			}
			else {
				Write-LogDebug " No Monitor configuration found for $layoutNameToUse layout!" -Style Warning
			}

			if ($layoutNameToUse -ne 'Empty') {
				# Phase 2: place every window into its monitor's fullscreen zone. The zone grid
				# was just applied above; windows are placed DIRECTLY at each monitor's single
				# zone rect (Invoke-SingleZoneWindowPlacement) instead of being snapped with
				# Win+Up. FancyZones' Win+Arrow is a RELATIVE move and a single-zone layout has
				# no neighbouring zone to resolve to: with moveWindowAcrossMonitors enabled it
				# throws an already-recognised window to the OTHER monitor's zone, and on one
				# monitor it no-ops - the exact mechanics that jumbled fullscreen opens. Direct
				# SetWindowPos placement is verified per window (Wait-WindowRect) and works on
				# windows parked on INVISIBLE desktops, so the desktop-switching loop, the focus
				# stealing, and the repeated re-snap of windows whose desktop could not be
				# resolved (the old "-1 bucket") are all gone with it.
				#
				# Each monitor's zone rect is computed once from the base (desktop 1) layout -
				# the expansion above clones that same layout to every desktop, so the rect is
				# desktop-independent.
				$simpleMonitorSpecs = Get-MonitorSpecs -MonitorInfo $cachedMonitorInfo
				$monitorZoneRects = [System.Collections.Generic.List[object]]::new()
				$allMonitorsSingleZone = $true

				foreach ($monitorKey in @($config.Monitors.Keys)) {
					$monitorEntry = $config.Monitors[$monitorKey]
					$baseLayoutName = $null
					if ($monitorEntry.VirtualDesktopLayouts -and $monitorEntry.VirtualDesktopLayouts.ContainsKey(1)) {
						$baseLayoutName = $monitorEntry.VirtualDesktopLayouts[1]
					}
					elseif ($monitorEntry.Layout) {
						$baseLayoutName = $monitorEntry.Layout
					}

					$monitorSpec = $simpleMonitorSpecs.($monitorKey)
					if (-not $baseLayoutName -or -not $monitorSpec) {
						continue
					}

					# Zone geometry uses the WORK AREA, same as Set-WindowLayouts - FancyZones
					# lays zones over the work area, not the full bounds.
					$workX = if ($null -ne $monitorSpec.WorkX) { $monitorSpec.WorkX } else { $monitorSpec.X }
					$workY = if ($null -ne $monitorSpec.WorkY) { $monitorSpec.WorkY } else { $monitorSpec.Y }
					$workWidth = if ($monitorSpec.WorkWidth) { $monitorSpec.WorkWidth } else { $monitorSpec.Width }
					$workHeight = if ($monitorSpec.WorkHeight) { $monitorSpec.WorkHeight } else { $monitorSpec.Height }

					$monitorZones = @(Get-FancyZoneCoordinates -LayoutName $baseLayoutName -MonitorX $workX -MonitorY $workY -MonitorWidth $workWidth -MonitorHeight $workHeight)
					if ($monitorZones.Count -eq 1) {
						# Full bounds for window-to-monitor matching (a window's center can sit
						# in the taskbar strip that the work area excludes).
						$monitorZoneRects.Add([PSCustomObject]@{
								Label  = $monitorKey
								Left   = $monitorSpec.X
								Top    = $monitorSpec.Y
								Right  = $monitorSpec.X + $monitorSpec.Width
								Bottom = $monitorSpec.Y + $monitorSpec.Height
								Zone   = $monitorZones[0]
							})
					}
					else {
						$allMonitorsSingleZone = $false
					}
				}

				if ($allMonitorsSingleZone -and $monitorZoneRects.Count -gt 0) {
					$placedCount = 0
					$skippedCount = 0
					$failedPlacements = [System.Collections.Generic.List[string]]::new()

					foreach ($win in @(Get-WindowHandle -ErrorAction SilentlyContinue)) {
						# Same shell-window exclusions as Snap-AllWindows -All.
						if ($win.Title -match '^(Program Manager|Windows Input Experience|TextInputHost|Search|Start|Action center)$') {
							continue
						}

						# Resolve the window's monitor from its center point, preferring the
						# pre-apply snapshot: FancyZones may have relocated the window while the
						# zone grids were applied above, and the window belongs fullscreen on the
						# monitor it sat on when the workspace was invoked. A minimized window
						# reports an off-screen rect (around -32000) in both readings, so restore
						# it once - the way the old foreground-based snap implicitly did - and
						# re-read its live position.
						$winLeft = $win.Left
						$winTop = $win.Top
						$winWidth = $win.Width
						$winHeight = $win.Height

						$preApplyRect = $preApplyWindowRects[$win.Handle]
						if ($preApplyRect) {
							$winLeft = $preApplyRect.Left
							$winTop = $preApplyRect.Top
							$winWidth = $preApplyRect.Width
							$winHeight = $preApplyRect.Height
						}

						$targetMonitorZone = $null

						for ($resolveAttempt = 1; $resolveAttempt -le 2 -and -not $targetMonitorZone; $resolveAttempt++) {
							$centerX = $winLeft + ($winWidth / 2)
							$centerY = $winTop + ($winHeight / 2)
							$targetMonitorZone = $monitorZoneRects | Where-Object {
								$centerX -ge $_.Left -and $centerX -le $_.Right -and
								$centerY -ge $_.Top -and $centerY -le $_.Bottom
							} | Select-Object -First 1

							if (-not $targetMonitorZone -and $resolveAttempt -eq 1) {
								[void][WindowModule.Native]::ShowWindow($win.Handle, [WindowModule.Native]::SW_RESTORE)
								Start-Sleep -Milliseconds $script:WindowModuleDelays.WindowRestoreMs
								$restoredRect = New-Object WindowModule.RECT
								if ([WindowModule.Native]::GetWindowRect($win.Handle, [ref]$restoredRect)) {
									$winLeft = $restoredRect.Left
									$winTop = $restoredRect.Top
									$winWidth = $restoredRect.Right - $restoredRect.Left
									$winHeight = $restoredRect.Bottom - $restoredRect.Top
								}
								else {
									break
								}
							}
						}

						if (-not $targetMonitorZone) {
							$skippedCount++
							Write-LogDebug "  ⚠ Could not resolve a monitor for [$($win.Title)] - skipping" -Style Warning
							continue
						}

						$placement = Invoke-SingleZoneWindowPlacement -WindowHandle $win.Handle `
							-TargetX $targetMonitorZone.Zone.X -TargetY $targetMonitorZone.Zone.Y `
							-TargetWidth $targetMonitorZone.Zone.Width -TargetHeight $targetMonitorZone.Zone.Height `
							-WindowTitle $win.Title

						if ($placement.Verified) {
							$placedCount++
							Write-LogDebug "     ✓ Placed [$($win.Title)] => $($targetMonitorZone.Label) fullscreen zone" -Style Success
						}
						else {
							$failedPlacements.Add($win.Title)
							Write-LogDebug "     ✗ Placement unverified for [$($win.Title)] (expected $($targetMonitorZone.Zone.X), $($targetMonitorZone.Zone.Y) $($targetMonitorZone.Zone.Width)x$($targetMonitorZone.Zone.Height))" -Style Error
						}
					}

					if ($failedPlacements.Count -gt 0) {
						Write-LogWarning "Placed [$placedCount] window(s) fullscreen, but [$($failedPlacements.Count)] failed:"
						foreach ($failedTitle in $failedPlacements) {
							Write-LogError "   $failedTitle" -NoLeadingNewline
						}
					}
					else {
						Write-LogDebug "=> Placed [$placedCount] window(s) fullscreen ([$skippedCount] skipped)!" -Style Success
					}
				}
				else {
					# Legacy per-desktop keyboard snap, kept only for a simple layout whose grid
					# is NOT single-zone (none ship today - Fullscreen is single-zone and Empty
					# never reaches here). Snapping needs the window focusable on the active
					# desktop, hence the switch per desktop; windows whose desktop cannot be
					# resolved go in the -1 bucket and are offered on every pass.
					$allDesktops = Get-DesktopList
					$desktopCount = ($allDesktops | Measure-Object).Count

					if ($desktopCount -gt 1) {
						$windowsByDesktopIndex = @{}
						foreach ($win in @(Get-WindowHandle -ErrorAction SilentlyContinue)) {
							$winDesktopIndex = -1
							try {
								$winDesktopIndex = Get-DesktopIndex (Get-DesktopFromWindow -Hwnd $win.Handle.ToInt64())
							}
							catch {
								$winDesktopIndex = -1
							}
							if (-not $windowsByDesktopIndex.ContainsKey($winDesktopIndex)) {
								$windowsByDesktopIndex[$winDesktopIndex] = [System.Collections.Generic.List[IntPtr]]::new()
							}
							$windowsByDesktopIndex[$winDesktopIndex].Add($win.Handle)
						}

						for ($d = 0; $d -lt $desktopCount; $d++) {
							$desktopHandles = [System.Collections.Generic.List[IntPtr]]::new()
							if ($windowsByDesktopIndex.ContainsKey($d)) {
								$desktopHandles.AddRange($windowsByDesktopIndex[$d])
							}
							if ($windowsByDesktopIndex.ContainsKey(-1)) {
								$desktopHandles.AddRange($windowsByDesktopIndex[-1])
							}

							if ($desktopHandles.Count -eq 0) {
								Write-LogDebug " Desktop [$($d + 1)] has no windows to snap - skipping switch"
								continue
							}

							Write-LogDebug " Switching to Desktop [$($d + 1)] for snapping..."
							$null = Switch-Desktop -Desktop $d
							if (-not (Wait-DesktopSwitch -TargetDesktopIndex $d)) {
								Start-Sleep -Milliseconds 25
							}
							$null = Snap-AllWindows -All -WindowHandles $desktopHandles.ToArray() -SnapDelayMs $SnapDelayMs
						}
						# Return to desktop 1
						$null = Switch-Desktop -Desktop 0
					}
					else {
						$null = Snap-AllWindows -All -SnapDelayMs $SnapDelayMs
					}
				}
			}

			if ($spinner) {
				Loading-Spinner -Stop -Spinner $spinner -Completed
				$spinner = $null
			}

			# Simple layouts (e.g. Fullscreen) have no per-zone window placement, but still
			# record the virtual desktop count and the FancyZones layout applied to each
			# desktop/monitor (Windows left empty).
			if ($layoutNameToUse -and $layoutsDir -and $config.Monitors) {
				$simpleDesktopCount = if ($existingDesktopCount -and $existingDesktopCount -gt 0) { $existingDesktopCount } else { 1 }
				Save-CurrentLayout -Workspace $layoutNameToUse -LayoutsDir $layoutsDir -MachineType $machineType `
					-DesktopOffset $DesktopOffset -Alongside:$Alongside -DesktopCount $simpleDesktopCount `
					-LayoutConfig $config.Layout -MonitorConfig $config.Monitors -WindowStates @()
			}

			Write-LogSuccess "Workspace layout applied successfully!"

			Visualize-Layouts -Layout $machineSpecificLayoutFileName.Replace(".psd1", "")

			return
		}

		if (-not $config.Layout) {
			if ($spinner) { [void](Loading-Spinner -Stop -Spinner $spinner -Discard); $spinner = $null }
			Write-LogError "Invalid layout configuration => [Layout] property not found!"
			return
		}

		# Calculate required virtual desktops from Monitors configuration
		# VirtualDesktopLayouts keys are 1-based, so max key equals the count
		$requiredVirtualDesktops = 1
		if ($config.Monitors) {
			foreach ($monitorEntry in $config.Monitors.GetEnumerator()) {
				$monitorConfig = $monitorEntry.Value
				if ($monitorConfig.VirtualDesktopLayouts) {
					# With 1-based keys, the maximum key value equals the desktop count
					$maxDesktopIndex = ($monitorConfig.VirtualDesktopLayouts.Keys | Measure-Object -Maximum).Maximum
					$desktopCount = $maxDesktopIndex  # 1-based: max key IS the count
					if ($desktopCount -gt $requiredVirtualDesktops) {
						$requiredVirtualDesktops = $desktopCount
					}
				}
			}
		}

		# Pause the live "Applying layout" spinner across the virtual-desktop and FancyZones
		# reconfiguration. These sub-steps (Remove-VirtualDesktops, Ensure-VirtualDesktops,
		# Apply-FancyZones) print their own section titles/summaries, which would otherwise be
		# clobbered and interleaved by the spinner's background timer (it rewrites its line via
		# carriage returns on a separate thread). Pause erases the spinner line and suspends the
		# timer so this output lands cleanly; Resume re-draws the spinner afterwards.
		if ($spinner) { Loading-Spinner -Pause }

		if (-not $windowOnlyRetryActive) {
			# When using alongside mode, we're adding a new workspace next to existing desktops
			# Don't reset existing desktops, just ensure we have enough total desktops
			# totalRequired = DesktopOffset + requiredVirtualDesktops
			$totalRequiredDesktops = $requiredVirtualDesktops + $DesktopOffset

			# Check current virtual desktop count and only reset if necessary
			$currentDesktops = Get-DesktopList
			$currentDesktopCount = ($currentDesktops | Measure-Object).Count

			if ($Alongside) {
				# Alongside mode: Don't remove existing desktops, only add more if needed

				Write-LogDebug "=> Opening workspace alongside$(if ($DesktopOffset -gt 0) { " with offset => [+$DesktopOffset]" })"
				Write-LogDebug " Workspace requires $requiredVirtualDesktops desktop(s)" -Style Step
				Write-LogDebug " Total desktops needed: [$totalRequiredDesktops] (current => $currentDesktopCount)" -Style Step

				if ($currentDesktopCount -lt $totalRequiredDesktops) {
					Write-LogDebug "=> Creating $($totalRequiredDesktops - $currentDesktopCount) additional desktop(s)..." -Style Warning
					$vdResult = Ensure-VirtualDesktops -Count $totalRequiredDesktops
					if (-not $vdResult) {
						throw "Failed to create required virtual desktops (RPC server may be unavailable)"
					}
				}
				else {
					Write-LogDebug "=> Sufficient desktops already exist ($currentDesktopCount >= $totalRequiredDesktops)" -Style Success
				}
			}
			else {
				# The resize target starts at what THIS layout needs, but a preserved alongside
				# workspace's desktops raise the floor: Ensure-VirtualDesktops removes desktops
				# from the RIGHT, which is exactly where an alongside workspace lives, so
				# shrinking to the layout's own count would delete it. The floor is resolved
				# LIVE from where the protected windows stand (desktop indexes shift and stored
				# ones go stale - same rule as Close-Workspace).
				$targetDesktopCount = $requiredVirtualDesktops
				if ($hasProtectedWindows) {
					$protectedFloor = 0
					$anyProtectedResolved = $false
					$overlappingProtected = 0

					foreach ($protectedHandle in $ProtectedWindowHandles) {
						$protectedIndex = Get-WindowDesktopIndex -WindowHandle $protectedHandle
						if ($protectedIndex -lt 0) { continue }

						$anyProtectedResolved = $true
						if (($protectedIndex + 1) -gt $protectedFloor) { $protectedFloor = $protectedIndex + 1 }

						# A protected window INSIDE this layout's own desktop range cannot be
						# protected by desktop arithmetic - the layout pass works those desktops.
						# Its window is still exempt from moving/counting, but the collision is
						# worth a warning: the workspaces are overlapping.
						if ($protectedIndex -lt $requiredVirtualDesktops) { $overlappingProtected++ }
					}

					if ($overlappingProtected -gt 0) {
						Write-LogWarning "$overlappingProtected preserved alongside window(s) sit inside this layout's desktop range (desktops 1-$requiredVirtualDesktops) - the workspaces overlap"
					}

					if ($anyProtectedResolved) {
						$targetDesktopCount = [Math]::Max($requiredVirtualDesktops, $protectedFloor)
					}
					else {
						# Protected windows exist but none resolved to a desktop (enumeration
						# hiccup). Shrinking on unknown occupancy could delete the alongside
						# workspace - never shrink; growing to the layout's need is still safe.
						$targetDesktopCount = [Math]::Max($requiredVirtualDesktops, $currentDesktopCount)
					}

					if ($targetDesktopCount -gt $requiredVirtualDesktops) {
						Write-LogDebug "=> Preserving alongside desktops - keeping $targetDesktopCount desktop(s) instead of shrinking to $requiredVirtualDesktops" -Style Success
					}
				}

				if ($currentDesktopCount -eq $targetDesktopCount) {
					Write-LogDebug "=> Virtual desktop count already matches required count ($targetDesktopCount) - skipping reset" -Style Success
				}
				else {
					Write-LogDebug "=> Virtual desktop count mismatch (current: $currentDesktopCount, required: $targetDesktopCount) - resizing to required count" -Style Warning

					# Delta resize: Ensure-VirtualDesktops grows AND shrinks. The previous
					# Remove-all-then-recreate pair collapsed to one desktop first, so going
					# 2->3 desktops paid one removal plus two creates (each a COM roundtrip
					# with settle sleeps) plus gratuitous desktop churn, instead of one create.
					$vdResult = Ensure-VirtualDesktops -Count $targetDesktopCount
					if (-not $vdResult) {
						throw "Failed to resize virtual desktops to required count (RPC server may be unavailable)"
					}
				}
			}

		}
		elseif (Test-LogVerbose) {
			Write-LogDebug "Window-only retry active - skipping virtual desktop reconfiguration" -Style Warning
		}

		if ($config.Monitors) {
			if ($windowOnlyRetryActive -and (Test-LogVerbose)) {
				Write-LogDebug "Window-only retry active - force-reapplying FancyZones monitor layout"
			}

			# Always reapply per-desktop FancyZones (including reruns) so snapped zones are refreshed
			# while still preserving any already-created virtual desktops.
			#
			# A window-only rerun exists only because the previous run could not get windows into
			# their zones, and the usual cause is a wrong LIVE zone grid. Reapplying idempotently
			# there is worse than useless: the check reads applied-layouts.json, which still claims
			# the correct layout, so every monitor is skipped and the rerun snaps into the very same
			# broken grid. -Force re-sends the shortcuts unconditionally on that path.
			$null = Apply-FancyZones -MonitorConfig $config.Monitors -MonitorInfo $cachedMonitorInfo `
				-DesktopOffset $DesktopOffset -DesktopCount $requiredVirtualDesktops -Force:$windowOnlyRetryActive
		}
		elseif ($windowOnlyRetryActive -and (Test-LogVerbose)) {
			Write-LogDebug "Window-only retry active - no monitor config found to reapply FancyZones" -Style Warning
		}

		# Reconfiguration sub-steps have finished printing their output - bring the spinner back.
		if ($spinner) { Loading-Spinner -Resume }

		# Use pre-captured existing windows if provided (from Open-Workspace)
		# Otherwise capture them now (for standalone calls to Set-WorkspaceWindowLayout)
		if ($PreCapturedExistingWindows) {
			$existingWindowHandles = $PreCapturedExistingWindows
		}
		else {
			$existingWindows = Get-WindowHandle -ErrorAction SilentlyContinue
			$existingWindowHandles = New-Object 'System.Collections.Generic.HashSet[IntPtr]'
			if ($existingWindows) {
				foreach ($window in $existingWindows) {
					[void]$existingWindowHandles.Add($window.Handle)
				}
			}
		}

		Write-LogDebug " Captured $($existingWindowHandles.Count) existing window handle(s)"

		# Use consolidated native types from WindowNative.cs (loaded in Window.psm1)
		# WindowModule.Native provides: SetForegroundWindow(), etc.

		$windowStates = @{}

		# Callback fired by Wait-ForWorkspaceWindows as each window first becomes individually stable.
		# Immediately moves the window to its configured virtual desktop so desktop relocation
		# overlaps with the remaining windows still loading, rather than waiting until all are ready.
		$onWindowStableCallback = {
			param($layoutEntry, $window)

			if ($null -eq $layoutEntry.DesktopNumber) { return }
			if ($Alongside -and $existingWindowHandles -and $existingWindowHandles.Contains($window.Handle)) { return }
			# Plain-mode analogue of the alongside guard above: a preserved workspace's window
			# matched a layout entry by title/process, but it is not this open's to move.
			if ($ProtectedWindowHandles -and $ProtectedWindowHandles.Contains($window.Handle)) { return }

			$internalDesktopIndex = ($layoutEntry.DesktopNumber - 1) + $DesktopOffset
			try {
				$null = Move-WindowToVirtualDesktop -WindowHandle $window.Handle -DesktopNumber $internalDesktopIndex
				if (Test-LogVerbose) {
					$displayDesktop = $layoutEntry.DesktopNumber + $DesktopOffset
					Write-LogDebug "Early move: [$($window.Title)] => Desktop $displayDesktop" -Style Success
				}
			}
			catch {}
		}

		if ($DisableAutoWait -or $windowOnlyRetryActive) {
			if (Test-LogVerbose) {
				if ($windowOnlyRetryActive) {
					Write-LogDebug "Window-only retry mode - skipping auto-wait" -Style Warning
				}
				else {
					Write-LogDebug "Auto-wait disabled - proceeding immediately!" -Style Error
				}
			}
		}
		else {
			$waitResult = Wait-ForWorkspaceWindows -LayoutConfig $config.Layout -TimeoutSeconds $TimeoutSeconds -OnWindowStable $onWindowStableCallback

			# Use the state snapshot whenever one was captured - even on partial success
			# (abandoned entries) the stable windows' handles feed the title-drift fallbacks.
			if ($waitResult -and $waitResult.WindowStates -and $waitResult.WindowStates.Count -gt 0) {
				$windowStates = $waitResult.WindowStates
				if (Test-LogVerbose) {
					Write-LogDebug "Window state snapshot captured for validation: $($windowStates.Count) window(s)" -Style Success
				}
			}

			if (-not ($waitResult -and $waitResult.Success)) {
				Write-LogDebug " Wait-ForWorkspaceWindows did not fully succeed (timeout or partial detection)" -Style Warning
			}
		}

		# Focus all browser windows on their first tab to ensure correct window title matching
		if ($layoutConfigToApply -and -not $windowOnlyRetryActive) {
			$browserProcesses = @("chrome", "firefox", "msedge", "brave", "chromium")
			$browserLayoutProcessPatterns = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
			# Resolved title patterns of the browser entries - used to decide which windows
			# actually need the tab reset (and which are already showing a wanted title).
			$browserEntryTitlePatterns = [System.Collections.Generic.List[string]]::new()

			foreach ($windowDef in $layoutConfigToApply) {
				if (-not $windowDef.ProcessName -or -not $windowDef.WindowTitle -or $windowDef.WindowTitle -eq '$null') {
					continue
				}

				$processName = $windowDef.ProcessName
				$isBrowser = $false
				if ($browserProcesses -contains $processName.ToLower()) {
					$isBrowser = $true
				}
				elseif ($processName -ieq 'Browser') {
					# "Browser" is a layout alias - expand to a real process regex so the window lookup works
					$processName = "(firefox|chrome|msedge|brave|chromium)"
					$isBrowser = $true
				}
				elseif ($processName -match '[\.\[\]\(\)\{\}\+\^\$\|\\*\?]') {
					try {
						$isBrowser = $browserProcesses | Where-Object { $_ -match $processName } | Select-Object -First 1
					}
					catch {
						$isBrowser = $false
					}
				}

				if ($isBrowser) {
					[void]$browserLayoutProcessPatterns.Add($processName)

					$resolvedEntry = Resolve-LayoutTokens -LayoutEntry $windowDef
					if ($resolvedEntry.WindowTitle -and $resolvedEntry.WindowTitle -ne '$null') {
						$browserEntryTitlePatterns.Add([string]$resolvedEntry.WindowTitle)
					}
				}
			}

			if ($browserLayoutProcessPatterns.Count -eq 0) {
				Write-LogDebug "[Skipping Browser First-Tab Normalization - no title-sensitive browser entries]"
			}
			else {
				# Add SendKeys support for browser tab switching only when needed.
				Ensure-WindowsFormsLoaded

				Write-LogDebug "[Focusing Browser Windows on First Tab]"

				# Fetch all windows once and filter per browser process (avoids one Get-WindowHandle call per process)
				$allWindows = Get-WindowHandle -ErrorAction SilentlyContinue

				# Pre-existing browser windows are only worth touching when some browser entry
				# currently matches NO window (its title may be hidden behind the active tab).
				# When every entry already resolves, resetting pre-existing windows to tab 1
				# would only disturb personal windows that are not part of this workspace.
				$unresolvedEntryExists = $false
				foreach ($titlePattern in $browserEntryTitlePatterns) {
					$patternMatched = $false
					foreach ($candidateWindow in $allWindows) {
						# A preserved workspace's window can never resolve an entry - the layout
						# pass is not allowed to use it, so counting it here would leave the
						# entry starved while claiming it is resolved.
						if ($ProtectedWindowHandles -and $ProtectedWindowHandles.Contains($candidateWindow.Handle)) { continue }
						if (Test-WindowTitleMatch -WindowTitle $candidateWindow.Title -Patterns @($titlePattern)) {
							$patternMatched = $true
							break
						}
					}
					if (-not $patternMatched) {
						$unresolvedEntryExists = $true
						break
					}
				}

				# Focus each browser window and switch to first tab
				foreach ($browserProcess in $browserLayoutProcessPatterns) {
					try {
						# Use regex matching if the process name contains special characters, otherwise exact match
						if ($browserProcess -match '[\.\[\]\(\)\{\}\+\^\$\|\\*\?]') {
							$browserWindows = $allWindows | Where-Object { $_.ProcessName -match $browserProcess }
						}
						else {
							$browserWindows = $allWindows | Where-Object { $_.ProcessName -eq $browserProcess }
						}

						if ($browserWindows) {
							foreach ($window in $browserWindows) {
								# A preserved workspace's browser window is never normalized -
								# resetting it to tab 1 would rearrange a workspace this open
								# must leave alone.
								if ($ProtectedWindowHandles -and $ProtectedWindowHandles.Contains($window.Handle)) {
									Write-LogDebug "  Skipping preserved alongside browser window => [$($window.Title)]" -Style Warning
									continue
								}

								# Windows opened by THIS flow are always normalized; pre-existing
								# ones only when an entry is still unresolved (see above).
								$isNewWindow = -not ($existingWindowHandles -and $existingWindowHandles.Contains($window.Handle))
								if (-not $isNewWindow -and -not $unresolvedEntryExists) {
									Write-LogDebug "  Skipping pre-existing browser window (all browser entries already resolve) => [$($window.Title)]" -Style Warning
									continue
								}

								# A window already showing a wanted title is on the right tab -
								# resetting it to tab 1 could hide that title and break matching.
								$titleAlreadyWanted = $false
								foreach ($titlePattern in $browserEntryTitlePatterns) {
									if (Test-WindowTitleMatch -WindowTitle $window.Title -Patterns @($titlePattern)) {
										$titleAlreadyWanted = $true
										break
									}
								}
								if ($titleAlreadyWanted) {
									Write-LogDebug "  Skipping browser window already showing a wanted title => [$($window.Title)]" -Style Warning
									continue
								}

								Write-LogDebug "  Processing browser window => [$($window.Title)]" -Style Step

								try {
									# Focus the window
									[void][WindowModule.Native]::SetForegroundWindow($window.Handle)
									Start-Sleep -Milliseconds $script:WindowModuleDelays.FocusSettleMs

									# Switch to first tab (Ctrl+1)
									[System.Windows.Forms.SendKeys]::SendWait("^1")
									Start-Sleep -Milliseconds $script:WindowModuleDelays.KeyboardShortcutMs

									if (Test-LogVerbose) {
										# Verify the tab switch by checking the new title
										$updatedWindow = Get-WindowHandle -ProcessName $browserProcess -ErrorAction SilentlyContinue |
											Where-Object { $_.Handle -eq $window.Handle } |
											Select-Object -First 1

										if ($updatedWindow) {
											Write-LogDebug "Focused on first tab => [$($updatedWindow.Title)]" -Style Success
										}
									}
								}
								catch {
									Write-LogDebug "    Failed to focus first tab for window [$($window.Title)]: $_" -Style Warning
								}
							}
						}
					}
					catch {
						Write-LogDebug "  Failed to process browser [$browserProcess]: $_" -Style Warning
					}
				}
			}
		}

		# Windows have loaded and the layout is being applied - resolve the spinner to a
		# success checkmark now, before the positioning/resize summary prints, so all
		# subsequent output appears cleanly beneath a single "✓".
		if ($spinner) {
			Loading-Spinner -Stop -Spinner $spinner -Completed
			$spinner = $null
		}

		# On first workspace open, normalize windows by resizing and centering before
		# precise layout positioning. This ensures freshly opened windows start from a
		# consistent state for FancyZones snapping. Skip if windows are already at their
		# exact target positions (e.g., rerun or workspace already configured).
		if (-not $windowOnlyRetryActive -and $PreCapturedExistingWindows -and $PreCapturedExistingWindows.Count -gt 0) {
			$currentAllWindows = Get-WindowHandle -ErrorAction SilentlyContinue
			$hasNewWindows = $false
			if ($currentAllWindows) {
				foreach ($win in $currentAllWindows) {
					if (-not $existingWindowHandles.Contains($win.Handle)) {
						$hasNewWindows = $true
						break
					}
				}
			}

			if ($hasNewWindows) {
				# Always normalize on first open - some apps (e.g. Outlook) remember their
				# last size/position which can interfere with FancyZones snapping.

				Write-LogDebug "[First Open - Normalizing Windows]"

				# Normalize only the windows THIS open created (not in the pre-open capture).
				# The previous non-alongside branch resized EVERY visible window on the machine
				# to 70% - including unrelated apps - only for Set-WindowLayouts to reposition
				# the workspace ones again right after.
				$newWindows = @($currentAllWindows | Where-Object { -not $existingWindowHandles.Contains($_.Handle) })
				Write-LogDebug "  Normalizing $($newWindows.Count) new window(s) only" -Style Step
				foreach ($newWin in $newWindows) {
					$null = Resize-Windows -WindowHandle $newWin.Handle
				}
			}
		}

		$setLayoutParams = @{
			LayoutConfig          = $layoutConfigToApply
			MonitorInfo           = $cachedMonitorInfo
			MonitorConfig         = $config.Monitors
			ExistingWindowHandles = $existingWindowHandles
			ExpectedWindowState   = $windowStates
			DesktopOffset         = $DesktopOffset
		}
		if ($Alongside) {
			$setLayoutParams["SkipExistingWindows"] = $true
		}
		if ($hasProtectedWindows) {
			$setLayoutParams["ProtectedWindowHandles"] = $ProtectedWindowHandles
		}
		if ($pinnedHandleMap -and $pinnedHandleMap.Count -gt 0) {
			$setLayoutParams["PinnedHandleMap"] = $pinnedHandleMap
		}
		# --- Position -> snap -> verify, with bounded IN-PROCESS retries ---
		# A failed snap/verification used to escalate straight to a full terminal-respawn rerun
		# (15-45s: other tabs killed, fresh shell + full module load, whole action list re-run).
		# The stale-COM state that once justified a fresh shell is self-healed in-process by the
		# RPC probe at entry, so wrong windows are retried HERE first: refresh the
		# existing-window snapshot (already-correct windows then skip via the position check),
		# re-position, re-snap, re-verify. Verification runs against the FULL layout config,
		# which also covers windows an aborted snap pass never reached. The terminal respawn
		# remains as the last resort only.
		$maxInProcessAttempts = 3   # 1 initial pass + 2 in-process retries
		$layoutApplied = $false
		$verificationResult = $null
		$snapFailures = @()
		$results = $null
		$retryTrigger = $null

		# Recovery action run before EVERY retry. A snap/verification failure almost never
		# means "the window refused to move" - it means the zone grid the snap targeted was
		# wrong: FancyZones dead, crash-looping, or holding a stale in-memory grid. Re-running
		# position -> snap -> verify against that same grid can never succeed, which is why
		# the liveness-only check this replaces recovered nothing:
		#   - a bare Start-FancyZones caches a successful readiness pass for 10s, so
		#     back-to-back retries got a cached $true and did literally nothing, and
		#   - even a real pass only proves the PROCESS is healthy, never that the workspace's
		#     zone grid is applied.
		# -ForceRestart invalidates that cache and rebuilds the process; the re-apply then has
		# to be forced too, because a restarted FancyZones reloads applied-layouts.json without
		# re-asserting the live grid, and that same JSON is what the idempotency check reads -
		# so an unforced re-apply reports "Already Applied" everywhere and sends nothing.
		#
		# This costs a PowerToys restart plus a desktop-switching layout pass per retry. That is
		# deliberate: the alternative it exists to prevent is a 15-45s terminal respawn.
		$resetFancyZonesState = {
			param([string]$Reason)

			Write-LogWarning "   Resetting FancyZones ($Reason)..." -NoLeadingNewline

			try {
				$null = Start-FancyZones -ForceRestart -MaxWaitSeconds 20 -ErrorAction Stop
			}
			catch {
				Write-LogWarning "   Failed to force-restart FancyZones: $($_.Exception.Message)" -NoLeadingNewline
			}

			if (-not $config.Monitors) {
				Write-LogWarning "   No monitor configuration - zone grids could not be re-applied" -NoLeadingNewline
				return
			}

			try {
				$null = Apply-FancyZones -MonitorConfig $config.Monitors -MonitorInfo $cachedMonitorInfo `
					-DesktopOffset $DesktopOffset -DesktopCount $requiredVirtualDesktops -Force
			}
			catch {
				Write-LogWarning "   Failed to re-apply FancyZones zone layouts: $($_.Exception.Message)" -NoLeadingNewline
			}
		}

		for ($layoutAttempt = 1; $layoutAttempt -le $maxInProcessAttempts; $layoutAttempt++) {
			if ($layoutAttempt -gt 1) {
				Write-LogWarning "In-process window retry (attempt $($layoutAttempt - 1)/$($maxInProcessAttempts - 1))..."

				# Synthesized input from the failed pass may have stranded a modifier.
				if (Get-Command Reset-KeyboardModifiers -ErrorAction SilentlyContinue) {
					$null = Reset-KeyboardModifiers -IncludeMouseButton
				}

				[void](& $resetFancyZonesState $(if ($retryTrigger) { $retryTrigger } else { 'layout not applied' }))

				# Windows moved during the failed pass - never let a retry match against a stale
				# enumeration. Both modes need this; only the snapshot handling below differs.
				Clear-WindowCache

				# Refresh the existing-handles snapshot so windows that are ALREADY correct are
				# skipped by Set-WindowLayouts' position check and only wrong windows get redone.
				# Not in alongside mode: there ExistingWindowHandles means "another workspace's
				# windows - do not touch" and must stay the original pre-open capture.
				if (-not $Alongside) {
					$retrySnapshotWindows = Get-WindowHandle -ErrorAction SilentlyContinue
					$retryExistingHandles = New-Object 'System.Collections.Generic.HashSet[IntPtr]'
					if ($retrySnapshotWindows) {
						foreach ($retryWindow in $retrySnapshotWindows) {
							[void]$retryExistingHandles.Add($retryWindow.Handle)
						}
					}
					$setLayoutParams["ExistingWindowHandles"] = $retryExistingHandles
				}
			}

			$results = Set-WindowLayouts @setLayoutParams

			$successful = ($results | Where-Object { $_.Status -eq "Configured" }).Count
			$notFound = ($results | Where-Object { $_.Status -eq "Not Found" }).Count

			if ($notFound -gt 0) {
				Write-LogDebug " Not Found => [$notFound]" -Style Warning
				# Verbose-only used to be the ONLY report of a starved layout, so a run that
				# filled 12 of 33 zones read exactly like a clean one. Name the shortfall with
				# both counts: the usual cause is too few eligible windows to go round (an
				# alongside open cannot use windows that were already open).
				Write-LogWarning "Layout short by $notFound window(s) - placed $successful of $($successful + $notFound) entries!"
			}

			Write-LogDebug "=> [$successful] layout(s) applied successfully!" -Style Success
			Write-LogDebug " Waiting for windows to stabilize..."

			Start-Sleep -Milliseconds $SnapDelayMs

			# Default (20px) tolerance: with 0, apps that self-adjust by a pixel (terminal cell
			# rounding, min-size constraints, DPI rounding) were re-positioned on EVERY open
			# forever and never converged.
			$resizeResult = Resize-PositionedWindows
			if ((Test-LogVerbose) -and $resizeResult.FailedWindows.Count -gt 0) {
				Write-LogDebug "Pre-snap resize failures => [$($resizeResult.FailedWindows.Count)]" -Style Warning
			}

			# Always 0, never $DesktopOffset. Add-PositionedWindow records each window's desktop
			# with the offset ALREADY folded in (Set-WindowLayouts: $config.DesktopNumber +
			# $DesktopOffset), and Snap-AllWindows runs those numbers back through
			# ConvertTo-InternalDesktopIndex, which adds DesktopOffset a second time. Passing
			# the real offset therefore sent the snap pass to a desktop the windows were never
			# on: with -DesktopOffset 2, a window tracked as desktop 3 resolved to internal
			# index 4 while it actually sat on index 2, and nothing on that desktop could snap.
			# Only alongside was passing 0 - and only alongside was correct.
			$null = Snap-AllWindows -DesktopOffset 0 -DesktopCount $requiredVirtualDesktops
			$snapResult = $script:LastSnapAllWindowsResult

			$snapFailures = @()
			if ($snapResult) {
				$failedWindowsProperty = $snapResult.PSObject.Properties['FailedWindows']
				if ($failedWindowsProperty -and $failedWindowsProperty.Value) {
					$snapFailures = @($failedWindowsProperty.Value)
				}
			}

			if ($snapFailures.Count -gt 0) {
				$retryTrigger = "snap failed for $($snapFailures.Count) window(s)"
				Write-LogWarning "Snap-AllWindows failed after retry logic - $($snapFailures.Count) window(s) did not snap:"

				foreach ($failure in $snapFailures) {
					Write-Host -ForegroundColor DarkCyan "`n   [$($failure.WindowTitle)]"
					if ($failure.Expected) {
						Write-LogSuccess "     Expected => $($failure.Expected)" -NoLeadingNewline
					}
					if ($failure.Actual) {
						Write-LogWarning "     Actual   => $($failure.Actual)" -NoLeadingNewline
					}
					if ($failure.Error) {
						Write-LogError "     Error    => $($failure.Error)" -NoLeadingNewline
					}
				}

				# Next in-process attempt (or escalation after the loop).
				continue
			}

			# Final fast verification - confirm every layout entry has a live, correctly-positioned
			# window. A normal open runs against the FULL layout config so entries a previous
			# aborted snap pass never reached are covered too.
			#
			# Alongside used to return an unconditional success here, which disabled the retry
			# loop below AND let Save-CurrentLayout persist a starved/mispositioned pass as the
			# truth - the next open then pinned windows to those wrong zones, which is what made
			# the scrambling compound run after run. It is verified now, but scoped twice over:
			# only the entries this pass actually placed a window for, matched only against
			# windows this open created. Another workspace's windows can therefore neither be
			# checked nor mistaken for ours, so the false failures the blanket skip existed to
			# avoid still cannot happen.
			$verificationResult = if (-not $Alongside) {
				# A preserved workspace's windows are excluded: the layout pass was forbidden
				# from touching them, so judging an entry against one would verify a window
				# this open never placed.
				$plainVerifyParams = @{
					LayoutConfig  = $config.Layout
					MonitorInfo   = $cachedMonitorInfo
					MonitorConfig = $config.Monitors
					DesktopOffset = $DesktopOffset
				}
				if ($hasProtectedWindows) {
					$plainVerifyParams['ExcludeWindowHandles'] = $ProtectedWindowHandles
				}
				Confirm-WorkspaceWindowPositions @plainVerifyParams
			}
			else {
				$claimedEntries = @(
					$results | Where-Object { $_.Status -eq 'Configured' -and $_.LayoutEntry } |
						ForEach-Object { $_.LayoutEntry }
				)

				if ($claimedEntries.Count -eq 0) {
					# Nothing was placed, so there is nothing a retry could re-place - the
					# shortfall warning above is the report. Retrying would only pay for
					# FancyZones restarts that cannot conjure windows.
					@{ Success = $true }
				}
				else {
					Confirm-WorkspaceWindowPositions `
						-LayoutConfig $claimedEntries `
						-MonitorInfo $cachedMonitorInfo `
						-MonitorConfig $config.Monitors `
						-DesktopOffset $DesktopOffset `
						-ExcludeWindowHandles $existingWindowHandles
				}
			}

			if ($verificationResult.Success) {
				$layoutApplied = $true
				break
			}

			$failCount = $verificationResult.Failures.Count
			$totalCount = $verificationResult.Total
			$retryTrigger = "verification failed for $failCount/$totalCount window(s)"
			Write-LogWarning "Layout verification failed - $failCount/$totalCount window(s) mispositioned:"

			foreach ($failure in $verificationResult.Failures) {
				Write-Host -ForegroundColor DarkCyan "`n   [$($failure.WindowTitle)]"
				Write-LogSuccess "     Expected => $($failure.Expected)" -NoLeadingNewline
				Write-LogWarning "     Actual   => $($failure.Actual)" -NoLeadingNewline
			}
		}

		if (-not $layoutApplied) {
			if (-not (Test-LogVerbose)) {
				Loading-Spinner -Stop -Spinner $spinner
			}

			# Same cleanup the success path runs after saving - giving up should not leave the
			# empty desktops these attempts created behind either.
			if ($Alongside) {
				Remove-VirtualDesktops -EmptyOnly
			}

			# Escalation: in-process retries exhausted. Track the terminal-respawn count across
			# spawns (process env with a one-shot User-scope mirror - see $readRerunState above).
			$maxReruns = 2
			$rerunCount = [int](& $readRerunState 'WORKSPACE_RERUN_COUNT')

			if ($rerunCount -ge $maxReruns) {
				Write-LogError "Maximum auto-reruns ($maxReruns) reached - stopping to prevent infinite loop!"
				& $writeRerunState 'WORKSPACE_RERUN_COUNT' $null
				return
			}

			& $writeRerunState 'WORKSPACE_RERUN_COUNT' ([string]($rerunCount + 1))
			if (-not $Alongside) {
				$escalationFailures = if ($snapFailures.Count -gt 0) {
					$snapFailures
				}
				elseif ($verificationResult -and $verificationResult.Failures) {
					@($verificationResult.Failures)
				}
				else {
					@()
				}
				$failedWindow = $escalationFailures | Where-Object { $null -ne $_.Handle -and $_.Handle -ne [IntPtr]::Zero } | Select-Object -First 1
				$firstFailure = $escalationFailures | Select-Object -First 1

				# The markers are informational only (logged by the respawned run): the retry
				# applies the FULL layout config, so windows an aborted snap pass never reached
				# are not stranded by a single-entry filter.
				if ($firstFailure -and $firstFailure.WindowTitle) {
					& $writeRerunState $windowOnlyRetryTitleEnvVar $firstFailure.WindowTitle
				}
				if ($firstFailure -and $firstFailure.ProcessName) {
					& $writeRerunState $windowOnlyRetryProcessEnvVar $firstFailure.ProcessName
				}
				& $writeRerunState $windowOnlyRetryEnvVar '1'
				[void](Initialize-WorkspaceWindowLayoutRerun -WindowOnlyRetry)

				if ($failedWindow) {
					$null = Resize-Windows -WindowHandle $failedWindow.Handle
				}
				[void](& $resetKeyboardStateBeforeRerun)
				[void](& $ensureFancyZonesBeforeRerun)

				$rerunParams = @{
					AutoAccept   = $true
					ErrorMessage = " Rerunning workspace setup in a fresh shell (in-process retries exhausted)! (attempt $($rerunCount + 1)/$maxReruns)"
				}
				# Prefer the exact recorded invocation over PSReadLine history scraping - the
				# shared history file may contain a newer command typed in another session.
				if (-not [string]::IsNullOrWhiteSpace($env:WORKSPACE_RERUN_COMMAND)) {
					$rerunParams["Command"] = $env:WORKSPACE_RERUN_COMMAND
				}

				try {
					ReRun-LastCommand @rerunParams
				}
				finally {
					# ReRun-LastCommand ends this process on success ([Environment]::Exit skips
					# finally blocks) - so REACHING this point means the respawn did NOT happen
					# (early return or spawn failure). Clear the one-shot markers so the next
					# manual open does not silently run in window-only retry mode.
					& $writeRerunState $windowOnlyRetryEnvVar $null
					& $writeRerunState $windowOnlyRetryTitleEnvVar $null
					& $writeRerunState $windowOnlyRetryProcessEnvVar $null
				}
			}
			else {
				Write-LogWarning "   In-process retries exhausted for alongside mode - please rerun manually if needed." -NoLeadingNewline
			}
			return
		}

		if (-not (Test-LogVerbose)) {
			Loading-Spinner -Stop -Spinner $spinner
		}

		# Clear rerun counter on success
		& $writeRerunState 'WORKSPACE_RERUN_COUNT' $null

		# Record the applied layout (virtual desktop count, FancyZones per desktop, and every
		# positioned window with its desktop/monitor/zone) so the next open/reopen/alongside
		# can pin identically-named windows back to their zones. Best-effort.
		#
		# The window list is built from the layout results rather than the snap-tracking set,
		# because tracking only contains windows that were *repositioned* this run - on an
		# idempotent re-run almost everything is already correct and skipped, which would
		# otherwise shrink the snapshot and break pinning on the following run. The results
		# include every configured window (moved or already-correct), keeping it complete.
		if ($layoutNameToUse -and $layoutsDir) {
			$recordedWindows = @(
				$results | Where-Object {
					$_.Status -eq 'Configured' -and $null -ne $_.Handle -and $_.Handle -ne [IntPtr]::Zero -and $null -ne $_.ExpectedX
				} | ForEach-Object {
					@{
						Handle         = $_.Handle
						# Actual process name (e.g. "chrome"), not the layout regex token, so the
						# pin's live-window process guard matches on the next open.
						ProcessName    = $_.WindowProcessName
						ProcessId      = $_.ProcessId
						WindowTitle    = $_.WindowTitle
						DesktopNumber  = $_.DesktopDisplay
						Monitor        = $_.MonitorLabel
						Zone           = $_.ZoneName
						Layout         = $_.LayoutName
						ExpectedX      = $_.ExpectedX
						ExpectedY      = $_.ExpectedY
						ExpectedWidth  = $_.ExpectedWidth
						ExpectedHeight = $_.ExpectedHeight
					}
				}
			)
			# A protecting plain open merges instead of replacing, so the preserved alongside
			# workspaces keep their CurrentLayout sections (and with them their zone pinning).
			Save-CurrentLayout -Workspace $layoutNameToUse -LayoutsDir $layoutsDir -MachineType $machineType `
				-DesktopOffset $DesktopOffset -Alongside:$Alongside -DesktopCount $requiredVirtualDesktops `
				-LayoutConfig $config.Layout -MonitorConfig $config.Monitors -WindowStates $recordedWindows `
				-PreserveOtherSections:$hasProtectedWindows
		}

		# Empty-desktop cleanup runs LAST, once, after the snapshot is written. It used to run
		# inside the retry loop right after each snap, where removing a desktop to the LEFT of
		# the workspace (the original desktop, now empty because its windows moved) shifts every
		# later desktop down by one - silently invalidating $DesktopOffset for the remaining
		# attempts and for the record just saved, whose contract is
		# "actual desktop = record Desktop + section DesktopOffset".
		if ($Alongside) {
			Remove-VirtualDesktops -EmptyOnly
		}

		Write-LogSuccess "Workspace layout applied successfully!"

		Visualize-Layouts -Layout $machineSpecificLayoutFileName.Replace(".psd1", "")

		return
	}
	catch {
		if ($spinner) {
			Loading-Spinner -Stop -Spinner $spinner -Discard
			$spinner = $null
		}

		Write-LogError "Error applying workspace layout: $($_.Exception.Message)"
		Write-LogError "   Stack trace => $($_.ScriptStackTrace)" -NoLeadingNewline

		# Rerun protection: track the rerun count across terminal spawns (process env
		# with a one-shot User-scope mirror - see $readRerunState above)
		$maxReruns = 2
		$rerunCount = [int](& $readRerunState 'WORKSPACE_RERUN_COUNT')

		if ($rerunCount -ge $maxReruns) {
			Write-LogError "Maximum auto-reruns ($maxReruns) reached - stopping to prevent infinite loop!"
			& $writeRerunState 'WORKSPACE_RERUN_COUNT' $null
			return
		}

		& $writeRerunState 'WORKSPACE_RERUN_COUNT' ([string]($rerunCount + 1))
		if (-not $Alongside) {
			$failedWindow = $null
			if ($snapResult -and $snapResult.FailedWindows) {
				$failedWindow = $snapResult.FailedWindows | Where-Object { $null -ne $_.Handle -and $_.Handle -ne [IntPtr]::Zero } | Select-Object -First 1
			}
			if ($snapResult -and $snapResult.FailedWindows -and $snapResult.FailedWindows.Count -gt 0) {
				$firstFailedSnap = $snapResult.FailedWindows | Select-Object -First 1
				if ($firstFailedSnap.WindowTitle) {
					& $writeRerunState $windowOnlyRetryTitleEnvVar $firstFailedSnap.WindowTitle
				}
			}
			& $writeRerunState $windowOnlyRetryEnvVar '1'
			[void](Initialize-WorkspaceWindowLayoutRerun -WindowOnlyRetry)

			if ($failedWindow) {
				$null = Resize-Windows -WindowHandle $failedWindow.Handle
			}
			[void](& $resetKeyboardStateBeforeRerun)
			[void](& $ensureFancyZonesBeforeRerun)

			$rerunParams = @{
				AutoAccept   = $true
				ErrorMessage = " Rerunning workspace setup (window-only retry)! (attempt $($rerunCount + 1)/$maxReruns)"
			}
			if (-not [string]::IsNullOrWhiteSpace($env:WORKSPACE_RERUN_COMMAND)) {
				$rerunParams["Command"] = $env:WORKSPACE_RERUN_COMMAND
			}

			try {
				ReRun-LastCommand @rerunParams
			}
			finally {
				# Reaching this point means the respawn did NOT happen (see the matching
				# cleanup in the escalation path above) - clear the one-shot markers.
				& $writeRerunState $windowOnlyRetryEnvVar $null
				& $writeRerunState $windowOnlyRetryTitleEnvVar $null
				& $writeRerunState $windowOnlyRetryProcessEnvVar $null
			}
		}
		else {
			Write-LogWarning "   Auto-rerun disabled for alongside mode - please rerun manually if needed." -NoLeadingNewline
		}
	}
	finally {
		# Safety net: guarantee the layout spinner is always torn down, even on the
		# early-return paths above, so its background animation timer never leaks.
		# Erase (no checkmark) - reaching here with a live spinner is not a clean success.
		if ($spinner) { [void](Loading-Spinner -Stop -Spinner $spinner -Discard) }
	}
}
