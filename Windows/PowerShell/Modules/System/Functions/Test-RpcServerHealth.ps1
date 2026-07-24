function Test-RpcServerHealth {
	<#
	.SYNOPSIS
		Verifies that required RPC services are running and (optionally) responsive.

	.DESCRIPTION
		Tests that all required Remote Procedure Call (RPC) infrastructure services
		are running and available. This is essential for FancyZones, virtual desktop
		management, and other system operations that depend on RPC.

		Required services:
		- RpcSs (Remote Procedure Call - System service)
		- DcomLaunch (DCOM Server Process Launcher)
		- RpcEptMapper (RPC Endpoint Mapper)

		With -Probe, also performs a live VirtualDesktop COM roundtrip against THIS
		session's COM state (via Test-VirtualDesktopComHealth: a background runspace
		in the current process, under a hard timeout). Successful probe results are
		cached briefly (8s) so the several preflights of one workspace open pay for a
		single probe; failures are never cached, so recovery paths always re-verify.
		The live probe catches both failure modes that a service-status check cannot see:

		- Stale session proxies: after an Explorer restart, this session's cached
		  VirtualDesktop COM proxies are permanently disconnected and every call fails
		  with 0x800706BA / 0x80010108 - while a child process would work fine. The
		  probe runs in-process precisely so it fails when the session would fail.
		- Hung endpoint: the service reports Running but COM roundtrips block; the
		  probe times out and reports unhealthy.

	.PARAMETER ServiceNames
		Array of RPC service names to check. Defaults to @("RpcSs", "DcomLaunch", "RpcEptMapper")

	.PARAMETER Probe
		When specified, runs a live in-process VirtualDesktop COM roundtrip with a
		hard timeout. Returns $false if the call fails with an RPC availability error
		or exceeds the timeout - even if all services report Running.

	.PARAMETER ProbeTimeoutMs
		Hard timeout for the live probe in milliseconds. Default is 5000. The probe
		shares this process's already-compiled types, so a healthy roundtrip returns
		in milliseconds; the timeout only bounds the genuinely-hung-endpoint case.

	.EXAMPLE
		Test-RpcServerHealth
		# Returns $true if all RPC services are running, $false otherwise

	.EXAMPLE
		Test-RpcServerHealth -Probe
		# Also verifies this session's VirtualDesktop COM state actually responds

	.NOTES
		Returns $true only if all required services are running (and the probe
		succeeds when -Probe is specified). Used by FancyZones, virtual desktop,
		and layout management functions.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $false)]
		[string[]]$ServiceNames = @("RpcSs", "DcomLaunch", "RpcEptMapper"),

		[Parameter(Mandatory = $false)]
		[switch]$Probe,

		[Parameter(Mandatory = $false)]
		[int]$ProbeTimeoutMs = 5000
	)

	# Cache successful live-probe results briefly: one workspace open runs this preflight
	# several times seconds apart (layout entry, desktop remove/ensure, alongside cleanup),
	# and each probe spins up a fresh runspace (~50-200ms) plus service checks. Failures are
	# NEVER cached, so recovery paths always re-verify against live state.
	if (-not $script:RpcProbeHealthyCache) {
		$script:RpcProbeHealthyCache = @{
			VerifiedAt = [datetime]::MinValue
			TtlSeconds = 8
		}
	}

	if ($Probe) {
		$probeCacheAge = ([datetime]::Now - $script:RpcProbeHealthyCache.VerifiedAt).TotalSeconds
		if ($probeCacheAge -ge 0 -and $probeCacheAge -lt $script:RpcProbeHealthyCache.TtlSeconds) {
			Write-LogDebug "  ✓ RPC live probe verified $([int]$probeCacheAge)s ago - using cached result" -Style Success
			return $true
		}
	}

	foreach ($serviceName in $ServiceNames) {
		try {
			$service = Get-Service -Name $serviceName -ErrorAction Stop
			if ($service.Status -ne 'Running') {
				Write-LogDebug "  ⚠ Required RPC service is not running => [$serviceName] (Status: $($service.Status))" -Style Warning
				return $false
			}
		}
		catch {
			Write-LogDebug "  ⚠ Could not verify required RPC service => [$serviceName]: $_" -Style Warning
			return $false
		}
	}

	if (Test-LogVerbose) {
		if ($Probe) {
			Write-LogDebug "  ✓ Required RPC services are running; checking live endpoint" -Style Success
		}
		else {
			Write-LogDebug "  ✓ All RPC services are running" -Style Success
		}
	}

	if (-not $Probe) {
		return $true
	}

	# Live roundtrip against THIS session's VirtualDesktop COM state. The previous
	# design probed in a Start-Job child process, which creates its own fresh COM
	# proxies - after an Explorer restart it reported healthy while the current
	# session stayed broken, so recovery never engaged for the state that mattered.
	if (-not (Get-Command Test-VirtualDesktopComHealth -ErrorAction SilentlyContinue)) {
		# Probe helper unavailable (Window module not loaded) - service status is all
		# that can be verified here.
		Write-LogDebug "  ⚠ Test-VirtualDesktopComHealth unavailable - skipping live probe" -Style Warning
		return $true
	}

	$probeResult = Test-VirtualDesktopComHealth -TimeoutMs $ProbeTimeoutMs

	if ($probeResult.TimedOut) {
		Write-LogDebug "  ⚠ RPC probe timed out after ${ProbeTimeoutMs}ms - endpoint appears hung" -Style Warning
		return $false
	}

	if ($probeResult.Healthy) {
		Write-LogDebug "  ✓ RPC live probe succeeded" -Style Success
		$script:RpcProbeHealthyCache.VerifiedAt = [datetime]::Now
		return $true
	}

	Write-LogDebug "  ⚠ RPC probe call failed => [$($probeResult.Error)]" -Style Warning

	$isRpcFailure = if (Get-Command Test-RpcUnavailableError -ErrorAction SilentlyContinue) {
		Test-RpcUnavailableError $probeResult.Error
	}
	else {
		$probeResult.Error -match '0x800706BA|0x800706BE|0x80010108|RPC server is unavailable'
	}

	if ($isRpcFailure) {
		return $false
	}

	# Non-RPC failure (e.g. VirtualDesktop module missing) - treat as healthy for RPC
	# purposes so it does not trigger unnecessary recovery.
	Write-LogDebug "    (non-RPC probe failure - treating RPC as healthy)" -Style Warning
	return $true
}
