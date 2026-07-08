function DockerWizard {
	<#
	.SYNOPSIS
		Starts or stops Docker Desktop and optional Docker Compose services.

	.DESCRIPTION
		Launches Docker Desktop so the Docker daemon becomes available.
		Optionally starts Docker Compose services for a given project path.
		When stopping, first requests a graceful Docker Desktop shutdown and then
		cleans up any Docker-owned WSL distros or helper processes that remain.

    .EXAMPLE
        DockerWizard

    .EXAMPLE
        DockerWizard -Stop

    .EXAMPLE
        DockerWizard -ComposeProjectPath "C:\Projects\MyApp"

    .EXAMPLE
        DockerWizard -ComposeFilePath "C:\WinuX\Docker\docker-compose.postgresql.yml"
    #>
	[CmdletBinding()]
	param (
		[Parameter()]
		[switch]$Stop,

		[Parameter()]
		[string]$ComposeProjectPath,

		[Parameter()]
		[string]$ComposeFilePath
	)

	if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
		Write-LogWarning "Docker is not installed!"
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

		$timeout = 60
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
		return
	}

	Write-LogTitle "Starting Docker"

	$daemonAlreadyRunning = & $testDockerDaemonReady

	if ($daemonAlreadyRunning) {
		if (-not $ComposeProjectPath -and -not $ComposeFilePath) {
			Write-LogWarning "Docker is already running!"
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

			$cleanupTimeout = 30
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

		$timeout = 180
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
			Write-LogError "Docker daemon did not become ready within 180 seconds!"
			$script:DockerStartFailed = $true
			return
		}

		$script:DockerStartFailed = $false
	}

	# Docker Compose handling
	$composeFile = $null

	# Use explicit compose file path if provided
	if ($ComposeFilePath -and (Test-Path $ComposeFilePath -ErrorAction SilentlyContinue)) {
		$composeFile = $ComposeFilePath
	}
	elseif ($ComposeProjectPath) {
		if (Test-Path (Join-Path $ComposeProjectPath "docker-compose.yml") -ErrorAction SilentlyContinue) {
			$composeFile = Join-Path $ComposeProjectPath "docker-compose.yml"
		}
		elseif (Test-Path (Join-Path $ComposeProjectPath "compose.yml") -ErrorAction SilentlyContinue) {
			$composeFile = Join-Path $ComposeProjectPath "compose.yml"
		}
	}

	if ($composeFile) {
		$runningContainers = docker compose -f $composeFile ps -q 2>$null
		if (-not $runningContainers) {
			Write-LogStep "=> Starting Docker Compose services..."
			docker compose -f $composeFile up -d
		}
		elseif ($daemonAlreadyRunning) {
			Write-LogWarning "Docker is already running!"
		}
	}
}
