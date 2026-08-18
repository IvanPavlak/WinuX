function DockerWizard {
	<#
	.SYNOPSIS
		Starts or stops Docker Desktop and optional Docker Compose services.

	.DESCRIPTION
		Launches Docker Desktop so the Docker daemon becomes available.
		Optionally starts Docker Compose services for a given project path.
		When stopping, first requests a graceful Docker Desktop shutdown and then
		cleans up any Docker-owned WSL distros or helper processes that remain.

		Polling timeouts are configurable via Configuration.DockerTimeouts
		(StartSeconds/StopSeconds/CleanupSeconds); built-in defaults apply when the
		configuration is absent.

		With -PassThru, returns a status object callers can branch on instead of
		communicating through module-scoped state:
		[PSCustomObject]@{ Success = <bool>; ComposeFilePath = <string or $null> }
		Success means everything ASKED for happened: the daemon came up, and - when a
		compose source was given - it resolved to a real file and `up -d` returned 0.
		A requested compose file that does not exist is a failure, not a no-op.

    .EXAMPLE
        DockerWizard

    .EXAMPLE
        DockerWizard -Stop

    .EXAMPLE
        DockerWizard -ComposeProjectPath "C:\Projects\MyApp"

    .EXAMPLE
        DockerWizard -ComposeFilePath "C:\WinuX\Docker\docker-compose.postgresql.yml"

    .EXAMPLE
        $result = DockerWizard -ComposeFilePath "C:\WinuX\Docker\docker-compose.postgresql.yml" -PassThru
    #>
	[CmdletBinding()]
	param (
		[Parameter()]
		[switch]$Stop,

		[Parameter()]
		[string]$ComposeProjectPath,

		[Parameter()]
		[string]$ComposeFilePath,

		[Parameter()]
		[switch]$PassThru
	)

	$newStatus = {
		param($Success, $ComposeFile)
		return [PSCustomObject]@{
			Success         = $Success
			ComposeFilePath = $ComposeFile
		}
	}

	$dockerTimeouts = $Configuration.DockerTimeouts
	$startTimeoutSeconds = if ($dockerTimeouts -and $dockerTimeouts.StartSeconds) { [int]$dockerTimeouts.StartSeconds } else { 180 }
	$stopTimeoutSeconds = if ($dockerTimeouts -and $dockerTimeouts.StopSeconds) { [int]$dockerTimeouts.StopSeconds } else { 60 }
	$cleanupTimeoutSeconds = if ($dockerTimeouts -and $dockerTimeouts.CleanupSeconds) { [int]$dockerTimeouts.CleanupSeconds } else { 30 }

	if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
		Write-LogWarning "Docker is not installed!"
		if ($PassThru) { return & $newStatus $false $null }
		return
	}

	$dockerProcessNames = @("Docker Desktop", "com.docker.backend", "com.docker.build", "docker-sandbox")

	docker desktop version *> $null
	$dockerDesktopCliAvailable = $LASTEXITCODE -eq 0

	$testDockerDaemonReady = {
		docker info *> $null
		return $LASTEXITCODE -eq 0
	}

	$getDockerDistros = {
		return @(
			wsl.exe -l -q 2>$null |
				ForEach-Object { $_.Trim() } |
				Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -like "docker-desktop*" }
		)
	}

	$testDockerDistrosRunning = {
		$wslState = wsl.exe -l -v 2>$null | Out-String
		return $wslState -match '(?im)^\s*\*?\s*docker-desktop(?:-data)?\s+Running\s+\d+\s*$'
	}

	$stopDockerOwnedWslProcesses = {
		$dockerOwnedWslProcesses = @(
			Get-CimInstance Win32_Process -Filter "Name = 'wsl.exe'" -ErrorAction SilentlyContinue |
				Where-Object { $_.CommandLine -match 'docker-desktop' }
		)

		foreach ($dockerOwnedWslProcess in $dockerOwnedWslProcesses) {
			Stop-Process -Id $dockerOwnedWslProcess.ProcessId -Force -ErrorAction SilentlyContinue
		}
	}

	$stopDockerResidualState = {
		Get-Process -Name $dockerProcessNames -ErrorAction SilentlyContinue |
			Stop-Process -Force -ErrorAction SilentlyContinue

		& $stopDockerOwnedWslProcesses

		foreach ($dockerDistro in (& $getDockerDistros)) {
			wsl.exe --terminate $dockerDistro *> $null
		}
	}

	$testDockerFullyStopped = {
		$remainingDockerProcesses = @(
			Get-Process -Name $dockerProcessNames -ErrorAction SilentlyContinue
		)
		$remainingDockerWslProcesses = @(
			Get-CimInstance Win32_Process -Filter "Name = 'wsl.exe'" -ErrorAction SilentlyContinue |
				Where-Object { $_.CommandLine -match 'docker-desktop' }
		)

		return $remainingDockerProcesses.Count -eq 0 -and
		$remainingDockerWslProcesses.Count -eq 0 -and
		-not (& $testDockerDistrosRunning)
	}

	if ($Stop) {
		Write-LogTitle "Stopping Docker Desktop"

		if (& $testDockerFullyStopped) {
			Write-LogWarning "Docker Desktop is already stopped!"
			if ($PassThru) { return & $newStatus $true $null }
			return
		}

		$spinner = Loading-Spinner -Start -Label "Stopping Docker Desktop"
		$gracefulStopRequested = $false

		if ($dockerDesktopCliAvailable) {
			docker desktop stop --detach *> $null
			$gracefulStopRequested = $LASTEXITCODE -eq 0
		}

		if (-not $gracefulStopRequested) {
			& $stopDockerResidualState
		}

		$timeout = $stopTimeoutSeconds
		$elapsed = 0
		$dockerStopped = $false

		while ($elapsed -lt $timeout) {
			if (& $testDockerFullyStopped) {
				$dockerStopped = $true
				break
			}

			Start-Sleep -Seconds 2
			$elapsed += 2

			if (-not $gracefulStopRequested -or $elapsed -eq 10 -or $elapsed -eq 30) {
				& $stopDockerResidualState
			}
		}

		Loading-Spinner -Stop -Spinner $spinner
		if ($PassThru) { return & $newStatus $dockerStopped $null }
		return
	}

	Write-LogTitle "Starting Docker"

	$daemonAlreadyRunning = & $testDockerDaemonReady

	if ($daemonAlreadyRunning) {
		if (-not $ComposeProjectPath -and -not $ComposeFilePath) {
			Write-LogWarning "Docker is already running!"
			if ($PassThru) { return & $newStatus $true $null }
			return
		}
	}
	else {
		$requiresCleanup = -not (& $testDockerFullyStopped)
		$spinner = $null
		$startRequested = $false

		if ($requiresCleanup) {
			Write-LogWarning "Docker Desktop is in a partial state - cleaning it up before restart..."
		}

		if ($dockerDesktopCliAvailable) {
			$spinner = Loading-Spinner -Start -Label "Starting Docker Desktop"
		}

		if ($requiresCleanup) {
			& $stopDockerResidualState

			$cleanupTimeout = $cleanupTimeoutSeconds
			$cleanupElapsed = 0

			while ($cleanupElapsed -lt $cleanupTimeout) {
				if (& $testDockerFullyStopped) {
					break
				}

				Start-Sleep -Seconds 2
				$cleanupElapsed += 2
			}
		}

		if ($dockerDesktopCliAvailable) {
			docker desktop start --detach *> $null
			$startRequested = $LASTEXITCODE -eq 0
		}

		if (-not $startRequested) {
			Open-Docker

			if (-not $spinner) {
				$spinner = Loading-Spinner -Start -Label "Starting Docker Desktop"
			}
		}

		$timeout = $startTimeoutSeconds
		$elapsed = 0
		$dockerReady = $false

		while ($elapsed -lt $timeout) {
			if (& $testDockerDaemonReady) {
				$dockerReady = $true
				break
			}

			Start-Sleep -Seconds 3
			$elapsed += 3
		}

		Loading-Spinner -Stop -Spinner $spinner

		if (-not $dockerReady) {
			Write-LogError "Docker daemon did not become ready within $startTimeoutSeconds seconds!"
			if ($PassThru) { return & $newStatus $false $null }
			return
		}
	}

	# Docker Compose handling
	$composeFile = $null

	# Whether compose work was ASKED for, which is not the same as it being
	# resolvable: a requested-but-missing compose file is a failure, and reporting
	# Success for it would have callers announce containers that never started
	$composeRequested = [bool]$ComposeFilePath -or [bool]$ComposeProjectPath

	# Use explicit compose file path if provided
	if ($ComposeFilePath) {
		if (Test-Path $ComposeFilePath -ErrorAction SilentlyContinue) {
			$composeFile = $ComposeFilePath
		}
		else {
			Write-LogWarning "Docker Compose file not found => [$ComposeFilePath]"
		}
	}
	elseif ($ComposeProjectPath) {
		if (Test-Path (Join-Path $ComposeProjectPath "docker-compose.yml") -ErrorAction SilentlyContinue) {
			$composeFile = Join-Path $ComposeProjectPath "docker-compose.yml"
		}
		elseif (Test-Path (Join-Path $ComposeProjectPath "compose.yml") -ErrorAction SilentlyContinue) {
			$composeFile = Join-Path $ComposeProjectPath "compose.yml"
		}
		else {
			Write-LogWarning "No Docker Compose file found in => [$ComposeProjectPath]"
		}
	}

	# `up -d` is idempotent - running it unconditionally reconciles a half-stopped
	# stack to the compose file instead of skipping while any one container runs
	$composeStarted = $false

	if ($composeFile) {
		Write-LogStep "=> Starting Docker Compose services..."
		docker compose -f $composeFile up -d
		$composeStarted = $LASTEXITCODE -eq 0

		if (-not $composeStarted) {
			Write-LogError "Docker Compose failed to start services from => [$composeFile]"
		}
	}

	if ($PassThru) {
		return & $newStatus (-not $composeRequested -or $composeStarted) $composeFile
	}
}
