function Wait-WindowsClosed {
	<#
	.SYNOPSIS
		Waits for windows to disappear and returns the ones that did not.

	.DESCRIPTION
		WM_CLOSE is posted, not sent: it asks a window to close and returns immediately. The window
		may go away in a few milliseconds, or it may put up a save prompt and stay. A caller that
		checks straight away reports windows as refused when they were merely still closing, and one
		that never checks cannot report a refusal at all.

		This polls the live window list until every handle is gone or the timeout expires, and returns
		whatever is still open. An empty result means they all closed. The window cache is invalidated
		before each poll, otherwise the check would keep reading the same pre-close snapshot and every
		window would look like it refused.

		Matching is by handle only. A window that closed and was replaced by a new window of the same
		application is a different window, and this deliberately does not wait for that one.

	.PARAMETER Window
		The windows to wait on. Any object exposing a .Handle works, including the records
		Get-WindowHandle returns. An empty collection returns immediately.

	.PARAMETER TimeoutMilliseconds
		How long to keep polling before giving up and reporting what is left. Defaults to 1500, which
		comfortably covers a normal application close without stalling a teardown behind an
		application that is clearly waiting on the user.

	.PARAMETER PollIntervalMilliseconds
		Delay between polls. Defaults to 250.

	.OUTPUTS
		[object[]] the input windows still open when polling stopped; empty when all closed.

	.EXAMPLE
		$refused = Wait-WindowsClosed -Window $posted
		if ($refused) { "still open: $($refused.Title -join ', ')" }
	#>
	[CmdletBinding()]
	[OutputType([object[]])]
	param(
		# AllowNull because a mandatory parameter otherwise gets an implicit not-null check that
		# rejects a collection containing a null element - which would defeat the null filtering the
		# body does deliberately, and make an incomplete caller-built list a terminating error
		# instead of the harmless thing it is.
		[Parameter(Mandatory = $true, Position = 0)]
		[AllowEmptyCollection()]
		[AllowNull()]
		[object[]]$Window,

		[Parameter()]
		[int]$TimeoutMilliseconds = 1500,

		[Parameter()]
		[int]$PollIntervalMilliseconds = 250
	)

	$pending = @($Window | Where-Object { $_ })

	if ($pending.Count -eq 0) {
		return @()
	}

	$deadline = [datetime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)

	while ($true) {
		Start-Sleep -Milliseconds $PollIntervalMilliseconds

		Clear-WindowCache

		$liveHandles = New-Object 'System.Collections.Generic.HashSet[int64]'
		foreach ($liveWindow in @(Get-WindowHandle -ErrorAction SilentlyContinue)) {
			if (-not $liveWindow) { continue }
			[void]$liveHandles.Add([int64]$liveWindow.Handle)
		}

		$pending = @($pending | Where-Object { $liveHandles.Contains([int64]$_.Handle) })

		if ($pending.Count -eq 0) {
			return @()
		}

		if ([datetime]::UtcNow -ge $deadline) {
			return $pending
		}
	}
}
