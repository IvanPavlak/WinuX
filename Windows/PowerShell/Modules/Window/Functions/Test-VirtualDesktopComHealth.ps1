function Test-VirtualDesktopComHealth {
	<#
	.SYNOPSIS
		Probes this session's VirtualDesktop COM state with a live roundtrip under a timeout.

	.DESCRIPTION
		Runs a cheap VirtualDesktop COM call ([VirtualDesktop.Desktop]::Count) on a
		background runspace inside the CURRENT process and waits up to -TimeoutMs for
		it. Because the probe shares this session's compiled types and cached COM
		proxies, it detects exactly the failure modes that matter to this session:

		- Stale COM proxies after an Explorer restart: the call fails fast with
		  0x800706BA / 0x80010108. A child-process probe (the previous Start-Job
		  design) creates its own fresh proxies and reports healthy in this state,
		  which is precisely wrong for the session that has to do the work.
		- A hung shell endpoint: the call blocks and the timeout flags it.

		When the VirtualDesktop types are not compiled in this process yet, the
		runspace imports the module and calls Get-DesktopCount instead, exercising the
		same COM activation path a first real call would take.

	.PARAMETER TimeoutMs
		Hard timeout for the roundtrip in milliseconds. Default is 5000.

	.OUTPUTS
		PSCustomObject with Healthy (bool), TimedOut (bool), and Error (string or $null).

	.EXAMPLE
		$probe = Test-VirtualDesktopComHealth -TimeoutMs 2500
		if (-not $probe.Healthy) { [void](Reset-VirtualDesktopState) }
	#>
	[CmdletBinding()]
	param (
		[Parameter()]
		[int]$TimeoutMs = 5000
	)

	# The probe runs from source text (not a scriptblock closure) so the runspace has
	# no dependency on this module's state. It reports the innermost exception plus
	# its HRESULT so RPC failures classify reliably even with localized error text.
	$probeScript = @'
try {
	$desktopType = ([System.Management.Automation.PSTypeName]'VirtualDesktop.Desktop').Type

	if ($desktopType) {
		$null = $desktopType.GetProperty('Count', [System.Reflection.BindingFlags]'Public,Static').GetValue($null)
	}
	else {
		Import-Module VirtualDesktop -ErrorAction Stop -WarningAction SilentlyContinue
		$null = Get-DesktopCount -ErrorAction Stop
	}

	[PSCustomObject]@{ Success = $true; Error = $null }
}
catch {
	$exception = $_.Exception
	while ($exception.InnerException) { $exception = $exception.InnerException }
	$hresultText = if ($exception.HResult) { ' (HRESULT 0x{0:X8})' -f $exception.HResult } else { '' }
	[PSCustomObject]@{ Success = $false; Error = "$($exception.Message)$hresultText" }
}
'@

	$powershell = $null
	try {
		$powershell = [PowerShell]::Create()
		[void]$powershell.AddScript($probeScript)
		$asyncResult = $powershell.BeginInvoke()

		if (-not $asyncResult.AsyncWaitHandle.WaitOne($TimeoutMs)) {
			# The COM call is blocked inside the shell. A hard stop cannot interrupt a
			# native RPC call and disposing would block on it too, so the runspace is
			# abandoned to finish (or fail) on its own.
			[void]$powershell.BeginStop($null, $null)
			return [PSCustomObject]@{ Healthy = $false; TimedOut = $true; Error = "probe timed out after ${TimeoutMs}ms" }
		}

		$output = $powershell.EndInvoke($asyncResult)
		$result = if ($output.Count -gt 0) { $output[$output.Count - 1] } else { $null }
		$powershell.Dispose()
		$powershell = $null

		if ($result -and $result.Success) {
			return [PSCustomObject]@{ Healthy = $true; TimedOut = $false; Error = $null }
		}

		$errorText = if ($result) { $result.Error } else { "probe returned no result" }
		return [PSCustomObject]@{ Healthy = $false; TimedOut = $false; Error = $errorText }
	}
	catch {
		if ($powershell) {
			try { $powershell.Dispose() } catch { $null = $_ }
		}
		return [PSCustomObject]@{ Healthy = $false; TimedOut = $false; Error = $_.Exception.Message }
	}
}
