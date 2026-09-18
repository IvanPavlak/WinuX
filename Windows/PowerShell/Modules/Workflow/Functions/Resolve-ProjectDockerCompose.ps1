function Resolve-ProjectDockerCompose {
	<#
	.SYNOPSIS
		Resolves the Docker Compose source a runnable project needs, if any.

	.DESCRIPTION
		The single place that knows which Docker Compose file a project's database
		containers come from. Looks up the project's RunnableProjectMappings entry,
		resolves the database provider (prompting when several are configured), and
		decides whether Docker is required: either the mapping sets UsesDocker, or the
		provider maps to a centralized compose file in Configuration.DockerComposeFiles,
		or the provider is Oracle (project-local compose file).

		Returns $null when the project needs no Docker, otherwise an object with the
		resolved provider and exactly one of ComposeFilePath (a DockerComposeFiles stack,
		resolved by Resolve-DockerComposeStackPath - relative to
		MachineSpecificPaths.DockerDirectory or absolute) or ComposeProjectPath (project
		root containing its own compose file, which DockerWizard probes for the
		Compose-spec names) - the same shapes DockerWizard accepts.

		Used by Run-Project (behind its optional Docker step); Start-Containers works
		directly on the DockerComposeFiles entries instead.

	.PARAMETER ProjectName
		Name of the runnable project to resolve (a RunnableProjectMappings entry).

	.PARAMETER DatabaseProvider
		Optional database provider to use; skips the provider menu when given.

	.EXAMPLE
		Resolve-ProjectDockerCompose -ProjectName "ExampleProject"

	.EXAMPLE
		Resolve-ProjectDockerCompose -ProjectName "ExampleProject" -DatabaseProvider "PostgreSQL"
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$ProjectName,

		[Parameter()]
		[string]$DatabaseProvider
	)

	$runnableMapping = (Get-ConfigSetting -Path 'RunnableProjectMappings' -Default @()) | Where-Object { $_.Name -eq $ProjectName }
	if (-not $runnableMapping) {
		Write-LogError "No runnable project mapping found for [$ProjectName] in Configuration.ps1"
		return $null
	}

	$usesDocker = $runnableMapping.UsesDocker
	$selectedProvider = $null

	$hasDatabaseProviders = $runnableMapping.DatabaseProviders -and $runnableMapping.DatabaseProviders.Count -gt 0

	if ($DatabaseProvider) {
		$selectedProvider = $DatabaseProvider
		Write-LogDebug " Database provider passed in => [$selectedProvider]" -Style Step
	}
	elseif ($hasDatabaseProviders -and $runnableMapping.DatabaseProviders.Count -gt 1) {
		# Multiple providers available - ask which one to use
		$providerParams = @{
			InputObject        = $null
			OptionList         = $runnableMapping.DatabaseProviders
			MenuTitle          = "[Database providers for $ProjectName]"
			DefaultOptionIndex = 1
		}
		$selectedProvider = Resolve-Selection @providerParams

		if (-not $selectedProvider) {
			Write-LogError "No database provider selected for [$ProjectName]!"
			return $null
		}

		Write-LogDebug " Selected database provider => [$selectedProvider]" -Style Step
	}
	elseif ($hasDatabaseProviders) {
		$selectedProvider = $runnableMapping.DatabaseProviders[0]
		Write-LogDebug " Single database provider configured => [$selectedProvider]" -Style Step
	}
	else {
		# No database providers configured - project does not use a database
		Write-LogDebug " No database providers configured => Docker not required for database" -Style Step
	}

	# Resolved once, and defaulted, because ContainsKey below is a METHOD call: a setup
	# that drops DockerComposeFiles entirely would throw on a null-valued expression
	$composeFileMap = Get-ConfigSetting -Path 'DockerComposeFiles' -Default @{}

	# Determine if Docker is needed: either explicitly set on the mapping,
	# or the selected provider has a centralized/project Docker Compose file
	if ($selectedProvider -and ($selectedProvider -eq "Oracle" -or $composeFileMap.ContainsKey($selectedProvider))) {
		$usesDocker = $true
	}

	if (-not $usesDocker) {
		return $null
	}

	$composeFilePath = $null
	$composeProjectPath = $null

	# Check if this provider names a stack in DockerComposeFiles. The path comes from
	# Resolve-DockerComposeStackPath, so an absolute entry is honored here exactly as it
	# is in Start-Containers instead of being joined under the Docker directory
	$centralComposeFile = if ($selectedProvider) { Resolve-DockerComposeStackPath -Name $selectedProvider } else { $null }
	if ($centralComposeFile) {
		$composeFilePath = $centralComposeFile

		Write-LogDebug "Using centralized Docker Compose => [$composeFilePath]" -Style Step -NoLeadingNewline
	}
	else {
		# Fall back to the project's own compose file - the shape for a project that owns its
		# whole stack (UsesDocker), and for Oracle. DockerWizard probes the Compose-spec names
		$mapping = (Get-ConfigSetting -Path 'ProjectTerminals' -Default @()) | Where-Object { $_.Name -eq $ProjectName }
		if (-not $mapping -or -not $mapping.BasePath) {
			Write-LogError "No ProjectTerminals mapping with a BasePath found for [$ProjectName] - cannot resolve its project-local Docker Compose file!"
			return $null
		}

		$current = $MachineSpecificPaths
		foreach ($property in $mapping.BasePath.Split('.')) {
			$current = $current.$property
		}
		$composeProjectPath = $current.Root

		# A BasePath that does not resolve leaves this empty, and handing DockerWizard an
		# empty path would start Docker and quietly do nothing else
		if ([string]::IsNullOrWhiteSpace($composeProjectPath)) {
			Write-LogError "BasePath [$($mapping.BasePath)] for [$ProjectName] does not resolve to a path with a Root in MachineSpecificPaths!"
			return $null
		}

		Write-LogDebug "Using project Docker Compose => [$composeProjectPath]" -Style Step -NoLeadingNewline
	}

	return [PSCustomObject]@{
		Provider           = $selectedProvider
		ComposeFilePath    = $composeFilePath
		ComposeProjectPath = $composeProjectPath
	}
}
