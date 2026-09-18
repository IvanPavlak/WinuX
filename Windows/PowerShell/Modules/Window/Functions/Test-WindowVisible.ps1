function Test-WindowVisible {
	<#
	.SYNOPSIS
		Tells whether a handle still refers to a live, visible window.

	.DESCRIPTION
		A handle counts as visible only while IsWindow AND IsWindowVisible both hold. A destroyed
		handle and a hidden window both read as $false - applications hide their window before
		tearing the process down, and a WM_CLOSE that reached its target has done its job at that
		point. This is the liveness probe a "did it close" wait polls after Close-Window.

	.PARAMETER Handle
		The window handle to probe. A zero handle is never visible.

	.OUTPUTS
		[bool] $true while the window is alive and visible.

	.EXAMPLE
		if (Test-WindowVisible -Handle $window.Handle) { "still open" }
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param(
		[Parameter(Mandatory = $true)]
		[AllowNull()]
		[IntPtr]$Handle
	)

	if ($null -eq $Handle -or $Handle -eq [IntPtr]::Zero) {
		return $false
	}

	return [bool][WindowModule.Native]::IsLiveVisibleWindow($Handle)
}
