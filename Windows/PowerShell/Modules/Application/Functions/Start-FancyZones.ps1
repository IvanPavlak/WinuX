function Start-FancyZones {
	<#
	.SYNOPSIS
		Ensures PowerToys FancyZones is running and ready with RPC health verification.

	.DESCRIPTION
		Checks if the PowerToys.FancyZones process is running and verifies all required RPC
		services are available. If not, attempts to start PowerToys and waits for FancyZones
		to initialize with full readiness validation including RPC service health.

		Readiness checks include:
		- PowerToys.FancyZones process is running with stable PID
		- FancyZones configuration directory exists
		- All JSON state files are parseable (if present)
		- Required RPC services are running (RpcSs, DcomLaunch, RpcEptMapper)

	.PARAMETER MaxWaitSeconds
		Maximum time to wait for FancyZones to start (default: 10 seconds).

	.PARAMETER ForceRestart
		Forces PowerToys/FancyZones to restart even if already running. This ensures
		reliability when applying zones rapidly or in close succession, preventing
		issues where FancyZones may not respond correctly. Restart uses a full
		PowerToys shutdown sequence before relaunch.

	.EXAMPLE
		Start-FancyZones
		Ensures FancyZones is running with default wait time.

	.EXAMPLE
		Start-FancyZones -MaxWaitSeconds 15
		Ensures FancyZones is running, waiting up to 15 seconds.

	.EXAMPLE
		Start-FancyZones -ForceRestart
		Restarts FancyZones to ensure reliability, useful for rapid successive calls.

	.NOTES
		Returns $true if FancyZones is running, $false if it could not be started.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $false)]
		[int]$MaxWaitSeconds = 10,

		[Parameter(Mandatory = $false)]
		[switch]$ForceRestart
	)

	Write-LogDebug "[Starting FancyZones]"

	$spinner = $null
	if (-not (Test-LogVerbose)) {
		$spinner = Loading-Spinner -Start -Label "Starting FancyZones"
	}

	$fancyZonesDirectory = Join-Path $env:LOCALAPPDATA "Microsoft\PowerToys\FancyZones"
	$customLayoutsPath = Join-Path $fancyZonesDirectory "custom-layouts.json"
	$appliedLayoutsPath = Join-Path $fancyZonesDirectory "applied-layouts.json"

	try {
		$closePowerToysSettings = {
			$settingsProcess = Get-Process -Name "PowerToys.Settings" -ErrorAction SilentlyContinue
			if ($settingsProcess) {
				if (Test-LogVerbose) {
					Write-LogDebug "Closing unwanted PowerToys.Settings window..." -Style Warning
				}
				Stop-Process -Id $settingsProcess.Id -Force -ErrorAction SilentlyContinue
			}
		}

		$testFancyZonesReady = {
			$processSamples = @()
			for ($sample = 0; $sample -lt 4; $sample++) {
				$runningProcess = Get-Process -Name "PowerToys.FancyZones" -ErrorAction SilentlyContinue | Select-Object -First 1
				if (-not $runningProcess) {
					return $false
				}

				$processSamples += $runningProcess.Id
				if ($sample -lt 3) {
					Start-Sleep -Milliseconds 250
				}
			}

			$stablePidCount = ($processSamples | Select-Object -Unique | Measure-Object).Count
			if ($stablePidCount -ne 1) {
				if (Test-LogVerbose) {
					Write-LogDebug "FancyZones PID changed during startup validation, waiting for stabilization..." -Style Warning
				}
				return $false
			}

			# Verify RPC services are running (required for FancyZones and virtual desktop operations)
			if (-not (Test-RpcServerHealth)) {
				if (Test-LogVerbose) {
					Write-LogDebug "RPC server health check failed, FancyZones cannot initialize" -Style Warning
				}
				return $false
			}

			if (-not (Test-Path $fancyZonesDirectory)) {
				if (Test-LogVerbose) {
					Write-LogDebug "FancyZones configuration directory is not ready yet..." -Style Warning
				}
				return $false
			}

			$jsonFilesToValidate = @($customLayoutsPath, $appliedLayoutsPath)
			$validatedFileCount = 0
			foreach ($jsonFile in $jsonFilesToValidate) {
				if (-not (Test-Path $jsonFile)) {
					continue
				}

				try {
					$null = Get-Content -Path $jsonFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
					$validatedFileCount++
				}
				catch {
					if (Test-LogVerbose) {
						Write-LogDebug "FancyZones file is not ready yet => [$jsonFile]" -Style Warning
					}
					return $false
				}
			}

			if ($validatedFileCount -eq 0 -and (Test-LogVerbose)) {
				Write-LogDebug "FancyZones JSON state files not created yet..." -Style Warning
			}

			# Process stability + config directory existence are mandatory.
			# JSON validation is opportunistic and only enforced when files already exist.
			return $true
		}

		# Check if FancyZones is already running
		$fancyZonesProcess = Get-Process -Name "PowerToys.FancyZones" -ErrorAction SilentlyContinue

		if ($ForceRestart) {
			Write-LogDebug "  ⚠ -ForceRestart specified, performing full PowerToys shutdown..." -Style Warning

			$fullShutdownSucceeded = Stop-PowerToysCompletely -PreferGracefulExit
			if (-not $fullShutdownSucceeded -and (Test-LogVerbose)) {
				Write-Warning "    WARNING: Could not fully stop all PowerToys processes before restart."
			}

			Write-LogDebug "    ✓ PowerToys stopped, proceeding with restart" -Style Success
			$fancyZonesProcess = $null
		}
		elseif ($fancyZonesProcess) {
			if (& $testFancyZonesReady) {
				Write-LogDebug "  ✓ FancyZones is already running and ready (PID => $($fancyZonesProcess.Id))" -Style Success
				& $closePowerToysSettings
				return $true
			}

			Write-LogDebug "  ⚠ FancyZones process exists but readiness checks failed - forcing restart..." -Style Warning
			$ForceRestart = $true
		}

		# Check if PowerToys is running without FancyZones (problematic state)
		$powerToysMainProcess = Get-Process -Name "PowerToys" -ErrorAction SilentlyContinue
		if ($powerToysMainProcess) {
			Write-LogDebug "  ⚠ PowerToys is running but FancyZones is not - forcing restart..." -Style Warning

			[void](Stop-PowerToysCompletely -PreferGracefulExit)
			Write-LogDebug "    ✓ PowerToys stopped, will restart..." -Style Success
		}

		Write-LogDebug "  ⚠ FancyZones is not running, attempting to start PowerToys..." -Style Warning

		# Try common PowerToys installation locations
		$powerToysLocations = @(
			"${env:ProgramFiles}\PowerToys\PowerToys.exe",
			"${env:LOCALAPPDATA}\PowerToys\PowerToys.exe",
			"${env:ProgramFiles(x86)}\PowerToys\PowerToys.exe"
		)

		$powerToysPath = $null
		foreach ($location in $powerToysLocations) {
			if (Test-Path $location) {
				$powerToysPath = $location
				break
			}
		}

		if (-not $powerToysPath) {
			if (Test-LogVerbose) {
				Write-Error "  ✗ Could not find PowerToys.exe in common installation locations"
				Write-LogDebug "Searched locations:" -Style Warning
				$powerToysLocations | ForEach-Object { Write-LogDebug "$_" -Style Warning }
			}
			return $false
		}

		Write-LogDebug "  Found PowerToys at => [$powerToysPath]" -Style Success

		# Start PowerToys
		try {
			Start-Process -FilePath $powerToysPath -WindowStyle Hidden -ErrorAction Stop
			Write-LogDebug "  Starting PowerToys..." -Style Step
		}
		catch {
			if (Test-LogVerbose) {
				Write-Error "  ✗ Failed to start PowerToys: $_"
			}
			return $false
		}

		# Wait for FancyZones process to become ready
		$waitInterval = 500  # milliseconds
		$maxAttempts = [Math]::Max([Math]::Ceiling(($MaxWaitSeconds * 1000) / $waitInterval), 1)
		$attempt = 0

		while ($attempt -lt $maxAttempts) {
			Start-Sleep -Milliseconds $waitInterval
			$attempt++

			if (& $testFancyZonesReady) {
				$fancyZonesProcess = Get-Process -Name "PowerToys.FancyZones" -ErrorAction SilentlyContinue | Select-Object -First 1
				if (Test-LogVerbose) {
					Write-LogDebug "  ✓ FancyZones started and passed readiness checks (PID: $($fancyZonesProcess.Id))" -Style Success
				}

				& $closePowerToysSettings

				# Give it a moment to fully initialize
				Start-Sleep -Milliseconds 50
				return $true
			}

			if ($attempt % 4 -eq 0) {
				Write-LogDebug "    Waiting for FancyZones... ($([int]($attempt * $waitInterval / 50))s / $MaxWaitSeconds`s)" -Style Step
			}
		}

		if (Test-LogVerbose) {
			Write-Error "  ✗ FancyZones did not start within $MaxWaitSeconds seconds"
		}

		# Kill PowerToys.Settings if it opened (cleanup even on failure)
		& $closePowerToysSettings

		return $false
	}
	finally {
		if ($spinner) {
			[void](Loading-Spinner -Stop -Spinner $spinner)
		}
	}
}
