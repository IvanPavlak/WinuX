function Stop-PowerToysCompletely {
	<#
	.SYNOPSIS
		Stops all PowerToys processes and verifies full shutdown.

	.DESCRIPTION
		Performs a complete PowerToys shutdown sequence that mirrors manual tray exit behavior:
		- Optionally requests graceful shutdown via the main PowerToys window
		- Waits for graceful exit to complete
		- Force-stops remaining PowerToys processes if needed
		- Escalates to taskkill process tree termination as a final fallback

		Returns $true only when no PowerToys-related process remains.

	.PARAMETER PreferGracefulExit
		Attempts graceful PowerToys shutdown before force termination.

	.PARAMETER MaxGracefulWaitMs
		Maximum milliseconds to wait for graceful exit before force termination.

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

	if ($PreferGracefulExit) {
		$mainPowerToysProcesses = @($allPowerToysProcesses | Where-Object { $_.ProcessName -eq "PowerToys" })
		foreach ($mainProcess in $mainPowerToysProcesses) {
			if ($mainProcess.HasExited) {
				continue
			}

			try {
				if ($mainProcess.MainWindowHandle -ne 0) {
					Write-LogDebug "    Requesting graceful PowerToys shutdown (tray-like exit)..." -Style Step

					[void]$mainProcess.CloseMainWindow()
				}
			}
			catch {
				if (Test-LogVerbose) {
					Write-Warning "    Graceful PowerToys shutdown request failed: $_"
				}
			}
		}

		$waitedMs = 0
		while ($waitedMs -lt $MaxGracefulWaitMs) {
			$stillRunning = @(Get-Process -Name "PowerToys*" -ErrorAction SilentlyContinue)
			if ($stillRunning.Count -eq 0) {
				break
			}

			Start-Sleep -Milliseconds 100
			$waitedMs += 100
		}
	}

	$remainingProcesses = @(Get-Process -Name "PowerToys*" -ErrorAction SilentlyContinue)
	foreach ($process in $remainingProcesses) {
		try {
			Write-LogDebug "    Force-stopping process: $($process.ProcessName) (PID: $($process.Id))" -Style Step
			Stop-Process -Id $process.Id -Force -ErrorAction Stop
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
	}

	Start-Sleep -Milliseconds 100
	$remainingProcesses = @(Get-Process -Name "PowerToys*" -ErrorAction SilentlyContinue)
	if ($remainingProcesses.Count -gt 0) {
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
	}

	Start-Sleep -Milliseconds 100
	$finalRemaining = @(Get-Process -Name "PowerToys*" -ErrorAction SilentlyContinue)
	return ($finalRemaining.Count -eq 0)
}
