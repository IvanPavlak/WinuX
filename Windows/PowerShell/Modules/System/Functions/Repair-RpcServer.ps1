function Repair-RpcServer {
	<#
	.SYNOPSIS
		Attempts to recover an unresponsive RPC server before resuming workspace operations.

	.DESCRIPTION
		Used when Test-RpcServerHealth -Probe indicates the session's RPC/COM state is
		broken (stale VirtualDesktop proxies after an Explorer restart) or the endpoint
		is hung (service Running but COM roundtrips fail with 0x800706BA / 0x800706BE).
		Runs a bounded retry loop (default 5 attempts with exponential backoff starting
		at 500 ms, capped at 8 s) where each attempt:

		  1. Runs Reset-VirtualDesktopState, which reconnects the session's cached
		     VirtualDesktop COM proxies to the current shell via reflection
		     (Reset-VirtualDesktopComProxy) and reloads the module. This is the
		     recovery that actually repairs the common failure mode and needs no
		     admin rights. When the Window module is unavailable, falls back to
		     unloading the VirtualDesktop module (legacy behavior).
		  2. Attempts Restart-Service RpcSs / DcomLaunch / RpcEptMapper -Force when
		     elevated. RpcSs is normally marked non-stoppable; this call typically
		     fails on a running system, but is attempted because in some cases (e.g.
		     when the service has actually entered an inconsistent state) the SCM
		     will honor it.
		  3. From the second attempt on, forcibly terminates PowerToys processes so
		     their stale COM clients stop wedging the endpoint. This is escalation
		     only - a session whose own proxies were stale recovers in step 1 without
		     collateral damage.
		  4. Waits the current backoff window and re-runs Test-RpcServerHealth -Probe.

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
		the service restart as best-effort and relies on session-side recovery
		(COM proxy reconnection, module reload) as the primary mechanism, which
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

		# Step 1: reconnect this session's VirtualDesktop COM state. This is the
		# recovery that actually works without admin: reflection-based proxy
		# reconnection plus a module reload, verified by an in-process roundtrip.
		if (Get-Command Reset-VirtualDesktopState -ErrorAction SilentlyContinue) {
			Write-LogDebug "    → Reset-VirtualDesktopState (reconnect session COM proxies)" -Style Step
			if (Reset-VirtualDesktopState) {
				Write-LogDebug "      ✓ VirtualDesktop session reconnected" -Style Success
			}
			else {
				Write-LogDebug "      ⚠ VirtualDesktop session still unhealthy after reset" -Style Warning
			}
		}
		else {
			# Legacy fallback: drop the cached module so the next probe at least
			# re-imports it (cannot refresh compiled COM proxies, but preserves the
			# old behavior when the Window module is not loaded).
			try {
				$vdModule = Get-Module -Name VirtualDesktop -ErrorAction SilentlyContinue
				if ($vdModule) {
					Remove-Module -Name VirtualDesktop -Force -ErrorAction SilentlyContinue
				}
			}
			catch {
				# Best-effort
			}
		}

		# Step 2: attempt service restarts. Requires admin and will usually fail on
		# RpcSs (non-stoppable on a running system) but is attempted as first-line
		# recovery for genuinely broken services. -ErrorAction Stop is caught
		# per-service to keep the loop alive.
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

		# Step 3: escalation from the second attempt on - terminate PowerToys so its
		# stale COM clients stop wedging the shell endpoint. Not done on the first
		# attempt: when only this session's proxies were stale, step 1 already fixed
		# it and PowerToys should not be collateral damage.
		if ($attempt -ge 2) {
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
