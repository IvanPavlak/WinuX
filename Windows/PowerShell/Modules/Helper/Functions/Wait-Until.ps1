function Wait-Until {
	<#
	.SYNOPSIS
		Polls a condition until it holds or a time budget runs out.

	.DESCRIPTION
		The one poll loop in the repository. Every "wait for the window to reach its rect", "wait
		for the desktop to show", "wait for the browser windows to go" used to own a stopwatch, a
		sleep and a give-up branch of its own, eight times over, each with its own off-by-one on
		the last check. This is that loop once: check, and if the condition does not hold and the
		budget is not spent, sleep the poll interval and check again. The budget is tested after a
		failed check and before the sleep, so the check after the last sleep always runs and a
		change that lands during it is still seen.

		Time comes from a wait clock (New-WaitClock), so a test hands in a fake whose Sleep
		advances virtual time and asserts the exact poll count without waiting.

	.PARAMETER Condition
		Scriptblock returning a truthy value when the wait is over. It can READ the caller's
		locals, but a plain assignment inside it lands in the scriptblock's own scope and is lost:
		a caller that needs "what was the state when we gave up" (the last rect seen, the windows
		still standing) records it into a hashtable or list created before the wait, which the
		condition mutates in place.

	.PARAMETER TimeoutMs
		The budget. 0 means a single check and no sleeping.

	.PARAMETER PollIntervalMs
		Sleep between checks. Default 10. 0 spins without sleeping (only sensible with a fake clock).

	.PARAMETER SleepFirst
		Sleep one interval before the first check. For waits whose first check is known to be
		premature (a WM_CLOSE was just posted).

	.PARAMETER Clock
		The wait clock to read and sleep through. Defaults to a real one.

	.OUTPUTS
		[bool] $true when the condition held, $false when the budget ran out.

	.EXAMPLE
		$landed = Wait-Until -Condition { (Get-CurrentVirtualDesktopIndex) -eq $Index } -TimeoutMs 750 -PollIntervalMs 10

	.EXAMPLE
		$seen = @{ Rect = $null }
		$verified = Wait-Until -TimeoutMs 300 -PollIntervalMs 15 -Condition {
			$seen.Rect = Get-WindowRect $handle
			Test-RectMatches $seen.Rect $expected
		}
		# $seen.Rect holds the last rect read, verified or not
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[scriptblock]$Condition,

		[Parameter(Mandatory = $true)]
		[ValidateRange(0, 3600000)]
		[int]$TimeoutMs,

		[Parameter()]
		[ValidateRange(0, 60000)]
		[int]$PollIntervalMs = 10,

		[Parameter()]
		[switch]$SleepFirst,

		[Parameter()]
		[AllowNull()]
		[object]$Clock
	)

	if ($null -eq $Clock) { $Clock = New-WaitClock }
	$startedAt = $Clock.ElapsedMs()

	if ($SleepFirst) { $Clock.Sleep($PollIntervalMs) }

	# Check, then decide whether to sleep: the budget is tested AFTER a failed check and BEFORE
	# the sleep, so the check that follows the last sleep always runs and a change that landed
	# during that sleep is seen before giving up.
	while ($true) {
		if (& $Condition) { return $true }
		if (($Clock.ElapsedMs() - $startedAt) -ge $TimeoutMs) { return $false }
		$Clock.Sleep($PollIntervalMs)
	}
}
