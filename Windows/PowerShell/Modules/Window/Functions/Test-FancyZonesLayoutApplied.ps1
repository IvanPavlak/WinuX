function Test-FancyZonesLayoutApplied {
	<#
	.SYNOPSIS
		Tests whether FancyZones has an applied layout for a virtual desktop.

	.DESCRIPTION
		Queries the applied FancyZones layout state (via Get-AppliedFancyZonesState) to
		determine whether a zone layout is currently applied for the given virtual desktop,
		optionally narrowed to a specific monitor. Snapping windows when no layout is applied
		can drop a window into a stale or wrong zone grid; this check lets callers detect that
		condition before injecting snap input. Returns $false when the applied-layouts state
		cannot be read, so callers can treat an unknown state as "not confirmed".

	.PARAMETER VirtualDesktopGuid
		The virtual desktop GUID to check. Accepted with or without surrounding braces and in
		any case; it is normalized to the "{UPPER-CASE}" form used by FancyZones.

	.PARAMETER MonitorId
		Optional FancyZones monitor identifier (EDID code or display path). When provided, the
		check requires a layout applied to that specific monitor on the desktop. When omitted,
		any monitor with an applied layout on the desktop satisfies the check.

	.OUTPUTS
		Boolean. $true when a matching applied layout exists, otherwise $false.

	.EXAMPLE
		Test-FancyZonesLayoutApplied -VirtualDesktopGuid "{CF6C2856-0D59-466D-AA7F-E6DF85C6034C}"

	.EXAMPLE
		Test-FancyZonesLayoutApplied -VirtualDesktopGuid $guid -MonitorId "LEN8ABC"
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param(
		[Parameter(Mandatory = $true)]
		[string]$VirtualDesktopGuid,

		[Parameter()]
		[string]$MonitorId
	)

	$state = Get-AppliedFancyZonesState
	if (-not $state -or $state.Count -eq 0) {
		# Unknown state - cannot confirm a layout is applied.
		return $false
	}

	# Normalize the GUID to the "{UPPER-CASE}" form used as the lookup key suffix.
	$normalizedGuid = $VirtualDesktopGuid.ToUpper()
	if (-not $normalizedGuid.StartsWith('{')) {
		$normalizedGuid = "{$normalizedGuid}"
	}

	if ($MonitorId) {
		$key = "$($MonitorId.ToUpper()):$normalizedGuid"
		return $state.ContainsKey($key)
	}

	foreach ($key in $state.Keys) {
		if ($key.EndsWith(":$normalizedGuid")) {
			return $true
		}
	}

	return $false
}
