function Test-SmallPrimaryDisplay {
	<#
	.SYNOPSIS
		Tests whether the display that is currently primary is laptop-class.

	.DESCRIPTION
		One shared answer to "am I on the small screen right now?" - the question every
		display-shaped setting has to ask before it can pick a sensible size.

		The machine type cannot answer it. A laptop reports the same machine type whether it
		is sitting on its own panel or docked to a large external monitor, so a per-machine
		value that is right undocked is wrong docked (and vice versa). Measuring the LIVE
		primary display is what separates the two.

		"Laptop-class" is a width of at most MaxWidthPx (3000 px by default): 1920x1080 and
		2560x1440 panels are in, a 3440x1440 ultrawide and a 4K desktop monitor are out. The
		primary display is measured because that is where the window actually lands; when no
		display reports itself primary the first enumerated one is used, and with no displays
		at all the answer is $false (never assume small).

		Consumers: Get-LayoutMachineType (SmallDisplayMachineType rule) and
		Resolve-DisplayAwareProfile (the SmallDisplay row of the display-aware config
		sections). Both used to inline this check; sharing it keeps the threshold in one
		place, so the laptop cannot start behaving as small for one of them and large for
		the other.

	.PARAMETER MonitorInfo
		Monitor records as returned by Get-MonitorInfo. Pass a snapshot the caller already
		holds to avoid re-querying. When omitted, monitors are fetched via Get-MonitorInfo.

	.PARAMETER MaxWidthPx
		Inclusive upper bound, in pixels, for a display to count as laptop-class.
		Default is 3000.

	.OUTPUTS
		[bool] True when the primary display is at most MaxWidthPx wide.

	.EXAMPLE
		Test-SmallPrimaryDisplay
		# True on a 1920x1080 laptop panel, False on a 3440x1440 ultrawide

	.EXAMPLE
		Test-SmallPrimaryDisplay -MonitorInfo $cachedMonitorInfo
		# Reuses a monitor snapshot the caller already captured

	.EXAMPLE
		Test-SmallPrimaryDisplay -MaxWidthPx 2000
		# Narrows "small" to 1080p-class panels only
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param (
		[Parameter()]
		[object[]]$MonitorInfo,

		[Parameter()]
		[int]$MaxWidthPx = 3000
	)

	$monitors = if ($PSBoundParameters.ContainsKey('MonitorInfo')) { $MonitorInfo } else { Get-MonitorInfo -Quiet }
	if (-not $monitors) {
		return $false
	}

	$primaryMonitor = $monitors | Where-Object { $_.IsPrimary } | Select-Object -First 1
	if (-not $primaryMonitor) {
		$primaryMonitor = $monitors | Select-Object -First 1
	}

	if (-not $primaryMonitor) {
		return $false
	}

	$isSmall = ($primaryMonitor.Width -le $MaxWidthPx)
	if ($isSmall) {
		Write-LogDebug " Detected small display ($($primaryMonitor.Width)x$($primaryMonitor.Height)) - at or below the $MaxWidthPx px laptop-class threshold" -Style Warning
	}

	return $isSmall
}
