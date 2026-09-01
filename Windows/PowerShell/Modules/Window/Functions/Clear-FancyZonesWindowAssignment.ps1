function Clear-FancyZonesWindowAssignment {
	<#
	.SYNOPSIS
		Removes FancyZones' zone-assignment marker from a window so a keyboard snap can resolve.

	.DESCRIPTION
		FancyZones' position-based Win+Arrow only considers zones the window is NOT currently
		assigned to (see Get-FancyZonesWindowAssignment for the marker itself). On a one-zone
		grid that makes a stale assignment fatal: the only zone is excluded, so the snap
		no-ops on a single monitor and, with moveWindowAcrossMonitors enabled, throws the
		window to the next monitor's zone instead. Stale assignments are routine, because the
		marker survives every programmatic move - Reset-Windows gathers windows with
		SetWindowPos and leaves each one still assigned to the zone it last occupied.

		Clearing the marker makes the window "new" to FancyZones again, so the next Win+Up
		deterministically snaps it INTO the zone it is sitting in - re-assigning it and
		rewriting its history entry. Only the live marker is touched; the window's existing
		app-zone-history.json entry is left as is (FancyZones rewrites it on the next snap).

	.PARAMETER WindowHandle
		Handle of the window to clear.

	.OUTPUTS
		[bool] $true when a marker was present and removed; $false when there was nothing to
		remove or the window was unreadable.

	.EXAMPLE
		if (Get-FancyZonesWindowAssignment -WindowHandle $handle) {
			$null = Clear-FancyZonesWindowAssignment -WindowHandle $handle
		}
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[IntPtr]$WindowHandle
	)

	if ($WindowHandle -eq [IntPtr]::Zero) { return $false }

	try {
		return [bool][WindowModule.Native]::ClearWindowZoneAssignment($WindowHandle)
	}
	catch {
		# Also covers a session whose in-memory native type predates this helper.
		return $false
	}
}
