function Wait-WindowRect {
	<#
	.SYNOPSIS
		Polls a window's rectangle until it matches expected bounds or a time budget elapses.

	.DESCRIPTION
		Repeatedly reads the window rectangle via GetWindowRect and returns as soon as the
		position AND size match the expected bounds within the tolerance. Replaces the
		"fixed sleep, check once" pattern used around FancyZones snap verification: the fixed
		delay both wasted time when the snap landed quickly and produced false failures when
		FancyZones processed the input slower than the delay, escalating to expensive fallbacks
		(shift-drag, workspace rerun). The first check runs immediately, so an already-correct
		window costs a single GetWindowRect call.

	.PARAMETER WindowHandle
		The handle of the window to observe.

	.PARAMETER ExpectedX
		Expected left edge in physical pixels.

	.PARAMETER ExpectedY
		Expected top edge in physical pixels.

	.PARAMETER ExpectedWidth
		Expected window width in physical pixels.

	.PARAMETER ExpectedHeight
		Expected window height in physical pixels.

	.PARAMETER TolerancePx
		Per-edge tolerance in pixels. Defaults to the module's PositionVerificationPx.

	.PARAMETER TimeoutMs
		Maximum time to poll before reporting failure. Default is 300ms.

	.PARAMETER PollIntervalMs
		Delay between polls. Default is 15ms.

	.PARAMETER Clock
		The wait clock (New-WaitClock) to read and sleep through. Defaults to a real one; tests
		hand in a fake.

	.OUTPUTS
		PSCustomObject with:
		- Verified  : $true once the rect matched within the budget
		- X/Y/Width/Height : the last observed bounds ($null when the rect was never readable)
		- ElapsedMs : how long the poll ran

	.EXAMPLE
		$result = Wait-WindowRect -WindowHandle $handle -ExpectedX 0 -ExpectedY 0 -ExpectedWidth 1720 -ExpectedHeight 1440
		if ($result.Verified) { "snapped" }
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[IntPtr]$WindowHandle,

		[Parameter(Mandatory = $true)]
		[int]$ExpectedX,

		[Parameter(Mandatory = $true)]
		[int]$ExpectedY,

		[Parameter(Mandatory = $true)]
		[int]$ExpectedWidth,

		[Parameter(Mandatory = $true)]
		[int]$ExpectedHeight,

		[Parameter()]
		[int]$TolerancePx = $script:WindowModuleTolerances.PositionVerificationPx,

		[Parameter()]
		[int]$TimeoutMs = 300,

		[Parameter()]
		[int]$PollIntervalMs = 15,

		[Parameter()]
		[AllowNull()]
		[object]$Clock
	)

	if ($null -eq $Clock) { $Clock = New-WaitClock }
	$startedAt = $Clock.ElapsedMs()

	# The poll records what it saw in this table rather than in locals: Wait-Until invokes the
	# condition in a child scope, where a plain assignment would be lost, while a property set
	# on a shared object is not.
	$seen = @{ X = $null; Y = $null; Width = $null; Height = $null; Unreadable = $false }

	$matched = Wait-Until -TimeoutMs $TimeoutMs -PollIntervalMs $PollIntervalMs -Clock $Clock -Condition {
		$rect = New-Object WindowModule.RECT
		if (-not [WindowModule.Native]::GetWindowRect($WindowHandle, [ref]$rect)) {
			# Handle is no longer readable (window closed/recreated) - polling cannot succeed, so
			# the wait ends now; the flag turns this early exit back into an unverified result.
			$seen.Unreadable = $true
			return $true
		}

		$seen.X = $rect.Left
		$seen.Y = $rect.Top
		$seen.Width = $rect.Right - $rect.Left
		$seen.Height = $rect.Bottom - $rect.Top

		return (([Math]::Abs($seen.X - $ExpectedX) -le $TolerancePx) -and
			([Math]::Abs($seen.Y - $ExpectedY) -le $TolerancePx) -and
			([Math]::Abs($seen.Width - $ExpectedWidth) -le $TolerancePx) -and
			([Math]::Abs($seen.Height - $ExpectedHeight) -le $TolerancePx))
	}

	return [PSCustomObject]@{
		Verified  = ($matched -and -not $seen.Unreadable)
		X         = $seen.X
		Y         = $seen.Y
		Width     = $seen.Width
		Height    = $seen.Height
		ElapsedMs = ($Clock.ElapsedMs() - $startedAt)
	}
}
