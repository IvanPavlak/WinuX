function Get-NextAvailableDesktopIndex {
	<#
	.SYNOPSIS
		Gets the index of the next available virtual desktop (one to the right of all existing desktops).

	.DESCRIPTION
		Returns the 0-based index of the first desktop position after all existing desktops.
		This is useful when you want to open a new workspace on a separate set of virtual desktops
		without disturbing the current workspace.

		Returns $null when the desktop count cannot be determined (VirtualDesktop module
		unavailable or enumeration failed) - never 0, because an alongside caller falling
		back to offset 0 would open the new workspace on top of the existing one. Callers
		must treat $null as "abort the alongside open".

	.EXAMPLE
		# If there are 2 desktops (0 and 1), returns 2
		$nextIndex = Get-NextAvailableDesktopIndex

	#>
	[CmdletBinding()]
	param ()

	try {
		# Use the cached module loader instead of a Get-Module -ListAvailable disk scan per call.
		if (-not (Import-VirtualDesktopModule)) {
			Write-Warning "VirtualDesktop module not found"
			return $null
		}

		$desktops = Get-DesktopList
		$currentCount = ($desktops | Measure-Object).Count

		Write-LogDebug "[Get-NextAvailableDesktopIndex]"
		Write-LogDebug " Current desktop count => $currentCount" -Style Step
		Write-LogDebug " Next available index => $currentCount (0-based)" -Style Success

		return $currentCount
	}
	catch {
		# Never fall back to 0: an alongside caller would lay the new workspace ON TOP of the
		# current one. $null signals "unknown" so the caller can abort instead of clobbering.
		Write-Warning "Failed to get desktop count: $_"
		return $null
	}
}
