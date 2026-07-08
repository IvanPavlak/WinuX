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
		  2. Window title regex tied to the browser brand - used to disambiguate
		     browsers that share a process name (Firefox vs. Tor Browser, both
		     "firefox.exe") and to filter out non-window child processes that
		     chromium-based browsers spawn (GPU, renderer, utility, etc.).

		When `-Exclude` is provided, WM_CLOSE is posted only to non-matching
		windows. Excluded windows are kept open. WM_CLOSE is posted per window
		handle (not via SendKeys), so excluded windows are never affected by
		focus-stealing races.

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

	# Title regex used to identify each browser's main top-level windows.
	# Keys must match browser names in Configuration.Universal.Browsers.
	$browserTitlePatterns = @{
		Firefox = "Mozilla Firefox|Firefox Developer Edition|Firefox Nightly"
		Tor     = "Tor Browser"
		Chrome  = "Google Chrome"
		Edge    = "Microsoft.?Edge"
		Brave   = "Brave"
	}

	# Build the list of running browsers to act on.
	$browserTargets = @()
	foreach ($browserName in $browsersConfig.Keys) {
		$browserDef = $browsersConfig[$browserName]
		if (-not $browserDef.Exe) {
			continue
		}

		$titlePattern = $browserTitlePatterns[$browserName]
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

	foreach ($target in $browserTargets) {
		Write-LogDebug " [$($target.Name)] Found [$(@($target.ProcessIds).Count)] process(es)" -Style Step

		$browserWindows = Get-BrowserWindowsByTarget -TargetPids $target.ProcessIds -TitlePattern $target.TitlePattern

		# Partition windows by exclusion patterns.
		$windowsToClose = @()
		$excludedTitles = @()

		foreach ($window in $browserWindows) {
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
	}

	Write-LogSuccess "Terminated all Browser processes successfully!"
}
