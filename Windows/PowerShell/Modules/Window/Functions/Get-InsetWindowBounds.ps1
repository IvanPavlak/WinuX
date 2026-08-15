# How far the pre-snap window is pushed off the target zone's exact center, in pixels.
# Lives next to its only consumer (and at file scope, so it is defined both inside the
# module and when this file is dot-sourced on its own) - see the .DESCRIPTION below for
# why a non-zero value is load-bearing rather than cosmetic.
$script:InsetCenterBiasPx = 2

function Get-InsetWindowBounds {
	<#
	.SYNOPSIS
		Calculates inset window bounds centered within a target zone.

	.DESCRIPTION
		Returns the adjusted bounds used before FancyZones snapping. The inset window
		sits inside the target zone so the snap target remains unambiguous, deliberately
		offset by WindowModuleTolerances.InsetCenterBiasPx instead of being perfectly
		centered on the zone.

		The bias is load-bearing. FancyZones' Win+Arrow is a RELATIVE move: it first
		decides which zone the window is currently in, then moves it to the neighbouring
		zone in that direction (across monitors, since moveWindowAcrossMonitors is on).
		The workspace flow depends on the opposite reading - "this window belongs to no
		zone, snap it into the one it is sitting in" - which FancyZones only takes while
		it does not recognise the window as already zoned. A window centered exactly on
		its zone is recognised, and every Win+Arrow then throws it into the neighbouring
		zone, leaving the expensive shift-drag fallback to do all the work.

		Historically the zone rectangles fed in here were a couple of pixels off the real
		FancyZones geometry, so "centered on the computed zone" happened to land the
		window off-center in the ACTUAL zone and the snap worked. Now that the zone math
		reproduces FancyZones exactly, that accident is gone and the offset has to be
		deliberate.

	.PARAMETER TargetX
		The target zone X coordinate.

	.PARAMETER TargetY
		The target zone Y coordinate.

	.PARAMETER TargetWidth
		The target zone width.

	.PARAMETER TargetHeight
		The target zone height.

	.PARAMETER InsetPercent
		The inset percentage applied on each side. Default is 0.05 (5 percent).
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[int]$TargetX,

		[Parameter(Mandatory = $true)]
		[int]$TargetY,

		[Parameter(Mandatory = $true)]
		[int]$TargetWidth,

		[Parameter(Mandatory = $true)]
		[int]$TargetHeight,

		[Parameter()]
		[ValidateRange(0.0, 0.49)]
		[double]$InsetPercent = 0.05
	)

	$zoneCenterX = $TargetX + ($TargetWidth / 2)
	$zoneCenterY = $TargetY + ($TargetHeight / 2)

	$adjustedWidth = [Math]::Max(1, [int]($TargetWidth * (1 - 2 * $InsetPercent)))
	$adjustedHeight = [Math]::Max(1, [int]($TargetHeight * (1 - 2 * $InsetPercent)))
	$adjustedX = [int]($zoneCenterX - ($adjustedWidth / 2)) + $script:InsetCenterBiasPx
	$adjustedY = [int]($zoneCenterY - ($adjustedHeight / 2)) + $script:InsetCenterBiasPx

	return [PSCustomObject]@{
		TargetX        = $TargetX
		TargetY        = $TargetY
		TargetWidth    = $TargetWidth
		TargetHeight   = $TargetHeight
		InsetPercent   = $InsetPercent
		ZoneCenterX    = $zoneCenterX
		ZoneCenterY    = $zoneCenterY
		AdjustedX      = $adjustedX
		AdjustedY      = $adjustedY
		AdjustedWidth  = $adjustedWidth
		AdjustedHeight = $adjustedHeight
		AdjustedRight  = $adjustedX + $adjustedWidth
		AdjustedBottom = $adjustedY + $adjustedHeight
	}
}
