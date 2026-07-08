function Confirm-WindowForeground {
	<#
	.SYNOPSIS
		Acquires and verifies stable foreground focus for a window.

	.DESCRIPTION
		Repeatedly forces the target window to the foreground and verifies the change took
		effect before returning. Focus handoff is asynchronous, so a single
		ForceForegroundWindow call can race with input injection; this helper retries with an
		increasing settle delay and only reports success once GetForegroundWindow confirms the
		window is actually focused. Used by Snap-AllWindows immediately before injecting snap
		hotkeys, and reusable by any flow that must guarantee focus before sending input.

	.PARAMETER WindowHandle
		The handle of the window to bring to the foreground.

	.PARAMETER BaseSettleMs
		Base settle delay in milliseconds after the first focus attempt. Each subsequent
		attempt adds 25ms. The effective delay is never less than 10ms. Default is 10.

	.PARAMETER MaxAttempts
		Maximum number of focus attempts before giving up. Default is 3.

	.OUTPUTS
		Boolean. $true once the window is confirmed foreground, otherwise $false.

	.EXAMPLE
		if (Confirm-WindowForeground -WindowHandle $handle) { [WindowModule.Native]::SendSnapKey($true) }
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[IntPtr]$WindowHandle,

		[Parameter()]
		[int]$BaseSettleMs = 10,

		[Parameter()]
		[int]$MaxAttempts = 3
	)

	for ($focusAttempt = 1; $focusAttempt -le $MaxAttempts; $focusAttempt++) {
		[void][WindowModule.Native]::ForceForegroundWindow($WindowHandle)

		$settleDelay = [Math]::Max(10, $BaseSettleMs + (($focusAttempt - 1) * 25))
		Start-Sleep -Milliseconds $settleDelay

		if ([WindowModule.Native]::GetForegroundWindow() -eq $WindowHandle) {
			return $true
		}
	}

	return $false
}
