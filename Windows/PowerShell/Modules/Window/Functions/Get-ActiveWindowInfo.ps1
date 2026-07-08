function Get-ActiveWindowInfo {
	<#
	.SYNOPSIS
		Gets information about windows and writes it to ActiveWindowInfo.txt on the desktop.

	.DESCRIPTION
		Retrieves detailed information about all open windows (or a filtered subset)
		including process name, window title, handle, position, and size. Writes the
		output to ActiveWindowInfo.txt on the desktop. Useful for determining what
		values to use in layout configurations.

	.PARAMETER Window
		A window title pattern to filter by. Supports the same wildcard and regex syntax
		used throughout the workspace setup (e.g., "*YouTube*", ".*Firefox.*").
		When omitted, all open windows are included.

	.PARAMETER Continuous
		If specified, continuously monitors the focused window and displays its info
		in the terminal. Each time focus changes, the new window's info is appended
		below the previous one so earlier entries remain visible and copyable.
		Press Ctrl+C to stop.

	.EXAMPLE
		Get-ActiveWindowInfo

	.EXAMPLE
		Get-ActiveWindowInfo -Window "*Firefox*"

	.EXAMPLE
		Get-ActiveWindowInfo -Window "(.*Calendar.*|.*Week.*)"

	.EXAMPLE
		Get-ActiveWindowInfo -Continuous
	#>
	[CmdletBinding()]
	param (
		[Parameter(Position = 0)]
		[string]$Window,

		[Parameter()]
		[switch]$Continuous
	)

	Write-LogTitle "Active Window Information"

	$outputPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'ActiveWindowInfo.txt'

	# Use Test-WindowTitleMatch for filtering when a Window pattern is provided
	$hasWindowFilter = -not [string]::IsNullOrEmpty($Window)

	if ($Continuous) {
		# Continuous mode: track the focused window handle and append info on each focus change
		$lastHandle = [IntPtr]::Zero

		Write-LogTitle "Continuous Window Monitoring"
		Write-LogStep " Focus different windows to capture their info. Press Ctrl+C to stop."
		Write-Host ""

		while ($true) {
			$hwnd = [WindowModule.Native]::GetForegroundWindow()

			if ($hwnd -ne [IntPtr]::Zero -and $hwnd -ne $lastHandle) {
				# Clear window cache to get fresh data
				Clear-WindowCache
				$allWindows = Get-CachedWindows
				$focused = $allWindows | Where-Object { $_.Handle -eq $hwnd } | Select-Object -First 1

				if ($focused) {
					# Apply title filter if specified
					$matchesFilter = $true
					if ($hasWindowFilter -and -not (Test-WindowTitleMatch -WindowTitle $focused.Title -Patterns @($Window))) {
						$matchesFilter = $false
					}

					if ($matchesFilter) {
						$info = [PSCustomObject]@{
							Handle      = $focused.Handle
							Title       = $focused.Title
							ProcessName = $focused.ProcessName
							ProcessId   = $focused.ProcessId
							X           = $focused.Left
							Y           = $focused.Top
							Width       = $focused.Width
							Height      = $focused.Height
						}

						Write-WindowInfoBlock -Info $info
						Write-Host ""
					}
				}

				$lastHandle = $hwnd
			}

			Start-Sleep -Milliseconds 200
		}
	}
	else {
		# One-shot mode: write all windows to file
		$allWindows = Get-CachedWindows

		$windowInfos = foreach ($win in $allWindows) {
			if ($hasWindowFilter -and -not (Test-WindowTitleMatch -WindowTitle $win.Title -Patterns @($Window))) {
				continue
			}

			[PSCustomObject]@{
				Handle      = $win.Handle
				Title       = $win.Title
				ProcessName = $win.ProcessName
				ProcessId   = $win.ProcessId
				X           = $win.Left
				Y           = $win.Top
				Width       = $win.Width
				Height      = $win.Height
			}
		}

		if ($windowInfos) {
			$sb = [System.Text.StringBuilder]::new()

			$filterLabel = if ($Window) { " (filter: $Window)" } else { "" }
			[void]$sb.AppendLine("[Window Information$filterLabel]")
			[void]$sb.AppendLine("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
			[void]$sb.AppendLine("Count: $($windowInfos.Count)")
			[void]$sb.AppendLine("")

			foreach ($info in $windowInfos) {
				[void]$sb.AppendLine((Create-CenteredBorder -Title $info.ProcessName -BorderChar '-'))
				[void]$sb.AppendLine("")
				[void]$sb.AppendLine("  Process Name  : $($info.ProcessName)")
				[void]$sb.AppendLine("  Window Title  : $($info.Title)")
				[void]$sb.AppendLine("  Window Handle : 0x$($info.Handle.ToString('X'))")
				[void]$sb.AppendLine("  Process ID    : $($info.ProcessId)")
				[void]$sb.AppendLine("  Position      : ($($info.X), $($info.Y))")
				[void]$sb.AppendLine("  Size          : $($info.Width)x$($info.Height)")
				[void]$sb.AppendLine("")
				[void]$sb.AppendLine("  Config template:")
				[void]$sb.AppendLine("  @{")
				[void]$sb.AppendLine("      ProcessName   = `"$($info.ProcessName)`"")
				[void]$sb.AppendLine("      WindowTitle   = `"$($info.Title)`"")
				[void]$sb.AppendLine("      DesktopNumber = 1")
				[void]$sb.AppendLine("      Zone          = `"Zone`"")
				[void]$sb.AppendLine("      Monitor       = `"Monitor`"")
				[void]$sb.AppendLine("  }")
				[void]$sb.AppendLine("")
			}

			[System.IO.File]::WriteAllText($outputPath, $sb.ToString())

			Write-LogSuccess "Wrote $($windowInfos.Count) window(s) to $outputPath"
		}
		else {
			$msg = if ($Window) { "No windows found matching pattern: $Window" } else { "No windows found" }
			Write-LogError $msg -NoLeadingNewline
		}
	}
}
