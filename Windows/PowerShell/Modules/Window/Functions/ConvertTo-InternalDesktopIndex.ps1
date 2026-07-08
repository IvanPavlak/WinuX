function ConvertTo-InternalDesktopIndex {
	<#
	.SYNOPSIS
		Converts a 1-based layout desktop number to a 0-based VirtualDesktop index.

	.DESCRIPTION
		Layout files express desktops as 1-based numbers (Desktop 1, 2, 3...), while the
		VirtualDesktop module uses 0-based indices. This helper centralizes that conversion
		and applies the workspace `DesktopOffset` so that "alongside" workspaces resolve to
		the correct physical desktop. The formula is `(DesktopNumber - 1) + DesktopOffset`,
		matching the convention already used by Apply-FancyZones and
		Confirm-WorkspaceWindowPositions. Centralizing it removes a class of off-by-one
		races where one function applied the offset and another did not.

	.PARAMETER DesktopNumber
		The 1-based desktop number from a layout entry.

	.PARAMETER DesktopOffset
		The workspace desktop offset (number of pre-existing desktops to the left). Default 0.

	.OUTPUTS
		Int32. The 0-based VirtualDesktop index for the given layout desktop number.

	.EXAMPLE
		ConvertTo-InternalDesktopIndex -DesktopNumber 1
		# Returns 0

	.EXAMPLE
		ConvertTo-InternalDesktopIndex -DesktopNumber 1 -DesktopOffset 2
		# Returns 2 (first workspace desktop sits after two existing desktops)
	#>
	[CmdletBinding()]
	[OutputType([int])]
	param(
		[Parameter(Mandatory = $true)]
		[int]$DesktopNumber,

		[Parameter()]
		[int]$DesktopOffset = 0
	)

	return ($DesktopNumber - 1) + $DesktopOffset
}
