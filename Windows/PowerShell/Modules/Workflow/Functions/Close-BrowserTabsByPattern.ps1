function Close-BrowserTabsByPattern {
	<#
    .SYNOPSIS
        Closes all browser tabs matching specific title patterns.

    .DESCRIPTION
        Cycles through all tabs in browser windows and closes tabs whose titles match
        the specified patterns. Supports Chrome, Edge, and Firefox browsers.
        Uses keyboard navigation (Ctrl+Tab, Ctrl+W) to cycle through and close tabs.

        A window whose own title matches is closed directly. Otherwise its tabs are cycled with
        keystrokes, which land in whichever window has focus - so the window is brought to the
        foreground and verified (Confirm-WindowForeground) before EVERY keystroke, and the window
        is left alone the moment that fails. Without that check a Ctrl+W meant for the browser
        closed the terminal tab the command was typed in. The active tab's title is read from
        this exact window (several browser windows share one process) with the window cache
        cleared, and after each keystroke the loop waits for the title to change, so it never
        acts on the title of a tab that is already gone.

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

		$totalClosedTabs = 0

		# Ensure $browserWindows is always an array
		$windowArray = if ($browserWindows -is [array]) { $browserWindows } else { @($browserWindows) }

		# The active tab's title, read from THIS window. Several browser windows share one process,
		# so "the first window of the process" can be another window - even one closed a moment
		# ago. The window list is cached briefly, so it is refreshed before every read.
		$readActiveTitle = {
			param([IntPtr]$WindowHandle)
			Clear-WindowCache
			$liveWindow = @(Get-WindowHandle -ProcessName $ProcessName -ErrorAction SilentlyContinue |
					Where-Object { $_.Handle -eq $WindowHandle })[0]
			if ($liveWindow) { [string]$liveWindow.Title } else { $null }
		}

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
				[void](Close-Window -Handle ([IntPtr]$window.Handle))
				$totalClosedTabs++
				Start-Sleep -Milliseconds 10
				continue
			}

			# If window doesn't match, try tab cycling (for browsers where tabs share the same window)
			$windowHandle = [IntPtr]$window.Handle
			$checkedTitles = @()
			$closedTabsInWindow = @()
			$maxTabs = 30  # Safety limit per window

			for ($i = 0; $i -lt $maxTabs; $i++) {
				$currentTitle = & $readActiveTitle $windowHandle

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

				# If we've already checked this title, we've cycled through all tabs
				if (-not $shouldClose -and $checkedTitles -contains $currentTitle) {
					break
				}

				# Keystrokes go to whichever window has focus. Verified right before each one, so a
				# Ctrl+W can never land in the terminal this command runs in.
				if (-not (Confirm-WindowForeground -WindowHandle $windowHandle)) {
					Write-LogDebug "  Could not keep the browser window in the foreground, leaving its tabs => [$currentTitle]" -Style Warning
					break
				}

				if ($shouldClose) {
					Write-LogDebug "   -> Closing tab => [$currentTitle]" -Style Step

					# Close this tab with Ctrl+W
					[System.Windows.Forms.SendKeys]::SendWait("^w")
					$closedTabsInWindow += $currentTitle
					$totalClosedTabs++
				}
				else {
					$checkedTitles += $currentTitle

					# Move to next tab
					[System.Windows.Forms.SendKeys]::SendWait("^{TAB}")
				}

				# The title follows the switch a moment later. Wait for it, so the next read is the
				# tab that is active now - not the one just closed or left. Two adjacent tabs with
				# the same title simply run out the short budget.
				[void](Wait-Until -TimeoutMs 300 -PollIntervalMs 10 -Condition {
						(& $readActiveTitle $windowHandle) -ne $currentTitle
					})
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
