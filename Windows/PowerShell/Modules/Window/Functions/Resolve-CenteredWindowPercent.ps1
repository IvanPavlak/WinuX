function Resolve-CenteredWindowPercent {
	<#
	.SYNOPSIS
		Resolves Center-Windows width/height percentages from a target pixel size.

	.DESCRIPTION
		Computes the width and height percentages needed to render a window at a fixed
		on-screen pixel size within a monitor's work area, then clamps them to the
		supplied [Min, Max] bounds and finally to Center-Windows' own [10, 100] range.

		This lets a caller (Kill-All) keep a terminal at roughly the same PHYSICAL size
		across displays: on a large monitor the computed percentage is small, on a small
		laptop panel it rises automatically (until the Max clamp), so the same target px
		maps to a comfortably sized window everywhere.

		The result is DPI-consistent: the target and the work-area dimensions come from
		the same Get-MonitorInfo coordinate space, so the computed fraction is correct
		regardless of the host process's DPI awareness.

	.PARAMETER WorkAreaWidth
		The target monitor's work-area width in pixels (e.g. Get-MonitorInfo WorkAreaWidth).

	.PARAMETER WorkAreaHeight
		The target monitor's work-area height in pixels (e.g. Get-MonitorInfo WorkAreaHeight).

	.PARAMETER TargetWidthPx
		The desired on-screen window width in pixels.

	.PARAMETER TargetHeightPx
		The desired on-screen window height in pixels.

	.PARAMETER MinWidthPercent
		Lower clamp for the resolved width percentage.

	.PARAMETER MaxWidthPercent
		Upper clamp for the resolved width percentage.

	.PARAMETER MinHeightPercent
		Lower clamp for the resolved height percentage.

	.PARAMETER MaxHeightPercent
		Upper clamp for the resolved height percentage.

	.EXAMPLE
		Resolve-CenteredWindowPercent -WorkAreaWidth 3440 -WorkAreaHeight 1400 `
			-TargetWidthPx 1376 -TargetHeightPx 700 `
			-MinWidthPercent 25 -MaxWidthPercent 72 -MinHeightPercent 35 -MaxHeightPercent 75
		# => @{ WidthPercent = 40; HeightPercent = 50 } (ultrawide, unchanged)

	.EXAMPLE
		Resolve-CenteredWindowPercent -WorkAreaWidth 1920 -WorkAreaHeight 1040 `
			-TargetWidthPx 1376 -TargetHeightPx 700 `
			-MinWidthPercent 25 -MaxWidthPercent 72 -MinHeightPercent 35 -MaxHeightPercent 75
		# => @{ WidthPercent = 72; HeightPercent = 67 } (laptop panel, larger fraction)
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[int]$WorkAreaWidth,

		[Parameter(Mandatory = $true)]
		[int]$WorkAreaHeight,

		[Parameter(Mandatory = $true)]
		[int]$TargetWidthPx,

		[Parameter(Mandatory = $true)]
		[int]$TargetHeightPx,

		[Parameter(Mandatory = $true)]
		[int]$MinWidthPercent,

		[Parameter(Mandatory = $true)]
		[int]$MaxWidthPercent,

		[Parameter(Mandatory = $true)]
		[int]$MinHeightPercent,

		[Parameter(Mandatory = $true)]
		[int]$MaxHeightPercent
	)

	# Clamp a value to [min, max] and then hard-clamp to Center-Windows' [10, 100]
	# ValidateRange so a misconfigured Min/Max can never throw at the call site.
	$clamp = {
		param($value, $min, $max)
		$value = [Math]::Max($min, [Math]::Min($max, $value))
		return [Math]::Max(10, [Math]::Min(100, $value))
	}

	# Degenerate work area or target: fall back to the Max clamp (closest to the
	# caller's legacy fixed percentage) rather than dividing by zero.
	if ($WorkAreaWidth -le 0 -or $TargetWidthPx -le 0) {
		$widthPercent = & $clamp $MaxWidthPercent $MinWidthPercent $MaxWidthPercent
	}
	else {
		$rawWidth = [int][Math]::Round($TargetWidthPx / $WorkAreaWidth * 100)
		$widthPercent = & $clamp $rawWidth $MinWidthPercent $MaxWidthPercent
	}

	if ($WorkAreaHeight -le 0 -or $TargetHeightPx -le 0) {
		$heightPercent = & $clamp $MaxHeightPercent $MinHeightPercent $MaxHeightPercent
	}
	else {
		$rawHeight = [int][Math]::Round($TargetHeightPx / $WorkAreaHeight * 100)
		$heightPercent = & $clamp $rawHeight $MinHeightPercent $MaxHeightPercent
	}

	return [PSCustomObject]@{
		WidthPercent  = $widthPercent
		HeightPercent = $heightPercent
	}
}
