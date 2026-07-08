function Get-NextAvailableDesktopIndex {
	<#
	.SYNOPSIS
		Gets the index of the next available virtual desktop (one to the right of all existing desktops).

	.DESCRIPTION
		Returns the 0-based index of the first desktop position after all existing desktops.
		This is useful when you want to open a new workspace on a separate set of virtual desktops
		without disturbing the current workspace.

	.EXAMPLE
		# If there are 2 desktops (0 and 1), returns 2
		$nextIndex = Get-NextAvailableDesktopIndex

	#>
	[CmdletBinding()]
	param ()

	try {
		# Import VirtualDesktop module if not loaded
		$moduleAvailable = Get-Module -ListAvailable -Name VirtualDesktop
		if (-not $moduleAvailable) {
			Write-Warning "VirtualDesktop module not found"
			return 0
		}

		if (-not (Get-Module -Name VirtualDesktop)) {
			Import-Module VirtualDesktop -ErrorAction Stop -WarningAction SilentlyContinue
		}

		$desktops = Get-DesktopList
		$currentCount = ($desktops | Measure-Object).Count

		Write-LogDebug "[Get-NextAvailableDesktopIndex]"
		Write-LogDebug " Current desktop count => $currentCount" -Style Step
		Write-LogDebug " Next available index => $currentCount (0-based)" -Style Success

		return $currentCount
	}
	catch {
		if (Test-LogVerbose) {
			Write-Warning "Failed to get desktop count: $_"
		}
		return 0
	}
}
