function Apply-FancyZones {
	<#
	.SYNOPSIS
		Applies FancyZones layouts to monitors on the workspace's virtual desktops.

	.DESCRIPTION
		Puts the zone layouts a layout file names - per monitor, per virtual desktop - in place.
		By default (Configuration.FancyZonesApplyMethod = "File") the entries are written straight
		into FancyZones' applied-layouts.json for every desktop this call owns
		(Write-AppliedFancyZonesLayouts); FancyZones watches that file and reloads it. One probe
		shortcut on the current desktop then makes FancyZones save its in-memory layout map back to
		the file, and Test-AppliedFancyZonesLayouts checks that every written entry survived - which
		proves the reload without switching to a single desktop. Any desktop that does not verify,
		and every desktop when the method is "Hotkeys", is handled by the shortcut pass: switch to
		the desktop, position the cursor on each monitor and send Win+Ctrl+Alt+[Number]
		(Send-FancyZonesLayoutShortcut).

	.PARAMETER MonitorConfig
		A hashtable containing monitor configurations with Layout property.
		Example (simple): @{ Primary = @{ Layout = "One" }; Secondary = @{ Layout = "Zero" } }
		Example (legacy): @{ Primary = @{ Layout = "One"; LayoutNumber = 1 } }
		Example (per-desktop): @{ Primary = @{ VirtualDesktopLayouts = @{ 1 = "One"; 2 = "Two"; 3 = "Three" } } }
		Example (per-desktop legacy): @{ Primary = @{ VirtualDesktopLayouts = @{ 1 = @{ Layout = "One"; LayoutNumber = 1 } } } }
		Note: VirtualDesktopLayouts uses 1-based indexing (desktop 1, 2, 3, etc.)

	.PARAMETER DesktopNumber
		The virtual desktop number to apply layouts for. If specified and monitor has VirtualDesktopLayouts,
		will use the layout defined for that desktop.

	.PARAMETER MonitorInfo
		Pre-fetched monitor info array to reuse instead of calling Get-MonitorInfo (caching optimization).

	.PARAMETER DesktopOffset
		Virtual desktop offset for multi-workspace placement; layouts apply to desktops
		starting from this index. Default is 0.

	.PARAMETER DesktopCount
		Caps how many desktops are processed (from the offset), preventing overwrite of
		adjacent workspaces' layouts. Default is 0.

	.PARAMETER Force
		Bypasses the applied-layouts idempotency check. In file mode the entries are rewritten
		even when the file already holds them, so FancyZones reloads the file and the probe
		verifies what it holds; in the shortcut pass every layout shortcut is re-sent. Use it
		whenever the on-disk applied-layouts state cannot be trusted to describe the LIVE zone
		grid: FancyZones was just restarted, or it is holding a stale grid while
		applied-layouts.json still claims the correct layout. That is exactly the case where a
		plain (idempotent) call reports "Already Applied" for every monitor and changes nothing.

	.EXAMPLE
		$config = Import-PowerShellDataFile -Path "WinuX-workspace-layout.psd1"
		Apply-FancyZones -MonitorConfig $config.Monitors

	.EXAMPLE
		Apply-FancyZones -MonitorConfig $config.Monitors -DesktopNumber 2

	.EXAMPLE
		Apply-FancyZones -MonitorConfig $config.Monitors -Force
		# Re-sends every layout shortcut, ignoring the applied-layouts state

	.NOTES
		Prerequisites:
		- PowerToys FancyZones must be installed and running
		- FancyZones layouts must be numbered (0-9) for keyboard shortcuts
		- Keyboard shortcut: Win+Ctrl+Alt+[Number] to switch to layout
		- File mode additionally needs an applied-layouts.json entry FancyZones itself wrote for
		  each attached monitor (it writes one on its first start with the monitor attached); a
		  monitor without one falls back to the shortcut pass
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[hashtable]$MonitorConfig,

		[Parameter(Mandatory = $false)]
		[int]$DesktopNumber,

		[Parameter(Mandatory = $false)]
		[array]$MonitorInfo,

		[Parameter(Mandatory = $false)]
		[int]$DesktopOffset = 0,

		[Parameter(Mandatory = $false)]
		[int]$DesktopCount = 0,

		[Parameter(Mandatory = $false)]
		[switch]$Force
	)

	# Use cached VirtualDesktop module loader
	$hasVirtualDesktopModule = Import-VirtualDesktopModule -Silent
	if (-not $hasVirtualDesktopModule -and $DesktopNumber) {
		Write-LogWarning "Could not load VirtualDesktop module. FancyZones will be applied for current desktop only!"
	}

	if (Test-LogVerbose) {
		if ($DesktopNumber) {
			Write-LogDebug "Applying FancyZones Layouts for Virtual Desktop $DesktopNumber"
		}
		else {
			Write-LogDebug "Applying FancyZones Layouts"
		}
	}

	# Ensure Windows Forms is loaded (cached)
	Ensure-WindowsFormsLoaded

	# Use consolidated native types from WindowNative.cs (loaded in Window.psm1)

	if (-not $global:Configuration) {
		Write-Error "Global configuration not loaded. Re run Load-PathConfiguration!"
		return $false
	}

	$fancyZonesReady = Start-FancyZones -PassThru
	if (-not $fancyZonesReady) {
		$fancyZonesReady = Start-FancyZones -ForceRestart -MaxWaitSeconds 20 -PassThru
	}

	if (-not $fancyZonesReady) {
		Write-Error "FancyZones is not ready after restart attempt."
		return $false
	}

	# How the layouts reach FancyZones. "File" writes applied-layouts.json for every owned desktop
	# and proves the reload with one probe shortcut (see $applyLayoutsViaFile below); "Hotkeys" is
	# the desktop-switching shortcut pass alone. An unknown value falls back to File with a note.
	$applyViaFile = $true
	$configuredApplyMethod = [string]$global:Configuration.FancyZonesApplyMethod
	if (-not [string]::IsNullOrWhiteSpace($configuredApplyMethod)) {
		switch ($configuredApplyMethod.Trim().ToLowerInvariant()) {
			'file' { $applyViaFile = $true }
			'hotkeys' { $applyViaFile = $false }
			default {
				Write-LogDebug "FancyZonesApplyMethod [$configuredApplyMethod] is neither File nor Hotkeys - using File" -Style Warning
			}
		}
	}
	if ($applyViaFile) {
		foreach ($requiredCommand in @('Write-AppliedFancyZonesLayouts', 'Test-AppliedFancyZonesLayouts', 'Send-FancyZonesLayoutShortcut', 'Get-VirtualDesktopGuid')) {
			if (-not (Get-Command $requiredCommand -ErrorAction SilentlyContinue)) {
				$applyViaFile = $false
			}
		}
	}

	# Get monitor information (use cached if provided)
	try {
		if ($MonitorInfo) {
			$monitors = $MonitorInfo
		}
		else {
			$monitors = Get-MonitorInfo
		}
	}
	catch {
		Write-Error "Failed to get monitor information: $_"
		return $false
	}

	# Resolve monitor labels once for this invocation to avoid repeating lookups
	# inside per-desktop/per-monitor loops.
	$monitorSpecs = Get-MonitorSpecs -MonitorInfo $monitors
	$resolvedMonitorByKey = @{}
	$matchedMonitorByKey = @{}
	$unresolvableKeys = @()
	foreach ($monitorKey in $MonitorConfig.Keys) {
		$resolvedMonitor = if ($monitorSpecs) { $monitorSpecs.($monitorKey) } else { $null }
		if ($resolvedMonitor) {
			$resolvedMonitorByKey[$monitorKey] = $resolvedMonitor
			$matchedMonitorByKey[$monitorKey] = $monitors | Where-Object {
				$_.Left -eq $resolvedMonitor.X -and $_.Top -eq $resolvedMonitor.Y -and
				$_.Width -eq $resolvedMonitor.Width -and $_.Height -eq $resolvedMonitor.Height
			} | Select-Object -First 1
		}
		else {
			$unresolvableKeys += $monitorKey
		}
	}

	# A layout naming a monitor that is not attached (Monitor6 on a two-monitor machine) is not
	# fatal - the attached monitors are still laid out - but it used to pass without a trace, so
	# the mismatch only surfaced later as windows landing somewhere unexpected. Warn once here
	# rather than per desktop, since the resolution is per invocation.
	if ($unresolvableKeys.Count -gt 0) {
		$attachedLabels = if ($monitorSpecs) {
			@($monitorSpecs.PSObject.Properties.Name | Sort-Object { Resolve-MonitorLabel -Label $_ }) -join ', '
		}
		else { "none detected" }

		$orderedUnresolvable = @($unresolvableKeys | Sort-Object { Resolve-MonitorLabel -Label $_ }) -join ', '
		Write-LogWarning "Layout targets monitor(s) [$orderedUnresolvable] that are not attached - skipping them. Attached monitors: $attachedLabels"
	}

	# Generic List with reference semantics: the $applyLayouts scriptblock below receives this
	# as a parameter, and `+=` on an array parameter would rebind a scope-LOCAL copy - every
	# "Shortcut Sent"/"Failed" record used to be silently lost, which kept $appliedCount at 0
	# and made the applied-layouts cache invalidation at the end dead code.
	$results = [System.Collections.Generic.List[object]]::new()

	# Idempotency: read currently applied FancyZones state to skip redundant shortcut sends
	$appliedState = $null
	$layoutUuidLookup = $null
	$desktopGuidLookup = @{}
	$displayToEdidMap = @{}
	$displayToInstanceMap = @{}

	try {
		# -Force skips the applied-layouts read entirely. Idempotency is driven by
		# applied-layouts.json, which is precisely the thing that lies when FancyZones'
		# LIVE zone grid is stale - reading it would mark every monitor "Already Applied"
		# and turn this whole call into a no-op. A null $appliedState makes both the
		# per-desktop pre-check and the per-monitor check fall through to a re-send.
		$appliedState = if ($Force) { $null } else { Get-AppliedFancyZonesState }

		if ($Force -and (Test-LogVerbose)) {
			Write-LogDebug "Force specified - bypassing applied-layouts idempotency (re-sending every layout shortcut)" -Style Warning
		}

		if ($appliedState) {
			# Build layout name → UUID lookup from custom-layouts.json
			$customLayoutsPath = Join-Path $env:LOCALAPPDATA "Microsoft\PowerToys\FancyZones\custom-layouts.json"
			$customLayouts = Get-CachedFancyZonesLayouts -LayoutsJsonPath $customLayoutsPath
			if ($customLayouts -and $customLayouts.'custom-layouts') {
				$layoutUuidLookup = @{}
				foreach ($cl in $customLayouts.'custom-layouts') {
					if ($cl.name -and $cl.uuid) {
						$layoutUuidLookup[$cl.name] = $cl.uuid.ToUpper()
					}
				}
			}
		}

		# Desktop index → GUID lookup. Get-VirtualDesktopGuid reads the registry value
		# (VirtualDesktopIDs) FancyZones keys its entries by; the idempotency check AND the file
		# pass need it, so it is built regardless of -Force.
		$registryDesktopIndex = 0
		while ($true) {
			$registryGuid = Get-VirtualDesktopGuid -DesktopIndex $registryDesktopIndex
			if (-not $registryGuid) { break }
			$desktopGuidLookup[$registryDesktopIndex] = $registryGuid
			$registryDesktopIndex++
		}

		# Display name → EDID code / PnP instance via EnumDisplayDevices. FancyZones keys
		# applied-layouts.json by EDID code (e.g., "LEN8ABC") and instance, not by "\\.\DISPLAY2".
		# The idempotency check and the file pass both need the mapping; empty maps (native type
		# not loaded yet) fall back to DeviceName matching.
		$deviceIdentity = Get-MonitorDeviceIdentityMap
		$displayToEdidMap = if ($deviceIdentity -and $deviceIdentity.Edid) { $deviceIdentity.Edid } else { @{} }
		$displayToInstanceMap = if ($deviceIdentity -and $deviceIdentity.Instance) { $deviceIdentity.Instance } else { @{} }

		# Guard against ambiguous monitor identity: FancyZones' applied-layouts.json keys each
		# entry by EDID code + virtual desktop only. Two identical monitors (same model) share
		# the same EDID, so their idempotency keys collide (last write wins). That makes the
		# "already applied" check unreliable - it can report a monitor as already correct based
		# on the OTHER monitor's layout and skip applying, leaving a stale layout in place.
		# When duplicate EDIDs are present we cannot safely skip, so disable the optimization
		# entirely and always (re)apply every monitor's layout.
		if ($appliedState -and $displayToEdidMap.Count -gt 0) {
			$duplicateEdids = @(Get-DuplicateMonitorEdid -DisplayToEdidMap $displayToEdidMap)
			if ($duplicateEdids.Count -gt 0) {
				# Duplicate EDIDs are only ambiguous when the PnP instance path cannot
				# disambiguate them: newer FancyZones schemas key applied-layouts.json by
				# EDID + monitor-instance, and the state lookup stores instance-qualified
				# keys. Idempotency stays enabled when every duplicated display has an
				# instance; otherwise fall back to always reapplying (previous behavior).
				$duplicatesWithoutInstance = @(
					$displayToEdidMap.Keys | Where-Object {
						$duplicateEdids -contains $displayToEdidMap[$_] -and -not $displayToInstanceMap.ContainsKey($_)
					}
				)

				if ($duplicatesWithoutInstance.Count -gt 0) {
					Write-LogDebug "  ⚠ Duplicate monitor EDID(s) detected ($($duplicateEdids -join ', ')) without instance paths - disabling idempotency skip to guarantee correct per-monitor layouts" -Style Warning
					$appliedState = $null
				}
				elseif (Test-LogVerbose) {
					Write-LogDebug "  Duplicate monitor EDID(s) detected ($($duplicateEdids -join ', ')) - idempotency kept via instance-qualified keys" -Style Warning
				}
			}
		}

		if ((Test-LogVerbose) -and $appliedState -and $layoutUuidLookup -and $desktopGuidLookup.Count -gt 0) {
			$edidInfo = if ($displayToEdidMap.Count -gt 0) { ", $($displayToEdidMap.Count) EDID mapping(s)" } else { "" }
			Write-LogDebug "Idempotency check enabled ($($desktopGuidLookup.Count) desktop(s), $($layoutUuidLookup.Count) layout(s)$edidInfo)"
		}
	}
	catch {
		# Silently continue - idempotency check is an optional optimization
		$appliedState = $null
	}

	# Pre-check: determines if ALL monitors on a given desktop already have the correct layout
	# This allows skipping Switch-Desktop entirely for desktops that need no changes
	$checkDesktopFullyApplied = {
		param($desktopLookupKey, $desktopIndex)

		if (-not $appliedState -or -not $layoutUuidLookup -or $desktopGuidLookup.Count -eq 0) {
			return $false
		}

		$desktopGuid = if ($desktopGuidLookup.ContainsKey($desktopIndex)) { $desktopGuidLookup[$desktopIndex] } else { $null }
		if (-not $desktopGuid) { return $false }

		foreach ($monitorKey in $MonitorConfig.Keys) {
			$monitor = $MonitorConfig[$monitorKey]

			# Determine which layout name applies for this desktop
			$layoutName = $null
			if ($monitor.VirtualDesktopLayouts -and $monitor.VirtualDesktopLayouts.ContainsKey($desktopLookupKey)) {
				$lc = $monitor.VirtualDesktopLayouts[$desktopLookupKey]
				$layoutName = if ($lc -is [string]) { $lc } elseif ($lc -is [hashtable] -and $lc.Layout) { $lc.Layout } else { $null }
			}
			elseif ($monitor.Layout) {
				$layoutName = $monitor.Layout
			}

			if (-not $layoutName) { continue }

			$targetUuid = if ($layoutUuidLookup.ContainsKey($layoutName)) { $layoutUuidLookup[$layoutName] } else { $null }
			if (-not $targetUuid) { return $false }

			# Resolve monitor to its EDID code or DeviceName
			$resolvedMonitor = if ($resolvedMonitorByKey.ContainsKey($monitorKey)) { $resolvedMonitorByKey[$monitorKey] } else { $null }
			if (-not $resolvedMonitor) { return $false }

			$matchedMonitor = if ($matchedMonitorByKey.ContainsKey($monitorKey)) { $matchedMonitorByKey[$monitorKey] } else { $null }

			if (-not $matchedMonitor) { return $false }

			$deviceName = $matchedMonitor.DeviceName
			$monitorId = $null
			if ($displayToEdidMap.ContainsKey($deviceName)) { $monitorId = $displayToEdidMap[$deviceName] }
			elseif ($deviceName) { $monitorId = $deviceName.ToUpper() }
			if (-not $monitorId) { return $false }

			# Prefer the instance-qualified key - unambiguous when identical monitors share an EDID.
			if ($displayToInstanceMap.ContainsKey($deviceName)) {
				$monitorId = "$monitorId|$($displayToInstanceMap[$deviceName])"
			}

			$stateKey = "$($monitorId):$desktopGuid"
			if (-not $appliedState.ContainsKey($stateKey) -or $appliedState[$stateKey] -ne $targetUuid) {
				return $false
			}
		}

		return $true
	}

	$applyLayouts = {
		param($currentDesktopNumber, $resultsArray)

		# Apply layouts to each monitor
		foreach ($monitorKey in $MonitorConfig.Keys) {
			$monitor = $MonitorConfig[$monitorKey]

			# Determine which layout to use based on VirtualDesktopLayouts or simple Layout
			$layoutConfig = $null
			$layoutName = $null
			$layoutNumber = $null

			if ($monitor.VirtualDesktopLayouts -and $null -ne $currentDesktopNumber) {
				# Use per-desktop layout configuration
				if ($monitor.VirtualDesktopLayouts.ContainsKey($currentDesktopNumber)) {
					$layoutConfig = $monitor.VirtualDesktopLayouts[$currentDesktopNumber]

					# Handle both string format ("One") and hashtable format (@{ Layout = "One"; LayoutNumber = 1 })
					if ($layoutConfig -is [string]) {
						# Simplified format: just the layout name
						$layoutName = $layoutConfig
						$layoutNumber = $null  # Will be resolved from configuration
					}
					elseif ($layoutConfig -is [hashtable]) {
						# Legacy format: hashtable with Layout and LayoutNumber
						$layoutName = $layoutConfig.Layout
						$layoutNumber = $layoutConfig.LayoutNumber
					}
					else {
						if (Test-LogVerbose) {
							Write-LogDebug "Invalid layout configuration for monitor [$monitorKey] on desktop [$currentDesktopNumber]" -Style Warning
						}
						continue
					}

					if (Test-LogVerbose) {
						Write-LogDebug "Found layout [$layoutName] for desktop [$currentDesktopNumber] on monitor [$monitorKey]" -Style Step
					}
				}
				else {
					if (Test-LogVerbose) {
						Write-LogDebug "No layout specified for monitor [$monitorKey] on desktop [$currentDesktopNumber]" -Style Warning
					}
					continue
				}
			}
			elseif ($monitor.Layout) {
				# Use simple layout configuration (backward compatible)
				$layoutName = $monitor.Layout
				$layoutNumber = $monitor.LayoutNumber
			}
			else {
				if (Test-LogVerbose) {
					Write-LogDebug "No layout specified for monitor [$monitorKey]" -Style Warning
				}
				continue
			}

			# Resolve monitor dimensions if not specified (display-agnostic format)
			$monitorX = $monitor.X
			$monitorY = $monitor.Y
			$monitorWidth = $monitor.Width
			$monitorHeight = $monitor.Height

			if ($null -eq $monitorX -or $null -eq $monitorY -or $null -eq $monitorWidth -or $null -eq $monitorHeight) {
				# Auto-detect monitor dimensions based on key (Primary, Secondary, etc.)
				# Use pre-resolved monitor specs to avoid repeated lookups
				$resolvedMonitor = if ($resolvedMonitorByKey.ContainsKey($monitorKey)) { $resolvedMonitorByKey[$monitorKey] } else { $null }

				if ($resolvedMonitor) {
					$monitorX = $resolvedMonitor.X
					$monitorY = $resolvedMonitor.Y
					$monitorWidth = $resolvedMonitor.Width
					$monitorHeight = $resolvedMonitor.Height
					if (Test-LogVerbose) {
						Write-LogDebug "Auto-detected: ${monitorWidth}x${monitorHeight} at ($monitorX, $monitorY)" -Style Success
					}
				}
				else {
					if (Test-LogVerbose) {
						Write-LogDebug "Could not auto-detect monitor '$monitorKey'" -Style Warning
					}
					continue
				}
			}

			if (Test-LogVerbose) {
				Write-LogDebug "Monitor [$monitorKey]"
				if ($currentDesktopNumber) {
					Write-LogDebug "Desktop [$currentDesktopNumber]" -Style Step
				}
				Write-LogDebug "Layout [$layoutName]" -Style Step
				Write-LogDebug "Position ($monitorX, $monitorY)" -Style Step
				Write-LogDebug "Size [${monitorWidth}x${monitorHeight}]" -Style Step
			}

			# Find matching physical monitor
			$matchedMonitor = $monitors | Where-Object {
				$_.Left -eq $monitorX -and
				$_.Top -eq $monitorY -and
				$_.Width -eq $monitorWidth -and
				$_.Height -eq $monitorHeight
			} | Select-Object -First 1

			if (-not $matchedMonitor) {
				Write-Warning "    ✗ Could not find physical monitor matching configuration"
				$resultsArray.Add([PSCustomObject]@{
					Monitor = $monitorKey
					Layout  = $layoutName
					Status  = "Monitor Not Found"
				})
				continue
			}

			if ($null -eq $layoutNumber) {
				if ($global:Configuration.LayoutNumbers.ContainsKey($layoutName)) {
					$layoutNumber = $global:Configuration.LayoutNumbers[$layoutName]
				}
				else {
					Write-Warning "    ✗ Layout '$layoutName' not found in configuration"
					Write-Warning "      Available layouts: $($global:Configuration.LayoutNumbers.Keys -join ', ')"
					$resultsArray.Add([PSCustomObject]@{
						Monitor = $monitorKey
						Layout  = $layoutName
						Status  = "Layout Number Unknown"
					})
					continue
				}
			}

			if ($layoutNumber -lt 0 -or $layoutNumber -gt 9) {
				if (Test-LogVerbose) {
					Write-Warning "    ✗ Layout number must be 0-9, got => [$layoutNumber]"
				}
				$resultsArray.Add([PSCustomObject]@{
					Monitor = $monitorKey
					Layout  = $layoutName
					Status  = "Invalid Layout Number"
				})
				continue
			}

			if (Test-LogVerbose) {
				Write-LogDebug "Layout number [$layoutNumber]" -Style Step
			}

			# Idempotency check: skip if this layout is already applied on this monitor + desktop
			$alreadyApplied = $false
			if ($appliedState -and $layoutUuidLookup -and $matchedMonitor) {
				try {
					$targetUuid = if ($layoutUuidLookup.ContainsKey($layoutName)) { $layoutUuidLookup[$layoutName] } else { $null }
					$actualDesktopIndex = if ($null -ne $currentDesktopNumber -and $currentDesktopNumber -gt 0) {
						ConvertTo-InternalDesktopIndex -DesktopNumber $currentDesktopNumber -DesktopOffset $DesktopOffset
					}
					else { $null }
					$desktopGuid = if ($null -ne $actualDesktopIndex -and $desktopGuidLookup.ContainsKey($actualDesktopIndex)) {
						$desktopGuidLookup[$actualDesktopIndex]
					}
					else { $null }

					if ($targetUuid -and $desktopGuid) {
						# Try EDID code first (from EnumDisplayDevices mapping), then fall back to DeviceName
						$deviceName = $matchedMonitor.DeviceName
						$monitorId = $null

						if ($displayToEdidMap.ContainsKey($deviceName)) {
							$monitorId = $displayToEdidMap[$deviceName]
						}
						elseif ($deviceName) {
							$monitorId = $deviceName.ToUpper()
						}

						# Prefer the instance-qualified key - unambiguous when identical
						# monitors share an EDID.
						if ($monitorId -and $displayToInstanceMap.ContainsKey($deviceName)) {
							$monitorId = "$monitorId|$($displayToInstanceMap[$deviceName])"
						}

						if ($monitorId) {
							$stateKey = "$($monitorId):$desktopGuid"
							if ($appliedState.ContainsKey($stateKey) -and $appliedState[$stateKey] -eq $targetUuid) {
								$alreadyApplied = $true
							}
						}
					}
				}
				catch {
					$alreadyApplied = $false
				}
			}

			if ($alreadyApplied) {
				if (Test-LogVerbose) {
					Write-LogDebug "Layout [$layoutName] already applied - skipping" -Style Warning
				}
				$resultsArray.Add([PSCustomObject]@{
					Monitor       = $monitorKey
					Layout        = $layoutName
					LayoutNumber  = $layoutNumber
					DesktopNumber = $currentDesktopNumber
					Status        = "Already Applied"
				})
				continue
			}

			try {
				# Cursor to the monitor's center, desktop window to the foreground, then the
				# Win+Ctrl+Alt+[Number] chord through batched SendInput.
				Send-FancyZonesLayoutShortcut -LayoutNumber $layoutNumber -MonitorX $monitorX -MonitorY $monitorY -MonitorWidth $monitorWidth -MonitorHeight $monitorHeight

				if (Test-LogVerbose) {
					Write-LogDebug "Layout shortcut sent" -Style Success
				}

				$resultsArray.Add([PSCustomObject]@{
					Monitor       = $monitorKey
					Layout        = $layoutName
					LayoutNumber  = $layoutNumber
					DesktopNumber = $currentDesktopNumber
					Status        = "Shortcut Sent"
				})
			}
			catch {
				if (Test-LogVerbose) {
					Write-Error "    ✗ Failed to send keyboard shortcut: $_"
				}
				$resultsArray.Add([PSCustomObject]@{
					Monitor       = $monitorKey
					Layout        = $layoutName
					DesktopNumber = $currentDesktopNumber
					Status        = "Failed"
					Error         = $_.Exception.Message
				})
			}
		}
	}

	# File-based application. Writes the entries for every owned desktop into applied-layouts.json
	# (Write-AppliedFancyZonesLayouts), lets FancyZones reload it, then proves the reload with ONE
	# shortcut on the current desktop: FancyZones answers a layout shortcut by saving its whole
	# in-memory layout map back to the file (ApplyQuickLayout -> SaveData), so re-reading the file
	# afterwards shows exactly what it holds - written entries that survive were loaded, entries
	# that vanish were not. Returns a hashtable of the 0-based desktop indexes whose every monitor
	# verified; the shortcut pass below skips those and handles the rest exactly as before.
	$applyLayoutsViaFile = {
		param($OwnedDesktops, [int]$CurrentDesktopIndex, $ResultsArray)

		$verifiedDesktops = @{}
		$owned = @($OwnedDesktops)
		if ($owned.Count -eq 0) { return $verifiedDesktops }

		$layoutKeyFor = {
			param([int]$InternalIndex)
			if ($DesktopOffset -gt 0) { $InternalIndex - $DesktopOffset + 1 } else { $InternalIndex + 1 }
		}

		# Explorer persists a new desktop's GUID to the registry moments after creating it; give the
		# highest owned index a short grace period instead of sending that desktop to the shortcut
		# pass for want of a GUID.
		$highestIndex = [int](($owned | Measure-Object -Property Number -Maximum).Maximum)
		$registryClock = [System.Diagnostics.Stopwatch]::StartNew()
		while (-not (Get-VirtualDesktopGuid -DesktopIndex $highestIndex) -and $registryClock.ElapsedMilliseconds -lt 1000) {
			Start-Sleep -Milliseconds 50
		}

		# Physical monitor per config key, resolved the way the shortcut pass resolves it: the
		# layout's own X/Y/Width/Height when it carries them, else the bounds Get-MonitorSpecs
		# assigned to the label. A key that resolves neither way has no device to write for.
		$fileMonitorByKey = @{}
		foreach ($monitorKey in $MonitorConfig.Keys) {
			$monitor = $MonitorConfig[$monitorKey]
			$rect = $null
			if ($null -ne $monitor.X -and $null -ne $monitor.Y -and $null -ne $monitor.Width -and $null -ne $monitor.Height) {
				$rect = @{ X = $monitor.X; Y = $monitor.Y; Width = $monitor.Width; Height = $monitor.Height }
			}
			elseif ($resolvedMonitorByKey.ContainsKey($monitorKey)) {
				$resolvedMonitor = $resolvedMonitorByKey[$monitorKey]
				$rect = @{ X = $resolvedMonitor.X; Y = $resolvedMonitor.Y; Width = $resolvedMonitor.Width; Height = $resolvedMonitor.Height }
			}
			if (-not $rect) { continue }

			$device = $monitors | Where-Object {
				$_.Left -eq $rect.X -and $_.Top -eq $rect.Y -and $_.Width -eq $rect.Width -and $_.Height -eq $rect.Height
			} | Select-Object -First 1
			if ($device) {
				$fileMonitorByKey[$monitorKey] = @{ Rect = $rect; DeviceName = $device.DeviceName }
			}
		}

		# One target per (desktop, monitor) with a layout. A monitor without an EDID/instance mapping
		# (old FancyZones schema, EnumDisplayDevices unavailable) cannot be written, so its desktop
		# stays with the shortcut pass.
		$targets = [System.Collections.Generic.List[object]]::new()
		$desktopLayoutCounts = @{}
		$desktopTargetable = @{}
		foreach ($desktop in $owned) {
			$internalIndex = [int]$desktop.Number
			$layoutKey = & $layoutKeyFor $internalIndex
			$desktopGuid = Get-VirtualDesktopGuid -DesktopIndex $internalIndex
			$desktopLayoutCounts[$internalIndex] = 0
			$desktopTargetable[$internalIndex] = [bool]$desktopGuid

			foreach ($monitorKey in $MonitorConfig.Keys) {
				$monitor = $MonitorConfig[$monitorKey]
				$layoutName = $null
				if ($monitor.VirtualDesktopLayouts) {
					if ($monitor.VirtualDesktopLayouts.ContainsKey($layoutKey)) {
						$lc = $monitor.VirtualDesktopLayouts[$layoutKey]
						$layoutName = if ($lc -is [string]) { $lc } elseif ($lc -is [hashtable] -and $lc.Layout) { $lc.Layout } else { $null }
					}
				}
				elseif ($monitor.Layout) {
					$layoutName = $monitor.Layout
				}
				if (-not $layoutName) { continue }

				$desktopLayoutCounts[$internalIndex]++
				$deviceName = if ($fileMonitorByKey.ContainsKey($monitorKey)) { $fileMonitorByKey[$monitorKey].DeviceName } else { $null }
				if (-not $desktopGuid -or -not $deviceName -or -not $displayToEdidMap.ContainsKey($deviceName) -or -not $displayToInstanceMap.ContainsKey($deviceName)) {
					$desktopTargetable[$internalIndex] = $false
					continue
				}

				$targets.Add([PSCustomObject]@{
						Monitor         = $displayToEdidMap[$deviceName]
						MonitorInstance = $displayToInstanceMap[$deviceName]
						VirtualDesktop  = $desktopGuid
						LayoutName      = $layoutName
						Label           = "$monitorKey/desktop $($internalIndex + 1)"
						MonitorKey      = $monitorKey
						DesktopIndex    = $internalIndex
						LayoutKey       = $layoutKey
					})
			}
		}

		if ($targets.Count -eq 0) {
			if (Test-LogVerbose) {
				Write-LogDebug " No desktop/monitor pair could be written to applied-layouts.json - using the shortcut pass" -Style Warning
			}
			return $verifiedDesktops
		}

		Write-LogDebug " Writing FancyZones layouts for [$($owned.Count)] desktop(s) into applied-layouts.json..."
		$writeResult = Write-AppliedFancyZonesLayouts -Targets $targets.ToArray() -Force:$Force
		if ($writeResult.Error) {
			Write-LogDebug " applied-layouts.json write failed - using the shortcut pass: $($writeResult.Error)" -Style Warning
			return $verifiedDesktops
		}

		# The writer's records line up with the targets by position; keep the ones it could resolve
		# and mark the desktop of every unresolved one for the shortcut pass.
		$resolved = @()
		for ($targetIndex = 0; $targetIndex -lt $targets.Count; $targetIndex++) {
			$record = $writeResult.Targets[$targetIndex]
			if ($record.Status -in @('Written', 'AlreadyApplied')) {
				$resolved += [PSCustomObject]@{ Target = $targets[$targetIndex]; Record = $record }
			}
			else {
				$desktopTargetable[$targets[$targetIndex].DesktopIndex] = $false
			}
		}
		if ($resolved.Count -eq 0) {
			Write-LogDebug " applied-layouts.json has no device entry for the attached monitor(s) yet - using the shortcut pass" -Style Warning
			return $verifiedDesktops
		}

		$verify = $null
		if ($writeResult.Written) {
			Start-Sleep -Milliseconds $script:WindowModuleDelays.AppliedLayoutsReloadMs

			# Probe on the current desktop when this call owns it, else on the first owned desktop -
			# the desktop the shortcut pass ends on in a DesktopOffset call anyway.
			$probeIndex = if ($desktopTargetable.ContainsKey($CurrentDesktopIndex) -and $desktopTargetable[$CurrentDesktopIndex] -and $desktopLayoutCounts[$CurrentDesktopIndex] -gt 0) {
				$CurrentDesktopIndex
			}
			else {
				[int]($owned | Select-Object -First 1).Number
			}

			$probe = $null
			foreach ($candidate in @($resolved | Where-Object { $_.Target.DesktopIndex -eq $probeIndex })) {
				$candidateKey = $candidate.Target.MonitorKey
				$rect = if ($fileMonitorByKey.ContainsKey($candidateKey)) { $fileMonitorByKey[$candidateKey].Rect } else { $null }
				$candidateMonitor = $MonitorConfig[$candidateKey]
				$number = $null
				if ($candidateMonitor.VirtualDesktopLayouts -and $candidateMonitor.VirtualDesktopLayouts.ContainsKey($candidate.Target.LayoutKey)) {
					$lc = $candidateMonitor.VirtualDesktopLayouts[$candidate.Target.LayoutKey]
					if ($lc -is [hashtable] -and $null -ne $lc.LayoutNumber) { $number = $lc.LayoutNumber }
				}
				elseif ($null -ne $candidateMonitor.LayoutNumber) {
					$number = $candidateMonitor.LayoutNumber
				}
				if ($null -eq $number -and $global:Configuration.LayoutNumbers -and $global:Configuration.LayoutNumbers.ContainsKey($candidate.Target.LayoutName)) {
					$number = $global:Configuration.LayoutNumbers[$candidate.Target.LayoutName]
				}
				if ($rect -and $null -ne $number -and [int]$number -ge 0 -and [int]$number -le 9) {
					$probe = @{ Rect = $rect; Number = [int]$number; Target = $candidate.Target }
					break
				}
			}
			if (-not $probe) {
				Write-LogDebug " No probe shortcut available on desktop [$($probeIndex + 1)] - using the shortcut pass" -Style Warning
				return $verifiedDesktops
			}

			if ($probeIndex -ne $CurrentDesktopIndex) {
				Write-LogDebug " Switching to Desktop [$($probeIndex + 1)] for the layout probe"
				try {
					$null = Invoke-WithRetry -ScriptBlock {
						$null = Switch-Desktop -Desktop $probeIndex -ErrorAction Stop
					} -MaxAttempts 3 -InitialDelayMs 100
				}
				catch {
					Write-LogDebug " Could not switch to desktop [$($probeIndex + 1)] for the probe: $_" -Style Warning
					return $verifiedDesktops
				}
				if (-not (Wait-DesktopSwitch -TargetDesktopIndex $probeIndex)) {
					Write-LogDebug " Desktop switch for the probe not confirmed - using the shortcut pass" -Style Warning
					return $verifiedDesktops
				}
			}

			if (Test-LogVerbose) {
				Write-LogDebug " Probe: layout [$($probe.Target.LayoutName)] on $($probe.Target.Label) - FancyZones saves its layout map in response" -Style Step
			}
			Send-FancyZonesLayoutShortcut -LayoutNumber $probe.Number -MonitorX $probe.Rect.X -MonitorY $probe.Rect.Y -MonitorWidth $probe.Rect.Width -MonitorHeight $probe.Rect.Height

			$verify = Test-AppliedFancyZonesLayouts -Targets @($resolved | ForEach-Object { $_.Record }) -WaitForWriteAfterUtc $writeResult.WrittenAtUtc
			if (-not $verify.SaveObserved) {
				Write-LogDebug " FancyZones did not rewrite applied-layouts.json after the probe shortcut - using the shortcut pass" -Style Warning
				return $verifiedDesktops
			}
		}
		else {
			# Nothing needed writing: the file already holds every layout. Confirm it as it stands.
			$verify = Test-AppliedFancyZonesLayouts -Targets @($resolved | ForEach-Object { $_.Record })
		}

		# A desktop counts as done only when every monitor with a layout on it resolved and verified.
		foreach ($desktop in $owned) {
			$internalIndex = [int]$desktop.Number
			if (-not $desktopTargetable[$internalIndex] -or $desktopLayoutCounts[$internalIndex] -eq 0) { continue }

			$desktopResolved = @()
			for ($resolvedIndex = 0; $resolvedIndex -lt $resolved.Count; $resolvedIndex++) {
				if ($resolved[$resolvedIndex].Target.DesktopIndex -eq $internalIndex) { $desktopResolved += $resolvedIndex }
			}
			if ($desktopResolved.Count -ne $desktopLayoutCounts[$internalIndex]) { continue }

			$allVerified = $true
			foreach ($resolvedIndex in $desktopResolved) {
				if ($verify.Targets[$resolvedIndex].Status -ne 'Verified') { $allVerified = $false }
			}
			if (-not $allVerified) { continue }

			$verifiedDesktops[$internalIndex] = $true
			foreach ($resolvedIndex in $desktopResolved) {
				$ResultsArray.Add([PSCustomObject]@{
						Monitor       = $resolved[$resolvedIndex].Target.MonitorKey
						Layout        = $resolved[$resolvedIndex].Target.LayoutName
						DesktopNumber = $resolved[$resolvedIndex].Target.LayoutKey
						Status        = $(if ($resolved[$resolvedIndex].Record.Status -eq 'Written') { 'Layout Written' } else { 'Already Applied' })
					})
			}
		}

		$leftToShortcuts = $owned.Count - $verifiedDesktops.Count
		if ($verifiedDesktops.Count -gt 0) {
			Write-LogDebug " FancyZones took the file update: [$($verifiedDesktops.Count)] desktop(s) verified without switching$(if ($leftToShortcuts -gt 0) { ", [$leftToShortcuts] left to the shortcut pass" })" -Style Success
		}
		else {
			Write-LogDebug " applied-layouts.json write did not verify on any desktop - using the shortcut pass" -Style Warning
		}

		return $verifiedDesktops
	}

	if ($hasVirtualDesktopModule) {
		try {
			if ($DesktopNumber) {
				& $applyLayouts -currentDesktopNumber $DesktopNumber -resultsArray $results
			}
			else {
				$currentDesktop = Invoke-WithRetry -ScriptBlock {
					Get-CurrentDesktop
				} -MaxAttempts 3 -InitialDelayMs 500

				$originalDesktopIndex = Invoke-WithRetry -ScriptBlock {
					Get-DesktopIndex $currentDesktop
				} -MaxAttempts 3 -InitialDelayMs 100

				$allDesktops = (Get-DesktopList) | Sort-Object -Property Number

				$desktopCount = ($allDesktops | Measure-Object).Count

				# File pass first: the desktops it verifies are skipped by the shortcut pass below.
				# Its owned set is exactly what the two branches iterate.
				$fileVerifiedDesktops = @{}
				if ($applyViaFile -and $desktopCount -gt 1) {
					$ownedDesktops = if ($DesktopOffset -gt 0) {
						$ownedUpperBound = if ($DesktopCount -gt 0) { $DesktopOffset + $DesktopCount } else { [int]::MaxValue }
						@($allDesktops | Where-Object { $_.Number -ge $DesktopOffset -and $_.Number -lt $ownedUpperBound })
					}
					elseif ($DesktopCount -gt 0) {
						@($allDesktops | Where-Object { $_.Number -lt $DesktopCount })
					}
					else {
						@($allDesktops)
					}

					try {
						$fileResult = & $applyLayoutsViaFile -OwnedDesktops $ownedDesktops -CurrentDesktopIndex $originalDesktopIndex -ResultsArray $results
						$fileVerifiedDesktops = @($fileResult | Where-Object { $_ -is [hashtable] } | Select-Object -Last 1)[0]
						if (-not $fileVerifiedDesktops) { $fileVerifiedDesktops = @{} }
					}
					catch {
						Write-LogDebug " File-based layout application failed - using the shortcut pass: $_" -Style Warning
						$fileVerifiedDesktops = @{}
					}
				}

				if ($desktopCount -gt 1) {
					# When using DesktopOffset, only apply to desktops starting from the offset
					# This allows multiple workspaces to coexist on different virtual desktop ranges
					if ($DesktopOffset -gt 0) {
						Write-LogDebug "Applying FancyZones with desktop offset [+$DesktopOffset]"

						# Filter desktops to only those in this workspace's range
						# Use DesktopCount to cap the upper bound and avoid overwriting adjacent workspaces
						$upperBound = if ($DesktopCount -gt 0) { $DesktopOffset + $DesktopCount } else { [int]::MaxValue }
						$workspaceDesktops = $allDesktops | Where-Object { $_.Number -ge $DesktopOffset -and $_.Number -lt $upperBound }

						if ($DesktopCount -gt 0 -and (Test-LogVerbose)) {
							Write-LogDebug "Limiting to workspace range: desktops $($DesktopOffset + 1)-$($DesktopOffset + $DesktopCount) (of $desktopCount total)"
						}

						$switchedDesktop = $false
						foreach ($desktop in $workspaceDesktops) {
							try {
								$internalDesktopIndex = $desktop.Number  # 0-based from VirtualDesktop module
								# Layout lookup uses 1-based key relative to workspace (desktop at offset=2 uses layout key 1)
								$layoutLookupKey = $internalDesktopIndex - $DesktopOffset + 1
								$displayDesktopNumber = $internalDesktopIndex + 1  # 1-based for display

								# The file pass already put and verified this desktop's layouts.
								if ($fileVerifiedDesktops.ContainsKey($internalDesktopIndex)) {
									continue
								}

								# Skip switching to this desktop if all monitors already have the correct layout
								if (& $checkDesktopFullyApplied -desktopLookupKey $layoutLookupKey -desktopIndex $internalDesktopIndex) {
									if (Test-LogVerbose) {
										Write-LogDebug "Desktop [$displayDesktopNumber] - all layouts already applied, skipping switch" -Style Warning
									}
									foreach ($mk in $MonitorConfig.Keys) {
										$mon = $MonitorConfig[$mk]
										$ln = $null
										if ($mon.VirtualDesktopLayouts -and $mon.VirtualDesktopLayouts.ContainsKey($layoutLookupKey)) {
											$lc = $mon.VirtualDesktopLayouts[$layoutLookupKey]
											$ln = if ($lc -is [string]) { $lc } elseif ($lc -is [hashtable]) { $lc.Layout } else { $null }
										}
										if ($ln) {
											$results.Add([PSCustomObject]@{
												Monitor       = $mk
												Layout        = $ln
												DesktopNumber = $layoutLookupKey
												Status        = "Already Applied"
											})
										}
									}
									continue
								}

								Write-LogDebug " Switching to Desktop [$displayDesktopNumber] (layout key => $layoutLookupKey)"
								Invoke-WithRetry -ScriptBlock {
									$null = Switch-Desktop -Desktop $internalDesktopIndex -ErrorAction Stop
								} -MaxAttempts 3 -InitialDelayMs 100
								$switchedDesktop = $true

								# The desktop switch is asynchronous and the layout hotkey applies to
								# whatever desktop is ACTIVE - confirm the switch landed before injecting,
								# otherwise the layout is silently recorded under the PREVIOUS desktop's GUID.
								if (-not (Wait-DesktopSwitch -TargetDesktopIndex $internalDesktopIndex)) {
									Write-LogDebug " Desktop switch to [$displayDesktopNumber] not confirmed - skipping layout application for this desktop" -Style Warning
									continue
								}

								& $applyLayouts -currentDesktopNumber $layoutLookupKey -resultsArray $results
							}
							catch {
								Write-LogDebug " Could not switch to desktop [$displayDesktopNumber]: $_" -Style Warning
							}
						}
					}
					else {
						Write-LogDebug "Applying FancyZones to all [$desktopCount] virtual desktops..."

						# When DesktopCount is specified, only apply to that many desktops (starting from offset 0)
						# This prevents overwriting FancyZones layouts of other workspaces on adjacent desktops
						$desktopsToApply = if ($DesktopCount -gt 0) {
							$allDesktops | Where-Object { $_.Number -lt $DesktopCount }
						}
						else {
							$allDesktops
						}

						if ($DesktopCount -gt 0 -and (Test-LogVerbose)) {
							Write-LogDebug "Limiting to workspace range: desktops 1-$DesktopCount (of $desktopCount total)"
						}

						$switchedDesktop = $false
						foreach ($desktop in $desktopsToApply) {
							try {
								$internalDesktopIndex = $desktop.Number  # 0-based from VirtualDesktop module
								$desktopNumberToApply = $internalDesktopIndex + 1  # Convert to 1-based for layout lookup

								# The file pass already put and verified this desktop's layouts.
								if ($fileVerifiedDesktops.ContainsKey($internalDesktopIndex)) {
									continue
								}

								# Skip switching to this desktop if all monitors already have the correct layout
								if (& $checkDesktopFullyApplied -desktopLookupKey $desktopNumberToApply -desktopIndex $internalDesktopIndex) {
									if (Test-LogVerbose) {
										Write-LogDebug "Desktop [$desktopNumberToApply] - all layouts already applied, skipping switch" -Style Warning
									}
									foreach ($mk in $MonitorConfig.Keys) {
										$mon = $MonitorConfig[$mk]
										$ln = $null
										if ($mon.VirtualDesktopLayouts -and $mon.VirtualDesktopLayouts.ContainsKey($desktopNumberToApply)) {
											$lc = $mon.VirtualDesktopLayouts[$desktopNumberToApply]
											$ln = if ($lc -is [string]) { $lc } elseif ($lc -is [hashtable]) { $lc.Layout } else { $null }
										}
										if ($ln) {
											$results.Add([PSCustomObject]@{
												Monitor       = $mk
												Layout        = $ln
												DesktopNumber = $desktopNumberToApply
												Status        = "Already Applied"
											})
										}
									}
									continue
								}

								Write-LogDebug " Switching to Desktop [$desktopNumberToApply]"
								Invoke-WithRetry -ScriptBlock {
									$null = Switch-Desktop -Desktop $internalDesktopIndex -ErrorAction Stop
								} -MaxAttempts 3 -InitialDelayMs 100
								$switchedDesktop = $true

								# Confirm the asynchronous switch landed before injecting the layout
								# hotkey - see the matching guard in the DesktopOffset branch above.
								if (-not (Wait-DesktopSwitch -TargetDesktopIndex $internalDesktopIndex)) {
									Write-LogDebug " Desktop switch to [$desktopNumberToApply] not confirmed - skipping layout application for this desktop" -Style Warning
									continue
								}

								& $applyLayouts -currentDesktopNumber $desktopNumberToApply -resultsArray $results
							}
							catch {
								Write-LogDebug " Could not switch to desktop [$desktopNumberToApply]: $_" -Style Warning
							}
						}
					}

					try {
						# Switch back to first desktop of this workspace (considering offset)
						# Only switch back if we actually switched away from the original desktop
						$returnDesktop = if ($DesktopOffset -gt 0) { $DesktopOffset } else { $originalDesktopIndex }
						if ($switchedDesktop) {
							# Let FancyZones finish committing the LAST applied desktop's layout before we
							# switch away from it. Without this, an in-flight commit can land on the desktop
							# we switch back to (the starting desktop), corrupting its layout.
							Start-Sleep -Milliseconds $script:WindowModuleDelays.LayoutCommitMs

							Write-LogDebug " Switching back to desktop [$($returnDesktop + 1)]..." -Style Success
							Invoke-WithRetry -ScriptBlock {
								$null = Switch-Desktop -Desktop $returnDesktop -ErrorAction Stop
							} -MaxAttempts 3 -InitialDelayMs 100

							# Deterministically re-apply the return desktop's layout while we are actually on
							# it. The per-desktop pass ends on the LAST desktop and then switches back here;
							# the last desktop has no following pass to override a bled-in layout, so this
							# desktop is the only one left unprotected against the commit/switch race above.
							# Re-applying now guarantees the desktop we land on ends with its correct layout.
							# The re-apply MUST happen on the return desktop - if the asynchronous
							# switch-back cannot be confirmed, skip it rather than stamping this
							# desktop's layout onto whichever desktop is still active.
							if (Wait-DesktopSwitch -TargetDesktopIndex $returnDesktop) {
								Start-Sleep -Milliseconds $script:WindowModuleDelays.LayoutCommitMs
								$returnLayoutKey = if ($DesktopOffset -gt 0) { 1 } else { $returnDesktop + 1 }
								& $applyLayouts -currentDesktopNumber $returnLayoutKey -resultsArray $results
								Start-Sleep -Milliseconds $script:WindowModuleDelays.LayoutCommitMs
							}
							else {
								Write-LogDebug " Switch back to desktop [$($returnDesktop + 1)] not confirmed - skipping return-desktop layout re-apply" -Style Warning
							}
						}
						elseif (Test-LogVerbose) {
							Write-LogDebug "No desktop switches needed - staying on current desktop" -Style Warning
						}
					}
					catch {
						Write-LogDebug " Could not return to original desktop: $_" -Style Warning
					}
				}
				else {
					# Only one desktop - use 1-based index for layout lookup
					& $applyLayouts -currentDesktopNumber 1 -resultsArray $results
				}
			}
		}
		catch {
			Write-LogDebug " Could not apply to all virtual desktops: $_" -Style Warning
			# Fallback to desktop 1 (1-based) on error
			& $applyLayouts -currentDesktopNumber 1 -resultsArray $results
		}
	}
 else {
		& $applyLayouts -currentDesktopNumber $DesktopNumber -resultsArray $results
	}

	# Invalidate applied-layouts cache if any layouts were actually sent (the file writer
	# invalidates it for its own writes)
	$appliedCount = ($results | Where-Object { $_.Status -eq "Shortcut Sent" } | Measure-Object).Count
	$writtenCount = ($results | Where-Object { $_.Status -eq "Layout Written" } | Measure-Object).Count
	if ($appliedCount -gt 0) {
		$script:AppliedLayoutsCache.Data = $null
		$script:AppliedLayoutsCache.Timestamp = [datetime]::MinValue
	}

	# Only print results table when layouts were actually changed, or in debug mode
	if ($appliedCount -gt 0 -or $writtenCount -gt 0 -or (Test-LogVerbose)) {
		$results | Format-Table -AutoSize
	}

	return $results
}
