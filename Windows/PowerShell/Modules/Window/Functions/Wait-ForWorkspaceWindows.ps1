# TODO: Ensure that if some windows are already opened when w is re-ran, cycle only through new ones with FocusWindows
# Also, for every browser, cycle tabs as well since if Email browser group truly is opened, but tab two is focused, then matching of window won't work as expected
function Wait-ForWorkspaceWindows {
	<#
	.SYNOPSIS
		Waits for all expected windows from a workspace layout to be ready.

	.DESCRIPTION
		Polls for windows defined in a layout configuration until all are detected
		or a timeout is reached. Supports searching by ProcessName, WindowTitle, or both.
		When both are specified, uses OR logic for redundant window detection.

		Supports duplicate layout entries where the same (ProcessName, WindowTitle) pair
		appears multiple times (e.g., two identical browser windows in different zones).
		Each duplicate entry independently tracks and claims a distinct window handle,
		preserving handle affinity across poll iterations to prevent stability resets
		from handle swapping.

	.PARAMETER LayoutConfig
		The layout configuration array containing window definitions with ProcessName
		and/or WindowTitle properties. When both are provided for a window, it will
		match if EITHER criterion is satisfied, making detection more robust.

	.PARAMETER TimeoutSeconds
		Maximum number of seconds to wait for all windows. Default is 60 seconds.

	.PARAMETER PollIntervalSeconds
		Time to wait between polling attempts. Default is 1 second.

	.PARAMETER FocusWindows
		When enabled, cycles through and focuses found windows to speed up loading.
		Some apps (Firefox, WhatsApp) load faster when focused. Default is enabled.

	.PARAMETER FocusDelayMs
		Milliseconds to focus each window before moving to the next.
		Default is 200ms. Increase if windows need more focus time to load.

	.PARAMETER MinimumStableDurationSeconds
		Number of seconds a window must remain stable (consistent title and dimensions)
		before being considered fully loaded. Default is 2 seconds. Increase for apps
		that take longer to initialize after the window appears.

	.PARAMETER RequireStableDimensions
		When enabled, requires window dimensions to remain stable (not resizing)
		during the MinimumStableDurationSeconds period. Default is enabled.

	.EXAMPLE
		$config = Import-PowerShellDataFile -Path "layout.psd1"
		Wait-ForWorkspaceWindows -LayoutConfig $config.Layout

	.EXAMPLE
		Wait-ForWorkspaceWindows -LayoutConfig $layout -TimeoutSeconds 30 -PollIntervalSeconds 0.5

	.EXAMPLE
		Wait-ForWorkspaceWindows -LayoutConfig $layout -FocusWindows -FocusDelayMs 300

	.EXAMPLE
		Wait-ForWorkspaceWindows -LayoutConfig $layout -MinimumStableDurationSeconds 3 -RequireStableDimensions
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[array]$LayoutConfig,

		[Parameter()]
		[int]$TimeoutSeconds = 15,

		[Parameter()]
		[double]$PollIntervalSeconds = 0.1,

		[Parameter()]
		[switch]$FocusWindows = $true,

		[Parameter()]
		[int]$FocusDelayMs = 5,

		[Parameter()]
		[double]$MinimumStableDurationSeconds = 1,

		[Parameter()]
		[switch]$RequireStableDimensions = $true,

		[Parameter()]
		[scriptblock]$OnWindowStable
	)

	# Use consolidated native types from WindowNative.cs (loaded in Window.psm1)
	# WindowModule.Native provides: SetForegroundWindow(), etc.

	# Extract expected windows from layout configuration.
	# Each layout entry gets its own expected-window record (including duplicates).
	# When the same (ProcessName, WindowTitle) appears multiple times, an Index suffix
	# is added so that stability tracking and handle claiming work per-entry.
	$expectedWindows = [System.Collections.Generic.List[hashtable]]::new()
	$layoutKeyCounter = @{}
	foreach ($windowDef in $LayoutConfig) {
		# Expand layout-file tokens (e.g. "Browser") to regex patterns so Get-WindowHandle
		# can actually match live processes. Raw values are kept for the user-facing
		# Description and for the browser-token detection below.
		$resolvedDef = Resolve-LayoutTokens -LayoutEntry $windowDef

		# Normalize WindowTitle (treat "$null" string as actual null)
		$normalizedWindowTitle = if ($windowDef.WindowTitle -and $windowDef.WindowTitle -ne '$null') {
			$windowDef.WindowTitle
		}
		else {
			$null
		}
		$resolvedWindowTitle = if ($resolvedDef.WindowTitle -and $resolvedDef.WindowTitle -ne '$null') {
			$resolvedDef.WindowTitle
		}
		else {
			$null
		}

		$baseKey = "$($windowDef.ProcessName)|$normalizedWindowTitle"
		if ($layoutKeyCounter.ContainsKey($baseKey)) {
			$layoutKeyCounter[$baseKey]++
		}
		else {
			$layoutKeyCounter[$baseKey] = 1
		}
		$entryIndex = $layoutKeyCounter[$baseKey]

		$windowInfo = @{
			ProcessName       = $windowDef.ProcessName
			WindowTitle       = $normalizedWindowTitle
			SearchProcessName = $resolvedDef.ProcessName
			SearchWindowTitle = $resolvedWindowTitle
			BaseKey           = $baseKey
			EntryIndex        = $entryIndex
			LayoutEntry       = $windowDef
			Description       = if ($normalizedWindowTitle) {
				"$($windowDef.ProcessName) - $normalizedWindowTitle"
			}
			else {
				$windowDef.ProcessName
			}
		}
		$expectedWindows.Add($windowInfo)
	}

	# Mark which keys are actually duplicates (appear more than once)
	$duplicateBaseKeys = New-Object 'System.Collections.Generic.HashSet[string]'
	foreach ($k in $layoutKeyCounter.GetEnumerator()) {
		if ($k.Value -gt 1) {
			[void]$duplicateBaseKeys.Add($k.Key)
		}
	}
	foreach ($ew in $expectedWindows) {
		$ew.IsDuplicateKey = $duplicateBaseKeys.Contains($ew.BaseKey)
		# For duplicate entries, append index to Description for clarity
		if ($ew.IsDuplicateKey) {
			$ew.Description = "$($ew.Description) (#$($ew.EntryIndex))"
		}
	}

	if ($expectedWindows.Count -eq 0) {
		Write-LogDebug " No windows defined in layout configuration - skipping wait" -Style Warning
		return @{
			Success      = $true
			WindowStates = @{}
		}
	}

	if (Test-LogVerbose) {
		Write-LogDebug "Waiting for $($expectedWindows.Count) window(s) to be ready ..." -Style Step
		if ($FocusWindows) {
			Write-LogDebug "Window focusing ENABLED => cycling through windows every ${FocusDelayMs}ms to speed up loading!" -Style Warning
		}
		Write-LogDebug "Timeout => $TimeoutSeconds seconds | Poll interval => $PollIntervalSeconds second(s)"
		Write-LogDebug "Stability requirements => ${MinimumStableDurationSeconds}s stable duration | Stable dimensions => $RequireStableDimensions"
	}

	# Generic browser titles that indicate the window isn't fully loaded
	$genericBrowserTitles = @(
		"Mozilla Firefox",
		"New Tab",
		"Google Chrome",
		"Microsoft Edge",
		"Chromium",
		"DBeaver"
	)

	# Track window titles for stability checking
	$windowTitleHistory = @{}

	# Reverse lookup: handle -> key for O(1) access in focus loop
	$handleToKey = @{}

	# Track which windows have already been focused (to avoid repeated focus-stealing)
	# A window is focused once when first detected, and re-focused only if its handle/title changes
	$focusedWindows = New-Object 'System.Collections.Generic.HashSet[IntPtr]'

	# Browser process names - only these benefit from focus-to-load acceleration
	$browserProcessNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
	@("firefox", "chrome", "msedge", "brave", "chromium", "Browser") | ForEach-Object { [void]$browserProcessNames.Add($_) }

	# Track collective stability - all windows must be stable together
	$collectiveStabilityStartTime = $null

	# Track which entries have already fired the OnWindowStable callback to ensure once-per-entry invocation
	$callbackTriggered = New-Object 'System.Collections.Generic.HashSet[string]'

	$startTime = Get-Date
	$allWindowsFound = $false
	$iteration = 0

	# Keep the Windows Terminal on top during the wait phase so browser focus calls
	# don't visually push it behind other windows (prevents screen flickering).
	# Find by process name ("WindowsTerminal") rather than GetForegroundWindow(),
	# because by this point browsers/apps have already been opened and stolen focus.
	$terminalHandle = [IntPtr]::Zero
	$terminalSetTopmost = $false
	$terminalWindow = Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue | Select-Object -First 1
	if ($terminalWindow) {
		$terminalHandle = $terminalWindow.Handle
		$terminalSetTopmost = [WindowModule.Native]::SetWindowTopmost($terminalHandle, $true)
		if (Test-LogVerbose) {
			if ($terminalSetTopmost) {
				Write-LogDebug "Terminal window set to topmost during wait phase (Handle => $terminalHandle)"
			}
			else {
				Write-LogDebug "Failed to set terminal window as topmost" -Style Warning
			}
		}
	}
	elseif (Test-LogVerbose) {
		Write-LogDebug "Could not find WindowsTerminal process - topmost not applied" -Style Warning
	}

	try {

		while (-not $allWindowsFound) {
			$iteration++
			$elapsedSeconds = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)

			$progressColor = "Green"
			if ($elapsedSeconds -ge 10 -and $elapsedSeconds -lt 20) {
				$progressColor = "Yellow"
			}
			elseif ($elapsedSeconds -ge 20 -and $elapsedSeconds -lt 30) {
				$progressColor = "DarkYellow"
			}
			elseif ($elapsedSeconds -ge 30) {
				$progressColor = "Red"
			}

			# Check if timeout reached
			if ($elapsedSeconds -ge $TimeoutSeconds) {
				if (Test-LogVerbose) {
					Write-Host -ForegroundColor $progressColor "`n=> Timeout reached after [$elapsedSeconds] seconds"
				}
				break
			}

			# Check each expected window
			$foundCount = 0
			$notFoundWindows = [System.Collections.Generic.List[string]]::new()
			$foundWindowHandles = [System.Collections.Generic.List[System.IntPtr]]::new()
			# Track windows that are found but NOT yet stable (these are the ones that need focusing)
			$unstableBrowserHandles = [System.Collections.Generic.List[System.IntPtr]]::new()

			# Track handles claimed during this poll iteration for duplicate entries
			$iterationClaimedHandles = New-Object 'System.Collections.Generic.HashSet[IntPtr]'

			foreach ($expectedWindow in $expectedWindows) {
				$windowFound = $false

				try {
					# Search by both ProcessName and WindowTitle if both are available
					# Get-WindowHandle uses OR logic, so it finds the window via whichever criterion matches
					# This provides redundancy - if one is slow or fails, the other succeeds
					$getWindowParams = @{}
					if ($expectedWindow.SearchProcessName) {
						$getWindowParams['ProcessName'] = $expectedWindow.SearchProcessName
					}
					if ($expectedWindow.SearchWindowTitle) {
						$getWindowParams['WindowTitle'] = $expectedWindow.SearchWindowTitle
					}

					$windows = Get-WindowHandle @getWindowParams -ErrorAction SilentlyContinue

					# For duplicate keys, filter out handles already claimed by earlier entries
					# in this poll iteration so each entry tracks a distinct window
					if ($expectedWindow.IsDuplicateKey -and $windows -and $windows.Count -gt 0) {
						$windows = @($windows | Where-Object { -not $iterationClaimedHandles.Contains($_.Handle) })
					}

					if ($windows -and $windows.Count -gt 0) {
						# Use entry index in key so duplicate entries get independent stability tracking
						$windowKey = if ($expectedWindow.IsDuplicateKey) {
							"$($expectedWindow.ProcessName)_$($expectedWindow.WindowTitle)_#$($expectedWindow.EntryIndex)"
						}
						else {
							"$($expectedWindow.ProcessName)_$($expectedWindow.WindowTitle)"
						}

						# For duplicate entries: prefer the handle already tracked in stability history
						# to avoid handle-swapping between poll iterations (which resets stability).
						# If the previously assigned handle is still in the unclaimed list, use it.
						$window = $null
						if ($expectedWindow.IsDuplicateKey -and $windowTitleHistory.ContainsKey($windowKey)) {
							$previousHandle = $windowTitleHistory[$windowKey].Handle
							$window = $windows | Where-Object { $_.Handle -eq $previousHandle } | Select-Object -First 1
						}
						if (-not $window) {
							$window = $windows[0]
						}

						$windowTitle = $window.Title

						# Check if window has proper dimensions (indicating it's fully initialized)
						# Some apps like DBeaver create a process/handle but the GUI takes time to initialize
						$minWidth = 50
						$minHeight = 50
						$hasProperDimensions = ($window.Width -gt $minWidth) -and ($window.Height -gt $minHeight)

						if (-not $hasProperDimensions) {
							if (-not $notFoundWindows.Contains($expectedWindow.Description)) {
								$notFoundWindows.Add("$($expectedWindow.Description) (window not ready: $($window.Width)x$($window.Height))")
							}
							# Still claim the handle for duplicate entries
							if ($expectedWindow.IsDuplicateKey -and $window.Handle) {
								[void]$iterationClaimedHandles.Add($window.Handle)
							}
							continue
						}

						# For browser windows with specific title requirements, validate the title is not generic
						# UNLESS the user explicitly expects a generic title (e.g., WindowTitle = "*New Tab*")
						$isBrowserProcess = ($expectedWindow.ProcessName -ieq "Browser") -or ($expectedWindow.ProcessName -in @("firefox", "chrome", "msedge", "chromium", "brave"))
						if ($isBrowserProcess -and $expectedWindow.WindowTitle) {
							# Check if the window title is generic (not fully loaded)
							$isGenericTitle = $false
							foreach ($genericTitle in $genericBrowserTitles) {
								if ($windowTitle -eq $genericTitle) {
									$isGenericTitle = $true
									break
								}
							}

							if ($isGenericTitle) {
								# Check if the user's expected pattern actually matches this generic title
								# If so, they explicitly want the generic title - accept it
								# Use Test-WindowTitleMatch to support both wildcard (e.g., *New Tab*) and regex (e.g., (.*Calendar.*|.*Week.*)) patterns
								if (Test-WindowTitleMatch -WindowTitle $windowTitle -Patterns @($expectedWindow.WindowTitle)) {
									# User expects this generic title, proceed normally
								}
								else {
									# Window exists but title is generic, not ready yet (user expects a specific page title)
									if (-not $windowTitleHistory.ContainsKey($windowKey)) {
										$windowTitleHistory[$windowKey] = @{
											Title              = $windowTitle
											ConsecutiveMatches = 0
											LastSeen           = Get-Date
										}
									}
									# Don't count this as found
									if (-not $notFoundWindows.Contains($expectedWindow.Description)) {
										$notFoundWindows.Add("$($expectedWindow.Description) (generic title: '$windowTitle')")
									}								# Still claim the handle for duplicate entries
									if ($expectedWindow.IsDuplicateKey -and $window.Handle) {
										[void]$iterationClaimedHandles.Add($window.Handle)
									}									continue
								}
							}
						}

						# Track title and dimension stability
						# Window must remain stable (same title, same dimensions if required) for MinimumStableDurationSeconds
						$currentTime = Get-Date
						$isStable = $false

						if (-not $windowTitleHistory.ContainsKey($windowKey)) {
							# First time seeing this window
							$windowTitleHistory[$windowKey] = @{
								Handle             = $window.Handle
								Title              = $windowTitle
								Width              = $window.Width
								Height             = $window.Height
								Left               = $window.Left
								Top                = $window.Top
								ConsecutiveMatches = 1
								FirstStableTime    = $currentTime
								LastSeen           = $currentTime
							}
							# Update reverse lookup
							$handleToKey[$window.Handle] = $windowKey
						}
						else {
							$history = $windowTitleHistory[$windowKey]
							$titleChanged = $history.Title -ne $windowTitle
							$dimensionsChanged = $false
							$handleChanged = $history.Handle -ne $window.Handle

							if ($RequireStableDimensions) {
								$dimensionsChanged = ($history.Width -ne $window.Width) -or ($history.Height -ne $window.Height)
							}

							if ($titleChanged -or $dimensionsChanged -or $handleChanged) {
								# Window changed, reset stability tracking for this window
								$history.Handle = $window.Handle
								$history.Title = $windowTitle
								$history.Width = $window.Width
								$history.Height = $window.Height
								$history.Left = $window.Left
								$history.Top = $window.Top
								$history.ConsecutiveMatches = 2
								$history.FirstStableTime = $currentTime
								$history.LastSeen = $currentTime

								# Update reverse lookup for handle changes
								$handleToKey[$window.Handle] = $windowKey

								# Reset focus tracking for this window so it gets re-focused after change
								[void]$focusedWindows.Remove($window.Handle)

								# Reset collective stability when ANY window changes
								$collectiveStabilityStartTime = $null

								$changeReason = if ($handleChanged) { "handle (window recreated)" } elseif ($titleChanged) { "title" } else { "dimensions" }
								if (-not $notFoundWindows.Contains($expectedWindow.Description)) {
									$notFoundWindows.Add("$($expectedWindow.Description) ($changeReason changed, resetting stability)")
								}
							}
							else {
								# Window is consistent, check stable duration
								$history.ConsecutiveMatches++
								$history.LastSeen = $currentTime
								$stableDuration = ($currentTime - $history.FirstStableTime).TotalSeconds

								if ($stableDuration -ge $MinimumStableDurationSeconds) {
									$isStable = $true
								}
								else {
									if (-not $notFoundWindows.Contains($expectedWindow.Description)) {
										$remainingTime = [math]::Round($MinimumStableDurationSeconds - $stableDuration, 1)
										$notFoundWindows.Add("$($expectedWindow.Description) (stabilizing: ${remainingTime}s remaining)")
									}
								}
							}
						}

						# Window is individually stable if it's been stable for the required duration
						if ($isStable) {
							$windowFound = $true
							$foundCount++
							# Track window handle for stable windows list
							if ($window.Handle) {
								$foundWindowHandles.Add($window.Handle)
							}
							# Claim this handle for duplicate entries
							if ($expectedWindow.IsDuplicateKey) {
								[void]$iterationClaimedHandles.Add($window.Handle)
							}
							# Fire early-stable callback once per entry so the caller can immediately
							# relocate this window without waiting for all other windows to stabilize.
							if ($OnWindowStable -and -not $callbackTriggered.Contains($windowKey)) {
								[void]$callbackTriggered.Add($windowKey)
								try { & $OnWindowStable $expectedWindow.LayoutEntry $window } catch {}
							}
						}
						else {
							# Window found but not yet stable - candidate for focus-to-load if it's a browser
							if ($window.Handle -and $browserProcessNames.Contains($expectedWindow.ProcessName)) {
								$unstableBrowserHandles.Add($window.Handle)
							}
							# Still claim the handle so the next duplicate entry picks a different window
							if ($expectedWindow.IsDuplicateKey -and $window.Handle) {
								[void]$iterationClaimedHandles.Add($window.Handle)
							}
						}
					}
				}
				catch {
					# Window not found yet, will retry
				}

				if (-not $windowFound -and -not ($notFoundWindows -like "*$($expectedWindow.Description)*")) {
					$notFoundWindows.Add($expectedWindow.Description)
				}
			}

			# Check if all windows are individually stable
			if ($foundCount -eq $expectedWindows.Count) {
				# All windows are individually stable, now check collective stability
				$currentTime = Get-Date

				if ($null -eq $collectiveStabilityStartTime) {
					# First time all windows are stable together, start collective timer
					$collectiveStabilityStartTime = $currentTime
					Write-LogDebug "=> All $foundCount window(s) individually stable!" -Style Success
					Write-LogDebug " Starting collective stability check..."
				}

				$collectiveStableDuration = ($currentTime - $collectiveStabilityStartTime).TotalSeconds

				if ($collectiveStableDuration -ge $MinimumStableDurationSeconds) {
					# All windows have been stable together for the required duration
					$allWindowsFound = $true
					if (Test-LogVerbose) {
						Write-Host -ForegroundColor $progressColor "`n=> All $foundCount window(s) collectively stable for ${collectiveStableDuration}s! Total elapsed => [$elapsedSeconds seconds]"
					}

					# Build state snapshot to return
					$windowStates = @{}
					foreach ($historyEntry in $windowTitleHistory.GetEnumerator()) {
						$state = $historyEntry.Value
						$windowStates[$state.Handle] = @{
							Title  = $state.Title
							X      = $state.Left
							Y      = $state.Top
							Width  = $state.Width
							Height = $state.Height
						}
					}

					return @{
						Success      = $true
						WindowStates = $windowStates
					}
				}
				else {
					# Still waiting for collective stability
					$remainingCollectiveTime = [math]::Round($MinimumStableDurationSeconds - $collectiveStableDuration, 1)
					if (-not $notFoundWindows.Contains("Collective Stability")) {
						$notFoundWindows.Add("Waiting for collective stability (${remainingCollectiveTime}s remaining)")
					}
				}
			}
			else {
				# Not all windows individually stable yet, reset collective timer
				$collectiveStabilityStartTime = $null
			}

			# Focus unstable browser windows to speed up their loading (if enabled)
			# Only targets browser processes (they load tabs faster when focused) and only
			# focuses each window ONCE to avoid repeated focus-stealing that causes screen flickering.
			# Re-focuses a window only if its handle/title changed (tracked via $focusedWindows HashSet).
			if ($FocusWindows -and $unstableBrowserHandles.Count -gt 0) {
				foreach ($windowHandle in $unstableBrowserHandles) {
					# Skip if already focused (unless reset by title/handle change)
					if ($focusedWindows.Contains($windowHandle)) {
						continue
					}

					try {
						# O(1) reverse lookup instead of pipeline enumeration
						$windowKey = $handleToKey[$windowHandle]
						$windowTitle = if ($windowKey -and $windowTitleHistory.ContainsKey($windowKey)) { $windowTitleHistory[$windowKey].Title } else { "Unknown" }

						if (Test-LogVerbose) {
							Write-LogDebug "Focusing browser window => [$windowTitle] (Handle => $windowHandle)" -Style Step
						}

						[void][WindowModule.Native]::SetForegroundWindow($windowHandle)
						Start-Sleep -Milliseconds $FocusDelayMs

						# Mark as focused so we don't re-focus on subsequent poll iterations
						[void]$focusedWindows.Add($windowHandle)
					}
					catch {
						# Ignore focus errors - window may have closed or become invalid
						if (Test-LogVerbose) {
							Write-LogDebug "Failed to focus window [$windowTitle] (Handle => $windowHandle)" -Style Warning
						}
					}
				}
			}

			# Display progress (every 5 iterations to avoid spam)
			if ($iteration % 5 -eq 0) {
				if (Test-LogVerbose) {
					Write-Host -ForegroundColor $progressColor "`n  [$elapsedSeconds`s] Found => $foundCount/$($expectedWindows.Count)"
					if ($notFoundWindows.Count -gt 0) {
						Write-Host -ForegroundColor $progressColor "   Waiting for:"
						foreach ($window in $notFoundWindows) {
							Write-Host -ForegroundColor DarkCyan "    • $window"
						}
					}
				}
			}

			# Wait before next poll
			Start-Sleep -Seconds $PollIntervalSeconds
		}

	} # end try
	finally {
		# Always restore terminal window to normal z-order when wait phase completes
		if ($terminalSetTopmost -and $terminalHandle -ne [IntPtr]::Zero) {
			[void][WindowModule.Native]::SetWindowTopmost($terminalHandle, $false)
			Write-LogDebug "=> Terminal window restored to normal z-order" -Style Success
		}
	}

	# If we exit the loop without finding all windows, show what's missing with diagnostics
	if (-not $allWindowsFound) {
		if (Test-LogVerbose) {
			Write-LogDebug "Windows still not found:" -Style Warning

			foreach ($expectedWindow in $expectedWindows) {
				$windowFound = $false
				try {
					# Search by both ProcessName and WindowTitle if both are available
					$getWindowParams = @{}
					if ($expectedWindow.SearchProcessName) {
						$getWindowParams['ProcessName'] = $expectedWindow.SearchProcessName
					}
					if ($expectedWindow.SearchWindowTitle) {
						$getWindowParams['WindowTitle'] = $expectedWindow.SearchWindowTitle
					}

					$windows = Get-WindowHandle @getWindowParams -ErrorAction SilentlyContinue
					$windowFound = ($windows -and $windows.Count -gt 0)
				}
				catch { }

				if (-not $windowFound) {
					Write-LogDebug "- $($expectedWindow.Description)" -Style Warning

					# If we searched by title, also check if process exists
					if ($expectedWindow.WindowTitle) {
						Write-LogDebug "No windows found matching title [$($expectedWindow.WindowTitle)]" -Style Step

						# Check if we can find windows by process name
						$processByName = Get-WindowHandle -ProcessName $expectedWindow.SearchProcessName -ErrorAction SilentlyContinue
						if ($processByName) {
							Write-LogDebug "Process [$($expectedWindow.ProcessName)] found with windows:" -Style Step
							$processByName | Select-Object -First 5 | ForEach-Object {
								Write-LogDebug "- [$($_.Title)]" -Style Step
							}
						}
					}
					else {
						# Try to find similar process names
						$allProcesses = Get-WindowHandle -All -ErrorAction SilentlyContinue
						$similarProcesses = $allProcesses | Where-Object {
							$_.ProcessName -like "*$($expectedWindow.ProcessName)*" -or
							$expectedWindow.ProcessName -like "*$($_.ProcessName)*"
						} | Select-Object -Unique ProcessName, Title

						if ($similarProcesses) {
							Write-LogDebug "Process '$($expectedWindow.ProcessName)' not found. Similar processes:" -Style Step
							$similarProcesses | Select-Object -First 5 | ForEach-Object {
								Write-LogDebug "* $($_.ProcessName) - '$($_.Title)'" -Style Step
							}
						}
						else {
							Write-LogDebug "Process '$($expectedWindow.ProcessName)' not found and no similar processes detected" -Style Step
						}
					}
				}
			}

			Write-LogDebug "Proceeding with layout setup..." -Style Warning
		}

		# Return failure with empty window states
		return @{
			Success      = $false
			WindowStates = @{}
		}
	}

	# This should never be reached, but return success just in case
	return @{
		Success      = $true
		WindowStates = @{}
	}
}
