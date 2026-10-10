function Stop-RunConditionSampler {
	<#
	.SYNOPSIS
		Stops a sampler started by Start-RunConditionSampler and returns its samples.

	.DESCRIPTION
		Signals the background loop, waits up to TimeoutMs for it to finish its current sample,
		and disposes the runspace. Never throws; a sampler that failed simply returns what it
		collected (possibly nothing).

	.PARAMETER Sampler
		The handle Start-RunConditionSampler returned.

	.PARAMETER TimeoutMs
		How long to wait for the loop to exit. Defaults to 3000.

	.OUTPUTS
		The samples, oldest first, one per pipeline object.

	.EXAMPLE
		$samples = @(Stop-RunConditionSampler -Sampler $sampler)
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[AllowNull()]
		[object]$Sampler,

		[Parameter()]
		[int]$TimeoutMs = 3000
	)

	if (-not $Sampler -or -not $Sampler.State) { return }

	$Sampler.State.Stop = $true
	try {
		if ($Sampler.AsyncResult) { $null = $Sampler.AsyncResult.AsyncWaitHandle.WaitOne($TimeoutMs) }
	}
	catch { }
	try {
		if ($Sampler.PowerShell) {
			if ($Sampler.AsyncResult -and -not $Sampler.AsyncResult.IsCompleted) { $Sampler.PowerShell.Stop() }
			$Sampler.PowerShell.Dispose()
		}
	}
	catch { }

	return $Sampler.State.Samples.ToArray()
}
