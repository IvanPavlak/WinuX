function Set-WindowForeground {
	<#
	.SYNOPSIS
		Asks Windows to bring a window to the foreground, fire and forget.

	.DESCRIPTION
		The plain SetForegroundWindow call through the Window module's native seam. It neither
		retries nor verifies: Windows may refuse the request (the calling process is not in the
		foreground, the target is minimized) and the function reports that as $false, nothing
		more. Flows that must GUARANTEE focus before injecting input use Confirm-WindowForeground,
		which forces the switch with thread attachment and confirms it with GetForegroundWindow.

		Every module used to call the static native method for this directly; routing them here
		keeps WindowModule.Native the one place user32 is declared, and lets a test mock a
		function instead of a compiled type.

	.PARAMETER Handle
		The window handle to activate. A zero handle is refused without calling Windows.

	.OUTPUTS
		[bool] Whatever SetForegroundWindow reported: $true when the request was accepted.

	.EXAMPLE
		[void](Set-WindowForeground -Handle $window.Handle)
		Brings the window forward without caring whether Windows honoured it.
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param(
		[Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
		[AllowNull()]
		[IntPtr]$Handle
	)

	if ($null -eq $Handle -or $Handle -eq [IntPtr]::Zero) {
		return $false
	}

	return [bool][WindowModule.Native]::SetForegroundWindow($Handle)
}
