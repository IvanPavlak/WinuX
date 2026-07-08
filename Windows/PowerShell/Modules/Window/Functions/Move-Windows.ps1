function Move-Windows {
	<#
	.SYNOPSIS
		Moves all open windows to a specified virtual desktop and optional monitor.

	.DESCRIPTION
		Enumerates all visible application windows and moves each one to the
		specified virtual desktop. Uses 1-based indexing for the user-facing
		parameter (desktop 1 is the first desktop). If the target virtual
		desktop does not exist, it is created automatically. After the move
		pass completes, switches focus to the target desktop.

		Optionally, windows can also be moved to a target physical monitor in
		the same pass by using -Monitor. Monitor targeting supports:
		- 1-based monitor index (for example: 1, 2)
		- Standard labels from Get-MonitorSpecs (Primary, Secondary, Monitor3...)
		- Exact monitor device name (for example: \\.\DISPLAY1)

		When monitor targeting is enabled, window position is preserved relative
		to the source monitor work area and then clamped to the destination
		monitor work area for safe placement.

		Use -Current to move windows to the same virtual desktop as the
		calling terminal, without needing to know which desktop number it is.

		Filtering supports ProcessName and/or WindowTitle with exact names,
		wildcard patterns (*, ?), and regex - delegated to Get-WindowHandle.
		When both are provided, windows matching EITHER criterion are moved
		(OR logic), consistent with Get-WindowHandle conventions.

		Uses existing module functions:
		- Get-WindowHandle for pattern-based window filtering (wildcard, regex, exact)
		- Get-CachedWindows for fast window enumeration (when no filters)
		- Move-WindowToVirtualDesktop for reliable virtual desktop placement
		- Import-VirtualDesktopModule for VirtualDesktop module availability

	.PARAMETER VirtualDesktop
		The virtual desktop number to move all windows to (1-based).
		Desktop 1 is the first desktop. Default is 1.
		Cannot be used together with -Current.

	.PARAMETER Current
		Moves windows to the virtual desktop where the calling terminal
		session is currently located. Detects the active desktop automatically.
		Cannot be used together with -VirtualDesktop.

	.PARAMETER ProcessName
		Optional. Only move windows belonging to processes matching this pattern (without .exe).
		Supports exact names, wildcard patterns (*, ?), and regex.
		Can be used alone or combined with WindowTitle (OR logic).
		When omitted (and no WindowTitle), all visible application windows are moved.

	.PARAMETER WindowTitle
		Optional. Only move windows whose title matches this pattern.
		Supports wildcard patterns (*, ?) and regex.
		Can be used alone or combined with ProcessName (OR logic).
		When omitted (and no ProcessName), all visible application windows are moved.

	.PARAMETER Monitor
		Optional. Also move windows to a target physical monitor.
		Accepted values:
		- 1-based monitor index (for example: 1, 2)
		- Monitor labels (Primary, Secondary, Monitor3, ...)
		- Exact monitor device name (for example: \\.\DISPLAY1)

	.EXAMPLE
		Move-Windows
		Moves all windows to the first virtual desktop.

	.EXAMPLE
		Move-Windows -VirtualDesktop 2
		Moves all windows to the second virtual desktop.

	.EXAMPLE
		Move-Windows -Current
		Moves all windows to the same virtual desktop as the calling terminal
		(and keeps focus there).

	.EXAMPLE
		Move-Windows -Current -ProcessName "chrome"
		Moves only Chrome windows to the current terminal's virtual desktop.

	.EXAMPLE
		Move-Windows -VirtualDesktop 3 -ProcessName "chrome"
		Moves only Chrome windows to the third virtual desktop.

	.EXAMPLE
		Move-Windows -ProcessName "(chrome|firefox|msedge)"
		Moves all browser windows to the first virtual desktop (regex match).

	.EXAMPLE
		Move-Windows -WindowTitle "*YouTube*"
		Moves windows with "YouTube" in the title to the first virtual desktop.

	.EXAMPLE
		Move-Windows -WindowTitle "^Visual Studio"
		Moves windows whose title starts with "Visual Studio" (regex match).

	.EXAMPLE
		Move-Windows -ProcessName "chrome" -WindowTitle "*GitHub*"
		Moves Chrome windows OR windows with "GitHub" in the title (OR logic).

	.EXAMPLE
		Move-Windows -Current -Monitor Secondary
		Moves all windows to the current desktop and repositions them on the
		Secondary monitor.

	.EXAMPLE
		Move-Windows -VirtualDesktop 2 -Monitor 1
		Moves all windows to Virtual Desktop 2 and onto monitor index 1.
	#>
	[CmdletBinding(DefaultParameterSetName = 'ByNumber')]
	param (
		[Parameter(ParameterSetName = 'ByNumber')]
		[ValidateRange(1, 100)]
		[int]$VirtualDesktop = 1,

		[Parameter(ParameterSetName = 'ByCurrent')]
		[switch]$Current,

		[Parameter()]
		[string]$ProcessName,

		[Parameter()]
		[string]$WindowTitle,

		[Parameter()]
		[string]$Monitor
	)

	begin {
		$abortProcessing = $false
		$rpcPolicy = if (Get-Command Get-RpcRetryPolicy -ErrorAction SilentlyContinue) {
			Get-RpcRetryPolicy -OperationLabel "moving windows"
		}
		else {
			@{ MaxAttempts = 3; InitialDelayMs = 200 }
		}
		$rpcMaxAttempts = [int]$rpcPolicy.MaxAttempts
		$rpcInitialDelayMs = [int]$rpcPolicy.InitialDelayMs
		$useRetry = [bool](Get-Command Invoke-WithRetry -ErrorAction SilentlyContinue)

		if ($Current) {
			# Detect the virtual desktop of the calling terminal
			if (-not (Import-VirtualDesktopModule)) {
				Write-LogError "Error: VirtualDesktop module is required for -Current!"
				$abortProcessing = $true
				return
			}

			try {
				$currentDesktop = Invoke-WithOptionalRetry -EnableRetry:$useRetry -ScriptBlock { Get-CurrentDesktop } -MaxAttempts $rpcMaxAttempts -InitialDelayMs $rpcInitialDelayMs
				$desktopIndex = Invoke-WithOptionalRetry -EnableRetry:$useRetry -ScriptBlock { Get-DesktopIndex $currentDesktop } -MaxAttempts $rpcMaxAttempts -InitialDelayMs $rpcInitialDelayMs
				$VirtualDesktop = $desktopIndex + 1
			}
			catch {
				Write-LogError "Error: Could not detect current virtual desktop: $($_.Exception.Message)"
				$abortProcessing = $true
				return
			}

			Write-LogDebug "Current terminal is on Virtual Desktop $VirtualDesktop"
		}
		else {
			# Ensure the VirtualDesktop module is available
			if (-not (Import-VirtualDesktopModule)) {
				Write-LogError "Error: VirtualDesktop module is required!"
				$abortProcessing = $true
				return
			}

			# Create the target virtual desktop if it doesn't exist
			# Retry to handle transient RPC server unavailable errors (0x800706BA)
			try {
				$desktopCount = Invoke-WithOptionalRetry -EnableRetry:$useRetry -ScriptBlock { Get-DesktopCount } -MaxAttempts $rpcMaxAttempts -InitialDelayMs $rpcInitialDelayMs
			}
			catch {
				Write-LogError "Error: Could not query virtual desktops: $($_.Exception.Message)"
				$abortProcessing = $true
				return
			}

			if ($VirtualDesktop -gt $desktopCount) {
				Write-LogDebug "Virtual Desktop $VirtualDesktop does not exist (only $desktopCount desktop(s) available). Creating..." -Style Warning
				$ensured = Ensure-VirtualDesktops -Count $VirtualDesktop
				if ($ensured -eq $false) {
					Write-LogError "Error: Failed to create Virtual Desktop $VirtualDesktop!"
					$abortProcessing = $true
					return
				}
			}

			# Convert 1-based user input to 0-based internal index
			$desktopIndex = $VirtualDesktop - 1
		}

		$targetMonitor = $null
		$monitorTargetLabel = $null
		$allMonitors = $null

		if ($Monitor) {
			$allMonitors = Get-MonitorInfo -Quiet
			if (-not $allMonitors -or $allMonitors.Count -eq 0) {
				Write-LogError "Error: Could not detect any monitors for -Monitor targeting!"
				$abortProcessing = $true
				return
			}

			$monitorInput = $Monitor.Trim()
			$monitorIndex = 0
			$isNumericMonitor = [int]::TryParse($monitorInput, [ref]$monitorIndex)

			if ($isNumericMonitor) {
				if ($monitorIndex -lt 1 -or $monitorIndex -gt $allMonitors.Count) {
					Write-LogError "Error: Monitor index [$monitorIndex] is out of range. Available monitor indices: 1..$($allMonitors.Count)."
					$abortProcessing = $true
					return
				}
				$targetMonitor = $allMonitors[$monitorIndex - 1]
				$monitorTargetLabel = "Monitor$monitorIndex"
			}

			if (-not $targetMonitor -and $monitorInput -ieq 'Primary') {
				$targetMonitor = $allMonitors | Where-Object { $_.IsPrimary } | Select-Object -First 1
				$monitorTargetLabel = 'Primary'
			}

			if (-not $targetMonitor) {
				$monitorSpecs = Get-MonitorSpecs -MonitorInfo $allMonitors
				if ($monitorSpecs -and ($monitorSpecs.PSObject.Properties.Name -contains $monitorInput)) {
					$targetSpec = $monitorSpecs.$monitorInput
					$targetMonitor = $allMonitors | Where-Object {
						$_.Left -eq $targetSpec.X -and $_.Top -eq $targetSpec.Y -and
						$_.Width -eq $targetSpec.Width -and $_.Height -eq $targetSpec.Height
					} | Select-Object -First 1
					if ($targetMonitor) {
						$monitorTargetLabel = $monitorInput
					}
				}
			}

			if (-not $targetMonitor) {
				$targetMonitor = $allMonitors | Where-Object { $_.DeviceName -ieq $monitorInput } | Select-Object -First 1
				if ($targetMonitor) {
					$monitorTargetLabel = $targetMonitor.DeviceName
				}
			}

			if (-not $targetMonitor) {
				$availableLabels = @('Primary')
				for ($i = 2; $i -le $allMonitors.Count; $i++) {
					$availableLabels += if ($i -eq 2) { 'Secondary' } else { "Monitor$i" }
				}
				Write-LogError "Error: Could not resolve monitor [$Monitor]. Available labels: $($availableLabels -join ', ')."
				$abortProcessing = $true
				return
			}

			Write-LogDebug "Target monitor resolved => $monitorTargetLabel ($($targetMonitor.DeviceName))"
		}
	}

	process {
		if ($abortProcessing) {
			return
		}

		if (Test-LogVerbose) {
			$targetText = if ($targetMonitor) {
				"Virtual Desktop $VirtualDesktop and monitor $monitorTargetLabel"
			}
			else {
				"Virtual Desktop $VirtualDesktop"
			}
			# Only call it "All Windows" when no filter narrows the set; otherwise just "Windows".
			$scopeText = if ($ProcessName -or $WindowTitle) { "Windows" } else { "All Windows" }
			Write-LogDebug "Moving $scopeText to $targetText"
		}

		# Clear cache first to get fresh window positions
		Clear-WindowCache

		# Delegate filtering to Get-WindowHandle (supports exact, wildcard, and regex
		# for both ProcessName and WindowTitle with OR logic when both are provided)
		$hasFilter = $ProcessName -or $WindowTitle
		if ($hasFilter) {
			$filterParams = @{}
			if ($ProcessName) { $filterParams.ProcessName = $ProcessName }
			if ($WindowTitle) { $filterParams.WindowTitle = $WindowTitle }
			$allWindows = Get-WindowHandle @filterParams
		}
		else {
			$allWindows = Get-CachedWindows
		}

		# System windows to skip
		$skipTitles = @(
			'Program Manager',
			'Windows Input Experience',
			'TextInputHost',
			'Search',
			'Start',
			'Action center',
			'Microsoft Text Input Application',
			'Windows Shell Experience Host',
			'NVIDIA GeForce Overlay',
			'Setup',
			''
		)

		$movedCount = 0
		$movedLabels = @()
		$alreadyCount = 0
		$skippedCount = 0
		$monitorMovedCount = 0
		$monitorSkippedCount = 0
		$excludedTitleCount = 0
		$excludedInvalidSizeCount = 0
		$totalEnumeratedWindows = @($allWindows).Count
		$totalEligibleWindows = 0

		foreach ($window in $allWindows) {
			$handle = $window.Handle
			$title = $window.Title
			$procName = $window.ProcessName

			# Skip system/shell windows
			if ($title -in $skipTitles) {
				$excludedTitleCount++
				continue
			}

			# Skip windows with no meaningful size (hidden or not real)
			if ($window.Width -le 0 -or $window.Height -le 0) {
				$excludedInvalidSizeCount++
				continue
			}

			$totalEligibleWindows++

			# Check if the window is already on the target desktop
			$isAlreadyOnDesktop = $false
			try {
				$windowDesktop = Invoke-WithOptionalRetry -EnableRetry:$useRetry -ScriptBlock { Get-DesktopFromWindow -Hwnd $handle.ToInt64() } -MaxAttempts $rpcMaxAttempts -InitialDelayMs $rpcInitialDelayMs
				$windowDesktopIndex = Invoke-WithOptionalRetry -EnableRetry:$useRetry -ScriptBlock { Get-DesktopIndex $windowDesktop } -MaxAttempts $rpcMaxAttempts -InitialDelayMs $rpcInitialDelayMs

				if ($windowDesktopIndex -eq $desktopIndex) {
					$isAlreadyOnDesktop = $true
					if (-not $targetMonitor) {
						$alreadyCount++
						Write-LogDebug "     ○ [$title] ($procName) is already on Virtual Desktop $VirtualDesktop" -Style Warning
						continue
					}
				}
			}
			catch {
				# If we can't determine the current desktop, proceed with the move
			}

			$result = $true
			if (-not $isAlreadyOnDesktop) {
				# Move window to the target virtual desktop
				$moveErr = $null
				$moveFailureMessage = ''
				try {
					$moveAction = {
						$localMoveErr = $null
						$localResult = Move-WindowToVirtualDesktop -WindowHandle $handle -DesktopNumber $desktopIndex -ErrorVariable localMoveErr -ErrorAction SilentlyContinue
						if (-not $localResult) {
							if ($localMoveErr) {
								throw $localMoveErr[0].Exception.Message
							}
							throw "Move-WindowToVirtualDesktop returned no result"
						}
						return $true
					}

					$result = Invoke-WithOptionalRetry -EnableRetry:$useRetry -ScriptBlock $moveAction -MaxAttempts $rpcMaxAttempts -InitialDelayMs $rpcInitialDelayMs
				}
				catch {
					$result = $false
					$moveFailureMessage = $_.Exception.Message
				}

				if ($result) {
					$movedCount++
					$movedLabels += Get-WindowDisplayName -ProcessName $procName -Title $title
					Write-LogDebug "     ✓ Moved [$title] ($procName) => Virtual Desktop $VirtualDesktop" -Style Success
				}
				else {
					$skippedCount++
					$reason = if ($moveFailureMessage) { ": $moveFailureMessage" } elseif ($moveErr) { ": $($moveErr[0].Exception.Message)" } else { '' }
					Write-LogDebug "     ✗ Failed to move [$title] ($procName)$reason" -Style Warning
					continue
				}
			}
			else {
				$alreadyCount++
				Write-LogDebug "     ○ [$title] ($procName) is already on Virtual Desktop $VirtualDesktop" -Style Warning
			}

			if ($targetMonitor) {
				# Preserve relative placement from source monitor work area and clamp
				# to destination work area to support different monitor sizes.
				$windowCenterX = $window.Left + [math]::Floor($window.Width / 2)
				$windowCenterY = $window.Top + [math]::Floor($window.Height / 2)

				$sourceMonitor = $allMonitors | Where-Object {
					$windowCenterX -ge $_.Left -and $windowCenterX -lt $_.Right -and
					$windowCenterY -ge $_.Top -and $windowCenterY -lt $_.Bottom
				} | Select-Object -First 1

				if (-not $sourceMonitor) {
					$sourceMonitor = $allMonitors | Where-Object { $_.IsPrimary } | Select-Object -First 1
					if (-not $sourceMonitor) {
						$sourceMonitor = $allMonitors[0]
					}
				}

				$maxSourceXSpan = [math]::Max(1, $sourceMonitor.WorkAreaWidth - $window.Width)
				$maxSourceYSpan = [math]::Max(1, $sourceMonitor.WorkAreaHeight - $window.Height)

				$relativeX = ($window.Left - $sourceMonitor.WorkAreaLeft) / $maxSourceXSpan
				$relativeY = ($window.Top - $sourceMonitor.WorkAreaTop) / $maxSourceYSpan
				$relativeX = [math]::Max(0, [math]::Min(1, $relativeX))
				$relativeY = [math]::Max(0, [math]::Min(1, $relativeY))

				$newWidth = [math]::Min($window.Width, $targetMonitor.WorkAreaWidth)
				$newHeight = [math]::Min($window.Height, $targetMonitor.WorkAreaHeight)
				$targetXSpan = [math]::Max(0, $targetMonitor.WorkAreaWidth - $newWidth)
				$targetYSpan = [math]::Max(0, $targetMonitor.WorkAreaHeight - $newHeight)

				$newX = $targetMonitor.WorkAreaLeft + [math]::Round($relativeX * $targetXSpan)
				$newY = $targetMonitor.WorkAreaTop + [math]::Round($relativeY * $targetYSpan)

				$maxX = $targetMonitor.WorkAreaLeft + $targetXSpan
				$maxY = $targetMonitor.WorkAreaTop + $targetYSpan
				$newX = [math]::Max($targetMonitor.WorkAreaLeft, [math]::Min($maxX, $newX))
				$newY = [math]::Max($targetMonitor.WorkAreaTop, [math]::Min($maxY, $newY))

				$monitorMoveResult = Set-WindowPosition -WindowHandle $handle -X $newX -Y $newY -Width $newWidth -Height $newHeight
				if ($monitorMoveResult) {
					$monitorMovedCount++
					Write-LogDebug "     ✓ Repositioned [$title] ($procName) => monitor $monitorTargetLabel" -Style Success
				}
				else {
					$monitorSkippedCount++
					Write-LogDebug "     ✗ Failed to reposition [$title] ($procName) on monitor $monitorTargetLabel" -Style Warning
				}
			}
		}

		# Ensure focus follows the destination desktop after window moves complete
		$switchedDesktop = $false
		try {
			Invoke-WithOptionalRetry -EnableRetry:$useRetry -ScriptBlock { Switch-Desktop -Desktop $desktopIndex -ErrorAction Stop } -MaxAttempts $rpcMaxAttempts -InitialDelayMs $rpcInitialDelayMs | Out-Null
			$switchedDesktop = $true
		}
		catch {
			Write-LogDebug "     ! Could not switch focus to Virtual Desktop ${VirtualDesktop}: $($_.Exception.Message)" -Style Warning
		}

		if (Test-LogVerbose) {
			$summary = "Moved [$movedCount] window(s) to Virtual Desktop $VirtualDesktop"
			if ($alreadyCount -gt 0) { $summary += ", already there [$alreadyCount]" }
			if ($skippedCount -gt 0) { $summary += ", skipped [$skippedCount]" }
			$summary += ", enumerated [$totalEnumeratedWindows], eligible [$totalEligibleWindows]"
			if ($excludedTitleCount -gt 0 -or $excludedInvalidSizeCount -gt 0) {
				$summary += ", excluded title [$excludedTitleCount], excluded invalid-size [$excludedInvalidSizeCount]"
			}
			if ($targetMonitor) {
				$summary += ", monitor moved [$monitorMovedCount]"
				if ($monitorSkippedCount -gt 0) { $summary += ", monitor failed [$monitorSkippedCount]" }
			}
			if ($switchedDesktop) { $summary += ", focused desktop [$VirtualDesktop]" }
			Write-LogDebug $summary
		}
		else {
			if ($movedCount -gt 0) {
				Write-LogSuccess "Moved $movedCount window(s) to Virtual Desktop $VirtualDesktop!"
				Write-LogList -Items $movedLabels
			}
			if ($alreadyCount -gt 0) {
				Write-LogWarning "$alreadyCount window(s) already on Virtual Desktop $VirtualDesktop."
			}
			if ($targetMonitor -and $monitorMovedCount -gt 0) {
				Write-LogSuccess "$monitorMovedCount window(s) moved to monitor $monitorTargetLabel."
			}
		}
	}
}
