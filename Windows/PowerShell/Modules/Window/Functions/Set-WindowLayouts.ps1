function Set-WindowLayouts {
	<#
	.SYNOPSIS
		Applies a predefined window layout configuration.

	.DESCRIPTION
		Moves windows to specific virtual desktops and positions them according to a layout configuration.
		The layout configuration specifies which windows should be on which desktops and their positions/sizes.

		Supports two positioning modes:
		1. Direct coordinates: X, Y, Width, Height (pixel values)
		2. Zone-based: Layout, Zone, Monitor (uses FancyZones layouts with human-readable names)

		Supports duplicate layout entries where the same (ProcessName, WindowTitle) pair
		appears multiple times to place identical windows in different zones. When duplicates
		are detected, each layout entry claims exactly one distinct window handle, ensuring
		each window is positioned in its own zone. For unique entries, all matching windows
		are processed together (original behaviour preserved).

	.PARAMETER LayoutConfig
		A hashtable or array of window configurations. Each configuration should include:
		- ProcessName: The process name to target
		- WindowTitle: (Optional) Specific window title to target
		- DesktopNumber: The virtual desktop number (1-based, e.g., 1 for first desktop)

		For direct positioning:
		- X, Y, Width, Height: Window position and size in pixels

		For zone-based positioning:
		- Layout: FancyZones layout name (e.g., "One", "Seven")
		- Zone: Human-readable zone name (e.g., "Left", "Top-Right")
		- Monitor: (Optional) Monitor spec with X, Y, Width, Height properties

		- ZoneName: (Optional) A descriptive name for the zone

	.PARAMETER ConfigPath
		Path to a JSON or PSD1 file containing the layout configuration.

	.PARAMETER MonitorInfo
		Array of monitor specs used to resolve string monitor labels (e.g. "Primary",
		"Secondary") to coordinates.

	.PARAMETER MonitorConfig
		Hashtable of the Monitors configuration section; used to auto-resolve layout names
		per monitor and desktop.

	.PARAMETER ExistingWindowHandles
		HashSet of handles open before the layout run; used to detect pre-existing windows
		and skip already-correct positioning.

	.PARAMETER ExpectedWindowState
		Hashtable of stable window state captured during the wait phase; enables handle-based
		recovery when titles change transiently.

	.PARAMETER DesktopOffset
		Integer shift applied to all 1-based desktop numbers. Default is 0.

	.PARAMETER SkipExistingWindows
		Switch (alongside mode) that skips windows existing before this workspace opened,
		since they belong to a previous workspace. Ineligible windows are removed from an
		entry's candidate list before any claiming happens, so an entry left with none reports
		"Not Found" (a visible, countable shortfall) instead of silently placing nothing.

	.PARAMETER CandidateWindowHandles
		Whitelist of window handles this pass may claim. Every other window is dropped from an
		entry's candidate list before claiming, exactly like -SkipExistingWindows and
		-ProtectedWindowHandles drop theirs. Set-WorkspaceWindowLayout passes the windows the
		wait phase confirmed stable for ONE desktop when it positions that desktop while the
		rest of the workspace is still loading, so a window still loading elsewhere - or one
		another desktop's entry already owns - is never claimed here, whatever the title regex
		says. Such a pass searches each entry once: a miss means the window is not stable yet
		and the pass after the wait places it, so the not-found retry ladder is skipped.

	.PARAMETER ExcludeWindowHandles
		Blacklist of window handles this pass may not claim, dropped at the same point as the
		other candidate filters. Set-WorkspaceWindowLayout passes the windows its per-desktop
		passes already placed when it finishes the remaining desktops.

	.PARAMETER DesktopNumbers
		Processes only the entries on these desktops (the layout's own 1-based DesktopNumber,
		default 1) while the WHOLE layout still drives duplicate-key detection and sort order.
		This is how Set-WorkspaceWindowLayout positions one desktop while the rest of the
		workspace is still loading: a key that appears once on that desktop but again on
		another must still claim exactly one window, which a layout subset could not know.

	.PARAMETER SkipEntryKeys
		Entry keys (the EntryKey field of an earlier result row) to leave alone, after
		duplicate-key detection over the whole layout. Set-WorkspaceWindowLayout passes the
		entries its per-desktop passes already placed when it finishes the rest of the layout.

	.PARAMETER KeepPositionedWindows
		Appends to the positioned-window tracking instead of resetting it first. Every call
		resets the tracking by default so Snap-AllWindows sees exactly the windows of that
		call; the per-desktop passes of one workspace open share a single tracking set and
		therefore pass this on every call but the first.

	.PARAMETER AbandonedEntries
		Layout entries the wait phase abandoned (Wait-ForWorkspaceWindows' AbandonedEntries: no
		window ever matched and no live process). They still produce their Not Found row, but
		get ONE search instead of the three-attempt retry ladder with its 0.5 s and 1 s waits -
		that ladder rides out transient title drift on a window that exists, and these have
		none.

	.PARAMETER ProtectedWindowHandles
		Live window handles a plain open must preserve (they belong to a live alongside
		workspace - see Get-WorkspaceOpenProtection). Protected windows are removed from every
		entry's candidate list before claiming, from the per-window backstop, and from every
		recreated-window recovery lookup, so no layout entry can ever move or reposition one.
		An entry whose only matches are protected reports "Not Found".

	.PARAMETER PinnedHandleMap
		Optional hashtable from a previous successful run (built by Set-WorkspaceWindowLayout
		from CurrentLayout.txt), keyed by "<DesktopNumber>|<Monitor>|<Zone>" mapping to the
		window that occupied that slot last time (@{ Handle; ProcessId; ProcessName }). For a
		duplicate (ProcessName, WindowTitle) entry it is the AUTHORITATIVE source of which
		window claims the zone: when the recorded window is still live and owned by the same
		process it is reclaimed exactly, so re-runs return every identical window to its own
		zone with no reshuffle. When no valid recorded window exists (first run, reboot, or a
		new window) the claim falls back to closest-bounds geometry. Unique entries and first
		runs are unaffected (the map is empty or unused).

	.EXAMPLE
		# Direct coordinates
		$layout = @(
			@{
				ProcessName = "chrome"
				DesktopNumber = 1
				X = 0; Y = 0; Width = 1920; Height = 1080
				ZoneName = "Browser-Main"
			}
		)
		Set-WindowLayouts -LayoutConfig $layout

	.EXAMPLE
		# Duplicate entries: two identical browser windows in different zones
		# Each entry claims one distinct window, opened via Open-Browser with Override
		$layout = @(
			@{
				ProcessName = "firefox"
				WindowTitle = "Google -"
				DesktopNumber = 1
				Zone = "Left"
				Monitor = "Secondary"
			}
			@{
				ProcessName = "firefox"
				WindowTitle = "Google -"
				DesktopNumber = 1
				Zone = "Right"
				Monitor = "Secondary"
			}
		)
		Set-WindowLayouts -LayoutConfig $layout

	.EXAMPLE
		# Zone-based positioning
		$layout = @(
			@{
				ProcessName = "Code"
				DesktopNumber = 1
				Layout = "One"
				Zone = "Left"
				Monitor = @{ X = 0; Y = 0; Width = 3440; Height = 1440 }
				ZoneName = "Editor-Left"
			},
			@{
				ProcessName = "firefox"
				DesktopNumber = 1
				Layout = "Seven"
				Zone = "Top-Right"
				Monitor = @{ X = 0; Y = -1440; Width = 3440; Height = 1440 }
				ZoneName = "Browser-TopMonitor-TopRight"
			}
		)
		Set-WindowLayouts -LayoutConfig $layout

	.EXAMPLE
		Set-WindowLayouts -ConfigPath "C:\MyLayouts\development.json"
	#>
	[CmdletBinding(DefaultParameterSetName = 'ByConfig')]
	param (
		[Parameter(ParameterSetName = 'ByConfig', Mandatory = $true)]
		[array]$LayoutConfig,

		[Parameter(ParameterSetName = 'ByPath', Mandatory = $true)]
		[string]$ConfigPath,

		[Parameter()]
		[array]$MonitorInfo,

		[Parameter()]
		[hashtable]$MonitorConfig,

		[Parameter()]
		[System.Collections.Generic.HashSet[IntPtr]]$ExistingWindowHandles,

		[Parameter()]
		[hashtable]$ExpectedWindowState,

		[Parameter()]
		[int]$DesktopOffset = 0,

		[Parameter()]
		[switch]$SkipExistingWindows,

		[Parameter()]
		[hashtable]$PinnedHandleMap,

		[Parameter()]
		[System.Collections.Generic.HashSet[IntPtr]]$ProtectedWindowHandles,

		[Parameter()]
		[System.Collections.Generic.HashSet[IntPtr]]$CandidateWindowHandles,

		[Parameter()]
		[System.Collections.Generic.HashSet[IntPtr]]$ExcludeWindowHandles,

		[Parameter()]
		[int[]]$DesktopNumbers,

		[Parameter()]
		[string[]]$SkipEntryKeys,

		[Parameter()]
		[switch]$KeepPositionedWindows,

		[Parameter()]
		[array]$AbandonedEntries
	)

	# The per-desktop passes of one workspace open append to one tracking set; every other
	# caller starts from a clean one so Snap-AllWindows sees exactly this call's windows.
	if (-not $KeepPositionedWindows) {
		Initialize-PositionedWindowTracking
	}

	if (Test-LogVerbose) {
		Write-LogDebug "[Setting Custom Window Layouts]"
		if ($DesktopOffset -gt 0) {
			Write-LogDebug "Desktop offset => +$DesktopOffset (all desktop numbers will be shifted)" -Style Step
		}
	}

	if ($PSCmdlet.ParameterSetName -eq 'ByPath') {
		if (-not (Test-Path $ConfigPath)) {
			Write-Error "Configuration file not found: $ConfigPath"
			return
		}

		$extension = [System.IO.Path]::GetExtension($ConfigPath)
		if ($extension -eq '.json') {
			$LayoutConfig = Get-Content $ConfigPath | ConvertFrom-Json
		}
		elseif ($extension -eq '.psd1') {
			$LayoutConfig = Import-PowerShellDataFile -Path $ConfigPath
		}
		else {
			Write-Error "Unsupported configuration file format. Use .json or .psd1"
			return
		}
	}

	# Expand layout-file tokens (e.g. "Browser") to regex patterns before any matching,
	# caching, or duplicate-detection runs. Returns clones - the original LayoutConfig
	# entries (read from .psd1) are never mutated, so visualizations still show the token.
	$LayoutConfig = @($LayoutConfig | ForEach-Object {
			if ($_ -is [hashtable]) { Resolve-LayoutTokens -LayoutEntry $_ } else { $_ }
		})

	$results = [System.Collections.Generic.List[PSObject]]::new()
	$movedWindows = @{} # Track windows by handle to prevent duplicate moves
	# Single source of truth for the pre-snap inset (SnapInsetPercent in configuration)
	$insetPercent = Get-WindowInsetPercent
	$positioningHeaderShown = $false

	# Pre-fetch monitor specs once (if needed) to avoid repeated calls
	$monitorSpecs = $null
	if ($MonitorInfo) {
		$monitorSpecs = Get-MonitorSpecs -MonitorInfo $MonitorInfo
	}

	# Sort configurations by Desktop, then Monitor Y, then Monitor X
	# This ensures processing order: Desktop 1 Monitor 1, Desktop 1 Monitor 2, Desktop 2 Monitor 1, etc.
	$sortedLayoutConfig = $LayoutConfig | ForEach-Object {
		$config = $_
		$monitorX = 0
		$monitorY = 0

		if ($config.Monitor) {
			if ($config.Monitor -is [string]) {
				# Resolve string label to coordinates using cached specs
				if (-not $monitorSpecs) {
					$monitorSpecs = Get-MonitorSpecs -MonitorInfo $MonitorInfo
				}
				$monitorSpec = $monitorSpecs.($config.Monitor)
				if ($monitorSpec) {
					$monitorX = $monitorSpec.X
					$monitorY = $monitorSpec.Y
				}
			}
			else {
				# Use hashtable coordinates directly
				$monitorX = if ($null -ne $config.Monitor.X) { $config.Monitor.X } else { 0 }
				$monitorY = if ($null -ne $config.Monitor.Y) { $config.Monitor.Y } else { 0 }
			}
		}

		# Add sort keys to config object
		[PSCustomObject]@{
			Config        = $config
			DesktopNumber = if ($config.DesktopNumber) { $config.DesktopNumber } else { 1 }
			MonitorY      = $monitorY
			MonitorX      = $monitorX
		}
	} | Sort-Object DesktopNumber, MonitorY, MonitorX

	# Pre-scan layout for duplicate (ProcessName, WindowTitle) keys.
	# When the same key appears multiple times (e.g., two "firefox / Google" entries in different zones),
	# each layout entry should consume exactly ONE distinct window instead of all matches.
	# For unique keys the behaviour is unchanged: all matching windows are processed together.
	$layoutKeyCount = @{}
	foreach ($item in $sortedLayoutConfig) {
		$cfg = $item.Config
		$key = "$($cfg.ProcessName)|$($cfg.WindowTitle)"
		if ($layoutKeyCount.ContainsKey($key)) {
			$layoutKeyCount[$key]++
		}
		else {
			$layoutKeyCount[$key] = 1
		}
	}

	# Handles already claimed by an earlier duplicate entry (only used when duplicates exist)
	$claimedHandles = New-Object 'System.Collections.Generic.HashSet[IntPtr]'

	if (Test-LogVerbose) {
		$dupKeys = $layoutKeyCount.GetEnumerator() | Where-Object { $_.Value -gt 1 }
		if ($dupKeys) {
			Write-LogDebug "[Duplicate layout entries detected]"
			foreach ($dk in $dupKeys) {
				Write-LogDebug "$($dk.Key) => $($dk.Value) entries (each will claim one distinct window)" -Style Step
			}
		}
		Write-LogDebug "[Moving Windows to Virtual Desktops]"
	}

	# Clear window cache before processing to ensure fresh data
	Clear-WindowCache

	# One key per layout entry - desktop, monitor and zone (or the direct coordinates) - so a
	# caller can tell which entries an earlier pass placed (every result row carries it as
	# EntryKey) and hand them back through -SkipEntryKeys.
	$entryKeyOf = {
		param($entry)
		$entryDesktop = if ($entry.DesktopNumber) { [int]$entry.DesktopNumber } else { 1 }
		$monitorPart = if ($entry.Monitor -is [string]) { $entry.Monitor } elseif ($entry.Monitor) { "$($entry.Monitor.X),$($entry.Monitor.Y)" } else { '' }
		$placePart = if ($entry.Zone) { [string]$entry.Zone } elseif ($null -ne $entry.X) { "$($entry.X),$($entry.Y),$($entry.Width),$($entry.Height)" } else { '' }
		"$entryDesktop|$monitorPart|$placePart|$($entry.ProcessName)|$($entry.WindowTitle)"
	}
	$skipEntryKeySet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
	foreach ($skipKey in @($SkipEntryKeys)) {
		if (-not [string]::IsNullOrEmpty($skipKey)) { [void]$skipEntryKeySet.Add($skipKey) }
	}
	# Entries the wait abandoned, keyed the same way (tokens resolved as the layout above was),
	# so the search below can tell them apart from an entry whose window merely lost its title.
	$abandonedEntryKeySet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
	foreach ($abandonedEntry in @($AbandonedEntries)) {
		if ($null -eq $abandonedEntry) { continue }
		$resolvedAbandoned = if ($abandonedEntry -is [hashtable]) { Resolve-LayoutTokens -LayoutEntry $abandonedEntry } else { $abandonedEntry }
		[void]$abandonedEntryKeySet.Add((& $entryKeyOf $resolvedAbandoned))
	}

	$applyPositionWorkItem = {
		param(
			[Parameter(Mandatory = $true)]
			[PSCustomObject]$Item
		)

		$window = $Item.Window
		$config = $Item.Config
		$posX = $Item.PosX
		$posY = $Item.PosY
		$posWidth = $Item.PosWidth
		$posHeight = $Item.PosHeight

		# The window object whose handle/process/title is recorded into the CurrentLayout.txt
		# snapshot for this entry. Defaults to the matched window and is upgraded to the
		# re-verified window when a reposition changes the handle (browsers recreate windows).
		$positionedWindowObj = $window

		if ((Test-LogVerbose) -and -not $positioningHeaderShown) {
			Write-LogDebug "[Applying Window Positions]"
			Write-LogDebug "Using $($insetPercent*100)% inset!"
			$positioningHeaderShown = $true
		}

		if (Test-LogVerbose) {
			Write-LogDebug "[$($config.ProcessName) -> $($window.Title)]"
		}

		# Apply position if we have coordinates
		if ($null -ne $posX -and $null -ne $posY -and $posWidth -and $posHeight) {
			# Check if this window existed before workspace layout started
			$isExistingWindow = $false
			if ($ExistingWindowHandles) {
				$isExistingWindow = $ExistingWindowHandles.Contains($window.Handle)
			}

			# Re-query window position to avoid stale data
			$currentWindowState = Get-WindowHandle -ProcessName $config.ProcessName -ErrorAction SilentlyContinue |
				Where-Object { $_.Handle -eq $window.Handle } |
				Select-Object -First 1

			if (-not $currentWindowState) {
				if ($config.WindowTitle) {
					if (Test-LogVerbose) {
						Write-LogDebug "Window handle not found by ProcessName, trying by WindowTitle..." -Style Warning
					}

					$currentWindowState = Get-WindowHandle -WindowTitle $config.WindowTitle -ErrorAction SilentlyContinue |
						Where-Object { $_.Handle -eq $window.Handle } |
						Select-Object -First 1
				}

				if (-not $currentWindowState -and $window.Title) {
					if (Test-LogVerbose) {
						Write-LogDebug "Original handle invalid, searching for window by title pattern..." -Style Warning
					}

					# Recreated-window recovery searches by title - exactly the signal a preserved
					# alongside workspace's identically titled window would answer to. Filter it
					# out so a mid-positioning recovery can never pick up a protected window.
					$possibleWindows = Get-WindowHandle -ProcessName $config.ProcessName -ErrorAction SilentlyContinue |
						Where-Object { $_.Title -eq $window.Title -and -not ($ProtectedWindowHandles -and $ProtectedWindowHandles.Contains($_.Handle)) }

					if (-not $possibleWindows -and $config.WindowTitle) {
						$possibleWindows = Get-WindowHandle -WindowTitle $config.WindowTitle -ErrorAction SilentlyContinue |
							Where-Object { -not ($ProtectedWindowHandles -and $ProtectedWindowHandles.Contains($_.Handle)) }
					}

					if ($possibleWindows -and $possibleWindows.Count -gt 0) {
						$currentWindowState = $possibleWindows[0]
						if (Test-LogVerbose) {
							Write-LogDebug "Found window with new handle: [$($currentWindowState.Handle)] - window was likely recreated" -Style Success
						}
						$window = $currentWindowState
						$positionedWindowObj = $currentWindowState
					}
				}

				if (-not $currentWindowState) {
					if (Test-LogVerbose) {
						Write-LogDebug "Window handle [$($window.Handle)] is no longer valid!" -Style Error
						Write-LogDebug "Original window title: [$($window.Title)]"

						$availableWindows = Get-WindowHandle -ProcessName $config.ProcessName -ErrorAction SilentlyContinue
						if ($availableWindows -and $availableWindows.Count -gt 0) {
							Write-LogDebug "Currently available windows for process [$($config.ProcessName)]:"
							foreach ($availWin in $availableWindows | Select-Object -First 5) {
								Write-LogDebug "• Handle: [$($availWin.Handle)] Title: [$($availWin.Title)]"
							}
						}
						else {
							Write-LogDebug "No windows found for process [$($config.ProcessName)]"
						}
					}
					return
				}
			}

			$tolerance = 20
			$currentLeft = $currentWindowState.Left
			$currentTop = $currentWindowState.Top
			$currentWidth = $currentWindowState.Width
			$currentHeight = $currentWindowState.Height
			$resizeBounds = Get-InsetWindowBounds -TargetX $posX -TargetY $posY -TargetWidth $posWidth -TargetHeight $posHeight -InsetPercent $insetPercent
			$adjustedX = $resizeBounds.AdjustedX
			$adjustedY = $resizeBounds.AdjustedY
			$adjustedWidth = $resizeBounds.AdjustedWidth
			$adjustedHeight = $resizeBounds.AdjustedHeight

			$xMatch = [Math]::Abs($currentLeft - $posX) -le $tolerance
			$yMatch = [Math]::Abs($currentTop - $posY) -le $tolerance
			$widthMatch = [Math]::Abs($currentWidth - $posWidth) -le $tolerance
			$heightMatch = [Math]::Abs($currentHeight - $posHeight) -le $tolerance

			$alwaysRepositionProcesses = @()
			$shouldAlwaysReposition = $alwaysRepositionProcesses -contains $config.ProcessName

			if ($isExistingWindow -and $xMatch -and $yMatch -and $widthMatch -and $heightMatch -and -not $shouldAlwaysReposition) {
				if (Test-LogVerbose) {
					Write-LogDebug "Window already in correct position, skipping..." -Style Warning
				}
			}
			else {
				if (Test-LogVerbose) {
					if (-not $isExistingWindow) {
						Write-LogDebug "Newly opened window - will position and snap!"
					}
					elseif ($shouldAlwaysReposition) {
						Write-LogDebug "Process [$($config.ProcessName)] in always-reposition list - will position and snap!" -Style Warning
					}
					elseif ($isExistingWindow) {
						Write-LogDebug "Window needs repositioning:" -Style Warning
						Write-LogDebug "Current position and size => ($currentLeft, $currentTop) ${currentWidth}x${currentHeight}" -Style Step
						Write-LogDebug "Expected position and size => ($posX, $posY) ${posWidth}x${posHeight}" -Style Step
						Write-LogDebug "Tolerance => [$tolerance px]" -Style Step
						if (-not $xMatch) {
							$xDiff = [Math]::Abs($currentLeft - $posX)
							Write-LogDebug "[✗] X mismatch => $xDiff px difference (current: $currentLeft, expected: $posX)" -Style Error
						}
						if (-not $yMatch) {
							$yDiff = [Math]::Abs($currentTop - $posY)
							Write-LogDebug "[✗] Y mismatch => $yDiff px difference (current: $currentTop, expected: $posY)" -Style Error
						}
						if (-not $widthMatch) {
							$wDiff = [Math]::Abs($currentWidth - $posWidth)
							Write-LogDebug "[✗] Width mismatch => $wDiff px difference (current: $currentWidth, expected: $posWidth)" -Style Error
						}
						if (-not $heightMatch) {
							$hDiff = [Math]::Abs($currentHeight - $posHeight)
							Write-LogDebug "[✗] Height mismatch => $hDiff px difference (current: $currentHeight, expected: $posHeight)" -Style Error
						}
					}
					Write-LogDebug "Zone bounds: ($posX, $posY) to ($($posX + $posWidth), $($posY + $posHeight))" -Style Step
					Write-LogDebug "Zone center: ($([int]$resizeBounds.ZoneCenterX), $([int]$resizeBounds.ZoneCenterY))" -Style Step
					Write-LogDebug "Setting position => $adjustedX, $adjustedY, ${adjustedWidth}x${adjustedHeight}" -Style Step
					$windowCenterX = $adjustedX + ($adjustedWidth / 2)
					$windowCenterY = $adjustedY + ($adjustedHeight / 2)
					$windowRight = $adjustedX + $adjustedWidth
					$windowBottom = $adjustedY + $adjustedHeight
					Write-LogDebug "Window bounds: ($adjustedX, $adjustedY) to ($windowRight, $windowBottom)" -Style Step
					Write-LogDebug "Window center will be at: ($([int]$windowCenterX), $([int]$windowCenterY))" -Style Step

					$leftInside = $adjustedX -ge $posX
					$rightInside = $windowRight -le ($posX + $posWidth)
					$topInside = $adjustedY -ge $posY
					$bottomInside = $windowBottom -le ($posY + $posHeight)

					if (-not ($leftInside -and $rightInside -and $topInside -and $bottomInside)) {
						Write-LogDebug "⚠ WARNING: Window positioned outside zone boundaries!" -Style Error
						if (-not $leftInside) { Write-LogDebug "Left edge $adjustedX < zone left $posX" -Style Error }
						if (-not $rightInside) { Write-LogDebug "Right edge $windowRight > zone right $($posX + $posWidth)" -Style Error }
						if (-not $topInside) { Write-LogDebug "Top edge $adjustedY < zone top $posY" -Style Error }
						if (-not $bottomInside) { Write-LogDebug "Bottom edge $windowBottom > zone bottom $($posY + $posHeight)" -Style Error }
					}
				}

				$null = Resize-Windows `
					-WindowHandle $window.Handle `
					-TargetX $posX `
					-TargetY $posY `
					-TargetWidth $posWidth `
					-TargetHeight $posHeight `
					-InsetPercent $insetPercent
				$positionResult = $script:LastResizeWindowsResult

				if ($positionResult -and $positionResult.ResizedCount -gt 0) {
					Start-Sleep -Milliseconds $script:WindowModuleDelays.WindowPositionMs

					$verifyWindow = Get-WindowHandle -ProcessName $config.ProcessName -ErrorAction SilentlyContinue |
						Where-Object { $_.Handle -eq $window.Handle } |
						Select-Object -First 1

					# Both verify-by-title fallbacks exclude protected windows for the same reason
					# as the recreated-window recovery above: a title match is exactly how a
					# preserved workspace's window would be mistaken for the one just positioned.
					if (-not $verifyWindow -and $window.Title) {
						$verifyWindow = Get-WindowHandle -ProcessName $config.ProcessName -ErrorAction SilentlyContinue |
							Where-Object { $_.Title -eq $window.Title -and -not ($ProtectedWindowHandles -and $ProtectedWindowHandles.Contains($_.Handle)) } |
							Select-Object -First 1

						if ($verifyWindow -and (Test-LogVerbose)) {
							Write-LogDebug "Window handle changed after positioning (was: $($window.Handle), now: $($verifyWindow.Handle))" -Style Warning
						}
					}

					if (-not $verifyWindow -and $config.WindowTitle) {
						$verifyWindow = Get-WindowHandle -WindowTitle $config.WindowTitle -ErrorAction SilentlyContinue |
							Where-Object { -not ($ProtectedWindowHandles -and $ProtectedWindowHandles.Contains($_.Handle)) } |
							Select-Object -First 1

						if ($verifyWindow -and (Test-LogVerbose)) {
							Write-LogDebug "Found window by WindowTitle pattern (new handle: $($verifyWindow.Handle))" -Style Warning
						}
					}

					if ($verifyWindow) {
						$verifyTolerance = 20
						$verifyXMatch = [Math]::Abs($verifyWindow.Left - $adjustedX) -le $verifyTolerance
						$verifyYMatch = [Math]::Abs($verifyWindow.Top - $adjustedY) -le $verifyTolerance
						$verifyWidthMatch = [Math]::Abs($verifyWindow.Width - $adjustedWidth) -le $verifyTolerance
						$verifyHeightMatch = [Math]::Abs($verifyWindow.Height - $adjustedHeight) -le $verifyTolerance

						if ($verifyXMatch -and $verifyYMatch) {
							if ($verifyWidthMatch -and $verifyHeightMatch) {
								if (Test-LogVerbose) {
									Write-LogDebug "✓ Position and dimensions verified!" -Style Success
								}
							}
							else {
								if (Test-LogVerbose) {
									Write-LogDebug "✓ Position verified, but dimensions differ (app may enforce size constraints)" -Style Warning
									Write-LogDebug "Expected: ${adjustedWidth}x${adjustedHeight}, Actual: $($verifyWindow.Width)x$($verifyWindow.Height)"
									Write-LogDebug "Proceeding with snap - FancyZones will use current window position"
								}
							}

							$positionedWindowObj = $verifyWindow
							$trackingDesktopNumber = $config.DesktopNumber + $DesktopOffset
							Add-PositionedWindow `
								-WindowHandle $verifyWindow.Handle `
								-ExpectedX $posX `
								-ExpectedY $posY `
								-ExpectedWidth $posWidth `
								-ExpectedHeight $posHeight `
								-WindowTitle $verifyWindow.Title `
								-DesktopNumber $trackingDesktopNumber `
								-ExpectedProcessName $verifyWindow.ProcessName `
								-ExpectedProcessId ([uint32]$verifyWindow.ProcessId) `
								-SingleZone:([bool]$Item.SingleZone)
						}
						else {
							if (Test-LogVerbose) {
								Write-LogDebug "Post-positioning verification failed, retrying once..." -Style Warning
								Write-LogDebug "Expected: ($adjustedX, $adjustedY) ${adjustedWidth}x${adjustedHeight}"
								Write-LogDebug "Actual: ($($verifyWindow.Left), $($verifyWindow.Top)) $($verifyWindow.Width)x$($verifyWindow.Height)"
							}

							$null = Resize-Windows `
								-WindowHandle $verifyWindow.Handle `
								-TargetX $posX `
								-TargetY $posY `
								-TargetWidth $posWidth `
								-TargetHeight $posHeight `
								-InsetPercent $insetPercent
							$retryResult = $script:LastResizeWindowsResult

							if ($retryResult -and $retryResult.ResizedCount -gt 0) {
								Start-Sleep -Milliseconds $script:WindowModuleDelays.WindowPositionMs

								$retryVerifyWindow = Get-WindowHandle -ProcessName $config.ProcessName -ErrorAction SilentlyContinue |
									Where-Object { $_.Handle -eq $verifyWindow.Handle } |
									Select-Object -First 1

								if (-not $retryVerifyWindow -and $verifyWindow.Title) {
									$retryVerifyWindow = Get-WindowHandle -ProcessName $config.ProcessName -ErrorAction SilentlyContinue |
										Where-Object { $_.Title -eq $verifyWindow.Title -and -not ($ProtectedWindowHandles -and $ProtectedWindowHandles.Contains($_.Handle)) } |
										Select-Object -First 1
								}

								if (-not $retryVerifyWindow -and $config.WindowTitle) {
									$retryVerifyWindow = Get-WindowHandle -WindowTitle $config.WindowTitle -ErrorAction SilentlyContinue |
										Where-Object { -not ($ProtectedWindowHandles -and $ProtectedWindowHandles.Contains($_.Handle)) } |
										Select-Object -First 1
								}

								if ($retryVerifyWindow) {
									$retryXMatch = [Math]::Abs($retryVerifyWindow.Left - $adjustedX) -le $verifyTolerance
									$retryYMatch = [Math]::Abs($retryVerifyWindow.Top - $adjustedY) -le $verifyTolerance
									$retryWidthMatch = [Math]::Abs($retryVerifyWindow.Width - $adjustedWidth) -le $verifyTolerance
									$retryHeightMatch = [Math]::Abs($retryVerifyWindow.Height - $adjustedHeight) -le $verifyTolerance

									if ($retryXMatch -and $retryYMatch) {
										if ($retryWidthMatch -and $retryHeightMatch) {
											if (Test-LogVerbose) {
												Write-LogDebug "✓ Retry successful!" -Style Success
											}
										}
										else {
											if (Test-LogVerbose) {
												Write-LogDebug "✓ Retry: Position verified, dimensions differ (app constraints)" -Style Warning
											}
										}

										$positionedWindowObj = $retryVerifyWindow
										$trackingDesktopNumber = $config.DesktopNumber + $DesktopOffset
										Add-PositionedWindow `
											-WindowHandle $retryVerifyWindow.Handle `
											-ExpectedX $posX `
											-ExpectedY $posY `
											-ExpectedWidth $posWidth `
											-ExpectedHeight $posHeight `
											-WindowTitle $retryVerifyWindow.Title `
											-DesktopNumber $trackingDesktopNumber `
											-ExpectedProcessName $retryVerifyWindow.ProcessName `
											-ExpectedProcessId ([uint32]$retryVerifyWindow.ProcessId) `
											-SingleZone:([bool]$Item.SingleZone)
									}
									else {
										if (Test-LogVerbose) {
											Write-LogDebug "Retry failed, window position still incorrect" -Style Error
											Write-LogDebug "Expected: ($adjustedX, $adjustedY), Actual: ($($retryVerifyWindow.Left), $($retryVerifyWindow.Top))"
										}
									}
								}
							}
						}
					}
					else {
						if (Test-LogVerbose) {
							Write-LogDebug "Window not found after positioning!" -Style Error
							Write-LogDebug "Original handle: [$($window.Handle)], Title: [$($window.Title)]"

							if ($config.WindowTitle) {
								$diagWindows = Get-WindowHandle -WindowTitle $config.WindowTitle -ErrorAction SilentlyContinue
								if ($diagWindows) {
									Write-LogDebug "Windows matching WindowTitle pattern [$($config.WindowTitle)]:"
									foreach ($diagWin in $diagWindows | Select-Object -First 3) {
										Write-LogDebug "• Handle: [$($diagWin.Handle)] Title: [$($diagWin.Title)]"
									}
								}
								else {
									Write-LogDebug "No windows found matching WindowTitle pattern [$($config.WindowTitle)]"
								}
							}

							$diagProcessWindows = Get-WindowHandle -ProcessName $config.ProcessName -ErrorAction SilentlyContinue
							if ($diagProcessWindows) {
								Write-LogDebug "Windows for process [$($config.ProcessName)]:"
								foreach ($diagWin in $diagProcessWindows | Select-Object -First 3) {
									Write-LogDebug "• Handle: [$($diagWin.Handle)] Title: [$($diagWin.Title)]"
								}
							}
							else {
								Write-LogDebug "No windows found for process [$($config.ProcessName)]"
							}
						}
					}
				}
				else {
					if (Test-LogVerbose) {
						Write-LogDebug "Failed to set window position!" -Style Error
					}
				}
			}
		}
		else {
			if (Test-LogVerbose) {
				Write-LogDebug "No positioning required" -Style Step
			}
		}

		# The window object whose identity is recorded - the re-verified one after a reposition,
		# otherwise the matched window (also covers the "already correct, skipped" case so the
		# snapshot records every configured window, not only the ones that moved this run).
		$recordedWindow = $positionedWindowObj
		$monitorLabel = if ($config.Monitor -is [string]) { $config.Monitor } else { '' }

		$results.Add([PSCustomObject]@{
				ProcessName       = $config.ProcessName
				WindowTitle       = $recordedWindow.Title
				Status            = "Configured"
				DesktopNumber     = $config.DesktopNumber
				Position          = if ($null -ne $posX) { "$posX,$posY" } else { "Not Set" }
				Size              = if ($posWidth) { "${posWidth}x${posHeight}" } else { "Not Set" }
				Zone              = if ($config.Zone) { "$($config.Layout)/$($config.Zone)" } else { "Direct Coordinates" }
				# Fields below feed the CurrentLayout.txt snapshot. WindowProcessName is the
				# window's ACTUAL process (e.g. "chrome") - distinct from ProcessName above,
				# which may be a layout token/regex like "(firefox|chrome|msedge|brave)". The
				# snapshot/pin must use the real name so the live-window process guard matches.
				Handle            = $recordedWindow.Handle
				WindowProcessName = $recordedWindow.ProcessName
				ProcessId         = [uint32]$recordedWindow.ProcessId
				MonitorLabel      = $monitorLabel
				# The token-resolved layout entry this result came from. Lets a caller rebuild
				# the exact subset of the layout this pass actually placed - Set-WorkspaceWindowLayout
				# verifies only that subset in alongside mode, where the rest of the layout was
				# deliberately left to whichever workspace already owns those windows.
				LayoutEntry       = $config
				ZoneName          = if ($config.Zone) { [string]$config.Zone } else { '' }
				LayoutName        = if ($Item.Layout) { [string]$Item.Layout } else { '' }
				DesktopDisplay    = $config.DesktopNumber + $DesktopOffset
				ExpectedX         = $posX
				ExpectedY         = $posY
				ExpectedWidth     = $posWidth
				ExpectedHeight    = $posHeight
				EntryKey          = $currentEntryKey
			})
	}

	foreach ($item in $sortedLayoutConfig) {
		$config = $item.Config

		# Per-desktop pipelining: the whole layout was counted above, so a duplicate key is
		# known as such even when only one of its entries is on the desktop being processed.
		# Entries outside the requested desktops, and entries an earlier pass already placed,
		# produce no row - the caller merges its passes' rows itself.
		if ($DesktopNumbers -and $DesktopNumbers.Count -gt 0) {
			$entryDesktop = if ($config.DesktopNumber) { [int]$config.DesktopNumber } else { 1 }
			if ($DesktopNumbers -notcontains $entryDesktop) { continue }
		}
		$currentEntryKey = & $entryKeyOf $config
		if ($skipEntryKeySet.Count -gt 0 -and $skipEntryKeySet.Contains($currentEntryKey)) { continue }

		if (Test-LogVerbose) {
			Write-LogDebug "[$($config.ProcessName) -> Desktop $($config.DesktopNumber)]"
			if ($config.ZoneName) {
				Write-LogDebug "Zone => $($config.ZoneName)" -Style Step
			}
		}

		# Get windows for this process with retry logic.
		# Windows (especially browser tabs) can temporarily lose their title during page loads,
		# redirects, or handle recreation. Retry with cache clearing to catch transient misses.
		# An entry the wait phase abandoned has no window to ride out title drift on: one search,
		# no 0.5 s + 1 s ladder, the same Not Found row. A per-desktop pass (-CandidateWindowHandles)
		# searches once too: the wait confirmed its candidates stable in this very poll, so a miss
		# means the entry's window is not there yet and the pass after the wait places it - the
		# ladder inside the wait only delayed every other desktop by 1.5 s per miss.
		$entryAbandonedByWait = ($abandonedEntryKeySet.Count -gt 0 -and $abandonedEntryKeySet.Contains($currentEntryKey))
		$singleSearchOnly = $entryAbandonedByWait -or ($null -ne $CandidateWindowHandles)
		$maxSearchRetries = if ($singleSearchOnly) { 1 } else { 3 }
		$searchRetryDelayMs = 500
		$windows = $null
		if ($singleSearchOnly -and (Test-LogVerbose)) {
			$singleSearchReason = if ($entryAbandonedByWait) { "Entry abandoned by the wait phase" } else { "Per-desktop pass" }
			Write-LogDebug "$singleSearchReason - single search, no retry ladder" -Style Warning
		}

		for ($searchAttempt = 1; $searchAttempt -le $maxSearchRetries; $searchAttempt++) {
			if ($searchAttempt -gt 1) {
				# Clear cache and wait before retrying to get fresh window data
				Clear-WindowCache
				Start-Sleep -Milliseconds $searchRetryDelayMs
				if (Test-LogVerbose) {
					Write-LogDebug "↻ Retry $searchAttempt/$maxSearchRetries - refreshed window cache (waited ${searchRetryDelayMs}ms)..."
				}
				# Increase delay for subsequent retries
				$searchRetryDelayMs = [Math]::Min($searchRetryDelayMs * 2, 2000)
			}

			if ($config.WindowTitle) {
				if ((Test-LogVerbose) -and $searchAttempt -eq 1) {
					Write-LogDebug "Searching for window with title pattern => $($config.WindowTitle)" -Style Step
				}
				$titleMatches = Get-WindowHandle -WindowTitle $config.WindowTitle
				# Enforce AND logic: when ProcessName is also specified, filter title matches
				# to only those belonging to the correct process. Without this, a broad title
				# regex (e.g. .*\bAsseto\b.*) can match windows from other processes
				# (e.g. "asseto - Visual Studio Code") and steal them from the correct entry.
				if ($config.ProcessName -and $titleMatches) {
					$processWindows = Get-WindowHandle -ProcessName $config.ProcessName
					$processHandles = [System.Collections.Generic.HashSet[IntPtr]]::new()
					foreach ($pw in $processWindows) { [void]$processHandles.Add($pw.Handle) }
					$filtered = @($titleMatches | Where-Object { $processHandles.Contains($_.Handle) })
					# If filtering produces results, use them; otherwise fall through to $null
					# so the pre-captured handle fallback can recover the correct window.
					$windows = if ($filtered.Count -gt 0) { $filtered } else { $null }
				}
				else {
					$windows = $titleMatches
				}

				# Some non-browser apps (notably Obsidian) can update title text dynamically,
				# causing title-pattern lookups to miss even though the correct process window exists.
				# Enforce a resilient fallback: first prefer a pre-captured stable handle from
				# Wait-ForWorkspaceWindows, then accept a single process window when unambiguous.
				if (-not $windows -and $config.ProcessName) {
					$processNameText = $config.ProcessName.ToString()
					$isBrowserLikeProcess = $processNameText -match '(?i)(browser|firefox|chrome|msedge|brave|chromium)'

					if (-not $isBrowserLikeProcess) {
						$processCandidates = @(Get-WindowHandle -ProcessName $config.ProcessName)
						if ($processCandidates.Count -gt 0) {
							$capturedCandidates = @()
							if ($ExpectedWindowState -and $ExpectedWindowState.Count -gt 0) {
								$capturedCandidates = @($processCandidates | Where-Object { $ExpectedWindowState.ContainsKey($_.Handle) })
							}

							if ($capturedCandidates.Count -gt 0) {
								$windows = @($capturedCandidates[0])
								if (Test-LogVerbose) {
									Write-LogDebug "⚠ Title pattern did not match current caption, recovered by stable process handle => [$($windows[0].Title)]" -Style Warning
								}
							}
							elseif ($processCandidates.Count -eq 1) {
								$windows = @($processCandidates[0])
								if (Test-LogVerbose) {
									Write-LogDebug "⚠ Title pattern did not match current caption, using sole process window => [$($windows[0].Title)]" -Style Warning
								}
							}
						}
					}
				}
			}
			else {
				if ((Test-LogVerbose) -and $searchAttempt -eq 1) {
					Write-LogDebug "Searching for process => $($config.ProcessName)" -Style Step
				}
				$windows = Get-WindowHandle -ProcessName $config.ProcessName
			}

			# Fallback: if title search failed, use pre-captured handles from Wait-ForWorkspaceWindows.
			# During the wait phase, the window was confirmed stable with a matching title and its handle
			# was recorded. If the title temporarily changed (e.g., browser page reload/redirect), the
			# handle is still valid - look it up by handle in the current process window list.
			if (-not $windows -and $config.WindowTitle -and $ExpectedWindowState -and $ExpectedWindowState.Count -gt 0) {
				foreach ($entry in $ExpectedWindowState.GetEnumerator()) {
					$capturedHandle = $entry.Key
					$capturedState = $entry.Value

					# Check if the title captured during the wait phase matches the expected pattern
					# Use Test-WindowTitleMatch to support both wildcard (e.g., *Gemini*) and regex (e.g., (.*Calendar.*|.*Week.*)) patterns
					if (Test-WindowTitleMatch -WindowTitle $capturedState.Title -Patterns @($config.WindowTitle)) {
						# Found a pre-captured handle whose stable title matched - verify it's still a live window
						$allProcessWindows = Get-WindowHandle -ProcessName $config.ProcessName
						$fallbackWindow = $allProcessWindows | Where-Object { $_.Handle -eq $capturedHandle } | Select-Object -First 1

						if ($fallbackWindow) {
							$windows = @($fallbackWindow)
							if (Test-LogVerbose) {
								Write-LogDebug "✗ No windows found matching current titles" -Style Warning
								Write-LogDebug "✓ Recovered via pre-captured handle from wait phase!" -Style Success
								Write-LogDebug "Handle => [$capturedHandle]" -Style Step
								Write-LogDebug "Captured title => [$($capturedState.Title)]" -Style Step
								Write-LogDebug "Current title  => [$($fallbackWindow.Title)]" -Style Step
							}
							break
						}
					}
				}
			}

			if ($windows) {
				if ($searchAttempt -gt 1 -and (Test-LogVerbose)) {
					Write-LogDebug "✓ Found window on retry attempt $searchAttempt!" -Style Success
				}
				break
			}

			# On non-final attempts, show brief status
			if ($searchAttempt -lt $maxSearchRetries -and (Test-LogVerbose)) {
				Write-LogDebug "⚠ Window not found (attempt $searchAttempt/$maxSearchRetries), will retry..." -Style Warning
			}
		}

		# Alongside mode: a window that existed before this workspace opened belongs to another
		# workspace and is refused by the positioning loop further down. Drop those candidates
		# HERE, before any entry can claim one. Filtering only at the point of use was doubly
		# lossy: the entry that picked a pre-existing window produced no result at all (so the
		# empty zone never showed up as "Not Found"), and the handle was never marked claimed,
		# so the NEXT duplicate entry could pick the very same ineligible window and lose itself
		# the same way. Filtering here leaves the eligible windows for the entries that can use
		# them and turns a genuine shortfall into a visible Not Found.
		#
		# After the search ladder, not inside it: that ladder exists to ride out transient TITLE
		# drift on windows that already exist, and no amount of re-querying makes an ineligible
		# window eligible. Running it per starved entry would add seconds each to a run that has
		# already gone wrong. A window that appears late is picked up by the caller's own
		# position -> snap -> verify retry instead.
		if ($SkipExistingWindows -and $ExistingWindowHandles -and $windows) {
			$candidateCount = @($windows).Count
			$windows = @($windows | Where-Object { -not $ExistingWindowHandles.Contains($_.Handle) })
			if ((Test-LogVerbose) -and $windows.Count -ne $candidateCount) {
				Write-LogDebug "⊘ Excluded $($candidateCount - $windows.Count) pre-existing window(s) - not eligible for an alongside layout" -Style Warning
			}
		}

		# Plain-mode candidate exclusion, same position and same reasoning as the alongside
		# filter above: a preserved workspace's window matches layout regexes ("Browser" matches
		# any browser window) but is another workspace's to keep - drop it before any entry can
		# claim it, so a genuine shortfall reports as "Not Found" instead of a stolen window.
		# After the search ladder, not inside it: no amount of re-querying makes a protected
		# window eligible.
		if ($ProtectedWindowHandles -and $windows) {
			$candidateCount = @($windows).Count
			$windows = @($windows | Where-Object { -not $ProtectedWindowHandles.Contains($_.Handle) })
			if ((Test-LogVerbose) -and $windows.Count -ne $candidateCount) {
				Write-LogDebug "⊘ Excluded $($candidateCount - $windows.Count) protected window(s) - preserved for a live alongside workspace" -Style Warning
			}
		}

		# Per-desktop pipelining, same position and same reasoning as the two filters above. A
		# pass for ONE desktop may only claim the windows the wait phase confirmed stable for that
		# desktop's entries (whitelist); the pass that finishes the remaining desktops may not
		# claim the windows the per-desktop passes already placed (blacklist). Neither is a
		# matter of title regexes - a catch-all entry matches every window of its process - so
		# both are enforced on the candidate list, before claiming.
		if ($null -ne $CandidateWindowHandles -and $windows) {
			$candidateCount = @($windows).Count
			$windows = @($windows | Where-Object { $CandidateWindowHandles.Contains($_.Handle) })
			if ((Test-LogVerbose) -and $windows.Count -ne $candidateCount) {
				Write-LogDebug "⊘ Excluded $($candidateCount - $windows.Count) window(s) outside this pass's candidate set" -Style Warning
			}
		}
		if ($null -ne $ExcludeWindowHandles -and $ExcludeWindowHandles.Count -gt 0 -and $windows) {
			$candidateCount = @($windows).Count
			$windows = @($windows | Where-Object { -not $ExcludeWindowHandles.Contains($_.Handle) })
			if ((Test-LogVerbose) -and $windows.Count -ne $candidateCount) {
				Write-LogDebug "⊘ Excluded $($candidateCount - $windows.Count) window(s) an earlier per-desktop pass already placed" -Style Warning
			}
		}

		if (-not $windows) {
			if (Test-LogVerbose) {
				Write-LogDebug "✗ No windows found after $maxSearchRetries attempts" -Style Warning

				# Verbose: Show all windows for this process if WindowTitle was specified
				if ($config.WindowTitle) {
					Write-LogDebug "Checking all windows for process '$($config.ProcessName)'..." -Style Step
					$allProcessWindows = Get-WindowHandle -ProcessName $config.ProcessName
					if ($allProcessWindows) {
						Write-LogDebug "Available windows for '$($config.ProcessName)':" -Style Step
						$allProcessWindows | ForEach-Object {
							Write-LogDebug "- $($_.Title)" -Style Step
						}
						Write-LogDebug "None matched pattern: $($config.WindowTitle)" -Style Warning
					}
					else {
						Write-LogDebug "No windows found for process '$($config.ProcessName)' at all" -Style Step
					}
				}
			}

			$results.Add([PSCustomObject]@{
					ProcessName   = $config.ProcessName
					Status        = "Not Found"
					DesktopNumber = $config.DesktopNumber
					EntryKey      = $currentEntryKey
				})
			continue
		}

		if (Test-LogVerbose) {
			Write-LogDebug "✓ Found $($windows.Count) window(s)" -Style Success
			if ($windows.Count -gt 1) {
				Write-LogDebug "Multiple windows found, applying layout to all" -Style Step
			}
		}

		# Calculate position once (outside loop) if using zone-based positioning
		$posX = $null
		$posY = $null
		$posWidth = $null
		$posHeight = $null
		# Reset per-entry so a direct-coordinate entry never inherits the previous
		# iteration's resolved layout name when recorded into the work item.
		$layoutName = $null
		# Whether this entry's resolved layout defines exactly one zone. Single-zone windows
		# take Snap-AllWindows' dedicated snap path (Invoke-SingleZoneWindowSnap: stale
		# FancyZones assignments cleared, centered at a deeper inset, Win+Up with shift-drag
		# fallback). Direct-coordinate entries stay $false - they never had a zone to snap
		# into.
		$singleZone = $false

		# Check if using zone-based positioning
		if ($config.Zone) {
			# Resolve layout name from MonitorConfig if not explicitly provided
			$layoutName = $config.Layout
			if (-not $layoutName -and $config.Monitor -and $null -ne $config.DesktopNumber -and $MonitorConfig) {
				# Look up layout from Monitors section (VirtualDesktopLayouts uses 1-based keys matching layout files)
				if ($MonitorConfig.ContainsKey($config.Monitor) -and
					$MonitorConfig[$config.Monitor].VirtualDesktopLayouts -and
					$MonitorConfig[$config.Monitor].VirtualDesktopLayouts.ContainsKey($config.DesktopNumber)) {
					$layoutName = $MonitorConfig[$config.Monitor].VirtualDesktopLayouts[$config.DesktopNumber]
					if (Test-LogVerbose) {
						Write-LogDebug "Auto-resolved layout from Monitors section => $layoutName" -Style Success
					}
				}
			}

			if (-not $layoutName) {
				if (Test-LogVerbose) {
					Write-Warning "  Could not determine layout for $($config.ProcessName). Specify Layout field or ensure Monitors section defines layout for Monitor=$($config.Monitor), Desktop=$($config.DesktopNumber)"
				}
				continue
			}

			if (Test-LogVerbose) {
				Write-LogDebug "Using zone-based positioning => [Layout=$layoutName | Zone=$($config.Zone)]" -Style Step
			}

			# Get monitor information - support both string labels and hashtable specs.
			# Zone geometry uses the monitor WORK AREA (Work* spec fields): FancyZones lays
			# zones over the work area, not the full bounds, so a visible taskbar shrinks
			# every zone. The two are identical when the taskbar is auto-hidden.
			#
			# Geometry starts as $null and every path has to fill it in - there are no default
			# dimensions. A hardcoded 3440x1440 ultrawide placed windows using geometry that can
			# belong to no attached display, and quietly retargeting an unresolvable label at
			# Primary stacked a third monitor's windows on top of the primary monitor's. Both
			# were unreachable in practice with two known monitors and became reachable as soon
			# as a layout named a monitor that is not attached.
			$monitorX = $null
			$monitorY = $null
			$monitorWidth = $null
			$monitorHeight = $null

			# Check if Monitor is a string label (e.g., "Primary", "Secondary")
			if ($config.Monitor -is [string]) {
				if (Test-LogVerbose) {
					Write-LogDebug "Resolving monitor => $($config.Monitor)" -Style Step
				}
				# Use pre-fetched monitor specs to avoid redundant calls
				if (-not $monitorSpecs) {
					$monitorSpecs = Get-MonitorSpecs -MonitorInfo $MonitorInfo
				}
				$monitorSpec = $monitorSpecs.($config.Monitor)

				if ($monitorSpec) {
					$monitorX = if ($null -ne $monitorSpec.WorkX) { $monitorSpec.WorkX } else { $monitorSpec.X }
					$monitorY = if ($null -ne $monitorSpec.WorkY) { $monitorSpec.WorkY } else { $monitorSpec.Y }
					$monitorWidth = if ($monitorSpec.WorkWidth) { $monitorSpec.WorkWidth } else { $monitorSpec.Width }
					$monitorHeight = if ($monitorSpec.WorkHeight) { $monitorSpec.WorkHeight } else { $monitorSpec.Height }
					if (Test-LogVerbose) {
						Write-LogDebug "✓ Monitor resolved => work area ${monitorWidth}x${monitorHeight} at ($monitorX, $monitorY)" -Style Success
					}
				}
			}
			# Otherwise treat as hashtable with X, Y, Width, Height properties
			# (explicit dimensions in a layout file are used verbatim)
			elseif ($config.Monitor) {
				$monitorX = if ($null -ne $config.Monitor.X) { $config.Monitor.X } else { 0 }
				$monitorY = if ($null -ne $config.Monitor.Y) { $config.Monitor.Y } else { 0 }
				$monitorWidth = $config.Monitor.Width
				$monitorHeight = $config.Monitor.Height
			}

			if (-not $monitorWidth -or -not $monitorHeight) {
				# Skipping loses one window; substituting geometry misplaces it silently, which
				# is harder to notice and harder to diagnose. Warn unconditionally - this is a
				# layout/display mismatch the user has to fix, not verbose diagnostics.
				$requestedMonitor = if ($config.Monitor -is [string]) { $config.Monitor }
				elseif ($config.Monitor) { "explicit geometry" }
				else { "<none specified>" }

				$attachedLabels = if ($monitorSpecs) {
					@($monitorSpecs.PSObject.Properties.Name | Sort-Object { Resolve-MonitorLabel -Label $_ }) -join ', '
				}
				else { "unknown" }

				Write-Warning "  Skipping $($config.ProcessName): monitor [$requestedMonitor] has no resolvable geometry. Attached monitors: $attachedLabels"
				continue
			}

			# Get zone coordinates
			$zone = Get-FancyZone -LayoutName $layoutName -ZoneName $config.Zone `
				-MonitorX $monitorX -MonitorY $monitorY `
				-MonitorWidth $monitorWidth -MonitorHeight $monitorHeight

			if ($zone) {
				$posX = $zone.X
				$posY = $zone.Y
				$posWidth = $zone.Width
				$posHeight = $zone.Height
				$singleZone = ($zone.TotalZoneCount -eq 1)
				if (Test-LogVerbose) {
					Write-LogDebug "✓ Zone coordinates calculated => [$posX,$posY ${posWidth}x${posHeight}]" -Style Success
					if ($singleZone) {
						Write-LogDebug "Single-zone layout - window will snap through the dedicated single-zone path" -Style Step
					}
				}
			}
			else {
				if (Test-LogVerbose) {
					Write-Warning "  Failed to calculate zone coordinates, skipping positioning"
				}
			}
		}
		# Otherwise use direct coordinates if specified
		elseif ($null -ne $config.X -and $null -ne $config.Y -and $config.Width -and $config.Height) {
			$posX = $config.X
			$posY = $config.Y
			$posWidth = $config.Width
			$posHeight = $config.Height
		}

		# Determine if this layout entry is a duplicate key
		$layoutKey = "$($config.ProcessName)|$($config.WindowTitle)"
		$isDuplicateKey = $layoutKeyCount[$layoutKey] -gt 1

		# When a (ProcessName, WindowTitle) pair appears multiple times in the layout,
		# each entry should consume exactly one distinct window to place in its own zone.
		# Filter out handles already claimed by earlier entries with the same key.
		if ($isDuplicateKey) {
			$windows = @($windows | Where-Object { -not $claimedHandles.Contains($_.Handle) })

			# Every candidate was already taken by an earlier entry with the same key - there
			# are fewer windows than entries. Report it like any other unmatched entry: falling
			# through with an empty set positions nothing AND records nothing, so the caller's
			# Configured/Not Found tallies added up to less than the layout and the shortfall
			# went unnoticed.
			if ($windows.Count -eq 0) {
				if (Test-LogVerbose) {
					Write-LogDebug "✗ No unclaimed window left for duplicate entry [$layoutKey]" -Style Warning
				}

				$results.Add([PSCustomObject]@{
						ProcessName   = $config.ProcessName
						Status        = "Not Found"
						DesktopNumber = $config.DesktopNumber
						EntryKey      = $currentEntryKey
					})
				continue
			}

			if ($windows.Count -gt 1) {
				# The old behaviour took $windows[0] - i.e. whatever EnumWindows returned
				# first (Z-order), which shifts whenever a window is raised/focused between
				# runs and therefore reshuffled identical windows across zones on every
				# re-open. Two strategies replace it, in priority order:
				$chosen = $null

				# 1) Authoritative pin. If CurrentLayout.txt recorded a specific window for
				#    this exact desktop|monitor|zone and that window is still live among the
				#    candidates with a matching process fingerprint, reclaim it. Within a
				#    session the HWND is a unique, stable identifier, so every window returns
				#    to its own zone with zero reshuffle. The process (name + id) guard makes
				#    a recycled handle from a different/relaunched process fall through to
				#    geometry instead (e.g. after a reboot the PID differs).
				if ($PinnedHandleMap) {
					$zoneKey = "$($config.DesktopNumber)|$($config.Monitor)|$($config.Zone)"
					if ($PinnedHandleMap.ContainsKey($zoneKey)) {
						$rec = $PinnedHandleMap[$zoneKey]
						$recordedHandle = $null
						try { $recordedHandle = [IntPtr][int64]$rec.Handle } catch { $recordedHandle = $null }

						if ($recordedHandle -and $recordedHandle -ne [IntPtr]::Zero) {
							$chosen = $windows | Where-Object {
								$_.Handle -eq $recordedHandle -and
								([string]::IsNullOrEmpty($rec.ProcessName) -or $_.ProcessName -eq $rec.ProcessName) -and
								((-not $rec.ProcessId) -or ([uint32]$_.ProcessId -eq [uint32]$rec.ProcessId))
							} | Select-Object -First 1

							if ($chosen -and (Test-LogVerbose)) {
								Write-LogDebug "Duplicate key => pinned recorded window for [$zoneKey] from CurrentLayout (handle $recordedHandle)" -Style Step
							}
						}
					}
				}

				# 2) Geometry fallback (no valid pin - first open, reboot, or a brand-new
				#    window). Claim the unclaimed candidate whose CURRENT bounds are closest
				#    to this entry's target zone, mirroring the scoring the final verifier
				#    (Confirm-WorkspaceWindowPositions) uses. On a true first open every
				#    candidate sits on the current desktop so this just assigns distinct
				#    windows; the pin keeps the assignment stable on every run after.
				if (-not $chosen) {
					$haveTarget = ($null -ne $posX -and $null -ne $posY -and $posWidth -and $posHeight)
					if ($haveTarget) {
						$bestScore = [double]::PositiveInfinity
						foreach ($candidate in $windows) {
							$candRect = New-Object WindowModule.RECT
							if ([WindowModule.Native]::GetWindowRect($candidate.Handle, [ref]$candRect)) {
								$cW = $candRect.Right - $candRect.Left
								$cH = $candRect.Bottom - $candRect.Top
								$candScore = [Math]::Abs($candRect.Left - $posX) + [Math]::Abs($candRect.Top - $posY) + [Math]::Abs($cW - $posWidth) + [Math]::Abs($cH - $posHeight)
								if ($candScore -lt $bestScore) {
									$bestScore = $candScore
									$chosen = $candidate
								}
							}
						}
					}
					if (-not $chosen) { $chosen = $windows[0] }
				}

				$windows = @($chosen)
			}

			if ((Test-LogVerbose) -and $windows.Count -gt 0) {
				Write-LogDebug "Duplicate key => claiming window [$($windows[0].Title)] (Handle => $($windows[0].Handle))"
			}
		}

		# Move windows to virtual desktops
		foreach ($window in $windows) {
			if (Test-LogVerbose) {
				Write-LogDebug "Processing window => [$($window.Title)]" -Style Step
			}

			# Backstop for alongside mode: ineligible candidates are already filtered out before
			# claiming (see the exclusion in the window-search loop above), so reaching this
			# guard means the window arrived by a path that bypassed that filter.
			if ($SkipExistingWindows -and $ExistingWindowHandles -and $ExistingWindowHandles.Contains($window.Handle)) {
				if (Test-LogVerbose) {
					Write-LogDebug "⊘ Skipping - window existed before this workspace (belongs to another workspace)" -Style Warning
				}
				continue
			}

			# Same backstop for protected windows: the candidate filter above already removed
			# them, so reaching this guard means the window arrived by a path that bypassed it.
			if ($ProtectedWindowHandles -and $ProtectedWindowHandles.Contains($window.Handle)) {
				if (Test-LogVerbose) {
					Write-LogDebug "⊘ Skipping - window is preserved for a live alongside workspace" -Style Warning
				}
				continue
			}

			# Check if this window has already been moved
			if ($movedWindows.ContainsKey($window.Handle)) {
				if (Test-LogVerbose) {
					Write-LogDebug "⊘ Skipping - already moved to desktop $($movedWindows[$window.Handle])" -Style Warning
				}
				continue
			}

			# Move to virtual desktop if specified
			if ($null -ne $config.DesktopNumber) {
				# Convert 1-based DesktopNumber to 0-based for VirtualDesktop module, then add offset
				$internalDesktopIndex = ($config.DesktopNumber - 1) + $DesktopOffset
				$displayDesktopNumber = $config.DesktopNumber + $DesktopOffset
				if (Test-LogVerbose) {
					$offsetNote = if ($DesktopOffset -gt 0) { " (original: $($config.DesktopNumber), offset: +$DesktopOffset)" } else { "" }
					Write-LogDebug "Attempting to move to virtual desktop $displayDesktopNumber$offsetNote..." -Style Step
				}
				try {
					$desktopResult = Move-WindowToVirtualDesktop -WindowHandle $window.Handle -DesktopNumber $internalDesktopIndex
					if (-not $desktopResult) {
						if (Test-LogVerbose) {
							Write-LogDebug "✗ Failed to move to desktop $displayDesktopNumber" -Style Error
						}
					}
					else {
						# Track this window as moved (store the actual desktop number with offset)
						$movedWindows[$window.Handle] = $displayDesktopNumber
					}
				}
				catch {
					if (Test-LogVerbose) {
						Write-LogDebug "✗ Error moving to desktop: $_" -Style Error
					}
				}
			}

			# Store window information for positioning phase.
			# Layout carries the resolved FancyZones layout name (from the Monitors section or
			# the explicit Layout field) so Add-PositionedWindow can record where the window
			# belongs for CurrentLayout.txt.
			$positionWorkItem = [PSCustomObject]@{
				Window     = $window
				Config     = $config
				PosX       = $posX
				PosY       = $posY
				PosWidth   = $posWidth
				PosHeight  = $posHeight
				Layout     = $layoutName
				SingleZone = $singleZone
			}

			# Settle only when a real desktop move happened this iteration - the fast path
			# (already on target) and dedup skips need no delay.
			if ($null -ne $config.DesktopNumber -and
				$script:LastMoveWindowToVirtualDesktopResult -and
				$script:LastMoveWindowToVirtualDesktopResult.Moved) {
				Start-Sleep -Milliseconds $script:WindowModuleDelays.WindowPositionMs
			}

			& $applyPositionWorkItem -Item $positionWorkItem

			# Mark this handle as claimed so the next duplicate entry gets a different window
			if ($isDuplicateKey) {
				[void]$claimedHandles.Add($window.Handle)
			}
		}
	}

	Write-LogDebug "=> Window layouts applied!" -Style Success
	return $results
}
