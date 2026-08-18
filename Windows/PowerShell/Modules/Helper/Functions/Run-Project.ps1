function Run-Project {
	<#
	.SYNOPSIS
		Open terminal tabs for configured runnable projects.

	.DESCRIPTION
		Selects from Configuration.RunnableProjects with optional multi-select.
		Opens Windows Terminal tabs configured for each selected project.
		Uses Resolve-Selection for interactive menu with -InSameShell option to run in current tab.

		The Docker step (resolving a project's compose source and starting containers)
		is optional, resolved Kill-All-style via Resolve-RunProjectSteps: configure it
		persistently with RunProject.Steps.Docker in Configuration.psd1 /
		Configuration.local.psd1 (a plain boolean or a per-machine-type hashtable with
		a Default fallback), or override per invocation with -Skip / -Include. A setup
		that runs its databases locally sets it to $false once and Run-Project never
		touches Docker - not even the database provider prompt.

	.PARAMETER Project
		Optional project name(s) to run. If omitted, shows interactive menu.

	.PARAMETER InSameShell
		If $true (default), use current shell tab. If $false, open new tabs.

	.PARAMETER Skip
		Step names to skip for this invocation, overriding config. Valid names: Docker.
		Wins over -Include when a step appears in both.

	.PARAMETER Include
		Step names to run for this invocation even if config disables them.
		Same valid names as -Skip.

	.EXAMPLE
		Run-Project  # Interactive menu
		Run-Project -Project "MyApp", "OtherApp"
		Run-Project -Project "MyApp" -InSameShell:$false
		Run-Project -Project "MyApp" -Skip Docker
	#>
	[CmdletBinding()]
	param (
		[Parameter()]
		[string[]]$Project,

		[Parameter()]
		[switch]$InSameShell = $true,

		[Parameter()]
		[ValidateSet("Docker")]
		[string[]]$Skip,

		[Parameter()]
		[ValidateSet("Docker")]
		[string[]]$Include
	)

	$stepStates = Resolve-RunProjectSteps -Skip $Skip -Include $Include

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

			# Resolve the project's Docker Compose source (provider menu included) and
			# start Docker if the project requires it - unless the Docker step is
			# disabled, in which case not even the provider prompt appears
			$dockerCompose = if ($stepStates.Docker) { Resolve-ProjectDockerCompose -ProjectName $Name } else { $null }

			if ($dockerCompose) {
				$dockerParams = @{ PassThru = $true }

				if ($dockerCompose.ComposeFilePath) {
					$dockerParams["ComposeFilePath"] = $dockerCompose.ComposeFilePath
				}
				else {
					$dockerParams["ComposeProjectPath"] = $dockerCompose.ComposeProjectPath
				}

				$dockerResult = DockerWizard @dockerParams
				if (-not $dockerResult.Success) {
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
