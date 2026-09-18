function Test-BrowserWindowOpen {
	<#
	.SYNOPSIS
		Tells whether a window handle still refers to a live, visible window.

	.DESCRIPTION
		The liveness probe Wait-BrowserWindowsClosed polls: a handle counts as open only while
		IsWindow AND IsWindowVisible both hold. A destroyed handle and a hidden window both read
		as closed - browsers hide their window before tearing the process down, and a WM_CLOSE
		that reached its target has done its job at that point.

		The probe itself is Test-WindowVisible in the Window module; this is the browser-side
		name Wait-BrowserWindowsClosed mocks so the wait loop's timing can be tested without a
		compiled user32 wrapper.

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

	return [bool](Test-WindowVisible -Handle $Handle)
}
