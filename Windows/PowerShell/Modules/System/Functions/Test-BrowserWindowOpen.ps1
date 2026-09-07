function Test-BrowserWindowOpen {
	<#
	.SYNOPSIS
		Tells whether a window handle still refers to a live, visible window.

	.DESCRIPTION
		The liveness probe Wait-BrowserWindowsClosed polls: a handle counts as open only while
		IsWindow AND IsWindowVisible both hold. A destroyed handle and a hidden window both read
		as closed - browsers hide their window before tearing the process down, and a WM_CLOSE
		that reached its target has done its job at that point.

		Kept as its own function so the wait loop's timing can be tested without a compiled
		user32 wrapper: the type is created on demand through Initialize-Win32BrowserHelperType.

	.PARAMETER Handle
		The window handle to probe.

	.OUTPUTS
		[bool] $true while the window is alive and visible.

	.EXAMPLE
		if (Test-BrowserWindowOpen -Handle $window.Handle) { "still open" }
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param(
		[Parameter(Mandatory = $true)]
		[IntPtr]$Handle
	)

	if ($Handle -eq [IntPtr]::Zero) {
		return $false
	}

	Initialize-Win32BrowserHelperType

	return [bool]([Win32BrowserHelper]::IsWindow($Handle) -and [Win32BrowserHelper]::IsWindowVisible($Handle))
}
