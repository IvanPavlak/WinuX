function Get-InsetWindowBounds {
	<#
	.SYNOPSIS
		Calculates inset window bounds centered within a target zone.

	.DESCRIPTION
		Returns the adjusted bounds used before FancyZones snapping. The inset window
		stays centered inside the target zone so the snap target remains unambiguous.

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
	$adjustedX = [int]($zoneCenterX - ($adjustedWidth / 2))
	$adjustedY = [int]($zoneCenterY - ($adjustedHeight / 2))

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
