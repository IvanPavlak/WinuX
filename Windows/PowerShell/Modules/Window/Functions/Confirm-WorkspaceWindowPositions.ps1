function Confirm-WorkspaceWindowPositions {
	<#
	.SYNOPSIS
		Performs a final verification that every window defined in the layout config
		exists and is at its expected zone position.

	.DESCRIPTION
		After Set-WindowLayouts positions windows and Snap-AllWindows snaps them into
		FancyZones, this function walks the original layout configuration and for each
		entry:
		  1. Resolves the expected zone coordinates (same logic as Set-WindowLayouts).
		  2. Searches for a live window matching ProcessName / WindowTitle (fresh cache).
		  3. Reads its position via the native GetWindowRect API.
		  4. Compares against the expected zone coordinates within Tolerance.

		If multiple live windows match the same `ProcessName`/`WindowTitle`, the verifier
		scores candidate windows by how closely their actual bounds match the expected
		bounds and selects the best-matching candidate. This minimizes misassignment
		when multiple windows share identical titles (for example, two browser windows).
		This catches windows that were never found during the first pass (e.g. WhatsApp
		not yet started), windows whose handles became invalid after positioning, and
		windows that ended up in the wrong position.

		Title-drift fallback: when strict ProcessName∩WindowTitle matching finds nothing
		for a non-browser app, the verifier accepts a single unambiguous process window
		instead of false-failing. This mirrors the same fallback in Set-WindowLayouts and
		exists because some apps rewrite their caption at runtime - for example, new
		Outlook (`Olk`) titles its window after the selected folder ("Inbox - ..." rather
		than the configured "Mail - ..."), so a window that was found and positioned
		correctly would otherwise be reported as missing and trigger a needless retry.
		The fallback only applies to non-browser processes (browser entries legitimately
		have many windows) and only when exactly one unclaimed process window remains, so
		duplicate-keyed entries are never misassigned. Configuring WindowTitle as a
		folder-agnostic pattern (e.g. ".*user@example\.com - Outlook") is the primary
		fix for caption drift; this fallback is the defensive backstop.

	.PARAMETER LayoutConfig
		The same layout array passed to Set-WindowLayouts - each entry has ProcessName,
		WindowTitle, DesktopNumber, Zone, Monitor, Layout, etc.

	.PARAMETER MonitorInfo
		Pre-fetched monitor information from Get-MonitorInfo.

	.PARAMETER MonitorConfig
		The Monitors hashtable from the workspace .psd1 config file, used to resolve
		layout names per virtual desktop per monitor.

	.PARAMETER DesktopOffset
		Desktop offset applied to all desktop numbers (for alongside mode).

	.PARAMETER Tolerance
		Maximum pixel deviation allowed per dimension before a window is considered
		mispositioned.  Default is 20 (matches Snap-AllWindows snap verification).

	.OUTPUTS
		[hashtable] with keys:
			Success  [bool]   - $true if all windows passed
			Total    [int]    - Total number of layout entries checked
			Passed   [int]    - Number of entries that passed
			Failures [array]  - List of PSCustomObjects describing each failure

	.EXAMPLE
		$result = Confirm-WorkspaceWindowPositions -LayoutConfig $config.Layout `
			-MonitorInfo $monitorInfo -MonitorConfig $config.Monitors
		if (-not $result.Success) { Write-Host "Verification failed!" }
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[array]$LayoutConfig,

		[Parameter()]
		[array]$MonitorInfo,

		[Parameter()]
		[hashtable]$MonitorConfig,

		[Parameter()]
		[int]$DesktopOffset = 0,

		[Parameter()]
		[int]$Tolerance = 50
	)

	$result = @{
		Success  = $true
		Total    = $LayoutConfig.Count
		Passed   = 0
		Failures = [System.Collections.Generic.List[PSObject]]::new()
	}

	# Expand layout-file tokens (e.g. "Browser") to regex patterns before any matching
	# or cache-key construction runs, so this function and Set-WindowLayouts agree on
	# the expanded values. Returns clones - original LayoutConfig entries are never mutated.
	$LayoutConfig = @($LayoutConfig | ForEach-Object {
			if ($_ -is [hashtable]) { Resolve-LayoutTokens -LayoutEntry $_ } else { $_ }
		})
	$result.Total = $LayoutConfig.Count

	Write-LogDebug "[Final Layout Verification - $($result.Total) window(s)]"

	# Fresh window cache for the verification pass
	Clear-WindowCache

	# Pre-fetch monitor specs once
	$monitorSpecs = $null
	if ($MonitorInfo) {
		$monitorSpecs = Get-MonitorSpecs -MonitorInfo $MonitorInfo
	}

	# Track handles already matched for duplicate layout keys (same logic as Set-WindowLayouts)
	$layoutKeyCount = @{}
	foreach ($cfg in $LayoutConfig) {
		$key = "$($cfg.ProcessName)|$($cfg.WindowTitle)"
		if ($layoutKeyCount.ContainsKey($key)) { $layoutKeyCount[$key]++ }
		else { $layoutKeyCount[$key] = 1 }
	}
	$claimedHandles = New-Object 'System.Collections.Generic.HashSet[IntPtr]'
	$hasVirtualDesktopModule = Import-VirtualDesktopModule -Silent
	$processMatchCache = @{}
	$titleMatchCache = @{}
	$intersectionCache = @{}
	$desktopIndexCache = @{}
	$desktopFilteredCache = @{}

	foreach ($cfg in $LayoutConfig) {
		$processName = $cfg.ProcessName
		$windowTitle = $cfg.WindowTitle
		$label = if ($windowTitle) { "$processName - $windowTitle" } else { $processName }
		$layoutKey = "$processName|$windowTitle"

		# ------------------------------------------------------------------
		# 1. Resolve expected zone coordinates (mirrors Set-WindowLayouts)
		# ------------------------------------------------------------------
		$expectedX = $null; $expectedY = $null; $expectedW = $null; $expectedH = $null

		if ($cfg.Zone) {
			# Resolve layout name
			$layoutName = $cfg.Layout
			if (-not $layoutName -and $cfg.Monitor -and $null -ne $cfg.DesktopNumber -and $MonitorConfig) {
				if ($MonitorConfig.ContainsKey($cfg.Monitor) -and
					$MonitorConfig[$cfg.Monitor].VirtualDesktopLayouts -and
					$MonitorConfig[$cfg.Monitor].VirtualDesktopLayouts.ContainsKey($cfg.DesktopNumber)) {
					$layoutName = $MonitorConfig[$cfg.Monitor].VirtualDesktopLayouts[$cfg.DesktopNumber]
				}
			}
			if (-not $layoutName) {
				# Cannot resolve layout - skip entry rather than false-fail
				Write-LogDebug "  ? [$label] - could not resolve layout, skipping" -Style Warning
				$result.Total--
				continue
			}

			# Resolve monitor coordinates. Zone geometry uses the WORK AREA (Work* spec
			# fields) to match FancyZones - must stay in lockstep with Set-WindowLayouts.
			$monX = 0; $monY = 0; $monW = 3440; $monH = 1440
			if ($cfg.Monitor) {
				if ($cfg.Monitor -is [string]) {
					if (-not $monitorSpecs) { $monitorSpecs = Get-MonitorSpecs -MonitorInfo $MonitorInfo }
					$spec = $monitorSpecs.($cfg.Monitor)
					if (-not $spec -and $monitorSpecs) { $spec = $monitorSpecs.Primary }
					if ($spec) {
						$monX = if ($null -ne $spec.WorkX) { $spec.WorkX } else { $spec.X }
						$monY = if ($null -ne $spec.WorkY) { $spec.WorkY } else { $spec.Y }
						$monW = if ($spec.WorkWidth) { $spec.WorkWidth } else { $spec.Width }
						$monH = if ($spec.WorkHeight) { $spec.WorkHeight } else { $spec.Height }
					}
				}
				else {
					$monX = if ($null -ne $cfg.Monitor.X) { $cfg.Monitor.X } else { 0 }
					$monY = if ($null -ne $cfg.Monitor.Y) { $cfg.Monitor.Y } else { 0 }
					$monW = if ($cfg.Monitor.Width) { $cfg.Monitor.Width } else { 3440 }
					$monH = if ($cfg.Monitor.Height) { $cfg.Monitor.Height } else { 1440 }
				}
			}

			$zone = Get-FancyZone -LayoutName $layoutName -ZoneName $cfg.Zone `
				-MonitorX $monX -MonitorY $monY -MonitorWidth $monW -MonitorHeight $monH

			if ($zone) {
				$expectedX = $zone.X; $expectedY = $zone.Y
				$expectedW = $zone.Width; $expectedH = $zone.Height
			}
		}
		elseif ($null -ne $cfg.X -and $null -ne $cfg.Y -and $cfg.Width -and $cfg.Height) {
			$expectedX = $cfg.X; $expectedY = $cfg.Y
			$expectedW = $cfg.Width; $expectedH = $cfg.Height
		}

		if ($null -eq $expectedX) {
			# No positioning info - nothing to verify
			Write-LogDebug "  ? [$label] - no positioning info, skipping" -Style Warning
			$result.Total--
			continue
		}

		# ------------------------------------------------------------------
		# 2. Find a live window matching this layout entry
		# ------------------------------------------------------------------
		$windows = $null
		if ($processName -and $windowTitle) {
			# Enforce AND matching: process and title must both match.
			if ($intersectionCache.ContainsKey($layoutKey)) {
				$windows = $intersectionCache[$layoutKey]
			}
			else {
				if ($titleMatchCache.ContainsKey($windowTitle)) {
					$titleMatched = $titleMatchCache[$windowTitle]
				}
				else {
					$titleMatched = @(Get-WindowHandle -WindowTitle $windowTitle)
					$titleMatchCache[$windowTitle] = $titleMatched
				}

				if ($processMatchCache.ContainsKey($processName)) {
					$processMatched = $processMatchCache[$processName]
				}
				else {
					$processMatched = @(Get-WindowHandle -ProcessName $processName)
					$processMatchCache[$processName] = $processMatched
				}

				$processHandles = New-Object 'System.Collections.Generic.HashSet[IntPtr]'
				foreach ($pw in $processMatched) {
					[void]$processHandles.Add($pw.Handle)
				}

				$windows = @($titleMatched | Where-Object { $processHandles.Contains($_.Handle) })
				$intersectionCache[$layoutKey] = $windows
			}
		}
		elseif ($windowTitle) {
			if ($titleMatchCache.ContainsKey($windowTitle)) {
				$windows = $titleMatchCache[$windowTitle]
			}
			else {
				$windows = @(Get-WindowHandle -WindowTitle $windowTitle)
				$titleMatchCache[$windowTitle] = $windows
			}
		}
		else {
			if ($processMatchCache.ContainsKey($processName)) {
				$windows = $processMatchCache[$processName]
			}
			else {
				$windows = @(Get-WindowHandle -ProcessName $processName)
				$processMatchCache[$processName] = $windows
			}
		}

		# Resilient fallback (mirrors Set-WindowLayouts): when strict title∩process
		# matching finds nothing for a non-browser app, the window's caption has likely
		# drifted from the configured pattern (e.g. Outlook showing "Inbox - ..." instead
		# of "Mail - ..."). Recover by accepting a single unambiguous process window so the
		# verifier does not false-fail a window that was found and positioned correctly.
		if ((-not $windows -or $windows.Count -eq 0) -and $processName) {
			$isBrowserLikeProcess = $processName -match '(?i)(browser|firefox|chrome|msedge|brave|chromium)'
			if (-not $isBrowserLikeProcess) {
				if ($processMatchCache.ContainsKey($processName)) {
					$processCandidates = @($processMatchCache[$processName])
				}
				else {
					$processCandidates = @(Get-WindowHandle -ProcessName $processName)
					$processMatchCache[$processName] = $processCandidates
				}
				$unclaimed = @($processCandidates | Where-Object { -not $claimedHandles.Contains($_.Handle) })
				if ($unclaimed.Count -eq 1) {
					$windows = $unclaimed
					Write-LogDebug "[$label] title pattern did not match caption - recovered via sole process window $($unclaimed[0].Title)" -Style Warning
				}
			}
		}

		# Prefer candidates on the expected virtual desktop. If none exist there,
		# keep cross-desktop candidates as a fallback.
		if ($windows -and $windows.Count -gt 1 -and $hasVirtualDesktopModule -and $null -ne $cfg.DesktopNumber) {
			$originalCandidateCount = $windows.Count
			$expectedDesktopIndex = ConvertTo-InternalDesktopIndex -DesktopNumber $cfg.DesktopNumber -DesktopOffset $DesktopOffset
			$desktopCacheKey = "$layoutKey|$expectedDesktopIndex"

			if ($desktopFilteredCache.ContainsKey($desktopCacheKey)) {
				$expectedDesktopCandidates = $desktopFilteredCache[$desktopCacheKey]
			}
			else {
				$expectedDesktopCandidates = @()

				foreach ($candidate in $windows) {
					$handleKey = $candidate.Handle.ToInt64().ToString()

					if (-not $desktopIndexCache.ContainsKey($handleKey)) {
						$windowDesktopIndex = $null
						try {
							$windowDesktop = Get-DesktopFromWindow -Hwnd $candidate.Handle.ToInt64()
							$windowDesktopIndex = Get-DesktopIndex $windowDesktop
						}
						catch {
							$windowDesktopIndex = $null
						}
						$desktopIndexCache[$handleKey] = $windowDesktopIndex
					}

					$cachedDesktopIndex = $desktopIndexCache[$handleKey]
					if ($null -ne $cachedDesktopIndex -and $cachedDesktopIndex -eq $expectedDesktopIndex) {
						$expectedDesktopCandidates += $candidate
					}
				}

				$desktopFilteredCache[$desktopCacheKey] = $expectedDesktopCandidates
			}

			if ($expectedDesktopCandidates.Count -gt 0) {
				$windows = $expectedDesktopCandidates
				Write-LogDebug "[$label] Prefer expected desktop $($cfg.DesktopNumber + $DesktopOffset) ($($expectedDesktopCandidates.Count)/$originalCandidateCount candidate(s))"
			}
			else {
				Write-LogDebug "[$label] No candidates found on expected desktop $($cfg.DesktopNumber + $DesktopOffset) - falling back to cross-desktop candidates" -Style Warning
			}
		}

		# Handle duplicate layout keys - claim one unclaimed window per entry
		$isDuplicate = $layoutKeyCount[$layoutKey] -gt 1

		if ($isDuplicate -and $windows) {
			# Filter out already-claimed handles first
			$candidates = @($windows | Where-Object { -not $claimedHandles.Contains($_.Handle) })

			# If multiple candidate windows share the same title, pick the one whose
			# actual bounds are closest to the expected bounds (minimizes misassignment).
			if ($candidates.Count -gt 1) {
				$scored = @()
				foreach ($w in $candidates) {
					$rectTmp = New-Object WindowModule.RECT
					if ([WindowModule.Native]::GetWindowRect($w.Handle, [ref]$rectTmp)) {
						$ax = $rectTmp.Left; $ay = $rectTmp.Top
						$aw = $rectTmp.Right - $rectTmp.Left; $ah = $rectTmp.Bottom - $rectTmp.Top
						# score = sum of absolute deltas (lower is better)
						$score = [Math]::Abs($ax - $expectedX) + [Math]::Abs($ay - $expectedY) + [Math]::Abs($aw - $expectedW) + [Math]::Abs($ah - $expectedH)
					}
					else {
						$score = [double]::PositiveInfinity
					}
					$scored += [PSCustomObject]@{ Window = $w; Score = $score }
				}

				# choose best-matching candidate
				$best = $scored | Sort-Object Score | Select-Object -First 1
				if ($best) { $windows = @($best.Window) }
				else { $windows = @() }
			}
			else {
				# single candidate - use it
				$windows = $candidates
			}
		}

		# Browser title drift: a tab's title can change between positioning and verification
		# (page finished loading), and the sole-process-window fallback above is deliberately
		# disabled for browsers (several windows share one process). Before declaring the
		# entry missing, accept the window the positioning pass ACTUALLY placed for these
		# expected bounds (and desktop) - it was matched and title-verified seconds earlier -
		# provided its handle is still alive and unclaimed. Without this, a mid-flow title
		# change escalated to reruns that can never fix a title mismatch.
		if ((-not $windows -or $windows.Count -eq 0) -and $script:PositionedWindowHandles) {
			$expectedDisplayDesktop = if ($null -ne $cfg.DesktopNumber) { [int]$cfg.DesktopNumber + $DesktopOffset } else { $null }

			foreach ($trackedState in $script:PositionedWindowHandles) {
				if ($null -eq $trackedState) { continue }
				if ([int]$trackedState.ExpectedX -ne [int]$expectedX -or
					[int]$trackedState.ExpectedY -ne [int]$expectedY -or
					[int]$trackedState.ExpectedWidth -ne [int]$expectedW -or
					[int]$trackedState.ExpectedHeight -ne [int]$expectedH) { continue }
				# Same zone coordinates can repeat across desktops - require the desktop too.
				if ($null -ne $expectedDisplayDesktop -and $null -ne $trackedState.DesktopNumber -and
					[int]$trackedState.DesktopNumber -ne $expectedDisplayDesktop) { continue }
				if ($claimedHandles.Contains($trackedState.Handle)) { continue }

				$trackedRect = New-Object WindowModule.RECT
				if ([WindowModule.Native]::GetWindowRect($trackedState.Handle, [ref]$trackedRect)) {
					$windows = @([PSCustomObject]@{
							Handle = $trackedState.Handle
							Title  = $trackedState.WindowTitle
						})
					Write-LogDebug "[$label] title pattern did not match current caption - recovered via tracked positioned window [$($trackedState.WindowTitle)]" -Style Warning
					break
				}
			}
		}

		if (-not $windows -or $windows.Count -eq 0) {
			$result.Success = $false
			$result.Failures.Add([PSCustomObject]@{
					WindowTitle = $label
					Handle      = $null
					Expected    = "($expectedX, $expectedY) ${expectedW}x${expectedH}"
					Actual      = "Window not found"
					DeltaX = $null; DeltaY = $null; DeltaW = $null; DeltaH = $null
				})

			Write-LogDebug "  ✗ [$label] - window not found" -Style Error
			continue
		}

		$window = $windows[0]
		if ($isDuplicate) { [void]$claimedHandles.Add($window.Handle) }

		# ------------------------------------------------------------------
		# 3. Read actual position via native API
		# ------------------------------------------------------------------
		$rect = New-Object WindowModule.RECT
		if (-not [WindowModule.Native]::GetWindowRect($window.Handle, [ref]$rect)) {
			$result.Success = $false
			$result.Failures.Add([PSCustomObject]@{
					WindowTitle = $label
					Handle      = $window.Handle
					Expected    = "($expectedX, $expectedY) ${expectedW}x${expectedH}"
					Actual      = "Handle invalid"
					DeltaX = $null; DeltaY = $null; DeltaW = $null; DeltaH = $null
				})
			Write-LogDebug "  ✗ [$label] - window handle no longer valid" -Style Error
			continue
		}

		$actualX = $rect.Left
		$actualY = $rect.Top
		$actualW = $rect.Right - $rect.Left
		$actualH = $rect.Bottom - $rect.Top

		# ------------------------------------------------------------------
		# 4. Compare against expected zone position
		# ------------------------------------------------------------------
		$deltaX = [Math]::Abs($actualX - $expectedX)
		$deltaY = [Math]::Abs($actualY - $expectedY)
		$deltaW = [Math]::Abs($actualW - $expectedW)
		$deltaH = [Math]::Abs($actualH - $expectedH)

		$xOk = $deltaX -le $Tolerance
		$yOk = $deltaY -le $Tolerance
		$wOk = $deltaW -le $Tolerance
		$hOk = $deltaH -le $Tolerance

		if ($xOk -and $yOk -and $wOk -and $hOk) {
			$result.Passed++
			Write-LogDebug "[$label] - at ($actualX, $actualY) ${actualW}x${actualH}" -Style Success
		}
		else {
			$result.Success = $false
			$result.Failures.Add([PSCustomObject]@{
					WindowTitle = $label
					Handle      = $window.Handle
					Expected    = "($expectedX, $expectedY) ${expectedW}x${expectedH}"
					Actual      = "($actualX, $actualY) ${actualW}x${actualH}"
					DeltaX = $deltaX; DeltaY = $deltaY; DeltaW = $deltaW; DeltaH = $deltaH
				})

			if (Test-LogVerbose) {
				Write-LogDebug "[$label]" -Style Error
				Write-LogDebug "Expected => ($expectedX, $expectedY) ${expectedW}x${expectedH}" -Style Success
				Write-LogDebug "Actual   => ($actualX, $actualY) ${actualW}x${actualH}" -Style Error
				$dims = @()
				if (-not $xOk) { $dims += "X +${deltaX}px" }
				if (-not $yOk) { $dims += "Y +${deltaY}px" }
				if (-not $wOk) { $dims += "W +${deltaW}px" }
				if (-not $hOk) { $dims += "H +${deltaH}px" }
				Write-LogDebug "Deltas   => $($dims -join ', ')" -Style Error
			}
		}
	}

	if ($result.Success) {
		Write-LogDebug "All $($result.Total) window(s) verified at expected positions!" -Style Success
	}
	else {
		Write-LogDebug "Verification failed => $($result.Failures.Count)/$($result.Total) window(s) mispositioned or missing" -Style Error
	}

	return $result
}
