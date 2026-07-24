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
		[int]$PollIntervalMs = 15
	)

	$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
	$lastX = $null
	$lastY = $null
	$lastWidth = $null
	$lastHeight = $null

	while ($true) {
		$rect = New-Object WindowModule.RECT
		if (-not [WindowModule.Native]::GetWindowRect($WindowHandle, [ref]$rect)) {
			# Handle is no longer readable (window closed/recreated) - polling cannot succeed.
			break
		}

		$lastX = $rect.Left
		$lastY = $rect.Top
		$lastWidth = $rect.Right - $rect.Left
		$lastHeight = $rect.Bottom - $rect.Top

		$matched = ([Math]::Abs($lastX - $ExpectedX) -le $TolerancePx) -and
			([Math]::Abs($lastY - $ExpectedY) -le $TolerancePx) -and
			([Math]::Abs($lastWidth - $ExpectedWidth) -le $TolerancePx) -and
			([Math]::Abs($lastHeight - $ExpectedHeight) -le $TolerancePx)

		if ($matched) {
			return [PSCustomObject]@{
				Verified  = $true
				X         = $lastX
				Y         = $lastY
				Width     = $lastWidth
				Height    = $lastHeight
				ElapsedMs = $stopwatch.ElapsedMilliseconds
			}
		}

		if ($stopwatch.ElapsedMilliseconds -ge $TimeoutMs) {
			break
		}

		if ($PollIntervalMs -gt 0) {
			Start-Sleep -Milliseconds $PollIntervalMs
		}
	}

	return [PSCustomObject]@{
		Verified  = $false
		X         = $lastX
		Y         = $lastY
		Width     = $lastWidth
		Height    = $lastHeight
		ElapsedMs = $stopwatch.ElapsedMilliseconds
	}
}
