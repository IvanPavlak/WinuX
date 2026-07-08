function Run-Project {
	<#
	.SYNOPSIS
		Open terminal tabs for configured runnable projects.

	.DESCRIPTION
		Selects from Configuration.RunnableProjects with optional multi-select.
		Opens Windows Terminal tabs configured for each selected project.
		Uses Resolve-Selection for interactive menu with -InSameShell option to run in current tab.

	.PARAMETER Project
		Optional project name(s) to run. If omitted, shows interactive menu.

	.PARAMETER InSameShell
		If $true (default), use current shell tab. If $false, open new tabs.

	.EXAMPLE
		Run-Project  # Interactive menu
		Run-Project -Project "MyApp", "OtherApp"
		Run-Project -Project "MyApp" -InSameShell:$false
	#>
	[CmdletBinding()]
	param (
		[Parameter()]
		[string[]]$Project,

		[Parameter()]
		[switch]$InSameShell = $true
	)

	$resolveParams = @{
		InputObject             = $Project
		OptionList              = $Configuration.RunnableProjects
		MenuTitle               = "[Available projects]"
		AllowMultipleSelections = $true
		DefaultOptionIndex      = 1
	}

	$resolvedProjects = Resolve-Selection @resolveParams

	Write-LogDebug "Resolved projects count: $($resolvedProjects.Count)" -Style Step
	Write-LogDebug "Resolved projects type: $($resolvedProjects.GetType().FullName)" -Style Step -NoLeadingNewline
	Write-LogDebug "Resolved projects: $($resolvedProjects -join ', ')" -Style Step -NoLeadingNewline

	# Capture the starting tab title so we can refocus after opening project tabs
	$startingWindow = Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue | Select-Object -First 1
	$startingTitle = if ($startingWindow) { $startingWindow.Title } else { $null }

	foreach ($Name in $resolvedProjects) {
		Write-LogDebug "Processing project: $Name" -Style Step -NoLeadingNewline

		try {
			Write-LogStep "Running $Name project..."

			# Get the mapping for runnable commands
			$runnableMapping = $Configuration.RunnableProjectMappings | Where-Object { $_.Name -eq $Name }
			Write-LogDebug "Runnable mapping found: $($null -ne $runnableMapping)" -Style Step -NoLeadingNewline
			if (-not $runnableMapping) {
				Write-LogError "No runnable project mapping found for [$Name] in Configuration.ps1"
				continue
			}

			# Resolve database provider
			$usesDocker = $runnableMapping.UsesDocker
			$selectedProvider = $null

			$hasDatabaseProviders = $runnableMapping.DatabaseProviders -and $runnableMapping.DatabaseProviders.Count -gt 0

			if ($hasDatabaseProviders -and $runnableMapping.DatabaseProviders.Count -gt 1) {
				# Multiple providers available - ask which one to use
				$providerParams = @{
					InputObject        = $null
					OptionList         = $runnableMapping.DatabaseProviders
					MenuTitle          = "[Database providers for $Name]"
					DefaultOptionIndex = 1
				}
				$selectedProvider = Resolve-Selection @providerParams

				if (-not $selectedProvider) {
					Write-LogError "No database provider selected! Skipping [$Name]!"
					continue
				}

				Write-LogDebug " Selected database provider => [$selectedProvider]" -Style Step
			}
			elseif ($hasDatabaseProviders -and $runnableMapping.DatabaseProviders.Count -eq 1) {
				$selectedProvider = $runnableMapping.DatabaseProviders[0]
				Write-LogDebug " Single database provider configured => [$selectedProvider]" -Style Step
			}
			else {
				# No database providers configured - project does not use a database
				Write-LogDebug " No database providers configured => Docker not required for database" -Style Step
			}

			# Determine if Docker is needed: either explicitly set on the mapping,
			# or the selected provider has a centralized/project Docker Compose file
			if ($selectedProvider -and ($selectedProvider -eq "Oracle" -or $Configuration.DockerComposeFiles.ContainsKey($selectedProvider))) {
				$usesDocker = $true
			}

			# Start Docker service and compose if the project requires it
			if ($usesDocker) {
				$script:DockerStartFailed = $false
				$dockerParams = @{}

				# Check if this provider has a centralized Docker Compose file in WinuX
				$centralComposeFile = $Configuration.DockerComposeFiles[$selectedProvider]
				if ($centralComposeFile) {
					# Use the centralized compose file from WinuX/Docker/
					$composeFilePath = Join-Path $MachineSpecificPaths.DockerDirectory $centralComposeFile
					$dockerParams["ComposeFilePath"] = $composeFilePath

					Write-LogDebug "Using centralized Docker Compose => [$composeFilePath]" -Style Step -NoLeadingNewline
				}
				else {
					# Fall back to project-specific docker-compose.yml (e.g., Oracle in ExampleProject)
					$mapping = $Configuration.ProjectTerminals | Where-Object { $_.Name -eq $Name }
					$current = $MachineSpecificPaths
					foreach ($property in $mapping.BasePath.Split('.')) {
						$current = $current.$property
					}
					$projectRoot = $current.Root
					$dockerParams["ComposeProjectPath"] = $projectRoot

					Write-LogDebug "Using project Docker Compose => [$projectRoot]" -Style Step -NoLeadingNewline
				}

				DockerWizard @dockerParams
				if ($script:DockerStartFailed) {
					Write-LogError "Docker is required but could not be started! Skipping [$Name]!"
					continue
				}
			}

			# Get the mapping for project paths and their keys (e.g., Api, Ui)
			$pathMapping = $Configuration.ProjectTerminals | Where-Object { $_.Name -eq $Name }
			Write-LogDebug "Path mapping found: $($null -ne $pathMapping)" -Style Step -NoLeadingNewline
			if (-not $pathMapping) {
				Write-LogError "No path mapping found for [$Name] in configuration."
				continue
			}

			# Close existing terminal tabs for this project to avoid duplicates
			Write-LogDebug "Closing existing terminal tabs for $Name..." -Style Step -NoLeadingNewline

			# TODO: This doesn't work with multiple projects!
			$closeTerminalParams = @{
				ProjectName = $Name
			}

			if ($startingWindow) {
				$closeTerminalParams["TerminalWindowHandle"] = $startingWindow.Handle
			}

			if ($startingTitle) {
				$closeTerminalParams["StartingTabTitle"] = $startingTitle
			}

			$closedCount = Close-ProjectTerminals @closeTerminalParams
			Write-LogDebug "Closed $closedCount tabs" -Style Step -NoLeadingNewline

			$commandsToRun = @()
			$tabTitles = @()

			$pathKeys = $pathMapping.Paths
			$projectCommands = $runnableMapping.Commands
			Write-LogDebug "Path keys count: $($pathKeys.Count), Commands count: $($projectCommands.Count)" -Style Step -NoLeadingNewline

			# Ensure there's a command for each path key
			if ($pathKeys.Count -ne $projectCommands.Count) {
				Write-LogError "Error => Mismatch between configured paths and number of commands for project [$Name]"
				Write-LogDebug "   Paths: $($pathKeys.Count), Commands: $($projectCommands.Count)" -Style Error -NoLeadingNewline
				continue
			}

			for ($i = 0; $i -lt $pathKeys.Count; $i++) {
				$pathKey = $pathKeys[$i]

				# Resolve the full path using the project name and path key
				$path = Resolve-ProjectPath -ProjectName $Name -PathKey $pathKey

				# Construct the command
				$commandScript = "Set-Location -Path '$path'"
				if (-not [string]::IsNullOrWhiteSpace($projectCommands[$i])) {
					$commandScript += "; $($projectCommands[$i])"
				}
				$commandsToRun += $commandScript

				# Generate the tab title using the project name and the path key
				$tabTitles += "$Name.$pathKey"
			}

			# If the starting tab matches a project tab, reuse it instead of opening a duplicate
			$currentTabCommand = $null
			$newTabCommands = @()
			$newTabTitles = @()

			for ($i = 0; $i -lt $tabTitles.Count; $i++) {
				if ($startingTitle -and $tabTitles[$i] -eq $startingTitle) {
					$currentTabCommand = $commandsToRun[$i]
					Write-LogDebug "Reusing current tab for => [$($tabTitles[$i])]" -Style Step -NoLeadingNewline
				}
				else {
					$newTabCommands += $commandsToRun[$i]
					$newTabTitles += $tabTitles[$i]
				}
			}

			Write-LogDebug "Commands to run count: $($newTabCommands.Count) new tab(s), current tab reuse: $($null -ne $currentTabCommand)" -Style Step -NoLeadingNewline
			Write-LogDebug "Tab titles: $($newTabTitles -join ', ')" -Style Step -NoLeadingNewline
			Write-LogDebug "InSameShell: $InSameShell" -Style Step -NoLeadingNewline
			Write-LogDebug "Calling Open-Terminal..." -Style Step -NoLeadingNewline

			# Open only new tabs for the other project components
			if ($newTabCommands.Count -gt 0) {
				Open-Terminal -Command $newTabCommands -InSameShell:$InSameShell -TabTitles $newTabTitles
			}

			Write-LogSuccess "Project $Name started successfully!"

			# Run the current tab's command last (after all other tabs are opened)
			# so the script finishes cleanly before the command takes over
			if ($currentTabCommand) {
				Write-LogDebug "Running command in current tab => [$currentTabCommand]" -Style Step -NoLeadingNewline
				Invoke-Expression $currentTabCommand
			}
		}
		catch {
			Write-LogError "Error: $($_.Exception.Message)" -BlankLineAfter
			Write-LogDebug "Stack trace: $($_.ScriptStackTrace)" -Style Error -NoLeadingNewline
		}
	}

	# Refocus back to the starting tab after all projects have been opened
	if ($startingTitle) {
		Focus-TerminalTab -TargetTitle $startingTitle
	}
}
