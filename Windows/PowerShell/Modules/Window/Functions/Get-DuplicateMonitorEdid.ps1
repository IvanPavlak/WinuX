function Get-DuplicateMonitorEdid {
	<#
	.SYNOPSIS
		Returns EDID codes that are shared by more than one monitor.

	.DESCRIPTION
		FancyZones' applied-layouts.json identifies each monitor by its EDID hardware
		code plus the virtual desktop GUID. When two or more displays are the same model
		they report the same EDID code, so their idempotency keys collide and a single
		key can no longer be mapped back to one physical monitor. Apply-FancyZones uses
		this helper to detect that situation and disable the "already applied" skip so
		every monitor's layout is always (re)applied rather than being false-skipped.

	.PARAMETER DisplayToEdidMap
		A dictionary mapping each display name (e.g., "\\.\DISPLAY1") to its EDID code
		(e.g., "AOCB316"). May be $null or empty.

	.OUTPUTS
		[string[]] The distinct EDID codes that appear for two or more displays. Empty
		when identity is unambiguous (or the map has fewer than two entries).

	.EXAMPLE
		$dups = Get-DuplicateMonitorEdid -DisplayToEdidMap @{ '\\.\DISPLAY1' = 'AOCB316'; '\\.\DISPLAY2' = 'AOCB316' }
		# $dups -> @('AOCB316')
	#>
	[CmdletBinding()]
	[OutputType([string[]])]
	param(
		[Parameter()]
		[AllowNull()]
		[System.Collections.IDictionary]$DisplayToEdidMap
	)

	if (-not $DisplayToEdidMap -or $DisplayToEdidMap.Count -lt 2) {
		return @()
	}

	$counts = @{}
	foreach ($edid in $DisplayToEdidMap.Values) {
		if (-not $edid) { continue }
		$key = "$edid"
		if ($counts.ContainsKey($key)) { $counts[$key]++ } else { $counts[$key] = 1 }
	}

	return @($counts.Keys | Where-Object { $counts[$_] -gt 1 })
}
