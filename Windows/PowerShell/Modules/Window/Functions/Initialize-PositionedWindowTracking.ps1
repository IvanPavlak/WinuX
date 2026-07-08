function Initialize-PositionedWindowTracking {
	<#
	.SYNOPSIS
		Initializes or clears the tracking set for positioned windows.

	.DESCRIPTION
		Creates a module-scoped HashSet to track window handles that have been positioned
		by Set-WindowLayouts. If the HashSet already exists, it will be cleared.
		This allows Snap-AllWindows to only snap windows that were intentionally positioned.

	.EXAMPLE
		Initialize-PositionedWindowTracking
		Initializes the positioned window tracking set.
	#>
	[CmdletBinding()]
	param()

	if (-not $script:PositionedWindowHandles) {
		$script:PositionedWindowHandles = [System.Collections.ArrayList]::new()
	}
	else {
		$script:PositionedWindowHandles.Clear()
	}

	Write-LogDebug " Positioned window tracking initialized!"
}
