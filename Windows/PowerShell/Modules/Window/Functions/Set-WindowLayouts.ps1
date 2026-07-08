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
		[hashtable]$PinnedHandleMap
	)

	Initialize-PositionedWindowTracking

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
	$insetPercent = 0.05
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

					$possibleWindows = Get-WindowHandle -ProcessName $config.ProcessName -ErrorAction SilentlyContinue |
						Where-Object { $_.Title -eq $window.Title }

					if (-not $possibleWindows -and $config.WindowTitle) {
						$possibleWindows = Get-WindowHandle -WindowTitle $config.WindowTitle -ErrorAction SilentlyContinue
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

					if (-not $verifyWindow -and $window.Title) {
						$verifyWindow = Get-WindowHandle -ProcessName $config.ProcessName -ErrorAction SilentlyContinue |
							Where-Object { $_.Title -eq $window.Title } |
							Select-Object -First 1

						if ($verifyWindow -and (Test-LogVerbose)) {
							Write-LogDebug "Window handle changed after positioning (was: $($window.Handle), now: $($verifyWindow.Handle))" -Style Warning
						}
					}

					if (-not $verifyWindow -and $config.WindowTitle) {
						$verifyWindow = Get-WindowHandle -WindowTitle $config.WindowTitle -ErrorAction SilentlyContinue |
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
								-ExpectedProcessId ([uint32]$verifyWindow.ProcessId)
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
										Where-Object { $_.Title -eq $verifyWindow.Title } |
										Select-Object -First 1
								}

								if (-not $retryVerifyWindow -and $config.WindowTitle) {
									$retryVerifyWindow = Get-WindowHandle -WindowTitle $config.WindowTitle -ErrorAction SilentlyContinue |
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
											-ExpectedProcessId ([uint32]$retryVerifyWindow.ProcessId)
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
				ZoneName          = if ($config.Zone) { [string]$config.Zone } else { '' }
				LayoutName        = if ($Item.Layout) { [string]$Item.Layout } else { '' }
				DesktopDisplay    = $config.DesktopNumber + $DesktopOffset
				ExpectedX         = $posX
				ExpectedY         = $posY
				ExpectedWidth     = $posWidth
				ExpectedHeight    = $posHeight
			})
	}

	foreach ($item in $sortedLayoutConfig) {
		$config = $item.Config
		if (Test-LogVerbose) {
			Write-LogDebug "[$($config.ProcessName) -> Desktop $($config.DesktopNumber)]"
			if ($config.ZoneName) {
				Write-LogDebug "Zone => $($config.ZoneName)" -Style Step
			}
		}

		# Get windows for this process with retry logic.
		# Windows (especially browser tabs) can temporarily lose their title during page loads,
		# redirects, or handle recreation. Retry with cache clearing to catch transient misses.
		$maxSearchRetries = 3
		$searchRetryDelayMs = 500
		$windows = $null

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
			$monitorX = 0
			$monitorY = 0
			$monitorWidth = 3440
			$monitorHeight = 1440

			if ($config.Monitor) {
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

					if (-not $monitorSpec -and $monitorSpecs) {
						# Unknown label (layout written for more monitors than attached):
						# the primary monitor's real geometry beats blind constants.
						$monitorSpec = $monitorSpecs.Primary
						if ($monitorSpec -and (Test-LogVerbose)) {
							Write-Warning "  Monitor '$($config.Monitor)' not found, falling back to Primary"
						}
					}

					if ($monitorSpec) {
						$monitorX = if ($null -ne $monitorSpec.WorkX) { $monitorSpec.WorkX } else { $monitorSpec.X }
						$monitorY = if ($null -ne $monitorSpec.WorkY) { $monitorSpec.WorkY } else { $monitorSpec.Y }
						$monitorWidth = if ($monitorSpec.WorkWidth) { $monitorSpec.WorkWidth } else { $monitorSpec.Width }
						$monitorHeight = if ($monitorSpec.WorkHeight) { $monitorSpec.WorkHeight } else { $monitorSpec.Height }
						if (Test-LogVerbose) {
							Write-LogDebug "✓ Monitor resolved => work area ${monitorWidth}x${monitorHeight} at ($monitorX, $monitorY)" -Style Success
						}
					}
					else {
						if (Test-LogVerbose) {
							Write-Warning "  Monitor '$($config.Monitor)' not found, using defaults"
						}
					}
				}
				# Otherwise treat as hashtable with X, Y, Width, Height properties
				# (explicit dimensions in a layout file are used verbatim)
				else {
					$monitorX = if ($null -ne $config.Monitor.X) { $config.Monitor.X } else { 0 }
					$monitorY = if ($null -ne $config.Monitor.Y) { $config.Monitor.Y } else { 0 }
					$monitorWidth = if ($config.Monitor.Width) { $config.Monitor.Width } else { 3440 }
					$monitorHeight = if ($config.Monitor.Height) { $config.Monitor.Height } else { 1440 }
				}
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
				if (Test-LogVerbose) {
					Write-LogDebug "✓ Zone coordinates calculated => [$posX,$posY ${posWidth}x${posHeight}]" -Style Success
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

			# When using alongside mode (SkipExistingWindows), skip windows that existed before
			# opening this workspace - they belong to a previous workspace
			if ($SkipExistingWindows -and $ExistingWindowHandles -and $ExistingWindowHandles.Contains($window.Handle)) {
				if (Test-LogVerbose) {
					Write-LogDebug "⊘ Skipping - window existed before this workspace (belongs to another workspace)" -Style Warning
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
				Window    = $window
				Config    = $config
				PosX      = $posX
				PosY      = $posY
				PosWidth  = $posWidth
				PosHeight = $posHeight
				Layout    = $layoutName
			}

			if ($null -ne $config.DesktopNumber) {
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
