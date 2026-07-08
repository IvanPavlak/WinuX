function Wait-DesktopSwitch {
	<#
	.SYNOPSIS
		Waits until the active virtual desktop matches a target index.

	.DESCRIPTION
		Polls the current virtual desktop index using the VirtualDesktop module and
		returns once it equals the target index, or $false on timeout. Used by
		Snap-AllWindows to confirm a Switch-Desktop call has actually taken effect
		before snapping windows, instead of relying on a fixed post-switch sleep that
		can race with the asynchronous desktop change. Transient errors raised while a
		switch is in flight are swallowed so polling continues until the timeout.

	.PARAMETER TargetDesktopIndex
		The 0-based virtual desktop index to wait for.

	.PARAMETER TimeoutMs
		Maximum time to poll before giving up. Default is 750ms.

	.PARAMETER PollIntervalMs
		Delay between polls. Default is 10ms. Set to 0 for a tight spin (used by tests).

	.OUTPUTS
		Boolean. $true if the desktop became active within the timeout, otherwise $false.

	.EXAMPLE
		Wait-DesktopSwitch -TargetDesktopIndex 1
		# Returns $true once virtual desktop index 1 is active.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[int]$TargetDesktopIndex,

		[Parameter()]
		[int]$TimeoutMs = 750,

		[Parameter()]
		[int]$PollIntervalMs = 10
	)

	$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
	while ($stopwatch.ElapsedMilliseconds -lt $TimeoutMs) {
		try {
			$currentDesktop = Get-Desktop
			$currentDesktopIndex = Get-DesktopIndex $currentDesktop
			if ($currentDesktopIndex -eq $TargetDesktopIndex) {
				return $true
			}
		}
		catch {
			# Transient RPC/COM errors are expected mid-switch - keep polling until timeout.
		}

		if ($PollIntervalMs -gt 0) {
			Start-Sleep -Milliseconds $PollIntervalMs
		}
	}

	return $false
}
