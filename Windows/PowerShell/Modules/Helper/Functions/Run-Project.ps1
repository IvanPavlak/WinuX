function Run-Project {
	<#
	.SYNOPSIS
		Open terminal tabs for configured runnable projects.

	.DESCRIPTION
		Selects from Configuration.RunnableProjectMappings with optional multi-select - the
		menu lists the mappings in the order they are configured, which is also the one place
		a runnable project is defined.
		Opens Windows Terminal tabs configured for each selected project.
		Uses Resolve-Selection for interactive menu with -InSameShell option to run in current tab.

		Each mapping's `Commands` is keyed by the ProjectTerminals path the command runs in
		(`@{ API = "dnr"; UI = "nir" }`), so a command sits next to the path it belongs to
		instead of lining up with it by position. A path with no command listed gets its
		terminal tab and nothing run in it.

		The project's tabs are read out of ProjectTerminals by Resolve-ProjectTerminalTab, the
		same reader Open-ProjectTerminals uses, so `rp` and `op` open the same set of tabs -
		including WSL tabs, which go to Open-WSLTab on the distribution's own Windows Terminal
		profile. A WSL tab does not take the project's commands: they are PowerShell commands and
		that tab is not PowerShell, so a command configured for a WSL key is reported and skipped
		while the tab itself still opens in the project directory. WSL tabs are spawned after the
		PowerShell tabs, so they appear last in the window whatever position they hold in `Paths`.

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

	$runnableProjectMappings = @(Get-ConfigSetting -Path 'RunnableProjectMappings' -Default @())
	$projectTerminals = @(Get-ConfigSetting -Path 'ProjectTerminals' -Default @())

	$resolveParams = @{
		InputObject             = $Project
		OptionList              = @($runnableProjectMappings | ForEach-Object { $_.Name })
		MenuTitle               = "[Available projects]"
		AllowMultipleSelections = $true
		DefaultOptionIndex      = 1
	}

	$resolvedProjects = Resolve-Selection @resolveParams

	# Nothing selected is an ordinary outcome - [Enter] at the menu - so the debug lines have to
	# survive it. $null.GetType() throws, and reporting the type of nothing is not worth a crash.
	$resolvedProjects = @($resolvedProjects)
	Write-LogDebug "Resolved projects count: $($resolvedProjects.Count)" -Style Step
	Write-LogDebug "Resolved projects: $($resolvedProjects -join ', ')" -Style Step -NoLeadingNewline

	# Capture the starting tab title so we can refocus after opening project tabs
	$startingWindow = Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue | Select-Object -First 1
	$startingTitle = if ($startingWindow) { $startingWindow.Title } else { $null }

	foreach ($Name in $resolvedProjects) {
		Write-LogDebug "Processing project: $Name" -Style Step -NoLeadingNewline

		try {
			Write-LogStep "Running $Name project..."

			# Get the mapping for runnable commands
			$runnableMapping = $runnableProjectMappings | Where-Object { $_.Name -eq $Name }
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
			$pathMapping = $projectTerminals | Where-Object { $_.Name -eq $Name }
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
			$wslTabs = @()

			$pathEntries = @($pathMapping.Paths)
			$projectCommands = $runnableMapping.Commands
			Write-LogDebug "Path entries count: $($pathEntries.Count), Commands count: $($projectCommands.Count)" -Style Step -NoLeadingNewline

			# One window for the whole project whenever the tabs do not go into this shell's own
			# window: Open-Terminal would otherwise mint a window ID of its own, and a WSL tab -
			# spawned separately, on the distribution's Windows Terminal profile - could never join it.
			$projectWindowId = if ($InSameShell) { $null } else { [guid]::NewGuid().ToString() }

			foreach ($pathEntry in $pathEntries) {
				# Resolve-ProjectTerminalTab is the one reader of the entry shapes ProjectTerminals
				# accepts, shared with Open-ProjectTerminals - including the WSL shapes, which this
				# function used to take for Windows paths and hand straight to Set-Location.
				$tab = Resolve-ProjectTerminalTab -ProjectName $Name -PathEntry $pathEntry

				# The command for this path, looked up by path key. A path with no command
				# just gets its tab; the legacy positional array is still read by index.
				$command = if ($projectCommands -is [System.Collections.IDictionary]) {
					$projectCommands[$tab.Key]
				}
				else {
					$index = [Array]::IndexOf($pathEntries, $pathEntry)
					if ($index -lt @($projectCommands).Count) { @($projectCommands)[$index] } else { $null }
				}

				if ($tab.Kind -eq "WSL") {
					if (-not $tab.Distribution) {
						Write-LogWarning "Skipping [$($tab.Title)] (DefaultWSLDistribution not configured)" -NoLeadingNewline
						continue
					}

					# The tab runs the distribution's shell, not pwsh, so a configured command
					# would be a PowerShell command handed to a shell that cannot run it. The tab
					# is opened in the project directory and the command is left to the user.
					if (-not [string]::IsNullOrWhiteSpace($command)) {
						Write-LogWarning "Command for [$($tab.Title)] is not run - a WSL tab does not take the project's PowerShell commands!" -NoLeadingNewline
					}

					$wslTabs += $tab
					continue
				}

				# A "Default" tab is a plain shell wherever Windows Terminal starts it, so it gets
				# no Set-Location in front of its command.
				$commandScript = if ($tab.Kind -eq "Path") { "Set-Location -Path '$($tab.Path)'" } else { "" }
				if (-not [string]::IsNullOrWhiteSpace($command)) {
					if ($commandScript) { $commandScript += "; " }
					$commandScript += $command
				}
				$commandsToRun += $commandScript

				$tabTitles += $tab.Title
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
				$terminalParams = @{
					Command     = $newTabCommands
					InSameShell = $InSameShell
					TabTitles   = $newTabTitles
				}

				if ($projectWindowId) { $terminalParams["WindowId"] = $projectWindowId }

				Open-Terminal @terminalParams
			}

			# WSL tabs come after the PowerShell batch. They are spawned one per wt invocation on
			# the distribution's own profile, so they cannot be chained into the batch above, and
			# they land last in the window whatever position they hold in Paths.
			foreach ($wslTab in $wslTabs) {
				Write-LogDebug "Opening WSL tab => [$($wslTab.Title)] in [$($wslTab.Path)]" -Style Step -NoLeadingNewline

				$wslParams = @{
					Distribution = $wslTab.Distribution
					TabTitle     = $wslTab.Title
					Quiet        = $true
				}

				if ($wslTab.Path) { $wslParams["Path"] = $wslTab.Path }
				if ($projectWindowId) { $wslParams["WindowId"] = $projectWindowId }

				Open-WSLTab @wslParams
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
