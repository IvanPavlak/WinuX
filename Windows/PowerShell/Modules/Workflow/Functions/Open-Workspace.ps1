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

		The whole open flow always runs in a completely new shell window: the invocation is
		relaunched in a fresh Windows Terminal window and the calling shell gets its prompt
		back immediately. Inside that new window, terminal-opening actions are forced to
		-InSameShell so the workspace's terminal tabs join the new window instead of
		spawning further windows.

	.EXAMPLE
		Open-Workspace WinuX
		# Opens WinuX workspace on the first virtual desktop(s)

	.EXAMPLE
		Open-Workspace Server -Alongside
		# Relaunches in a new shell window and opens Server workspace on virtual desktops
		# to the right of existing ones; Server's terminal tabs open in that new window

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

	# -Alongside relaunches this whole invocation inside a brand-new shell window (see
	# the relaunch block below). The relaunched instance is marked with this env var;
	# the marker is consumed immediately so only THIS invocation treats itself as the
	# relaunched one - a later -Alongside run typed into that same shell window
	# relaunches into its own new window again.
	$alongsideShellEnvVar = 'OPEN_WORKSPACE_ALONGSIDE_SHELL'
	$isAlongsideShell = -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($alongsideShellEnvVar, 'Process'))
	if ($isAlongsideShell) {
		[Environment]::SetEnvironmentVariable($alongsideShellEnvVar, $null, 'Process')
	}

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
		# -Alongside always runs in a completely new shell: replay this exact invocation
		# in a fresh Windows Terminal window and hand the calling shell its prompt back.
		# The new window is created under a GUID chosen HERE and handed to the child as
		# WT_WINDOW_ID, so every InSameShell tab the child opens targets this exact
		# window - "wt -w 0" resolves to the most recently used window, which with the
		# caller's window still open is not necessarily the new one. The bootstrap
		# command also marks the new shell via $alongsideShellEnvVar (so it executes
		# the flow instead of relaunching again), carries the timer start across so the
		# reported duration includes the relaunch, and clears WT_PROJECT_TAB because
		# the new window's WT process can inherit it from a project-tab caller and the
		# bootstrap tab must not pass for a project tab. Inside the new shell,
		# terminal-opening actions are forced to -InSameShell (see the action loop) so
		# their tabs join the new window, and a configured
		# Terminate-WindowsTerminalTabs -OnlyCurrent closes the redundant bootstrap tab
		# as its final step.
		if ($Alongside -and -not $isAlongsideShell) {
			$quote = { param($value) "'" + ([string]$value -replace "'", "''") + "'" }

			$invocationTokens = @('Open-Workspace')
			if ($Workspace) {
				$invocationTokens += '-Workspace'
				$invocationTokens += (@($Workspace) | ForEach-Object { & $quote $_ }) -join ', '
			}
			if ($Project) {
				$invocationTokens += '-Project'
				$invocationTokens += (@($Project) | ForEach-Object { & $quote $_ }) -join ', '
			}
			$invocationTokens += '-Alongside'
			foreach ($extraArg in $ExtraArgs) {
				if ($extraArg -is [string] -and $extraArg.StartsWith('-')) {
					$invocationTokens += $extraArg
				}
				elseif ($extraArg -is [bool]) {
					$invocationTokens += '$' + $extraArg.ToString().ToLower()
				}
				elseif ($extraArg -is [array]) {
					$invocationTokens += (@($extraArg) | ForEach-Object { & $quote $_ }) -join ', '
				}
				else {
					$invocationTokens += & $quote $extraArg
				}
			}

			$alongsideWindowId = [guid]::NewGuid().ToString()
			$effectiveStartUtc = $currentInvocationStartUtc - $carryOverElapsed
			$bootstrapCommand = "`$env:WT_PROJECT_TAB = `$null; " +
			"`$env:WT_WINDOW_ID = '$alongsideWindowId'; " +
			"`$env:$workspaceTimerEnvVar = '$($effectiveStartUtc.ToString('o'))'; " +
			"`$env:$alongsideShellEnvVar = '1'; " +
			($invocationTokens -join ' ')

			$workspaceLabel = if ($Workspace) { " $($Workspace -join ', ')" } else { "" }
			Write-LogTitle "Relaunching [Open-Workspace$workspaceLabel -Alongside] in a new shell window"
			Write-LogDebug " [Open-Workspace] Alongside relaunch command => [$($invocationTokens -join ' ')]" -Style Success
			Write-LogDebug " [Open-Workspace] Alongside shell window ID => [$alongsideWindowId]" -Style Success
			Open-Terminal -Command $bootstrapCommand -WindowId $alongsideWindowId
			return
		}

		# Every process this flow spawns (apps, terminals, and PowerToys if Start-FancyZones
		# has to launch it) inherits this shell's token. From an elevated shell that means
		# elevated app windows - which a non-elevated FancyZones cannot snap - and/or an
		# elevated PowerToys that outlives this session. Warn once; the flow itself proceeds
		# unchanged.
		if (Test-AdminPrivileges -CheckOnly) {
			Write-LogWarning "Running from an elevated shell - spawned windows (and PowerToys, if started by this flow) will be elevated. FancyZones cannot snap elevated windows unless PowerToys itself runs elevated. Prefer running workspaces from a non-admin shell."
		}

		# The relaunched shell's own hosting window IS the new workspace's terminal
		# window (project tabs join it via InSameShell), but it was spawned by the
		# parent invocation moments before this run - so the per-workspace "existing
		# windows" capture below would classify it as pre-existing, and the alongside
		# layout (which skips existing windows to protect other workspaces) would
		# never place it on the workspace desktops. Identify it up front by flashing
		# a unique marker into this shell's window title and finding which Windows
		# Terminal window reflects it, so each capture can exclude it.
		$ownTerminalWindowHandle = $null
		if ($Alongside -and $isAlongsideShell) {
			$originalHostTitle = $null
			try {
				$originalHostTitle = $Host.UI.RawUI.WindowTitle
				$titleProbe = "AlongsideShell_" + [guid]::NewGuid().ToString()
				$Host.UI.RawUI.WindowTitle = $titleProbe
				Start-Sleep -Milliseconds 50

				$ownTerminalWindow = Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue |
					Where-Object { $_.Title -like "*$titleProbe*" } |
					Select-Object -First 1

				if ($ownTerminalWindow) {
					$ownTerminalWindowHandle = $ownTerminalWindow.Handle
					Write-LogDebug " [Open-Workspace] Alongside shell hosting window => [$ownTerminalWindowHandle]" -Style Success
				}
				else {
					Write-LogDebug " [Open-Workspace] Could not identify the alongside shell's own window (title probe not reflected) - the new terminal window will not be laid out" -Style Warning
				}
			}
			catch {
				Write-LogDebug " [Open-Workspace] Window title probe failed => $($_.Exception.Message)" -Style Warning
			}
			finally {
				if ($null -ne $originalHostTitle) {
					try { $Host.UI.RawUI.WindowTitle = $originalHostTitle } catch {}
				}
			}
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
				if ($null -eq $desktopOffset) {
					# Desktop enumeration failed - proceeding with offset 0 would open this
					# workspace ON TOP of the existing one, the exact thing -Alongside prevents.
					Write-LogError "Cannot determine the next available desktop for [$workspaceName] (virtual desktop enumeration failed) - skipping alongside open."
					continue
				}
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

			# The relaunched shell's own window hosts this workspace's terminal tabs -
			# treat it as NEW so the alongside layout places it on the workspace desktops.
			if ($ownTerminalWindowHandle) {
				$existingHandlesBeforeOpen.Remove($ownTerminalWindowHandle) | Out-Null
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

				# Inside the relaunched alongside shell every terminal-opening action must
				# land its tabs in THIS new window instead of spawning yet another one:
				# force InSameShell on. Get-FilteredParams strips the parameter from
				# actions that do not support it.
				if ($Alongside -and $isAlongsideShell) {
					$actionParams["InSameShell"] = $true
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

				# Skip Terminate-WindowsTerminalTabs -OnlyCurrent when the calling tab is a
				# project terminal tab for THIS workspace (idempotent re-run), but NOT when
				# it's from a DIFFERENT workspace's project tab. In alongside mode this code
				# only ever runs inside the relaunched shell (the parent invocation returns
				# right after spawning it), where the calling tab is the disposable bootstrap
				# tab - closing it is exactly what we want, so alongside is not skipped here.
				if ($action -eq "Terminate-WindowsTerminalTabs" -and $actionParams.ContainsKey("OnlyCurrent") -and $actionParams["OnlyCurrent"]) {
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

		# The flow above synthesizes keyboard input (FancyZones shortcuts, Win+Arrow
		# snaps, shift-drag, terminal tab cycling). Guarantee the session never leaves
		# this flow with a modifier logically held down. No-op when
		# nothing is stuck.
		if (Get-Command Reset-KeyboardModifiers -ErrorAction SilentlyContinue) {
			$null = Reset-KeyboardModifiers
		}
	}
}
