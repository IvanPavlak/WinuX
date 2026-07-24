function Set-WorkspaceWindowLayout {
	<#
	.SYNOPSIS
		Applies a workspace-specific window layout configuration.

	.DESCRIPTION
		Loads and applies a predefined window layout for a specific workspace.
		Layout files are stored in machine-specific subfolders within the Window module's
		Layouts directory (e.g., Layouts/PC/, Layouts/Laptop/, Layouts/Work/).

		Supports layouts with duplicate window entries where the same ProcessName and
		WindowTitle appear multiple times to place identical windows in different zones.
		This is used with Open-Browser's Override parameter which opens the same URL
		group in a separate browser window, allowing both to be positioned independently.

		On snap failure or final layout verification failure, automatically triggers a
		workspace rerun in window-only retry mode that:
		- Preserves already configured virtual desktops
		- Re-applies FancyZones monitor layouts
		- Targets only the failed window entry on the rerun
		- Re-runs resize + snap for that window in a fresh shell
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
		Default is 30 seconds.

	.PARAMETER SnapDelayMs
		Milliseconds to wait after positioning before snapping windows.
		Default is SnapDelayMs. Increase if windows are not properly snapped.

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
		[switch]$Alongside
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
	# rerun loop. Each value is therefore mirrored at User scope as "value|unix-timestamp".
	# Reads prefer the process copy (identical behavior to the plain env vars when it
	# propagates) and fall back to the mirror; the mirror is one-shot - consumed on first
	# read and aged out after the TTL - so a stale value can never leak into a later run.
	$rerunStateTtlMinutes = 10
	$readRerunState = {
		param([string]$Name)
		$processValue = [Environment]::GetEnvironmentVariable($Name, 'Process')
		$persisted = [Environment]::GetEnvironmentVariable($Name, 'User')
		if (-not [string]::IsNullOrEmpty($persisted)) {
			[Environment]::SetEnvironmentVariable($Name, $null, 'User')
		}
		if (-not [string]::IsNullOrEmpty($processValue)) { return $processValue }
		if ([string]::IsNullOrEmpty($persisted)) { return $null }
		$parts = $persisted -split '\|', 2
		if ($parts.Count -lt 2) { return $null }
		$timestamp = 0L
		if (-not [long]::TryParse($parts[1], [ref]$timestamp)) { return $null }
		$ageMinutes = ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $timestamp) / 60.0
		if ($ageMinutes -gt $rerunStateTtlMinutes -or $ageMinutes -lt 0) { return $null }
		return $parts[0]
	}
	$writeRerunState = {
		param([string]$Name, [string]$Value)
		[Environment]::SetEnvironmentVariable($Name, $Value, 'Process')
		if ([string]::IsNullOrEmpty($Value)) {
			[Environment]::SetEnvironmentVariable($Name, $null, 'User')
		}
		else {
			[Environment]::SetEnvironmentVariable($Name, "$Value|$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())", 'User')
		}
	}

	$windowOnlyRetryActive = (& $readRerunState $windowOnlyRetryEnvVar) -eq '1'
	$windowOnlyRetryTitle = & $readRerunState $windowOnlyRetryTitleEnvVar
	$windowOnlyRetryProcess = & $readRerunState $windowOnlyRetryProcessEnvVar
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

			$machineType = DetermineMachineType

			$layoutNameToUse = $WorkspaceName
			if (-not $WorkspaceName -or $WorkspaceName -eq 'Fullscreen') {
				$layoutNameToUse = 'Fullscreen'
			}

			if ($cachedMonitorInfo) {
				# Detect if using a small display (laptop-sized)
				$primaryMonitor = $cachedMonitorInfo | Where-Object { $_.IsPrimary } | Select-Object -First 1
				if (-not $primaryMonitor) {
					$primaryMonitor = $cachedMonitorInfo | Select-Object -First 1
				}

				# A small (laptop-class) display uses a dedicated single-monitor layout set whose
				# machine-type name is configured (e.g. "Laptop"); empty/unset = no override.
				$smallDisplayType = $Configuration.SmallDisplayMachineType
				if ($primaryMonitor -and $primaryMonitor.Width -le 3000 -and -not [string]::IsNullOrWhiteSpace($smallDisplayType)) {
					$machineType = $smallDisplayType
					Write-LogDebug " Detected small display ($($primaryMonitor.Width)x$($primaryMonitor.Height)) => using $machineType layout" -Style Warning
				}
			}

			$machineSpecificLayoutFileName = "${layoutNameToUse}_${machineType}.psd1"

			$machineSpecificLayoutPath = Join-Path $layoutsDir $machineType $machineSpecificLayoutFileName

			if (Test-Path $machineSpecificLayoutPath) {
				$LayoutPath = $machineSpecificLayoutPath
				Write-LogDebug "Using machine-specific layout => [$machineSpecificLayoutFileName]" -Style Success
			}
			else {
				if ($spinner) { [void](Loading-Spinner -Stop -Spinner $spinner -Discard); $spinner = $null }
				Write-LogWarning "No layout configuration found for workspace => [$WorkspaceName]"
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

		if ($windowOnlyRetryActive -and $layoutConfigToApply) {
			$targetedLayoutConfig = @($layoutConfigToApply | Where-Object {
					($windowOnlyRetryTitle -and $_.WindowTitle -eq $windowOnlyRetryTitle) -or
					($windowOnlyRetryProcess -and $_.ProcessName -eq $windowOnlyRetryProcess)
				})

			if ($targetedLayoutConfig.Count -gt 0) {
				$layoutConfigToApply = $targetedLayoutConfig
				Write-LogDebug " Retrying only targeted window layout entries => [$($layoutConfigToApply.Count)]" -Style Warning
			}
			elseif (Test-LogVerbose) {
				Write-LogDebug "Target retry window marker did not match layout entries - applying full layout config" -Style Warning
			}
		}

		$simpleLayoutWorkspaces = $global:Configuration.SimpleLayoutWorkspaces

		if ($simpleLayoutWorkspaces -contains $layoutNameToUse) {
			if ($config.Monitors) {
				# Ensure ALL physical monitors are covered, not just those in the layout file.
				# Layout files may only define Primary (e.g., Fullscreen_Work.psd1) but the
				# machine could be docked with multiple monitors. Auto-add missing monitors
				# using the first defined monitor's layout as a template.
				if ($cachedMonitorInfo) {
					$monitorSpecs = Get-MonitorSpecs -MonitorInfo $cachedMonitorInfo
					$templateMonitor = $config.Monitors.Values | Select-Object -First 1
					foreach ($specKey in $monitorSpecs.Keys) {
						if (-not $config.Monitors.ContainsKey($specKey) -and $templateMonitor -and $templateMonitor.VirtualDesktopLayouts) {
							$config.Monitors[$specKey] = @{
								VirtualDesktopLayouts = @{}
							}
							foreach ($dk in $templateMonitor.VirtualDesktopLayouts.Keys) {
								$config.Monitors[$specKey].VirtualDesktopLayouts[$dk] = $templateMonitor.VirtualDesktopLayouts[$dk]
							}
							Write-LogDebug "  Auto-added monitor [$specKey] to simple layout config" -Style Warning
						}
					}
				}

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
				# Phase 2: now that the FancyZones "Zero" (fullscreen) layout is applied to every
				# monitor on every desktop, snap each desktop's windows into that zone. We must
				# switch to each desktop in turn because snapping requires the target window to be
				# focusable on the active desktop. Snap-AllWindows -CurrentDesktopOnly restricts
				# each pass to the windows that actually live on that desktop, so every window is
				# snapped exactly once on its own desktop/monitor instead of being re-snapped on
				# every pass (GetAllWindows enumerates windows across all virtual desktops).
				$allDesktops = Get-DesktopList
				$desktopCount = ($allDesktops | Measure-Object).Count

				if ($desktopCount -gt 1) {
					for ($d = 0; $d -lt $desktopCount; $d++) {
						Write-LogDebug " Switching to Desktop [$($d + 1)] for snapping..."
						$null = Switch-Desktop -Desktop $d
						if (-not (Wait-DesktopSwitch -TargetDesktopIndex $d)) {
							Start-Sleep -Milliseconds 25
						}
						$null = Snap-AllWindows -All -CurrentDesktopOnly -SnapDelayMs $SnapDelayMs
					}
					# Return to desktop 1
					$null = Switch-Desktop -Desktop 0
				}
				else {
					$null = Snap-AllWindows -All -SnapDelayMs $SnapDelayMs
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
			elseif ($currentDesktopCount -eq $requiredVirtualDesktops) {
				Write-LogDebug "=> Virtual desktop count already matches required count ($requiredVirtualDesktops) - skipping reset" -Style Success
			}
			else {
				Write-LogDebug "=> Virtual desktop count mismatch (current: $currentDesktopCount, required: $requiredVirtualDesktops) - resetting desktops" -Style Warning

				$removeResult = Remove-VirtualDesktops
				if ($removeResult -eq $false) {
					throw "Failed to remove virtual desktops (RPC server may be unavailable)"
				}

				if ($requiredVirtualDesktops -gt 1) {
					$vdResult = Ensure-VirtualDesktops -Count $requiredVirtualDesktops
					if (-not $vdResult) {
						throw "Failed to create required virtual desktops (RPC server may be unavailable)"
					}
				}
			}

		}
		elseif (Test-LogVerbose) {
			Write-LogDebug "Window-only retry active - skipping virtual desktop reconfiguration" -Style Warning
		}

		if ($config.Monitors) {
			if ($windowOnlyRetryActive -and (Test-LogVerbose)) {
				Write-LogDebug "Window-only retry active - reapplying FancyZones monitor layout"
			}

			# Always reapply per-desktop FancyZones (including reruns) so snapped zones are refreshed
			# while still preserving any already-created virtual desktops.
			$null = Apply-FancyZones -MonitorConfig $config.Monitors -MonitorInfo $cachedMonitorInfo -DesktopOffset $DesktopOffset -DesktopCount $requiredVirtualDesktops
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

			if ($waitResult -and $waitResult.Success) {
				$windowStates = $waitResult.WindowStates
				if ((Test-LogVerbose) -and $windowStates.Count -gt 0) {
					Write-LogDebug "Window state snapshot captured for validation: $($windowStates.Count) window(s)" -Style Success
				}
			}
			else {
				Write-LogDebug " Wait-ForWorkspaceWindows did not fully succeed (timeout or partial detection)" -Style Warning
			}
		}

		# Focus all browser windows on their first tab to ensure correct window title matching
		if ($layoutConfigToApply -and -not $windowOnlyRetryActive) {
			$browserProcesses = @("chrome", "firefox", "msedge", "brave", "chromium")
			$browserLayoutProcessPatterns = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

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
				}
			}

			if ($browserLayoutProcessPatterns.Count -eq 0) {
				Write-LogDebug "[Skipping Browser First-Tab Normalization - no title-sensitive browser entries]"
			}
			else {
				# Add SendKeys support for browser tab switching only when needed.
				Ensure-WindowsFormsLoaded
				$uiAutomationAvailable = $false
				try {
					Add-Type -AssemblyName UIAutomationClient -ErrorAction Stop
					$uiAutomationAvailable = $true
				}
				catch {
					Write-LogDebug " UI Automation unavailable - browser tab count checks will be skipped" -Style Warning
				}

				$testBrowserWindowHasMultipleTabs = {
					param($WindowHandle)

					if (-not $uiAutomationAvailable -or $null -eq $WindowHandle -or $WindowHandle -eq [IntPtr]::Zero) {
						return $null
					}

					try {
						$root = [System.Windows.Automation.AutomationElement]::FromHandle($WindowHandle)
						if (-not $root) {
							return $null
						}

						$tabCondition = New-Object System.Windows.Automation.PropertyCondition(
							[System.Windows.Automation.AutomationElement]::ControlTypeProperty,
							[System.Windows.Automation.ControlType]::TabItem
						)

						$tabItems = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $tabCondition)
						return ($tabItems.Count -gt 1)
					}
					catch {
						return $null
					}
				}

				Write-LogDebug "[Focusing Browser Windows on First Tab]"

				# Fetch all windows once and filter per browser process (avoids one Get-WindowHandle call per process)
				$allWindows = Get-WindowHandle -ErrorAction SilentlyContinue

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
								Write-LogDebug "  Processing browser window => [$($window.Title)]" -Style Step

								try {
									$hasMultipleTabs = & $testBrowserWindowHasMultipleTabs -WindowHandle $window.Handle
									if ($hasMultipleTabs -eq $false) {
										Write-LogDebug "    Skipping first-tab normalization - single-tab window detected" -Style Warning
										continue
									}

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

				# $anyWindowNeedsPositioning = $false
				# $normMonitorSpecs = if ($cachedMonitorInfo) { Get-MonitorSpecs -MonitorInfo $cachedMonitorInfo } else { $null }
				# Clear-WindowCache

				# foreach ($layoutEntry in $config.Layout) {
				# 	$targetX = $null; $targetY = $null; $targetW = $null; $targetH = $null

				# 	if ($layoutEntry.Zone) {
				# 		$normLayoutName = $layoutEntry.Layout
				# 		if (-not $normLayoutName -and $layoutEntry.Monitor -and $null -ne $layoutEntry.DesktopNumber -and $config.Monitors) {
				# 			if ($config.Monitors.ContainsKey($layoutEntry.Monitor) -and
				# 				$config.Monitors[$layoutEntry.Monitor].VirtualDesktopLayouts -and
				# 				$config.Monitors[$layoutEntry.Monitor].VirtualDesktopLayouts.ContainsKey($layoutEntry.DesktopNumber)) {
				# 				$normLayoutName = $config.Monitors[$layoutEntry.Monitor].VirtualDesktopLayouts[$layoutEntry.DesktopNumber]
				# 			}
				# 		}
				# 		if (-not $normLayoutName) { continue }

				# 		$normMonX = 0; $normMonY = 0; $normMonW = 3440; $normMonH = 1440
				# 		if ($layoutEntry.Monitor) {
				# 			if ($layoutEntry.Monitor -is [string] -and $normMonitorSpecs) {
				# 				$spec = $normMonitorSpecs.($layoutEntry.Monitor)
				# 				# Zone geometry uses the work area (Work* fields) - see Set-WindowLayouts
				# 				if ($spec) { $normMonX = $spec.WorkX; $normMonY = $spec.WorkY; $normMonW = $spec.WorkWidth; $normMonH = $spec.WorkHeight }
				# 			}
				# 			elseif ($layoutEntry.Monitor -isnot [string]) {
				# 				$normMonX = if ($null -ne $layoutEntry.Monitor.X) { $layoutEntry.Monitor.X } else { 0 }
				# 				$normMonY = if ($null -ne $layoutEntry.Monitor.Y) { $layoutEntry.Monitor.Y } else { 0 }
				# 				$normMonW = if ($layoutEntry.Monitor.Width) { $layoutEntry.Monitor.Width } else { 3440 }
				# 				$normMonH = if ($layoutEntry.Monitor.Height) { $layoutEntry.Monitor.Height } else { 1440 }
				# 			}
				# 		}

				# 		$normZone = Get-FancyZone -LayoutName $normLayoutName -ZoneName $layoutEntry.Zone `
				# 			-MonitorX $normMonX -MonitorY $normMonY -MonitorWidth $normMonW -MonitorHeight $normMonH
				# 		if ($normZone) {
				# 			$targetX = $normZone.X; $targetY = $normZone.Y
				# 			$targetW = $normZone.Width; $targetH = $normZone.Height
				# 		}
				# 	}
				# 	elseif ($null -ne $layoutEntry.X -and $null -ne $layoutEntry.Y -and $layoutEntry.Width -and $layoutEntry.Height) {
				# 		$targetX = $layoutEntry.X; $targetY = $layoutEntry.Y
				# 		$targetW = $layoutEntry.Width; $targetH = $layoutEntry.Height
				# 	}

				# 	if ($null -eq $targetX) { continue }

				# 	$matchWindow = $null
				# 	if ($layoutEntry.WindowTitle) {
				# 		$matchWindow = Get-WindowHandle -WindowTitle $layoutEntry.WindowTitle | Select-Object -First 1
				# 	}
				# 	else {
				# 		$matchWindow = Get-WindowHandle -ProcessName $layoutEntry.ProcessName | Select-Object -First 1
				# 	}

				# 	if (-not $matchWindow) {
				# 		$anyWindowNeedsPositioning = $true
				# 		break
				# 	}

				# 	$normTolerance = 20
				# 	$xOk = [Math]::Abs($matchWindow.Left - $targetX) -le $normTolerance
				# 	$yOk = [Math]::Abs($matchWindow.Top - $targetY) -le $normTolerance
				# 	$wOk = [Math]::Abs($matchWindow.Width - $targetW) -le $normTolerance
				# 	$hOk = [Math]::Abs($matchWindow.Height - $targetH) -le $normTolerance

				# 	if (-not ($xOk -and $yOk -and $wOk -and $hOk)) {
				# 		$anyWindowNeedsPositioning = $true
				# 		break
				# 	}
				# }
				#if ($anyWindowNeedsPositioning) {

				Write-LogDebug "[First Open - Normalizing Windows]"

				if ($Alongside) {
					# In alongside mode, only normalize NEW windows to avoid
					# disturbing the already-positioned workspace
					$newWindows = @($currentAllWindows | Where-Object { -not $existingWindowHandles.Contains($_.Handle) })
					Write-LogDebug "  Alongside mode - normalizing $($newWindows.Count) new window(s) only" -Style Step
					foreach ($newWin in $newWindows) {
						$null = Resize-Windows -WindowHandle $newWin.Handle
					}
				}
				else {
					$null = Resize-Windows
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
		if ($pinnedHandleMap -and $pinnedHandleMap.Count -gt 0) {
			$setLayoutParams["PinnedHandleMap"] = $pinnedHandleMap
		}
		$results = Set-WindowLayouts @setLayoutParams

		$successful = ($results | Where-Object { $_.Status -eq "Configured" }).Count
		$notFound = ($results | Where-Object { $_.Status -eq "Not Found" }).Count

		if ($notFound -gt 0) {
			Write-LogDebug " Not Found => [$notFound]" -Style Warning
		}

		Write-LogDebug "=> [$successful] layout(s) applied successfully!" -Style Success
		Write-LogDebug " Waiting for windows to stabilize..."

		Start-Sleep -Milliseconds $SnapDelayMs

		$resizeResult = Resize-PositionedWindows -Tolerance 0
		if ((Test-LogVerbose) -and $resizeResult.FailedWindows.Count -gt 0) {
			Write-LogDebug "Pre-snap resize failures => [$($resizeResult.FailedWindows.Count)]" -Style Warning
		}

		$snapDesktopOffset = if ($Alongside) { 0 } else { $DesktopOffset }
		$null = Snap-AllWindows -DesktopOffset $snapDesktopOffset -DesktopCount $requiredVirtualDesktops
		$snapResult = $script:LastSnapAllWindowsResult

		if ($Alongside) {
			Remove-VirtualDesktops -EmptyOnly
		}

		$snapFailures = @()
		if ($snapResult) {
			$failedWindowsProperty = $snapResult.PSObject.Properties['FailedWindows']
			if ($failedWindowsProperty -and $failedWindowsProperty.Value) {
				$snapFailures = @($failedWindowsProperty.Value)
			}
		}

		if ($snapFailures.Count -gt 0) {
			if (-not (Test-LogVerbose)) {
				Loading-Spinner -Stop -Spinner $spinner
			}

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
				$failedWindow = $snapFailures | Where-Object { $null -ne $_.Handle -and $_.Handle -ne [IntPtr]::Zero } | Select-Object -First 1
				$failedSnap = $snapFailures | Select-Object -First 1

				if ($failedSnap -and $failedSnap.WindowTitle) {
					& $writeRerunState $windowOnlyRetryTitleEnvVar $failedSnap.WindowTitle
				}
				if ($failedSnap -and $failedSnap.ProcessName) {
					& $writeRerunState $windowOnlyRetryProcessEnvVar $failedSnap.ProcessName
				}
				& $writeRerunState $windowOnlyRetryEnvVar '1'
				[void](Initialize-WorkspaceWindowLayoutRerun -WindowOnlyRetry)

				if ($failedWindow) {
					$null = Resize-Windows -WindowHandle $failedWindow.Handle
				}
				[void](& $resetKeyboardStateBeforeRerun)
				[void](& $ensureFancyZonesBeforeRerun)
				ReRun-LastCommand -AutoAccept -ErrorMessage " Rerunning workspace setup due to snap failure (window-only retry)! (attempt $($rerunCount + 1)/$maxReruns)"
			}
			else {
				Write-LogWarning "   Auto-rerun disabled for alongside mode - please rerun manually if needed." -NoLeadingNewline
			}
			return
		}

		# Final fast verification - confirm every layout entry has a live, correctly-positioned window
		# Skip verification in alongside mode - shared windows between workspaces make position
		# checks unreliable (windows may legitimately belong to the other workspace's layout)
		$verificationResult = if (-not $Alongside) {
			Confirm-WorkspaceWindowPositions `
				-LayoutConfig $layoutConfigToApply `
				-MonitorInfo $cachedMonitorInfo `
				-MonitorConfig $config.Monitors `
				-DesktopOffset $DesktopOffset
		}
		else {
			@{ Success = $true }
		}


		if (-not $verificationResult.Success) {
			if (-not (Test-LogVerbose)) {
				Loading-Spinner -Stop -Spinner $spinner
			}

			$failCount = $verificationResult.Failures.Count
			$totalCount = $verificationResult.Total
			Write-LogWarning "Layout verification failed - $failCount/$totalCount window(s) mispositioned:"

			foreach ($failure in $verificationResult.Failures) {
				Write-Host -ForegroundColor DarkCyan "`n   [$($failure.WindowTitle)]"
				Write-LogSuccess "     Expected => $($failure.Expected)" -NoLeadingNewline
				Write-LogWarning "     Actual   => $($failure.Actual)" -NoLeadingNewline
			}

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
				$failedWindow = $verificationResult.Failures | Where-Object { $null -ne $_.Handle -and $_.Handle -ne [IntPtr]::Zero } | Select-Object -First 1
				if (-not $failedWindow -and $snapResult -and $snapResult.FailedWindows) {
					$failedWindow = $snapResult.FailedWindows | Where-Object { $null -ne $_.Handle -and $_.Handle -ne [IntPtr]::Zero } | Select-Object -First 1
				}
				$failedLayoutEntry = $verificationResult.Failures | Select-Object -First 1
				if ($failedLayoutEntry -and $failedLayoutEntry.WindowTitle) {
					& $writeRerunState $windowOnlyRetryTitleEnvVar $failedLayoutEntry.WindowTitle
				}
				if ($failedLayoutEntry -and $failedLayoutEntry.ProcessName) {
					& $writeRerunState $windowOnlyRetryProcessEnvVar $failedLayoutEntry.ProcessName
				}
				& $writeRerunState $windowOnlyRetryEnvVar '1'
				[void](Initialize-WorkspaceWindowLayoutRerun -WindowOnlyRetry)

				if ($failedWindow) {
					$null = Resize-Windows -WindowHandle $failedWindow.Handle
				}
				[void](& $resetKeyboardStateBeforeRerun)
				[void](& $ensureFancyZonesBeforeRerun)
				ReRun-LastCommand -AutoAccept -ErrorMessage " Rerunning workspace setup due to mispositioned windows (window-only retry)! (attempt $($rerunCount + 1)/$maxReruns)"
			}
			else {
				Write-LogWarning "   Auto-rerun disabled for alongside mode - please rerun manually if needed." -NoLeadingNewline
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
			Save-CurrentLayout -Workspace $layoutNameToUse -LayoutsDir $layoutsDir -MachineType $machineType `
				-DesktopOffset $DesktopOffset -Alongside:$Alongside -DesktopCount $requiredVirtualDesktops `
				-LayoutConfig $config.Layout -MonitorConfig $config.Monitors -WindowStates $recordedWindows
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
			ReRun-LastCommand -AutoAccept -ErrorMessage " Rerunning workspace setup (window-only retry)! (attempt $($rerunCount + 1)/$maxReruns)"
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
