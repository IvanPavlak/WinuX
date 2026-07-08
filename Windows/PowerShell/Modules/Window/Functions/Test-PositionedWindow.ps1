function Test-PositionedWindow {
	<#
	.SYNOPSIS
		Tests whether a window handle is tracked as positioned.

	.DESCRIPTION
		Checks if a window handle has been registered as positioned by Set-WindowLayouts.
		Returns $true if the window was positioned, $false otherwise.

	.PARAMETER WindowHandle
		The IntPtr handle of the window to check.

	.OUTPUTS
		Boolean indicating whether the window is tracked as positioned.

	.EXAMPLE
		if (Test-PositionedWindow -WindowHandle $window.Handle) {
			# Window was positioned by Set-WindowLayouts
		}
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[IntPtr]$WindowHandle
	)

	if (-not $script:PositionedWindowHandles) {
		return $false
	}

	# Check if any tracked window state has this handle
	foreach ($windowState in $script:PositionedWindowHandles) {
		if ($windowState.Handle -eq $WindowHandle) {
			return $true
		}
	}

	return $false
}
