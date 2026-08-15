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

		The PID-stability sampling (4 samples over 750ms) only runs while the process is
		young (under ~5s old) - a long-lived process cannot be mid-crash-loop, so a single
		sample suffices on the happy path. A successful verification is cached for 10s
		(cleared by -ForceRestart and on any failed check), so the several Start-FancyZones
		calls of one workspace open pay for a single readiness pass.

	.PARAMETER MaxWaitSeconds
		Maximum time to wait for FancyZones to start (default: 10 seconds).

	.PARAMETER ForceRestart
		Forces PowerToys/FancyZones to restart even if already running. This ensures
		reliability when applying zones rapidly or in close succession, preventing
		issues where FancyZones may not respond correctly. Restart uses a full
		PowerToys shutdown sequence before relaunch.

	.PARAMETER PassThru
		Emits the readiness result ($true / $false) to the pipeline. Without it the
		function outputs nothing, so an interactive call leaves only the spinner and
		its completion mark on screen. Programmatic callers that branch on readiness
		pass -PassThru and capture the value.

	.EXAMPLE
		Start-FancyZones
		Ensures FancyZones is running with default wait time.

	.EXAMPLE
		Start-FancyZones -MaxWaitSeconds 15
		Ensures FancyZones is running, waiting up to 15 seconds.

	.EXAMPLE
		Start-FancyZones -ForceRestart
		Restarts FancyZones to ensure reliability, useful for rapid successive calls.

	.EXAMPLE
		$ready = Start-FancyZones -PassThru
		Captures the readiness result for branching (e.g. escalate to -ForceRestart).

	.NOTES
		With -PassThru, outputs $true if FancyZones is running, $false if it could not
		be started. Without -PassThru nothing is emitted.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $false)]
		[int]$MaxWaitSeconds = 10,

		[Parameter(Mandatory = $false)]
		[switch]$ForceRestart,

		[Parameter(Mandatory = $false)]
		[switch]$PassThru
	)

	Write-LogDebug "[Starting FancyZones]"

	$fancyZonesDirectory = Join-Path $env:LOCALAPPDATA "Microsoft\PowerToys\FancyZones"
	$customLayoutsPath = Join-Path $fancyZonesDirectory "custom-layouts.json"
	$appliedLayoutsPath = Join-Path $fancyZonesDirectory "applied-layouts.json"

	# Module-scoped "verified ready" cache: the full readiness pass (process sampling +
	# service checks + JSON parses) is expensive, and one workspace open calls this function
	# several times seconds apart (Apply-FancyZones begin, Snap-AllWindows begin, per-desktop
	# simple-layout passes). A recent successful verification is trusted for a short TTL.
	if (-not $script:FancyZonesReadyCache) {
		$script:FancyZonesReadyCache = @{
			VerifiedAt = [datetime]::MinValue
			TtlSeconds = 10
		}
	}

	$fancyZonesProcess = Get-Process -Name "PowerToys.FancyZones" -ErrorAction SilentlyContinue

	# Cache hit fast path, resolved BEFORE the spinner is created. One workspace open calls
	# this several times seconds apart (Apply-FancyZones begin, Snap-AllWindows begin, each
	# retry reset), and every cached no-op used to still start and stop a spinner - printing
	# a "Starting FancyZones" line for work that was not done, three in a row after a single
	# retry reset. A call that does nothing now says nothing.
	if (-not $ForceRestart -and $fancyZonesProcess) {
		$readyCacheAge = ([datetime]::Now - $script:FancyZonesReadyCache.VerifiedAt).TotalSeconds
		if ($readyCacheAge -ge 0 -and $readyCacheAge -lt $script:FancyZonesReadyCache.TtlSeconds) {
			Write-LogDebug "  ✓ FancyZones readiness verified $([int]$readyCacheAge)s ago - using cached result" -Style Success
			if ($PassThru) { return $true }
			return
		}
	}

	$spinner = $null
	if (-not (Test-LogVerbose)) {
		$spinner = Loading-Spinner -Start -Label "Starting FancyZones"
	}

	# The boolean result is EMITTED FROM THE FINALLY BLOCK, after the spinner line is
	# finalized. A "return $true" inside the try emits its value BEFORE finally runs,
	# so an interactive call printed "True" onto the live spinner line and mangled it
	# ("Truearting FancyZones"). Inside the try, set $startResult and use a bare
	# "return"; never return a value directly.
	$startResult = $false
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
			$runningProcess = Get-Process -Name "PowerToys.FancyZones" -ErrorAction SilentlyContinue | Select-Object -First 1
			if (-not $runningProcess) {
				return $false
			}

			# PID-stability sampling exists to catch a FancyZones that is still crash-looping
			# during startup. A process that has been alive for a few seconds cannot be
			# mid-crash-loop, so a single sample suffices - that is the happy path on every
			# workspace open and skips 750ms of fixed sampling sleeps. StartTime can throw
			# (access denied on elevation mismatch); fall back to sampling in that case.
			$processAgeSeconds = $null
			try {
				$processAgeSeconds = ([datetime]::Now - $runningProcess.StartTime).TotalSeconds
			}
			catch {
				$processAgeSeconds = $null
			}

			if ($null -eq $processAgeSeconds -or $processAgeSeconds -lt 5) {
				$processSamples = @($runningProcess.Id)
				for ($sample = 1; $sample -lt 4; $sample++) {
					Start-Sleep -Milliseconds 250
					$runningProcess = Get-Process -Name "PowerToys.FancyZones" -ErrorAction SilentlyContinue | Select-Object -First 1
					if (-not $runningProcess) {
						return $false
					}
					$processSamples += $runningProcess.Id
				}

				$stablePidCount = ($processSamples | Select-Object -Unique | Measure-Object).Count
				if ($stablePidCount -ne 1) {
					if (Test-LogVerbose) {
						Write-LogDebug "FancyZones PID changed during startup validation, waiting for stabilization..." -Style Warning
					}
					return $false
				}
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

		if ($ForceRestart) {
			Write-LogDebug "  ⚠ -ForceRestart specified, performing full PowerToys shutdown..." -Style Warning

			# The restart invalidates any previous readiness verification.
			$script:FancyZonesReadyCache.VerifiedAt = [datetime]::MinValue

			$fullShutdownSucceeded = Stop-PowerToysCompletely -PreferGracefulExit
			if (-not $fullShutdownSucceeded -and (Test-LogVerbose)) {
				Write-Warning "    WARNING: Could not fully stop all PowerToys processes before restart."
			}

			Write-LogDebug "    ✓ PowerToys stopped, proceeding with restart" -Style Success
			$fancyZonesProcess = $null
		}
		elseif ($fancyZonesProcess) {
			# The ready-cache was already consulted above (before the spinner) - reaching
			# here means it was cold or stale, so run the full readiness pass.
			if (& $testFancyZonesReady) {
				Write-LogDebug "  ✓ FancyZones is already running and ready (PID => $($fancyZonesProcess.Id))" -Style Success
				$script:FancyZonesReadyCache.VerifiedAt = [datetime]::Now
				& $closePowerToysSettings
				$startResult = $true
				return
			}

			$script:FancyZonesReadyCache.VerifiedAt = [datetime]::MinValue
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
			return
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
			return
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

				$script:FancyZonesReadyCache.VerifiedAt = [datetime]::Now
				& $closePowerToysSettings

				# Give it a moment to fully initialize
				Start-Sleep -Milliseconds 50
				$startResult = $true
				return
			}

			if ($attempt % 4 -eq 0) {
				Write-LogDebug "    Waiting for FancyZones... ($([int]($attempt * $waitInterval / 1000))s / $MaxWaitSeconds`s)" -Style Step
			}
		}

		if (Test-LogVerbose) {
			Write-Error "  ✗ FancyZones did not start within $MaxWaitSeconds seconds"
		}

		# Kill PowerToys.Settings if it opened (cleanup even on failure)
		& $closePowerToysSettings

		return
	}
	finally {
		if ($spinner) {
			if ($startResult) {
				# The label already told the story while the spinner ran - finish with
				# a bare "✓" instead of repeating it.
				[void](Loading-Spinner -Stop -Spinner $spinner -CheckmarkOnly)
			}
			else {
				# Never leave a success checkmark on a failure path.
				[void](Loading-Spinner -Stop -Spinner $spinner -Discard)
			}
		}

		# Function output (only with -PassThru): emitted here, AFTER the spinner line
		# is finalized, so the value can never interleave with the spinner rendering.
		if ($PassThru) {
			$startResult
		}
	}
}
