function Terminate-AllBrowserProcesses {
	<#
	.SYNOPSIS
		Terminates all configured browser processes gracefully.

	.DESCRIPTION
		Iterates over every browser declared in `Configuration.Universal.Browsers`
		(Firefox, Tor, Chrome, Edge, Brave) and posts WM_CLOSE messages to each
		browser's visible top-level windows for graceful shutdown.

		Browser identification is two-staged:
		  1. Process name derived from the configured executable filename
		     (e.g. firefox.exe -> "firefox", chrome.exe -> "chrome").
		  2. Window title regex tied to the browser brand - used to attribute a
		     window to a brand for logging when browsers share a process name
		     (Firefox vs. Tor Browser, both "firefox.exe"). It no longer gates
		     which windows are closed: EVERY visible, titled window of a targeted
		     browser process is closed, including the ones without the brand
		     suffix (undocked DevTools, Picture-in-Picture, installed web apps,
		     dialogs) that used to be left standing. A window reachable through
		     two targets is closed once.

		When `-Exclude` is provided, WM_CLOSE is posted only to non-matching
		windows. Excluded windows are kept open. WM_CLOSE is posted per window
		handle (not via SendKeys), so excluded windows are never affected by
		focus-stealing races.

		WM_CLOSE is asynchronous, so the function then WAITS for the windows to
		disappear (Wait-BrowserWindowsClosed, up to a few seconds), posts WM_CLOSE
		once more to any still standing, waits again, and reports the survivors as
		a warning instead of declaring success. Browsers are never force-killed: a
		window that ignores two WM_CLOSE rounds is holding a dialog (unsaved form,
		download in progress, "close all tabs?") that the user has to answer.

	.PARAMETER Exclude
		Array of window title patterns to exclude from termination.
		Supports both wildcard and regex patterns (same format as layout .psd1 files):
		  Wildcard: "*YouTube*", "*Gmail*"
		  Regex: ".*YouTube.*", "(.*Gmail.*|.*Inbox.*)"
		Browser windows whose title matches any of these patterns will be kept
		open. All other browser windows will be closed.

	.EXAMPLE
		Terminate-AllBrowserProcesses

	.EXAMPLE
		Terminate-AllBrowserProcesses -Exclude "*YouTube*"

	.EXAMPLE
		Terminate-AllBrowserProcesses -Exclude "*YouTube*", "*Gmail*"
	#>
	[CmdletBinding()]
	param (
		[Parameter()]
		[string[]]$Exclude
	)

	Write-LogTitle "Terminating All Browser Processes"

	Initialize-Win32BrowserHelperType

	# Resolve browser definitions from Configuration.psd1.
	$browsersConfig = $null
	if ($Configuration -and $Configuration.Universal -and $Configuration.Universal.Browsers) {
		$browsersConfig = $Configuration.Universal.Browsers
	}

	if (-not $browsersConfig) {
		Write-LogDebug " No browsers configured in Configuration.Universal.Browsers!" -Style Warning
		Write-LogSuccess "Terminated all Browser processes successfully!"
		return
	}

	# Build the list of running browsers to act on. Title regexes come from
	# Get-BrowserTitlePattern - the shared map also used by Open-Browser's
	# -Instances counting.
	$browserTargets = @()
	foreach ($browserName in $browsersConfig.Keys) {
		$browserDef = $browsersConfig[$browserName]
		if (-not $browserDef.Exe) {
			continue
		}

		$titlePattern = Get-BrowserTitlePattern -BrowserName $browserName
		if (-not $titlePattern) {
			Write-LogDebug " No window title pattern known for browser [$browserName] - skipping" -Style Warning
			continue
		}

		$processName = [System.IO.Path]::GetFileNameWithoutExtension($browserDef.Exe)
		$processIds = @((Get-Process -Name $processName -ErrorAction SilentlyContinue).Id)
		if (-not $processIds) {
			continue
		}

		$browserTargets += [PSCustomObject]@{
			Name         = $browserName
			ProcessName  = $processName
			ProcessIds   = $processIds
			TitlePattern = $titlePattern
		}
	}

	if (-not $browserTargets) {
		Write-LogDebug " No browser processes found!" -Style Warning
		Write-LogSuccess "Terminated all Browser processes successfully!"
		return
	}

	# Every window WM_CLOSE was posted to, across all browsers, so the wait below can check them
	# in one go. Handles are tracked so a window reached through two targets sharing a process
	# name (Firefox and Tor Browser are both firefox.exe) is closed and counted once.
	$allWindowsToClose = @()
	$seenHandles = [System.Collections.Generic.HashSet[long]]::new()

	foreach ($target in $browserTargets) {
		Write-LogDebug " [$($target.Name)] Found [$(@($target.ProcessIds).Count)] process(es)" -Style Step

		$browserWindows = Get-BrowserWindowsByTarget -TargetPids $target.ProcessIds -TitlePattern $target.TitlePattern

		# Partition windows by exclusion patterns.
		$windowsToClose = @()
		$excludedTitles = @()

		foreach ($window in $browserWindows) {
			if (-not $seenHandles.Add([long]$window.Handle)) {
				continue
			}

			if ($Exclude -and (Test-WindowTitleMatch -WindowTitle $window.Title -Patterns $Exclude)) {
				if ($window.Title -notin $excludedTitles) {
					$excludedTitles += $window.Title
				}
			}
			else {
				$windowsToClose += $window
			}
		}

		if (Test-LogVerbose) {
			if ($excludedTitles.Count -gt 0) {
				Write-LogDebug " Keeping [$($excludedTitles.Count)] excluded [$($target.Name)] window(s)" -Style Warning
				$excludedTitles | ForEach-Object {
					Write-LogDebug "   $_" -Style Warning
				}
			}
			if ($windowsToClose.Count -gt 0) {
				Write-LogDebug " Closing [$($windowsToClose.Count)] [$($target.Name)] window(s)" -Style Step
				$windowsToClose | ForEach-Object {
					Write-LogDebug "   $($_.Title)" -Style Step
				}
			}
		}

		# Post WM_CLOSE per non-excluded window handle. Per-handle and deterministic
		# - does not touch the foreground, so excluded windows are guaranteed safe.
		Close-BrowserWindows -WindowsToClose $windowsToClose
		$allWindowsToClose += $windowsToClose
	}

	# WM_CLOSE is posted, not sent: the call returns before the browser has looked at it. Wait
	# for the windows to actually go, post once more to whatever is left (a message that landed
	# while the browser was busy starting up or saving its session is simply retried), and
	# report what still stands. Nothing here force-kills a browser: a window that survives two
	# WM_CLOSE rounds is holding a dialog that wants an answer - unsaved form data, a download
	# in progress, "close all tabs?" - and killing the process would answer it for the user.
	$survivors = @()
	if ($allWindowsToClose.Count -gt 0) {
		$survivors = @(Wait-BrowserWindowsClosed -Windows $allWindowsToClose -TimeoutMs $script:BrowserCloseWaitMs)

		if ($survivors.Count -gt 0) {
			Write-LogDebug " [$($survivors.Count)] browser window(s) still open after the first WM_CLOSE - posting again" -Style Warning
			Close-BrowserWindows -WindowsToClose $survivors
			$survivors = @(Wait-BrowserWindowsClosed -Windows $survivors -TimeoutMs $script:BrowserCloseRetryWaitMs)
		}
	}

	if ($survivors.Count -gt 0) {
		Write-LogWarning "$($survivors.Count) browser window(s) did not close (a dialog may be waiting for an answer):"
		Write-LogList -Items @($survivors | ForEach-Object { $_.Title })
	}
	else {
		Write-LogSuccess "Terminated all Browser processes successfully!"
	}
}

# How long Terminate-AllBrowserProcesses waits for WM_CLOSE to take effect - the first round,
# then the retry round. Script-scoped so tests can shorten them.
$script:BrowserCloseWaitMs = 4000
$script:BrowserCloseRetryWaitMs = 2000
