function Apply-FancyZones {
	<#
	.SYNOPSIS
		Applies FancyZones layouts to monitors using keyboard shortcuts.

	.DESCRIPTION
		Applies predefined FancyZones layouts to monitors by triggering FancyZones
		keyboard shortcuts on a window positioned on each monitor.

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

	.EXAMPLE
		$config = Import-PowerShellDataFile -Path "WinuX-workspace-layout.psd1"
		Apply-FancyZones -MonitorConfig $config.Monitors

	.EXAMPLE
		Apply-FancyZones -MonitorConfig $config.Monitors -DesktopNumber 2

	.NOTES
		Prerequisites:
		- PowerToys FancyZones must be installed and running
		- FancyZones layouts must be numbered (0-9) for keyboard shortcuts
		- Keyboard shortcut: Win+Ctrl+Alt+[Number] to switch to layout
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
		[int]$DesktopCount = 0
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

	$fancyZonesReady = Start-FancyZones
	if (-not $fancyZonesReady) {
		$fancyZonesReady = Start-FancyZones -ForceRestart -MaxWaitSeconds 20
	}

	if (-not $fancyZonesReady) {
		Write-Error "FancyZones is not ready after restart attempt."
		return $false
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
	foreach ($monitorKey in $MonitorConfig.Keys) {
		$resolvedMonitor = if ($monitorSpecs) { $monitorSpecs.($monitorKey) } else { $null }
		if ($resolvedMonitor) {
			$resolvedMonitorByKey[$monitorKey] = $resolvedMonitor
			$matchedMonitorByKey[$monitorKey] = $monitors | Where-Object {
				$_.Left -eq $resolvedMonitor.X -and $_.Top -eq $resolvedMonitor.Y -and
				$_.Width -eq $resolvedMonitor.Width -and $_.Height -eq $resolvedMonitor.Height
			} | Select-Object -First 1
		}
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
		$appliedState = Get-AppliedFancyZonesState

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

			# Build desktop index → GUID lookup from Windows registry
			$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VirtualDesktops"
			$vdIds = (Get-ItemProperty -Path $regPath -Name "VirtualDesktopIDs" -ErrorAction Stop).VirtualDesktopIDs
			if ($vdIds -and $vdIds.Length -gt 0) {
				$guidSize = 16
				$vdCount = [math]::Floor($vdIds.Length / $guidSize)
				for ($i = 0; $i -lt $vdCount; $i++) {
					$bytes = $vdIds[($i * $guidSize)..((($i + 1) * $guidSize) - 1)]
					$guid = [System.Guid]::new([byte[]]$bytes)
					$desktopGuidLookup[$i] = "{$($guid.ToString().ToUpper())}"
				}
			}

			# Build display name → EDID code mapping via EnumDisplayDevices
			# FancyZones applied-layouts.json uses EDID codes (e.g., "LEN8ABC"), not "\\.\DISPLAY2"
			try {
				$deviceInfoList = [WindowModule.Native]::GetMonitorDeviceInfo()
				foreach ($devInfo in $deviceInfoList) {
					if ($devInfo.DisplayName -and $devInfo.EdidCode) {
						$displayToEdidMap[$devInfo.DisplayName] = $devInfo.EdidCode.ToUpper()
						# PnP instance path - unique per physical device, present in newer
						# FancyZones schemas; enables idempotency for duplicate-EDID monitors.
						if ($devInfo.MonitorInstance) {
							$displayToInstanceMap[$devInfo.DisplayName] = $devInfo.MonitorInstance.ToUpper()
						}
					}
				}
			}
			catch {
				# EnumDisplayDevices unavailable (type not loaded yet) - fall back to DeviceName matching
				$displayToEdidMap = @{}
				$displayToInstanceMap = @{}
			}

			# Guard against ambiguous monitor identity: FancyZones' applied-layouts.json keys each
			# entry by EDID code + virtual desktop only. Two identical monitors (same model) share
			# the same EDID, so their idempotency keys collide (last write wins). That makes the
			# "already applied" check unreliable - it can report a monitor as already correct based
			# on the OTHER monitor's layout and skip applying, leaving a stale layout in place.
			# When duplicate EDIDs are present we cannot safely skip, so disable the optimization
			# entirely and always (re)apply every monitor's layout.
			if ($displayToEdidMap.Count -gt 0) {
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
				# Move cursor to center of target monitor to activate it
				$cursorX = $monitorX + ($monitorWidth / 2)
				$cursorY = $monitorY + ($monitorHeight / 2)

				if (Test-LogVerbose) {
					Write-LogDebug "Moving cursor to monitor center ($cursorX, $cursorY)" -Style Step
				}
				[void][WindowModule.Native]::SetCursorPos($cursorX, $cursorY)
				Start-Sleep -Milliseconds $script:WindowModuleDelays.CursorSettleMs

				$desktopHandle = [WindowModule.Native]::GetDesktopWindow()
				[void][WindowModule.Native]::SetForegroundWindow($desktopHandle)
				Start-Sleep -Milliseconds $script:WindowModuleDelays.FocusSettleMs

				# Send FancyZones layout switch shortcut: Win+Ctrl+Alt+[Number] using batched SendInput
				if (Test-LogVerbose) {
					Write-LogDebug "Sending keyboard shortcut [Win+Ctrl+Alt+$layoutNumber]" -Style Step
				}

				# Use optimized batched SendInput instead of multiple keybd_event calls
				[WindowModule.Native]::SendFancyZonesLayoutShortcut($layoutNumber)

				Start-Sleep -Milliseconds $script:WindowModuleDelays.KeyboardShortcutMs

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

	# Invalidate applied-layouts cache if any layouts were actually sent
	$appliedCount = ($results | Where-Object { $_.Status -eq "Shortcut Sent" } | Measure-Object).Count
	if ($appliedCount -gt 0) {
		$script:AppliedLayoutsCache.Data = $null
		$script:AppliedLayoutsCache.Timestamp = [datetime]::MinValue
	}

	# Only print results table when shortcuts were actually sent, or in debug mode
	if ($appliedCount -gt 0 -or (Test-LogVerbose)) {
		$results | Format-Table -AutoSize
	}

	return $results
}
