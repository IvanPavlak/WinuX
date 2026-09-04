function Stop-PowerToysCompletely {
	<#
	.SYNOPSIS
		Stops all PowerToys processes and verifies full shutdown.

	.DESCRIPTION
		Performs a complete PowerToys shutdown sequence that mirrors manual tray exit behavior:
		- Optionally requests graceful shutdown via the main PowerToys window
		- Waits for that graceful exit - only when a close request was actually delivered
		- Force-stops remaining PowerToys processes, waiting on each killed process handle so
		  survivors are counted only once the kills have landed
		- Escalates to taskkill process tree termination as a final fallback

		Returns $true only when no PowerToys-related process remains.

		PowerToys.exe is a tray application and normally has no main window (MainWindowHandle 0),
		so there is nothing to post WM_CLOSE to. The graceful wait therefore runs only after
		CloseMainWindow() reported that a close message was posted; otherwise the function goes
		straight to force termination instead of idling for -MaxGracefulWaitMs on an exit that
		was never requested.

	.PARAMETER PreferGracefulExit
		Attempts graceful PowerToys shutdown before force termination.

	.PARAMETER MaxGracefulWaitMs
		Maximum milliseconds to wait for graceful exit before force termination. Spent only when
		a close request was delivered to a PowerToys main window.

	.EXAMPLE
		Stop-PowerToysCompletely
		Stops all PowerToys processes using force termination when needed.

	.EXAMPLE
		Stop-PowerToysCompletely -PreferGracefulExit
		Requests graceful tray-like shutdown first, then force-stops any remaining processes.

	.NOTES
		Used by Start-FancyZones restart paths to guarantee a clean PowerToys relaunch.
	#>
	[CmdletBinding()]
	param(
		[Parameter()]
		[switch]$PreferGracefulExit,

		[Parameter()]
		[int]$MaxGracefulWaitMs = 3000
	)

	$allPowerToysProcesses = @(Get-Process -Name "PowerToys*" -ErrorAction SilentlyContinue)
	if ($allPowerToysProcesses.Count -eq 0) {
		return $true
	}

	# Process.Kill() - what Stop-Process -Force issues - is asynchronous: the process stays
	# enumerable while the kernel tears it down. Waiting on the process handle (bounded) is the
	# only exact signal that it is gone; a fixed sleep either overshoots or re-enumerates a
	# process that is already dying and escalates a tree kill against it. Returns $true when the
	# exit was observed. Test doubles are plain objects without the method: nothing to wait on.
	$waitForProcessExit = {
		param($Process, [int]$TimeoutMs)

		try {
			if ($Process.PSObject.Methods['WaitForExit']) {
				return [bool]$Process.WaitForExit($TimeoutMs)
			}
		}
		catch {
			# Access denied or the handle is already gone - the re-enumeration below decides.
		}

		return $false
	}

	if ($PreferGracefulExit) {
		$gracefulExitRequested = $false
		$mainPowerToysProcesses = @($allPowerToysProcesses | Where-Object { $_.ProcessName -eq "PowerToys" })
		foreach ($mainProcess in $mainPowerToysProcesses) {
			if ($mainProcess.HasExited) {
				continue
			}

			try {
				# PowerToys.exe is a tray application and normally has NO main window
				# (MainWindowHandle 0), so there is nothing to post WM_CLOSE to. CloseMainWindow()
				# returns $true only when the close message was actually posted.
				if ($mainProcess.MainWindowHandle -ne 0) {
					Write-LogDebug "    Requesting graceful PowerToys shutdown (tray-like exit)..." -Style Step

					if ($mainProcess.CloseMainWindow()) {
						$gracefulExitRequested = $true
					}
				}
			}
			catch {
				if (Test-LogVerbose) {
					Write-Warning "    Graceful PowerToys shutdown request failed: $_"
				}
			}
		}

		# The wait is only worth anything after a close request went out. Before this guard the
		# loop ran regardless and, with no main window to close, idled for the whole
		# -MaxGracefulWaitMs (3.6 to 4.1 s measured per forced FancyZones restart) on an exit
		# that had never been requested - then force-stopped anyway.
		if ($gracefulExitRequested) {
			$waitedMs = 0
			while ($waitedMs -lt $MaxGracefulWaitMs) {
				$stillRunning = @(Get-Process -Name "PowerToys*" -ErrorAction SilentlyContinue)
				if ($stillRunning.Count -eq 0) {
					Write-LogDebug "    PowerToys exited gracefully after ${waitedMs}ms" -Style Success
					break
				}

				Start-Sleep -Milliseconds 100
				$waitedMs += 100
			}
		}
		else {
			Write-LogDebug "    PowerToys has no main window to close - skipping the graceful wait" -Style Step
		}
	}

	$remainingProcesses = @(Get-Process -Name "PowerToys*" -ErrorAction SilentlyContinue)
	if ($remainingProcesses.Count -eq 0) {
		return $true
	}

	$allKillsObserved = $true
	foreach ($process in $remainingProcesses) {
		$killObserved = $false
		try {
			Write-LogDebug "    Force-stopping process: $($process.ProcessName) (PID: $($process.Id))" -Style Step
			Stop-Process -Id $process.Id -Force -ErrorAction Stop
			$killObserved = & $waitForProcessExit $process 1000
		}
		catch {
			if (Test-LogVerbose) {
				Write-Warning "    Could not stop process $($process.ProcessName): $_"
			}
			try {
				taskkill /F /PID $process.Id 2>$null
			}
			catch {
				if (Test-LogVerbose) {
					Write-Warning "    taskkill also failed for PID $($process.Id)"
				}
			}
		}

		if (-not $killObserved) {
			$allKillsObserved = $false
		}
	}

	# A kill whose exit was observed needs no settle. Anything else (taskkill fallback, a wait
	# that timed out, an object without a handle) gets the same brief grace as before, so the
	# survivor count below is not taken mid-teardown.
	if (-not $allKillsObserved) {
		Start-Sleep -Milliseconds 100
	}

	$remainingProcesses = @(Get-Process -Name "PowerToys*" -ErrorAction SilentlyContinue)
	if ($remainingProcesses.Count -eq 0) {
		return $true
	}

	if (Test-LogVerbose) {
		Write-Warning "    PowerToys processes still running, escalating to tree kill..."
	}

	try {
		taskkill /F /T /IM "PowerToys.exe" 2>$null
	}
	catch {
		if (Test-LogVerbose) {
			Write-Warning "    taskkill tree kill failed for PowerToys.exe"
		}
	}

	Start-Sleep -Milliseconds 100
	$remainingProcesses = @(Get-Process -Name "PowerToys*" -ErrorAction SilentlyContinue)
	if ($remainingProcesses.Count -gt 0) {
		$remainingProcesses | ForEach-Object {
			try {
				taskkill /F /PID $_.Id 2>$null
			}
			catch {
				# Best effort fallback
			}
		}
	}

	Start-Sleep -Milliseconds 100
	$finalRemaining = @(Get-Process -Name "PowerToys*" -ErrorAction SilentlyContinue)
	return ($finalRemaining.Count -eq 0)
}
