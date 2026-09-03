function Open-Workspace {
	<#
	.SYNOPSIS
		Opens a predefined workspace with configured applications, browser tabs, and window layouts.

	.DESCRIPTION
		Opens a workspace by executing a sequence of configured actions such as opening projects,
		browsers, applications, and applying window layouts across virtual desktops.

		Actions can receive the workspace's project context via the {SelectedProjects} token: a
		configured parameter whose FULL value is the literal string "{SelectedProjects}" resolves
		at runtime to the explicit -Project argument, else to the projects returned by this
		workspace's Open-Project action. When neither exists the parameter is dropped, so the
		consuming action (e.g. Open-ProjectSwagger) can no-op or apply its own default. Declare
		consumers AFTER the Open-Project action.

		A plain (non-Alongside) open resets only what it owns. Workspaces that are tracked as
		opened -Alongside and still have at least one live window are PRESERVED
		(Get-WorkspaceOpenProtection): their windows are never moved or counted by any action,
		their virtual desktops are never removed, and their tracker entries and CurrentLayout
		sections survive the plain open's writes. Rerunning "Open-Workspace A" with workspace B
		open alongside therefore resets A without destroying B.

	.PARAMETER Workspace
		The name of the workspace(s) to open. Can be specified by name or selected from a menu.
		Omit it for the interactive menu; pressing [Enter] there with no input opens the workspace
		named by $Configuration.DefaultWorkspace. When no usable default is configured the prompt
		offers to cancel instead, and [Enter] exits without opening anything.

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

		The mode is forwarded as -Alongside to every action that declares the parameter
		(Get-FilteredParams drops it from the ones that do not), because alongside changes what
		an action may work with, not only where its windows land: the layout pass positions
		solely the windows this open created, so a count-based opener such as
		Open-Browser -Instances must open that many NEW windows instead of counting
		already-open ones toward the target - otherwise the layout is starved by exactly the
		number of windows that happened to be open, and worsens on every rerun.

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
	$summaryPrinted = $false
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

		# [Enter] at the workspace menu opens $Configuration.DefaultWorkspace - the same shape
		# Send-WakeOnLan uses for DefaultWakeOnLanMachine (config key + prompt naming the actual
		# default + post-selection fallback). The default is only honoured, and only advertised
		# in the prompt, when it actually has a WorkspaceActions entry: offering a workspace whose
		# open could merely log "No actions configured" would be the same broken promise this
		# replaces. With no usable default the prompt says "cancel" and [Enter] does exactly that.
		$defaultWorkspace = $Configuration.DefaultWorkspace
		if ($defaultWorkspace -is [array]) { $defaultWorkspace = @($defaultWorkspace)[0] }
		$defaultWorkspace = if ([string]::IsNullOrWhiteSpace($defaultWorkspace)) { $null } else { ([string]$defaultWorkspace).Trim() }

		if ($defaultWorkspace -and -not ($Configuration.WorkspaceActions -and $Configuration.WorkspaceActions[$defaultWorkspace])) {
			Write-LogDebug " [Open-Workspace] Configured DefaultWorkspace [$defaultWorkspace] has no WorkspaceActions entry - [Enter] will cancel instead" -Style Warning
			$defaultWorkspace = $null
		}

		# A -Workspace argument that resolves to nothing is a bad argument, not a request for the
		# default, so only the genuinely interactive [Enter] falls back below. This mirrors exactly
		# when Resolve-Selection takes its InputObject path instead of showing the menu.
		$hasWorkspaceArgument = @($Workspace | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -gt 0

		$workspacePrompt = if ($defaultWorkspace) {
			"Enter workspace(s) or press [Enter] to open default workspace => $defaultWorkspace"
		}
		else {
			"Enter workspace(s), or press [Enter] to cancel"
		}

		$resolveParams = @{
			InputObject              = $Workspace
			OptionList               = $Configuration.Workspaces
			MenuTitle                = "[Available workspaces]"
			PromptMessage            = $workspacePrompt
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

		# Resolve-Selection re-prompts on invalid menu input, so on the interactive path an empty
		# result means one thing only: the user pressed [Enter] on the prompt above.
		if (-not $workspaces -and -not $hasWorkspaceArgument -and $defaultWorkspace) {
			Write-LogDebug " [Open-Workspace] Empty selection - opening default workspace => [$defaultWorkspace]" -Style Success
			$workspaces = @($defaultWorkspace)
		}

		if (-not $workspaces) {
			Write-LogWarning "No valid workspaces selected! Exiting..."
			return
		}

		# Record this exact invocation (with RESOLVED workspace names - the user may have picked
		# them from the interactive menu) so a failure-path respawn reruns precisely this command
		# instead of scraping the shared PSReadLine history, where any other session may have
		# written a newer line meanwhile. Cleared in the finally block; consumed by
		# Set-WorkspaceWindowLayout when it escalates to ReRun-LastCommand.
		$quoteRerunToken = { param($value) "'" + ([string]$value -replace "'", "''") + "'" }
		$rerunTokens = @('Open-Workspace')
		$rerunTokens += '-Workspace'
		$rerunTokens += (@($workspaces) | ForEach-Object { & $quoteRerunToken $_ }) -join ', '
		if ($Project) {
			$rerunTokens += '-Project'
			$rerunTokens += (@($Project) | ForEach-Object { & $quoteRerunToken $_ }) -join ', '
		}
		if ($Alongside) {
			$rerunTokens += '-Alongside'
		}
		foreach ($extraArg in $ExtraArgs) {
			if ($extraArg -is [string] -and $extraArg.StartsWith('-')) {
				$rerunTokens += $extraArg
			}
			elseif ($extraArg -is [bool]) {
				$rerunTokens += '$' + $extraArg.ToString().ToLower()
			}
			elseif ($extraArg -is [array]) {
				$rerunTokens += (@($extraArg) | ForEach-Object { & $quoteRerunToken $_ }) -join ', '
			}
			else {
				$rerunTokens += & $quoteRerunToken $extraArg
			}
		}
		$env:WORKSPACE_RERUN_COMMAND = $rerunTokens -join ' '

		# What this plain open must leave alone: alongside workspaces that are still standing.
		# Resolved ONCE, before any action can spawn a process - a window created mid-run must
		# never be mistaken for a protected one. The handle set is threaded to every action
		# below and the entries seed the tracker write, so a plain rerun of workspace A no
		# longer removes B's desktops, steals B's windows, or wipes B's records. Alongside
		# opens already add without destroying and need no protection of their own.
		$openProtection = if (-not $Alongside) { Get-WorkspaceOpenProtection } else { $null }
		if ($openProtection) {
			$protectedNames = @($openProtection.Entries | ForEach-Object { [string]$_.Workspace } | Select-Object -Unique)
			Write-LogDebug " [Open-Workspace] Preserving live alongside workspace(s) => [$($protectedNames -join ', ')] ($($openProtection.WindowHandles.Count) protected window(s))" -Style Success
		}

		# How many workspaces of THIS invocation have been recorded so far. Only the first one of a
		# plain run defines the session (and so adopts what is on screen); the rest append to it.
		$workspacesRecorded = 0

		foreach ($workspaceName in $workspaces) {
			# Benchmark clocks for this workspace: one for the whole open, one per action. The
			# layout action's own phase breakdown is read back from Get-WorkspaceLayoutTimings
			# when the row is written - see $recordWorkspaceBenchmark below.
			$workspaceClock = [System.Diagnostics.Stopwatch]::StartNew()
			$workspaceStartedAt = [DateTimeOffset]::Now
			$actionTimings = [System.Collections.Generic.List[object]]::new()

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

			# Teardown tracking. Close-Workspace closes what an open ACTUALLY produced, never what
			# configuration says it would produce, and the before/after delta recorded here is the
			# only evidence of that. Capturing it is what keeps a single-instance application out of
			# the wrong workspace: Obsidian already running because an earlier workspace opened it
			# is in the "before" set, so it never becomes this workspace's to close. Terminal tabs
			# need their own snapshot because they are not top-level windows - opening three project
			# tabs in an existing window changes no window handle at all.
			$existingTerminalTabsBeforeOpen = Get-TerminalTabSnapshot

			# The matching AFTER snapshot, taken further down at the last moment the terminal is still
			# on the visible desktop - right before the layout action parks it on one of this
			# workspace's own desktops. Leaving it to the recorder means reading a terminal that is by
			# then off screen, which costs a desktop round trip the user sees as the view jumping to
			# the terminal and back AFTER this workspace's final Focus-VirtualDesktop landing. Reset
			# per workspace: a later workspace of a multi-workspace run captures its own.
			$terminalTabsAfterOpen = $null

			$workspaceStateRecorded = $false
			$recordWorkspaceState = {
				# The FIRST workspace of a plain run also claims what was already on screen, not
				# only what it created. A plain open resets the desktops, so when it finishes the
				# screen IS this workspace - including any app that was already running and
				# therefore produced no new window to diff (Open-ClaudeDesktop reporting "already
				# running"). Without that, such an app escapes one teardown, is already running at
				# every later open, is never recorded again, and can never be closed.
				# Get-WorkspaceOpenDelta keeps Universal.VisibleWindowExclusions out of that claim,
				# so the terminal window this was typed in stays nobody's to close.
				#
				# -Alongside must not adopt: it adds to a screen other workspaces are using, and
				# claiming their windows would let closing this one take theirs. Later workspaces of
				# a multi-workspace plain run likewise only claim what they created, and append so
				# they do not replace the entry of the workspace that defined the session.
				$isFirstOfPlainRun = (-not $Alongside) -and ($workspacesRecorded -eq 0)

				$saveStateParams = @{
					Workspace               = $workspaceName
					ExistingWindowHandles   = $existingHandlesBeforeOpen
					ExistingTerminalTabs    = $existingTerminalTabsBeforeOpen
					PreCapturedTerminalTabs = $terminalTabsAfterOpen
					DesktopOffset           = $desktopOffset
					Alongside               = [bool]$Alongside
					AdoptUnclaimed          = [bool]$isFirstOfPlainRun
					Append                  = ($workspacesRecorded -gt 0)
				}

				# A plain rerun's tracker write must carry the surviving alongside entries forward
				# (or they become unclosable) and must not adopt their windows into this entry.
				# Keys are added conditionally - the parameters are never bound to $null.
				if ($openProtection) {
					$saveStateParams['PreserveEntry'] = $openProtection.Entries
					$saveStateParams['ProtectedWindowHandles'] = $openProtection.WindowHandles
				}

				Save-WorkspaceState @saveStateParams
			}

			# Measured, not eyeballed: one benchmark row per workspace open, from the per-action
			# clock above and the phase clock Set-WorkspaceWindowLayout publishes through
			# Get-WorkspaceLayoutTimings. Both calls are guarded by Get-Command - the Window
			# module may be absent and the tests stub them - and the write is best-effort, so the
			# benchmark can never fail an open. The layout record is attached only when it was
			# produced by THIS workspace: the getter returns the session's most recent run, which
			# a workspace without a layout action would otherwise inherit from an earlier open.
			$recordWorkspaceBenchmark = {
				if (-not (Get-Command Write-WorkspaceBenchmark -ErrorAction SilentlyContinue)) { return }

				$layoutTimings = $null
				if (Get-Command Get-WorkspaceLayoutTimings -ErrorAction SilentlyContinue) {
					$candidateTimings = Get-WorkspaceLayoutTimings
					if ($candidateTimings -and $candidateTimings.RecordedAt -and $candidateTimings.RecordedAt -ge $workspaceStartedAt) {
						$layoutTimings = $candidateTimings
					}
				}

				try {
					Write-WorkspaceBenchmark -Workspace $workspaceName `
						-TotalSeconds ([math]::Round($workspaceClock.Elapsed.TotalSeconds, 2)) `
						-ActionTimings $actionTimings.ToArray() `
						-LayoutTimings $layoutTimings `
						-Alongside:$Alongside
				}
				catch {
					Write-LogDebug " [Open-Workspace] Benchmark row not written => $($_.Exception.Message)" -Style Warning
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

				# Inside the relaunched alongside shell every terminal-opening action must
				# land its tabs in THIS new window instead of spawning yet another one:
				# force InSameShell on. Get-FilteredParams strips the parameter from
				# actions that do not support it.
				if ($Alongside -and $isAlongsideShell) {
					$actionParams["InSameShell"] = $true
				}

				# Alongside changes WHAT an action may work with, not only where the layout
				# lands: the layout pass positions solely the windows this open created, so a
				# count-based action (Open-Browser -Instances) has to open that many NEW windows
				# rather than count pre-existing ones toward the target - otherwise the layout is
				# starved by exactly the number of windows that were already open. Forward the
				# mode to every action that declares it; Get-FilteredParams drops it from the
				# ones that do not.
				if ($Alongside) {
					$actionParams["Alongside"] = $true
				}

				# Plain-open counterpart of the -Alongside forwarding above: every action that
				# declares ProtectedWindowHandles receives the handles of the alongside
				# workspaces being preserved (Get-FilteredParams drops it from the rest). The
				# layout pass must not move them, count-based openers must not count them, and
				# the desktop resize must not shrink below them.
				if ($openProtection) {
					$actionParams["ProtectedWindowHandles"] = $openProtection.WindowHandles
				}

				# Generic project-context handoff: a parameter whose FULL value is the literal
				# "{SelectedProjects}" resolves at runtime to (1) the explicit -Project argument,
				# else (2) the projects returned by this workspace's Open-Project action. With
				# neither available the parameter is dropped so the action can no-op or apply
				# its own default. Declare consumers (e.g. Open-ProjectSwagger) AFTER Open-Project.
				$resolvedSelectedProjects = if ($Project) {
					@($Project)
				}
				elseif ($selectedProjects) {
					@($selectedProjects | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
				}
				else {
					@()
				}

				foreach ($tokenKey in @($actionParams.Keys)) {
					$tokenValue = $actionParams[$tokenKey]
					if ($tokenValue -is [string] -and $tokenValue -eq "{SelectedProjects}") {
						if ($resolvedSelectedProjects.Count -gt 0) {
							$actionParams[$tokenKey] = $resolvedSelectedProjects
							Write-LogDebug " [Open-Workspace] {SelectedProjects} => [$($resolvedSelectedProjects -join ', ')] for [$action].$tokenKey" -Style Success
						}
						else {
							$actionParams.Remove($tokenKey)
							Write-LogDebug " [Open-Workspace] Dropped [$tokenKey] for [$action] - no projects resolved for {SelectedProjects}" -Style Warning
						}
					}
				}

				if ($action -eq "Open-Project") {
					if (-not $actionParams.ContainsKey("Project") -and $Project) {
						$actionParams["Project"] = $Project
					}

					# Capture the selected projects for {SelectedProjects} substitution in later actions
					$actionClock = [System.Diagnostics.Stopwatch]::StartNew()
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
					$actionTimings.Add([PSCustomObject]@{ Action = $action; Seconds = [math]::Round($actionClock.Elapsed.TotalSeconds, 2) })

					# Skip the general execution block for Open-Project since we already executed it
					continue
				}

				# Pass pre-captured existing windows and desktop offset to Set-WorkspaceWindowLayout
				if ($action -eq "Set-WorkspaceWindowLayout") {
					$actionParams["PreCapturedExistingWindows"] = $existingHandlesBeforeOpen
					if ($desktopOffset -gt 0) {
						$actionParams["DesktopOffset"] = $desktopOffset
					}

					# Last moment the terminal is guaranteed readable: THIS action is what moves it onto
					# one of the workspace's own desktops, and Windows Terminal composes its tab strip
					# only while its desktop is on screen. Every tab-creating action (Open-Project,
					# Open-Terminal) has already run by now, so this snapshot is the same one the
					# recorder would take at the end of the open - minus the desktop round trip.
					#
					# -EnsureVisible only bites for a later workspace of a multi-workspace run, whose
					# terminal an earlier layout may already have parked elsewhere; it is a no-op while
					# the terminal is on the visible desktop, which is the normal case here.
					if ($null -eq $terminalTabsAfterOpen) {
						$terminalTabsAfterOpen = Get-TerminalTabSnapshot -EnsureVisible
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

				# Terminate-WindowsTerminalTabs with -OnlyCurrent/-IncludeCurrent ends THIS
				# process via [Environment]::Exit, which skips finally blocks - the elapsed
				# summary and the keyboard-modifier self-heal in the finally below would never
				# run. Do both now, before handing control to the terminating action.
				if ($action -eq "Terminate-WindowsTerminalTabs" -and
					(($actionParams.ContainsKey("OnlyCurrent") -and $actionParams["OnlyCurrent"]) -or
					($actionParams.ContainsKey("IncludeCurrent") -and $actionParams["IncludeCurrent"]))) {
					# Same reason the summary is printed early: the teardown record must exist before
					# the process exits, or the workspace this run just opened would be untracked and
					# Close-Workspace could not close it.
					if (-not $workspaceStateRecorded) {
						$workspaceStateRecorded = $true
						& $recordWorkspaceState
						& $recordWorkspaceBenchmark
						$workspacesRecorded++
					}

					$stopwatch.Stop()
					$elapsedSeconds = [math]::Round(($carryOverElapsed + $stopwatch.Elapsed).TotalSeconds, 1)
					Write-LogSuccess "Workspace(s) opened in $elapsedSeconds seconds!"
					$summaryPrinted = $true
					[Environment]::SetEnvironmentVariable($workspaceTimerEnvVar, $null, 'Process')
					[Environment]::SetEnvironmentVariable('WORKSPACE_RERUN_COMMAND', $null, 'Process')
					if (Get-Command Reset-KeyboardModifiers -ErrorAction SilentlyContinue) {
						$null = Reset-KeyboardModifiers
					}
				}

				$actionClock = [System.Diagnostics.Stopwatch]::StartNew()
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
				$actionTimings.Add([PSCustomObject]@{ Action = $action; Seconds = [math]::Round($actionClock.Elapsed.TotalSeconds, 2) })
			}

			# Every action has run, so whatever is on screen beyond the pre-open capture is this
			# workspace's. A terminating action already recorded it and exited; this covers the
			# ordinary path where the flow simply reaches the end.
			if (-not $workspaceStateRecorded) {
				$workspaceStateRecorded = $true
				& $recordWorkspaceState
				& $recordWorkspaceBenchmark
				$workspacesRecorded++
			}
		}

		$stopwatch.Stop()
		if (-not $summaryPrinted) {
			$elapsedSeconds = [math]::Round(($carryOverElapsed + $stopwatch.Elapsed).TotalSeconds, 1)
			Write-LogSuccess "Workspace(s) opened in $elapsedSeconds seconds!"
		}
	}
	finally {
		[Environment]::SetEnvironmentVariable($workspaceTimerEnvVar, $null, 'Process')
		[Environment]::SetEnvironmentVariable('WORKSPACE_RERUN_COMMAND', $null, 'Process')

		# The flow above synthesizes keyboard input (FancyZones shortcuts, Win+Arrow
		# snaps, shift-drag, terminal tab cycling). Guarantee the session never leaves
		# this flow with a modifier logically held down. No-op when
		# nothing is stuck.
		if (Get-Command Reset-KeyboardModifiers -ErrorAction SilentlyContinue) {
			$null = Reset-KeyboardModifiers
		}
	}
}
