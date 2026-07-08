function Open-Project {
	<#
	.SYNOPSIS
		Opens a development project with all configured tools and terminal tabs.

	.DESCRIPTION
		Reads the project's action list from `ProjectActions` in Configuration.psd1
		and executes each action in order. Actions are named PowerShell functions
		(e.g. `Open-VSCode`, `Open-VisualStudio`, `Open-Browser`) with parameters
		resolved at runtime. The `{ProjectName}` placeholder in action parameters
		is replaced with the actual project name at execution time.

		When no project name is supplied, shows an interactive menu of all projects
		defined in the `Projects` array in Configuration.psd1. Multiple projects
		can be selected and will each be opened in sequence.

		The special action `Open-ProjectTerminals-Or-RunProject` is context-sensitive:
		with `-RunApp` it starts the project server via `Run-Project`; otherwise
		it opens terminal tabs via `Open-ProjectTerminals`.

		Returns the list of project names that were opened.

	.PARAMETER Project
		One or more project names as defined in the `Projects` configuration array.
		Omit to show the interactive selection menu.

	.PARAMETER RunApp
		Switch to start the project's runnable app instead of opening terminals.
		Applies to the `Open-ProjectTerminals-Or-RunProject` action only.

	.EXAMPLE
		Open-Project
		Shows the project selection menu.

	.EXAMPLE
		Open-Project -Project "MyApp"
		Opens the MyApp project with all configured actions.

	.EXAMPLE
		Open-Project -Project "MyApp" -RunApp
		Opens MyApp and starts the application server.
	#>
	[CmdletBinding()]
	param (
		[Parameter()]
		[string[]]$Project,

		[Parameter()]
		[switch]$RunApp,

		[Parameter()]
		[string]$VSCodeWorkspace
	)

	$resolveParams = @{
		InputObject              = $Project
		OptionList               = $Configuration.Projects
		MenuTitle                = "[Available projects]"
		PromptMessage            = "Enter project(s) or press Enter to skip"
		AllowMultipleSelections  = $true
		AllowEmptyPromptResponse = $true
	}

	$projects = Resolve-Selection @resolveParams

	if ($null -eq $projects) {
		Write-LogWarning "No project selected!"
	}

	$RunAppBool = $RunApp.IsPresent

	foreach ($projectName in $projects) {
		$projectActions = $Configuration.ProjectActions[$projectName]

		if (-not $projectActions) {
			Write-LogWarning "No actions configured for project [$projectName]"
			continue
		}

		foreach ($actionConfig in $projectActions) {
			$action = $actionConfig.Action
			$parameters = $actionConfig.Parameters

			$actionParams = @{}

			if ($parameters) {
				foreach ($key in $parameters.Keys) {
					$value = $parameters[$key]

					if ($value -is [string] -and $value -eq "{ProjectName}") {
						$value = $projectName
					}

					$actionParams[$key] = $value
				}
			}

			# TODO: Make run compatible with workspaces (unpredictable tab opening of the app, maybe not worth the trouble)
			if ($action -eq "Open-VSCode" -and $VSCodeWorkspace) {
				# A VS Code workspace override REPLACES the project folder for this editor
				# window: open the .code-workspace file instead of the project's folder.
				# Terminals and every other action still run as configured.
				try {
					& "Open-VSCodeWorkspace" -VSCodeWorkspace $VSCodeWorkspace
				}
				catch {
					Write-LogError "Error opening VS Code workspace [$VSCodeWorkspace] for project [$projectName] => $_"
				}
			}
			elseif ($action -eq "Open-ProjectTerminals-Or-RunProject") {
				if ($RunAppBool) {
					& "Run-Project" @actionParams
				}
				else {
					& "Open-ProjectTerminals" @actionParams
				}
			}
			else {
				try {
					if ($actionParams.Count -gt 0) {
						& $action @actionParams
					}
					else {
						& $action
					}
				}
				catch {
					Write-LogError "Error executing action [$action] for project [$projectName] => $_"
				}
			}
		}
	}

	return $projects
}
