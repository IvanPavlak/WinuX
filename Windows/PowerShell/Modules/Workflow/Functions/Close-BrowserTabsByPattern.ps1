function Close-BrowserTabsByPattern {
	<#
    .SYNOPSIS
        Closes all browser tabs matching specific title patterns.

    .DESCRIPTION
        Cycles through all tabs in browser windows and closes tabs whose titles match
        the specified patterns. Supports Chrome, Edge, and Firefox browsers.
        Uses keyboard navigation (Ctrl+Tab, Ctrl+W) to cycle through and close tabs.

    .PARAMETER ProcessName
        The process name of the browser (e.g., "chrome", "msedge", "firefox")

    .PARAMETER TitlePatterns
        Array of regex patterns to match against tab titles

    .OUTPUTS
        Returns the count of closed tabs

    .EXAMPLE
        Close-BrowserTabsByPattern -ProcessName "chrome" -TitlePatterns @("(?i)swagger", "(?i)problem.*loading.*page")
        Closes all Chrome tabs with "Swagger" or "Problem loading page" in the title

    .EXAMPLE
        Close-BrowserTabsByPattern -ProcessName "msedge" -TitlePatterns @("(?i)localhost:5000")
        Closes all Edge tabs matching localhost:5000
    #>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[string]$ProcessName,

		[Parameter(Mandatory)]
		[string[]]$TitlePatterns
	)

	try {
		$browserWindows = Get-WindowHandle -ProcessName $ProcessName -ErrorAction SilentlyContinue

		if (-not $browserWindows) {
			Write-LogDebug "  No browser windows found for process [$ProcessName]" -Style Warning
			return 0
		}

		if (Test-LogVerbose) {
			$windowCount = if ($browserWindows -is [array]) { $browserWindows.Count } else { 1 }
			Write-LogDebug "  Found $windowCount browser window(s), cycling through tabs..." -Style Success
		}

		Add-Type -AssemblyName System.Windows.Forms
		[void][System.Reflection.Assembly]::LoadWithPartialName("Microsoft.VisualBasic")

		$totalClosedTabs = 0

		# Ensure $browserWindows is always an array
		$windowArray = if ($browserWindows -is [array]) { $browserWindows } else { @($browserWindows) }

		foreach ($window in $windowArray) {
			Write-LogDebug "  Processing browser window => [$($window.Title)]"

			# First check if this window's title matches (for Firefox with process isolation where each tab is a separate window)
			$shouldCloseWindow = $false
			foreach ($pattern in $TitlePatterns) {
				if (Test-LogVerbose) {
					$matchResult = if ($window.Title -match $pattern) { "MATCH" } else { "no match" }
					Write-LogDebug "Checking pattern [$pattern] against window [$($window.Title)] => $matchResult"
				}
				if ($window.Title -match $pattern) {
					$shouldCloseWindow = $true
					break
				}
			}

			if ($shouldCloseWindow) {
				Write-LogDebug "   -> Closing window directly => [$($window.Title)]" -Style Step
				[CloseProjectWin32]::PostMessage($window.Handle, [CloseProjectWin32]::WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
				$totalClosedTabs++
				Start-Sleep -Milliseconds 10
				continue
			}

			# If window doesn't match, try tab cycling (for browsers where tabs share the same window)
			# Focus this browser window
			try {
				$process = Get-Process -Id $window.ProcessId -ErrorAction SilentlyContinue
				if ($process) {
					[Microsoft.VisualBasic.Interaction]::AppActivate($process.Id)
					Start-Sleep -Milliseconds 10
				}
			}
			catch {
				Write-LogDebug "  Could not focus window, skipping..." -Style Warning
				continue
			}

			$checkedTitles = @()
			$closedTabsInWindow = @()
			$maxTabs = 30  # Safety limit per window

			for ($i = 0; $i -lt $maxTabs; $i++) {
				# Get current tab title
				$currentWindow = Get-WindowHandle -ProcessName $ProcessName -ErrorAction SilentlyContinue |
					Where-Object { $_.ProcessId -eq $window.ProcessId } |
					Select-Object -First 1

				if (-not $currentWindow) {
					break
				}

				$currentTitle = $currentWindow.Title

				if (-not $currentTitle) {
					break
				}

				# Check if this tab matches any pattern
				$shouldClose = $false
				foreach ($pattern in $TitlePatterns) {
					if (Test-LogVerbose) {
						$matchResult = if ($currentTitle -match $pattern) { "MATCH" } else { "no match" }
						Write-LogDebug "Checking pattern [$pattern] against [$currentTitle] => $matchResult"
					}
					if ($currentTitle -match $pattern) {
						$shouldClose = $true
						break
					}
				}

				if ($shouldClose) {
					Write-LogDebug "   -> Closing tab => [$currentTitle]" -Style Step

					# Close this tab with Ctrl+W
					[System.Windows.Forms.SendKeys]::SendWait("^w")
					$closedTabsInWindow += $currentTitle
					$totalClosedTabs++
					Start-Sleep -Milliseconds 10

					# After closing, we're automatically moved to another tab
					# Continue checking from the current position
					continue
				}

				# If we've already checked this title, we've cycled through all tabs
				if ($checkedTitles -contains $currentTitle) {
					break
				}

				$checkedTitles += $currentTitle

				# Move to next tab
				[System.Windows.Forms.SendKeys]::SendWait("^{TAB}")
				Start-Sleep -Milliseconds 10
			}

			if ($closedTabsInWindow.Count -gt 0 -and (Test-LogVerbose)) {
				Write-LogDebug "Closed $($closedTabsInWindow.Count) tab(s) in this window" -Style Success
			}
		}

		return $totalClosedTabs
	}
	catch {
		Write-LogDebug "  Error closing browser tabs => $_" -Style Error
		return 0
	}
}
