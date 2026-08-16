function Resolve-CenterTerminalSizing {
	<#
	.SYNOPSIS
		Resolves the CenterTerminalSizing block that applies to the current display.

	.DESCRIPTION
		CenterTerminalSizing accepts two shapes, and this returns the pixel-target block for
		whichever one is configured:

		  - FLAT (legacy): the section holds TargetWidthPx directly. It is returned as-is -
		    one target for every machine, which is all most setups need since the target is
		    already converted to per-display percentages at run time by
		    Resolve-CenteredWindowPercent.
		  - KEYED: the section holds rows (SmallDisplay / machine type / Default), resolved by
		    Resolve-DisplayAwareProfile. This exists to TUNE the target per machine - a
		    physically small panel may want a smaller terminal than the percentages alone
		    would give it.

		The flat check runs first and wins outright. That is what makes the hybrid case
		correct: Configuration.local.psd1 deep-merges over the base, so a user who keeps the
		old flat override on top of a keyed base ends up with TargetWidthPx and rows in the
		same hashtable. Their explicit override is the one they edited, so it wins.

		A keyed row is only accepted when it is a hashtable carrying TargetWidthPx; anything
		else resolves to $null so Center-Terminal falls back to its own defaults rather than
		handing junk to Resolve-CenteredWindowPercent.

	.PARAMETER Section
		The CenterTerminalSizing section, in either shape. Null or empty resolves to $null.

	.PARAMETER MonitorInfo
		Monitor records as returned by Get-MonitorInfo, forwarded to the row resolver so the
		caller's snapshot is reused instead of re-queried.

	.OUTPUTS
		[hashtable] The sizing block to use, or $null when none applies.

	.EXAMPLE
		Resolve-CenterTerminalSizing -Section $global:Configuration.CenterTerminalSizing -MonitorInfo $monitors
		# The Default row's block on the ultrawide, the SmallDisplay row's block on a laptop panel

	.EXAMPLE
		Resolve-CenterTerminalSizing -Section @{ TargetWidthPx = 1376; TargetHeightPx = 700 }
		# Legacy flat section, returned unchanged
	#>
	[CmdletBinding()]
	[OutputType([hashtable])]
	param (
		[Parameter()]
		[hashtable]$Section,

		[Parameter()]
		[object[]]$MonitorInfo
	)

	if (-not $Section -or $Section.Count -eq 0) {
		return $null
	}

	# Flat shape - see .DESCRIPTION for why this is checked before the rows.
	if ($Section.ContainsKey('TargetWidthPx')) {
		return $Section
	}

	$resolveSplat = @{ Section = $Section }
	if ($PSBoundParameters.ContainsKey('MonitorInfo')) {
		$resolveSplat['MonitorInfo'] = $MonitorInfo
	}

	$row = Resolve-DisplayAwareProfile @resolveSplat
	if ($row -is [hashtable] -and $row.ContainsKey('TargetWidthPx')) {
		return $row
	}

	return $null
}
