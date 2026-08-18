function Start-Containers {
	<#
	.SYNOPSIS
		Starts or stops the configured Docker Compose stacks without running any project.

	.DESCRIPTION
		First-class entry point for the containers themselves: starts Docker Desktop
		(via DockerWizard) and brings up a Docker Compose stack registered in
		Configuration.DockerComposeFiles, so tools like DBeaver can connect while the
		project APIs/UIs stay closed.

		The stacks are the DockerComposeFiles entries (name => compose file). Values
		resolve relative to MachineSpecificPaths.DockerDirectory, or are used as-is
		when they are absolute paths, so any stack can be registered - not just
		database providers. With a single configured entry there is nothing to choose:
		the stack simply starts (or stops). With several, a multi-select menu is
		shown. After a start, the compose file's published host ports are printed so
		the connection target is obvious.

		-Stop runs `docker compose stop` for the selected stacks (containers are kept
		and fast to resume); adding -Down runs `docker compose down` instead
		(containers and network removed, volumes kept). Docker Desktop itself is left
		running either way - use DockerWizard -Stop to shut it down.

	.PARAMETER Name
		Optional stack name(s) from Configuration.DockerComposeFiles. If omitted, the
		single configured stack is used directly, or a menu is shown when several are
		configured.

	.PARAMETER Stop
		Stops the selected stacks' compose services instead of starting them.

	.PARAMETER Down
		With -Stop, removes the containers and network (`docker compose down`)
		instead of just stopping them. Volumes are kept. Implies -Stop.

	.EXAMPLE
		Start-Containers

	.EXAMPLE
		Start-Containers PostgreSQL

	.EXAMPLE
		Start-Containers -Stop

	.EXAMPLE
		Start-Containers PostgreSQL -Stop -Down
	#>
	[CmdletBinding()]
	param (
		[Parameter(Position = 0)]
		[string[]]$Name,

		[Parameter()]
		[switch]$Stop,

		[Parameter()]
		[switch]$Down
	)

	if ($Down) {
		$Stop = $true
	}

	if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
		Write-LogWarning "Docker is not installed!"
		return
	}

	$composeStacks = $Configuration.DockerComposeFiles
	if (-not $composeStacks -or $composeStacks.Count -eq 0) {
		Write-LogWarning "No Docker Compose stacks configured in Configuration.DockerComposeFiles!"
		return
	}

	$stackNames = @($composeStacks.Keys | Sort-Object)

	if ($stackNames.Count -eq 1 -and -not $Name) {
		# A single configured stack is an on/off switch - there is nothing to choose
		$resolvedNames = @($stackNames[0])
	}
	else {
		$resolveParams = @{
			InputObject             = $Name
			OptionList              = $stackNames
			MenuTitle               = "[Docker Compose stacks]"
			AllowMultipleSelections = $true
			DefaultOptionIndex      = 1
		}

		$resolvedNames = @(Resolve-Selection @resolveParams)
	}

	if ($resolvedNames.Count -eq 0) {
		Write-LogWarning "No stack selected!"
		return
	}

	$resolveStackFile = {
		param($StackName)

		$configuredPath = $composeStacks[$StackName]
		if ([System.IO.Path]::IsPathRooted($configuredPath)) {
			return $configuredPath
		}

		return Join-Path $MachineSpecificPaths.DockerDirectory $configuredPath
	}

	$writeComposePorts = {
		param($ComposeFile)

		$currentService = $null
		$inPorts = $false

		foreach ($line in @(Get-Content $ComposeFile -ErrorAction SilentlyContinue)) {
			if ($line -match '^\s{2}(\S[^:\s]*):\s*$') {
				$currentService = $Matches[1]
				$inPorts = $false
				continue
			}

			if ($line -match '^\s+ports:\s*$') {
				$inPorts = $true
				continue
			}

			if ($inPorts) {
				if ($line -match '^\s+-\s*"?(\d+):\d+"?\s*$') {
					Write-LogStep "=> [$currentService] => localhost:$($Matches[1])" -NoLeadingNewline
				}
				elseif ($line -notmatch '^\s+-') {
					$inPorts = $false
				}
			}
		}
	}

	if ($Stop) {
		docker info *> $null
		if ($LASTEXITCODE -ne 0) {
			Write-LogWarning "Docker is not running - nothing to stop!"
			return
		}

		$composeCommand = if ($Down) { "down" } else { "stop" }
		Write-LogTitle "Stopping containers"

		foreach ($stackName in $resolvedNames) {
			$composeFile = & $resolveStackFile $stackName

			if (-not (Test-Path $composeFile -ErrorAction SilentlyContinue)) {
				Write-LogWarning "Docker Compose file not found for [$stackName] => [$composeFile]"
				continue
			}

			Write-LogStep "=> Running docker compose $composeCommand for [$stackName]..."
			docker compose -f $composeFile $composeCommand

			if ($LASTEXITCODE -eq 0) {
				Write-LogSuccess "[$stackName] containers $(if ($Down) { "removed (volumes kept)" } else { "stopped" })!"
			}
			else {
				Write-LogError "docker compose $composeCommand failed for [$stackName]!"
			}
		}

		return
	}

	foreach ($stackName in $resolvedNames) {
		$composeFile = & $resolveStackFile $stackName

		# Checked before DockerWizard so a misconfigured path fails immediately
		# instead of after a full Docker Desktop cold start
		if (-not (Test-Path $composeFile -ErrorAction SilentlyContinue)) {
			Write-LogError "Docker Compose file not found for [$stackName] => [$composeFile]"
			continue
		}

		$dockerResult = DockerWizard -ComposeFilePath $composeFile -PassThru

		if (-not $dockerResult.Success) {
			Write-LogError "Containers could not be started for [$stackName]!"
			continue
		}

		Write-LogSuccess "[$stackName] containers are up!"

		if ($dockerResult.ComposeFilePath) {
			& $writeComposePorts $dockerResult.ComposeFilePath
		}
	}
}
