function Open-Workspace {
	<#
	.SYNOPSIS
		Opens a predefined workspace with configured applications, browser tabs, and window layouts.

	.DESCRIPTION
		Opens a workspace by executing a sequence of configured actions such as opening projects,
		browsers, applications, and applying window layouts across virtual desktops.

	.PARAMETER Workspace
		The name of the workspace(s) to open. Can be specified by name or selected from a menu.

	.PARAMETER Project
		Optional project name(s) to pass to Open-Project action within the workspace.

	.PARAMETER Alongside
		Opens the workspace on new virtual desktop(s) alongside existing ones.
		This allows running multiple workspaces simultaneously without interfering with each other.
		New workspace desktops are added to the right of existing ones.
		For example, if you have WinuX workspace open and want to work on Server simultaneously,
		use: Open-Workspace Server -Alongside

	.EXAMPLE
		Open-Workspace WinuX
		# Opens WinuX workspace on the first virtual desktop(s)

	.EXAMPLE
		Open-Workspace Server -Alongside
		# Opens Server workspace on virtual desktops to the right of existing ones

	#>
	[CmdletBinding()]
	param (
		[Parameter(Position = 0)]
		[string[]]$Workspace,

		[Parameter(Position = 1)]
		[string[]]$Project,

		[Parameter()]
		[switch]$Alongside,

		[Parameter(ValueFromRemainingArguments = $true)]
		[object[]]$ExtraArgs
	)

	$workspaceTimerEnvVar = 'OPEN_WORKSPACE_START_UTC'
	$currentInvocationStartUtc = [DateTimeOffset]::UtcNow
	$carryOverElapsed = [TimeSpan]::Zero
	$persistedStartUtc = $null
	$persistedStartUtcRaw = [Environment]::GetEnvironmentVariable($workspaceTimerEnvVar, 'Process')

	if (-not [string]::IsNullOrWhiteSpace($persistedStartUtcRaw)) {
		try {
			$persistedStartUtc = [DateTimeOffset]::ParseExact(
				$persistedStartUtcRaw,
				'o',
				[System.Globalization.CultureInfo]::InvariantCulture,
				[System.Globalization.DateTimeStyles]::RoundtripKind
			)

			if ($currentInvocationStartUtc -ge $persistedStartUtc) {
				$carryOverElapsed = $currentInvocationStartUtc - $persistedStartUtc
			}
			else {
				[Environment]::SetEnvironmentVariable($workspaceTimerEnvVar, $currentInvocationStartUtc.ToString('o'), 'Process')
			}
		}
		catch {
			[Environment]::SetEnvironmentVariable($workspaceTimerEnvVar, $currentInvocationStartUtc.ToString('o'), 'Process')
		}
	}
	else {
		[Environment]::SetEnvironmentVariable($workspaceTimerEnvVar, $currentInvocationStartUtc.ToString('o'), 'Process')
	}

	$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
	try {
		# Every process this flow spawns (apps, terminals, and PowerToys if Start-FancyZones
		# has to launch it) inherits this shell's token. From an elevated shell that means
		# elevated app windows - which a non-elevated FancyZones cannot snap - and/or an
		# elevated PowerToys that outlives this session. Warn once; the flow itself proceeds
		# unchanged.
		if (Test-AdminPrivileges -CheckOnly) {
			Write-LogWarning "Running from an elevated shell - spawned windows (and PowerToys, if started by this flow) will be elevated. FancyZones cannot snap elevated windows unless PowerToys itself runs elevated. Prefer running workspaces from a non-admin shell."
		}

		$resolveParams = @{
			InputObject              = $Workspace
			OptionList               = $Configuration.Workspaces
			MenuTitle                = "[Available workspaces]"
			PromptMessage            = "Enter workspace(s) or press [Enter] to open default workspace"
			AllowEmptyPromptResponse = $true
			AllowMultipleSelections  = $true
		}

		# Parse ExtraArgs into a hashtable for forwarding to actions
		# Supports: -ParamName Value, -SwitchParam, -ParamName "Value With Spaces"
		$extraParams = @{}
		if ($ExtraArgs) {
			for ($i = 0; $i -lt $ExtraArgs.Count; $i++) {
				$arg = $ExtraArgs[$i]
				if ($arg -is [string] -and $arg.StartsWith('-')) {
					$paramName = $arg.TrimStart('-')
					# Check if next arg is a value or another parameter/end of array
					if (($i + 1) -lt $ExtraArgs.Count -and -not ($ExtraArgs[$i + 1] -is [string] -and $ExtraArgs[$i + 1].StartsWith('-'))) {
						$extraParams[$paramName] = $ExtraArgs[$i + 1]
						$i++  # Skip the value in next iteration
					}
					else {
						# It's a switch parameter
						$extraParams[$paramName] = $true
					}
				}
			}
		}

		$workspaces = Resolve-Selection @resolveParams

		# Uncomment this if you want some "Workspace" to open as default on wrong input
		# if ($null -eq $workspaces) {
		#     $workspaces = @("Default")
		# }

		if (-not $workspaces) {
			Write-LogWarning "No valid workspaces selected! Exiting..."
			return
		}

		foreach ($workspaceName in $workspaces) {
			# Calculate desktop offset if -Alongside flag is used
			$desktopOffset = 0
			if ($Alongside) {
				$desktopOffset = Get-NextAvailableDesktopIndex
				Write-LogTitle "Opening $workspaceName Workspace alongside current"
			}
			else {
				Write-LogTitle "Opening $workspaceName Workspace"
			}

			$workspaceActions = $Configuration.WorkspaceActions[$workspaceName]

			if (-not $workspaceActions) {
				Write-LogWarning "No actions configured for workspace [$workspaceName]"
				continue
			}

			# Resolve the VS Code workspace override for THIS workspace, if any. Precedence:
			#   1. explicit -VSCodeWorkspace <name> on the command line
			#   2. per-workspace default in $Configuration.DefaultVSCodeWorkspaces
			#   3. bare "-VSCodeWorkspace" flag (no value) => interactive Resolve-Selection menu
			#   4. none => today's behaviour (VS Code opens the project folder; layout matches it)
			# The resolved name is forwarded via $effectiveExtraParams to Open-Project (which
			# reroutes its Open-VSCode action to Open-VSCodeWorkspace) and to
			# Set-WorkspaceWindowLayout (which retitles the inferred VS Code layout entry).
			$effectiveExtraParams = @{}
			foreach ($k in $extraParams.Keys) { $effectiveExtraParams[$k] = $extraParams[$k] }

			$vscodeWorkspaceRaw = $extraParams['VSCodeWorkspace']
			$resolvedVSCodeWorkspace = $null
			if ($vscodeWorkspaceRaw -is [string] -and -not [string]::IsNullOrWhiteSpace($vscodeWorkspaceRaw)) {
				$resolvedVSCodeWorkspace = $vscodeWorkspaceRaw.Trim()
			}
			elseif ($vscodeWorkspaceRaw) {
				# Bare "-VSCodeWorkspace" with no value => list available workspaces to choose from.
				$availableVSCodeWorkspaces = Get-VSCodeWorkspaceNames
				if ($availableVSCodeWorkspaces.Count -gt 0) {
					$resolvedVSCodeWorkspace = Resolve-Selection -OptionList $availableVSCodeWorkspaces `
						-MenuTitle "[Available VS Code workspaces]" `
						-PromptMessage "Enter VS Code workspace or press [Enter] to skip" `
						-AllowEmptyPromptResponse
				}
				else {
					Write-LogWarning "No VS Code workspaces found to choose from!"
				}
			}
			elseif ($Configuration.DefaultVSCodeWorkspaces -and $Configuration.DefaultVSCodeWorkspaces[$workspaceName]) {
				$resolvedVSCodeWorkspace = $Configuration.DefaultVSCodeWorkspaces[$workspaceName]
			}

			if ($resolvedVSCodeWorkspace -is [array]) {
				$resolvedVSCodeWorkspace = @($resolvedVSCodeWorkspace)[0]
			}

			if ($resolvedVSCodeWorkspace) {
				$effectiveExtraParams['VSCodeWorkspace'] = $resolvedVSCodeWorkspace
				Write-LogDebug " [Open-Workspace] VS Code workspace override => [$resolvedVSCodeWorkspace]" -Style Success
			}
			else {
				$effectiveExtraParams.Remove('VSCodeWorkspace') | Out-Null
			}

			# Capture existing windows BEFORE opening any applications
			# This allows Set-WorkspaceWindowLayout to properly detect first run
			$existingWindowsBeforeOpen = Get-WindowHandle -ErrorAction SilentlyContinue
			$existingHandlesBeforeOpen = New-Object 'System.Collections.Generic.HashSet[IntPtr]'
			if ($existingWindowsBeforeOpen) {
				foreach ($win in $existingWindowsBeforeOpen) {
					$existingHandlesBeforeOpen.Add($win.Handle) | Out-Null
				}
			}

			$selectedProjects = @()

			# Pre-compute which project tab names belong to THIS workspace
			# Used to make the OnlyCurrent guard workspace-aware: skip terminate only
			# when the calling tab is from the SAME workspace (idempotent re-run),
			# not when it's from a DIFFERENT workspace's project tab
			$workspaceProjectTabNames = @()
			foreach ($ac in $workspaceActions) {
				if ($ac.Action -eq "Open-Project") {
					$projName = if ($ac.Parameters -and $ac.Parameters.Project) { $ac.Parameters.Project } elseif ($Project) { $Project } else { $null }
					if ($projName) {
						$projMapping = $Configuration.ProjectTerminals | Where-Object { $_.Name -eq $projName }
						if ($projMapping) {
							$paths = $projMapping.Paths
							foreach ($path in $paths) {
								$workspaceProjectTabNames += "$projName.$path"
							}
						}
					}
				}
			}

			foreach ($actionConfig in $workspaceActions) {
				$action = $actionConfig.Action
				$parameters = $actionConfig.Parameters

				if ($action -eq "Return") {
					return
				}

				$actionParams = @{}

				if ($parameters) {
					foreach ($key in $parameters.Keys) {
						$actionParams[$key] = $parameters[$key]
					}
				}

				# Merge extra parameters (from command line) - action config takes precedence.
				# Uses $effectiveExtraParams (the CLI args with the resolved VSCodeWorkspace name
				# folded in) so the override reaches Open-Project and Set-WorkspaceWindowLayout.
				foreach ($key in $effectiveExtraParams.Keys) {
					if (-not $actionParams.ContainsKey($key)) {
						$actionParams[$key] = $effectiveExtraParams[$key]
					}
				}

				if ($action -eq "Open-Project") {
					if (-not $actionParams.ContainsKey("Project") -and $Project) {
						$actionParams["Project"] = $Project
					}

					# Capture the selected projects for swagger mapping
					try {
						$filteredParams = Get-FilteredParams -CommandName $action -Params $actionParams
						if ($filteredParams.Count -gt 0) {
							$selectedProjects = & $action @filteredParams
						}
						else {
							$selectedProjects = & $action
						}
					}
					catch {
						Write-LogError "Error executing action [$action] for workspace [$workspaceName]: $_"
					}

					# Skip the general execution block for Open-Project since we already executed it
					continue
				}
				elseif ($action -eq "Open-Browser") {
					# Inject the current project's Swagger UI tab into the browser groups (when it has one
					# and it isn't already open). The swagger-group resolution + duplicate check now lives in
					# Resolve-SwaggerBrowserGroup so it can be reused outside of Open-Workspace.
					# Priority: 1) explicit -Project, 2) projects selected by a preceding Open-Project action.
					$projectForSwagger = if ($Project) {
						$Project
					}
					elseif ($selectedProjects -and $selectedProjects.Count -gt 0) {
						$selectedProjects
					}
					else {
						$null
					}

					if ($projectForSwagger) {
						$swaggerBrowser = if ($actionParams.ContainsKey("Browser")) { $actionParams["Browser"] } else { $null }
						$swaggerGroup = Resolve-SwaggerBrowserGroup -Project $projectForSwagger -Browser $swaggerBrowser

						if ($swaggerGroup) {
							if ($actionParams.ContainsKey("Groups")) {
								$actionParams["Groups"] += $swaggerGroup
							}
							else {
								$actionParams["Groups"] = @($swaggerGroup)
							}
						}
					}
				}

				# Pass pre-captured existing windows and desktop offset to Set-WorkspaceWindowLayout
				if ($action -eq "Set-WorkspaceWindowLayout") {
					$actionParams["PreCapturedExistingWindows"] = $existingHandlesBeforeOpen
					if ($desktopOffset -gt 0) {
						$actionParams["DesktopOffset"] = $desktopOffset
					}
					if ($Alongside) {
						$actionParams["Alongside"] = $true
					}
				}

				# In alongside mode the workspace lands on desktops to the right of existing ones,
				# so the configured Focus-VirtualDesktop landing (e.g. DesktopNumber = 1) must be
				# shifted by the same offset. Inject DesktopOffset so the workspace's own first
				# desktop (DesktopNumber + offset) is focused instead of the original desktop 1.
				if ($action -eq "Focus-VirtualDesktop" -and $desktopOffset -gt 0) {
					$actionParams["DesktopOffset"] = $desktopOffset
				}

				# Skip Terminate-WindowsTerminalTabs -OnlyCurrent when:
				# 1. -Alongside is active (the calling tab belongs to an existing workspace)
				# 2. The calling tab is a project terminal tab for THIS workspace (idempotent re-run)
				#    But NOT when it's from a DIFFERENT workspace's project tab
				if ($action -eq "Terminate-WindowsTerminalTabs" -and $actionParams.ContainsKey("OnlyCurrent") -and $actionParams["OnlyCurrent"]) {
					if ($Alongside) {
						Write-LogDebug " [Open-Workspace] Skipping Terminate-WindowsTerminalTabs -OnlyCurrent (opening alongside)" -Style Warning
						continue
					}
					if ($env:WT_PROJECT_TAB) {
						$isCallerTabForThisWorkspace = $workspaceProjectTabNames | Where-Object { $env:WT_PROJECT_TAB -match [regex]::Escape($_) }
						if ($isCallerTabForThisWorkspace) {
							Write-LogDebug " [Open-Workspace] Skipping Terminate-WindowsTerminalTabs -OnlyCurrent (calling from same-workspace project tab: $env:WT_PROJECT_TAB)" -Style Warning
							continue
						}
						# Don't skip - calling tab is from a different workspace's project
						Write-LogDebug " [Open-Workspace] Proceeding with Terminate-WindowsTerminalTabs -OnlyCurrent (calling from different-workspace project tab: $env:WT_PROJECT_TAB)"
					}
				}

				try {
					$filteredParams = Get-FilteredParams -CommandName $action -Params $actionParams
					if ($filteredParams.Count -gt 0) {
						& $action @filteredParams
					}
					else {
						& $action
					}
				}
				catch {
					Write-LogError "Error executing action [$action] for workspace [$workspaceName]: $_" -NoLeadingNewline
				}
			}
		}

		$stopwatch.Stop()
		$elapsedSeconds = [math]::Round(($carryOverElapsed + $stopwatch.Elapsed).TotalSeconds, 1)
		Write-LogSuccess "Workspace(s) opened in $elapsedSeconds seconds!"
	}
	finally {
		[Environment]::SetEnvironmentVariable($workspaceTimerEnvVar, $null, 'Process')
	}
}
