function Repair-RpcServer {
	<#
	.SYNOPSIS
		Attempts to recover an unresponsive RPC server before resuming workspace operations.

	.DESCRIPTION
		Used when Test-RpcServerHealth -Probe indicates the RPC endpoint is hung
		(service is Running but COM roundtrips fail with 0x800706BA / 0x800706BE).
		Runs a bounded retry loop (default 5 attempts with exponential backoff
		starting at 500 ms, capped at 8 s) where each attempt:

		  1. Attempts Restart-Service RpcSs / DcomLaunch / RpcEptMapper -Force.
		     RpcSs is normally marked non-stoppable; this call typically fails on a
		     running system, but is attempted because in some cases (e.g. when the
		     service has actually entered an inconsistent state) the SCM will honor it.
		  2. Forcibly terminates known RPC-consumer state that we control - PowerToys
		     and the VirtualDesktop COM proxies cached in this PowerShell session - so
		     the next probe re-establishes fresh COM connections.
		  3. Waits the current backoff window and re-runs Test-RpcServerHealth -Probe.

		Returns $true as soon as the probe reports healthy. Returns $false only after
		all attempts are exhausted, in which case callers should continue with their
		normal flow (downstream commands may still succeed or trigger their own
		recovery) rather than aborting with a reboot message.

	.PARAMETER ProbeTimeoutMs
		Hard timeout for each post-recovery RPC probe. Default is 2500.

	.PARAMETER MaxAttempts
		Maximum number of recovery attempts in the retry loop. Default is 5.

	.PARAMETER InitialBackoffMs
		Initial delay between attempts. Doubles each attempt up to an 8 s cap.
		Default is 500.

	.EXAMPLE
		if (-not (Test-RpcServerHealth -Probe)) {
			[void](Repair-RpcServer)
		}

	.NOTES
		Restarting RpcSs almost always requires a reboot on a live Windows session
		because critical services depend on it. This function intentionally treats
		the service restart as best-effort and relies on consumer-side cleanup
		(PowerToys, COM proxy disposal) as the primary recovery mechanism, which
		does NOT require admin.
	#>
	[CmdletBinding()]
	param (
		[Parameter()]
		[int]$ProbeTimeoutMs = 2500,

		[Parameter()]
		[int]$MaxAttempts = 5,

		[Parameter()]
		[int]$InitialBackoffMs = 500
	)

	Write-LogTitle "Repairing RPC Server"

	$isAdmin = $false
	try {
		$currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
		$principal = New-Object System.Security.Principal.WindowsPrincipal($currentIdentity)
		$isAdmin = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
	}
	catch {
		$isAdmin = $false
	}

	$servicesToRestart = @('RpcSs', 'DcomLaunch', 'RpcEptMapper')
	$backoffMs = [Math]::Max(100, $InitialBackoffMs)

	for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
		Write-LogStep "  → Recovery attempt $attempt / $MaxAttempts" -NoLeadingNewline

		# Step 1+2: Attempt service restarts. Requires admin and will usually fail on
		# RpcSs (non-stoppable on a running system) but is attempted as the user-requested
		# first-line recovery. -ErrorAction Stop is caught per-service to keep the loop alive.
		if ($isAdmin) {
			foreach ($serviceName in $servicesToRestart) {
				try {
					Write-LogDebug "    → Restart-Service $serviceName -Force" -Style Step
					Restart-Service -Name $serviceName -Force -ErrorAction Stop
					Write-LogDebug "      ✓ $serviceName restarted" -Style Success
				}
				catch {
					Write-LogDebug "      ⚠ Could not restart $serviceName => $($_.Exception.Message)" -Style Warning
				}
			}
		}
		elseif ((Test-LogVerbose) -and $attempt -eq 1) {
			Write-LogDebug "    ⚠ Not elevated - skipping Restart-Service for RPC services" -Style Warning
		}

		# Step 3: Tear down consumer-side state so the next probe forms fresh COM
		# connections. This is the recovery mechanism that actually works without admin.
		try {
			$powerToysProcs = Get-Process -Name "PowerToys*" -ErrorAction SilentlyContinue
			if ($powerToysProcs) {
				Write-LogDebug "    → Stopping PowerToys processes to drop stale COM clients" -Style Step
				$powerToysProcs | Stop-Process -Force -ErrorAction SilentlyContinue
			}
		}
		catch {
			# Best-effort
		}

		# Drop cached VirtualDesktop module COM references in this session
		try {
			$vdModule = Get-Module -Name VirtualDesktop -ErrorAction SilentlyContinue
			if ($vdModule) {
				Remove-Module -Name VirtualDesktop -Force -ErrorAction SilentlyContinue
			}
		}
		catch {
			# Best-effort
		}

		# Let DCOM settle (exponential backoff between attempts so we don't hammer
		# the SCM while the endpoint is mid-recovery).
		Start-Sleep -Milliseconds $backoffMs

		# Step 4: Re-probe
		$healthy = Test-RpcServerHealth -Probe -ProbeTimeoutMs $ProbeTimeoutMs
		if ($healthy) {
			Write-LogSuccess "RPC server recovered (attempt $attempt)."
			return $true
		}

		if ($attempt -lt $MaxAttempts) {
			Write-Host -ForegroundColor DarkYellow "    ⚠ Still unresponsive - retrying after ${backoffMs}ms..."
			$backoffMs = [Math]::Min(8000, $backoffMs * 2)
		}
	}

	Write-LogWarning "RPC server did not recover after $MaxAttempts attempts - continuing anyway, downstream commands may retry."
	if (-not $isAdmin) {
		Write-Host -ForegroundColor DarkYellow "   (Recovery was run without admin - an elevated shell may have better odds.)"
	}

	return $false
}
