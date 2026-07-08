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

		With -Probe, also performs a lightweight live roundtrip against the
		VirtualDesktop COM interface under a timeout. This catches the
		"service is Running but the RPC endpoint is hung" failure mode that
		causes 0x800706BA / 0x800706BE during workspace setup. A service-status
		check alone cannot detect this.

	.PARAMETER ServiceNames
		Array of RPC service names to check. Defaults to @("RpcSs", "DcomLaunch", "RpcEptMapper")

	.PARAMETER Probe
		When specified, runs a live VirtualDesktop COM roundtrip (Get-DesktopList)
		in a background job with a hard timeout. Returns $false if the call hangs,
		throws an RPC error, or exceeds the timeout - even if all services report
		Running.

	.PARAMETER ProbeTimeoutMs
		Hard timeout for the live probe in milliseconds. Default is 5000. The probe
		spins up a Start-Job (child pwsh.exe) and imports VirtualDesktop, which on a
		busy machine (e.g. mid-workspace-launch) can take several seconds before the
		actual COM call runs. Keep this generous to avoid false-positive RPC failure
		detections; the probe is only meant to flag genuinely hung endpoints.

	.EXAMPLE
		Test-RpcServerHealth
		# Returns $true if all RPC services are running, $false otherwise

	.EXAMPLE
		Test-RpcServerHealth -Probe
		# Also verifies the RPC endpoint actually responds (catches hung-but-running state)

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

	# Live roundtrip: run a cheap VirtualDesktop COM call under a timeout in a
	# background job. If the RPC endpoint is hung (Running but not responsive),
	# the job will either throw with an RPC error code or exceed the timeout.
	try {
		$probeJob = Start-Job -ScriptBlock {
			try {
				Import-Module VirtualDesktop -ErrorAction Stop -WarningAction SilentlyContinue
				$null = Get-DesktopList -ErrorAction Stop
				return @{ Success = $true; Error = $null }
			}
			catch {
				return @{ Success = $false; Error = $_.Exception.Message }
			}
		}

		$completed = Wait-Job -Job $probeJob -Timeout ([Math]::Max(1, [int]($ProbeTimeoutMs / 1000)))

		if (-not $completed) {
			Write-LogDebug "  ⚠ RPC probe timed out after ${ProbeTimeoutMs}ms - endpoint appears hung" -Style Warning
			Stop-Job -Job $probeJob -ErrorAction SilentlyContinue
			Remove-Job -Job $probeJob -Force -ErrorAction SilentlyContinue
			return $false
		}

		$result = Receive-Job -Job $probeJob -ErrorAction SilentlyContinue
		Remove-Job -Job $probeJob -Force -ErrorAction SilentlyContinue

		if (-not $result -or -not $result.Success) {
			$errorText = if ($result) { $result.Error } else { "no result" }
			Write-LogDebug "  ⚠ RPC probe call failed => [$errorText]" -Style Warning
			# Detect classic RPC unavailability codes
			if ($errorText -match '0x800706BA|0x800706BE|RPC server is unavailable') {
				return $false
			}
			# Non-RPC failure (e.g. VirtualDesktop module missing) - treat as healthy
			# for RPC purposes so we don't trigger unnecessary service restarts.
			Write-LogDebug "    (non-RPC probe failure - treating RPC as healthy)" -Style Warning
			return $true
		}

		Write-LogDebug "  ✓ RPC live probe succeeded" -Style Success
		return $true
	}
	catch {
		Write-LogDebug "  ⚠ Could not execute RPC probe => $_" -Style Warning
		# Probe infrastructure failure - don't punish RPC for it.
		return $true
	}
}
