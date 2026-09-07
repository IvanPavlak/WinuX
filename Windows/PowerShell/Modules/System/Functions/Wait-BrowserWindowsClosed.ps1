function Wait-BrowserWindowsClosed {
	<#
	.SYNOPSIS
		Waits for browser windows that were sent WM_CLOSE to actually disappear.

	.DESCRIPTION
		Close-BrowserWindows POSTS WM_CLOSE, which is asynchronous: the call returns before the
		browser has even seen the message, let alone finished shutting down. Terminate-AllBrowserProcesses
		used to report success at that point, so a window that stayed open - a "close all tabs?"
		or beforeunload dialog waiting for an answer, a download-in-progress prompt, a browser
		that had not processed the message yet - was never noticed.

		This polls the supplied handles until none of them is a live, visible window any more, or
		the timeout expires, and returns the windows still standing so the caller can retry or
		report them. A destroyed handle (IsWindow false) and a hidden one (a browser hides its
		window before tearing the process down) both count as closed.

	.PARAMETER Windows
		Window objects with a Handle property, as returned by Get-BrowserWindowsByTarget.

	.PARAMETER TimeoutMs
		How long to wait for every window to go. Default 4000 ms - a browser with many tabs
		needs a second or two to save its session and exit.

	.PARAMETER PollIntervalMs
		Delay between checks. Default 100 ms.

	.OUTPUTS
		The subset of Windows still alive and visible when the wait ended; empty when all closed.

	.EXAMPLE
		$survivors = Wait-BrowserWindowsClosed -Windows $windowsToClose
		if ($survivors) { Close-BrowserWindows -WindowsToClose $survivors }
	#>
	[CmdletBinding()]
	[OutputType([object[]])]
	param(
		[Parameter()]
		[object[]]$Windows,

		[Parameter()]
		[int]$TimeoutMs = 4000,

		[Parameter()]
		[int]$PollIntervalMs = 100
	)

	$remaining = @($Windows | Where-Object { $null -ne $_ })
	if ($remaining.Count -eq 0) {
		return @()
	}

	$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
	while ($true) {
		$remaining = @($remaining | Where-Object { Test-BrowserWindowOpen -Handle $_.Handle })

		if ($remaining.Count -eq 0 -or $stopwatch.ElapsedMilliseconds -ge $TimeoutMs) {
			break
		}

		Start-Sleep -Milliseconds $PollIntervalMs
	}

	return $remaining
}
