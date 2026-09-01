function Get-FancyZonesWindowAssignment {
	<#
	.SYNOPSIS
		Reads FancyZones' own zone-assignment marker for a window.

	.DESCRIPTION
		FancyZones stamps every window IT moved into a zone with the FancyZones_zones window
		property, a zone-index bitmask (zone 0 => 0x1, zone 1 => 0x2, ...). The property is
		how FancyZones itself distinguishes a SNAPPED window - one it assigned, wrote into
		app-zone-history.json for, and will relocate on zone-set and display changes - from a
		window that merely sits at zone-like coordinates. A plain SetWindowPos never sets it,
		and FancyZones' own operations are the only thing that clears it, so the marker
		survives every programmatic move (Reset-Windows included).

		Zero therefore means "not registered with FancyZones", which is exactly the state a
		direct placement leaves behind and the state Invoke-SingleZoneWindowSnap exists to
		avoid. The property name is a PowerToys implementation detail (stable across releases,
		verified against PowerToys 0.100); if a future release renames it, this function reads
		0 for every window and its consumers degrade to snapping without assignment awareness
		rather than failing.

	.PARAMETER WindowHandle
		Handle of the window to inspect.

	.OUTPUTS
		[uint64] zone-index bitmask, or 0 when the window carries no FancyZones assignment
		(or the handle is unreadable).

	.EXAMPLE
		$mask = Get-FancyZonesWindowAssignment -WindowHandle $handle
		if ($mask -eq 0) { "window is only positioned, not snapped" }
	#>
	[CmdletBinding()]
	[OutputType([uint64])]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[IntPtr]$WindowHandle
	)

	if ($WindowHandle -eq [IntPtr]::Zero) { return [uint64]0 }

	try {
		return [uint64][WindowModule.Native]::GetWindowZoneAssignment($WindowHandle)
	}
	catch {
		# Also covers a session whose in-memory native type predates this helper.
		return [uint64]0
	}
}
