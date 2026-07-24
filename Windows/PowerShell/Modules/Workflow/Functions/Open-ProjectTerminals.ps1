function Send-TerminalKeys {
	# Thin, mockable wrapper around the .NET SendKeys call so tests can stub it: no real
	# keystrokes are sent during testing, and the intermittent SendWait Win32 throw is avoided.
	# Module-private (not exported / not a separate Functions file), so it adds no manifest/docs surface.
	param([Parameter(Mandatory)][string]$Keys)
	Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
	[System.Windows.Forms.SendKeys]::SendWait($Keys)
}

function Open-ProjectTerminals {
	<#
	.SYNOPSIS
		Opens project-specific terminals with automatic tab naming and optional focus control.

	.DESCRIPTION
		Opens terminal tabs for specified projects based on configuration in $Configuration.ProjectTerminals.
		Each project can have multiple paths (e.g., Api, Ui, Root) that open in separate tabs.

		Features:
		- Automatic tab naming using format "ProjectName.PathKey" (e.g., "ExampleProject.Api", "WinuX.Root")
		- Optional onefetch display for repository information
		- Flexible tab focus options: return to origin, focus specific project tab, or use tab index
		- Interactive project selection when no project is specified
		- Configurable window grouping via InSameShell and InSameGroup parameters:
		  - InSameShell + InSameGroup: All tabs in the current window
		  - InSameShell + not InSameGroup: Each project in its own new window
		  - not InSameShell + InSameGroup: All projects grouped in one new window
		  - not InSameShell + not InSameGroup: Every tab in its own new window

		Special path types in Paths array:
		- "DEFAULT": Opens a plain terminal tab at the default starting directory (no Set-Location).
		  Useful for projects that just need a shell without a specific path (e.g., Server).
		- "WSL": Opens a WSL tab using the configured DefaultWSLDistribution.
		- @{ Key = "Name"; Path = "C:\custom\path" }: Opens a tab at an explicit custom path
		  without requiring a matching entry in PathTemplates.
		- @{ Key = "Name" }: Opens a plain tab (like DEFAULT) with a custom tab name.

	.PARAMETER Project
		Array of project names to open terminals for. Projects must be defined in $Configuration.ProjectTerminals.
		If not specified, displays an interactive selection menu.
		Available projects: WinuX, ExampleProject, AnotherProject

	.PARAMETER InvokeOnefetch
		Executes the onefetch command in each terminal tab to display repository information.
		Default: $true

	.PARAMETER InSameShell
		Opens all terminal tabs in the current Windows Terminal window instead of creating a new window.
		Default: $false
		Note: When not explicitly specified, only one Windows Terminal window is open, and that
		window has no existing project tabs, this is automatically set to $true so tabs open in
		the existing window. If project tabs from another project are already open, the new
		project opens in a new window to keep project groups separate.

	.PARAMETER InSameGroup
		Controls whether tabs from different projects are grouped together in the same window.
		Default: $true

		Behavior matrix with InSameShell:
		- InSameShell:$true  + InSameGroup:$true  => All tabs open in the current window
		- InSameShell:$true  + InSameGroup:$false => Each project opens in its own new window
		- InSameShell:$false + InSameGroup:$true  => All projects grouped in a single new window
		- InSameShell:$false + InSameGroup:$false => Every tab opens in its own new window

	.PARAMETER FocusTab
		Specifies which tab to focus after all project terminals are opened.
		Options:
		- "origin": Returns focus to the original tab where the function was called
		- "ProjectName.PathKey": Focuses a specific project tab (e.g., "ExampleProject.Api", "WinuX.Root")
		- Numeric index: Focuses tab at specific position (e.g., "0" for first tab, "1" for second tab)
		Default: "0" (focuses the first tab)

		Note: Named tab focusing uses keyboard navigation (Ctrl+Shift+Tab) relative to the last created tab.

	.PARAMETER Force
		Forces opening terminals even if they are already open. Bypasses the idempotency check that
		normally skips projects when all their tabs are already open. When Force is specified, all tabs
		will be opened regardless of whether they already exist.
		Default: $false

	.EXAMPLE
		Open-ProjectTerminals
		Opens interactive menu to select project(s).

	.EXAMPLE
		Open-ProjectTerminals -Project "WinuX"
		Opens terminal for WinuX project with tab named "WinuX.Root".

	.EXAMPLE
		Open-ProjectTerminals -Project "ExampleProject"
		Opens terminals for ExampleProject project with tabs "ExampleProject.Api" and "ExampleProject.Ui".

	.EXAMPLE
		Open-ProjectTerminals -Project "ExampleProject" -FocusTab "origin"
		Opens ExampleProject terminals and returns focus to the original tab.

	.EXAMPLE
		Open-ProjectTerminals -Project "ExampleProject" -FocusTab "ExampleProject.Api"
		Opens ExampleProject terminals and focuses the "ExampleProject.Api" tab.

	.EXAMPLE
		Open-ProjectTerminals -Project "ExampleProject", "AnotherProject" -InvokeOnefetch:$false
		Opens terminals for both ExampleProject and AnotherProject projects without running onefetch.

	.EXAMPLE
		Open-ProjectTerminals -Project "WinuX" -InSameShell:$false
		Opens WinuX terminal in a new Windows Terminal window.

	.EXAMPLE
		Open-ProjectTerminals -Project "ExampleProject", "AnotherProject" -InSameGroup:$false
		Opens ExampleProject and AnotherProject terminals each in their own new Windows Terminal window.

	.EXAMPLE
		Open-ProjectTerminals -Project "ExampleProject", "AnotherProject" -InSameShell:$false -InSameGroup:$false
		Opens every terminal tab in its own new window.

	.EXAMPLE
		Open-ProjectTerminals -Project "ExampleProject" -FocusTab "1"
		Opens ExampleProject terminals and focuses the second tab (index 1).

	.EXAMPLE
		Open-ProjectTerminals -Project "Server"
		Opens Server terminals with a default PowerShell tab and a WSL tab.
		# Config: Paths = @("DEFAULT", "WSL")

	.EXAMPLE
		# Custom path entry in configuration:
		# "MyProject" = @{ BasePath = "Projects.MyProject"; Paths = @("API", @{ Key = "Logs"; Path = "C:\Logs" }) }
		# Opens the API tab from PathTemplates and a "Logs" tab at C:\Logs.

	.EXAMPLE
		Open-ProjectTerminals -Project "ExampleProject" -Force
		Opens ExampleProject terminals even if they are already open, bypassing idempotency checks.

	.EXAMPLE
		Open-ProjectTerminals -Project "ExampleProject", "AnotherProject" -Force -InSameShell:$false
		Forces opening both ExampleProject and AnotherProject projects in new windows, even if tabs already exist.
	#>
	[CmdletBinding()]
	param (
		[Parameter()]
		[string[]]$Project,

		[Parameter()]
		[switch]$InvokeOnefetch = $true,

		[Parameter()]
		[switch]$InSameShell = $false,

		[Parameter()]
		[switch]$InSameGroup = $true,

		[Parameter()]
		[string]$FocusTab = "0",

		[Parameter()]
		[switch]$Force = $false
	)

	# Auto-detect: if only one Windows Terminal window is open, InSameShell was
	# not explicitly specified, and no project tabs are already open, use the
	# same window so tabs join the existing instance
	if (-not $PSBoundParameters.ContainsKey('InSameShell')) {
		$allWtWindows = @(Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue)
		if ($allWtWindows.Count -eq 1) {
			# Build a regex that matches any known project tab title (e.g. "WinuX.Root")
			$projectNames = @($Configuration.ProjectTerminals.Name)
			$hasProjectTabs = $false

			if ($projectNames.Count -gt 0) {
				$escapedNames = $projectNames | ForEach-Object { [regex]::Escape($_) }
				$projectTabPattern = "^($($escapedNames -join '|'))\."
				$wtHandle = $allWtWindows[0].Handle

				# Preferred path: read all tab titles through UI Automation - no focus
				# stealing, no Ctrl+Tab cycling, no navigate-back pass.
				$tabTitles = Get-WindowsTerminalTabTitles -WindowHandle $wtHandle

				if ($null -ne $tabTitles) {
					foreach ($tabTitle in $tabTitles) {
						if ($tabTitle -match $projectTabPattern) {
							$hasProjectTabs = $true
							break
						}
					}
				}
				else {
					# Legacy fallback (UIA unavailable): cycle tabs with Ctrl+Tab and
					# navigate back to the starting tab afterwards.
					Add-Type -AssemblyName System.Windows.Forms
					[void][WindowModule.Native]::SetForegroundWindow($wtHandle)
					Start-Sleep -Milliseconds 50

					$startWindow = Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue |
						Where-Object { $_.Handle -eq $wtHandle }
					$startingTitle = if ($startWindow) { $startWindow.Title } else { $null }

					if ($startingTitle) {
						$checkedTitles = @($startingTitle)

						if ($startingTitle -match $projectTabPattern) {
							$hasProjectTabs = $true
						}

						if (-not $hasProjectTabs) {
							$maxTabs = 20
							for ($i = 0; $i -lt $maxTabs; $i++) {
								Send-TerminalKeys "^{TAB}"
								Start-Sleep -Milliseconds 10

								$currentWindow = Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue |
									Where-Object { $_.Handle -eq $wtHandle }
								$currentTitle = if ($currentWindow) { $currentWindow.Title } else { $null }

								if (-not $currentTitle -or $checkedTitles -contains $currentTitle) { break }
								$checkedTitles += $currentTitle

								if ($currentTitle -match $projectTabPattern) {
									$hasProjectTabs = $true
									break
								}
							}
						}

						# Navigate back to the starting tab if we moved away
						if ($checkedTitles.Count -gt 1) {
							for ($i = 0; $i -lt 20; $i++) {
								$currentWindow = Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue |
									Where-Object { $_.Handle -eq $wtHandle }
								$currentTitle = if ($currentWindow) { $currentWindow.Title } else { $null }
								if ($currentTitle -eq $startingTitle) { break }
								Send-TerminalKeys "^{TAB}"
								Start-Sleep -Milliseconds 10
							}
						}
					}
				}
			}

			if (-not $hasProjectTabs) {
				$InSameShell = [switch]::new($true)
			}
		}
	}

	# Handle origin tab naming for later focus
	$originTabName = $null
	if ($FocusTab -eq "origin" -and $InSameShell -and $InSameGroup) {
		$originTabName = "OriginTab_$(Get-Random -Minimum 10000 -Maximum 99999)"
		$host.UI.RawUI.WindowTitle = $originTabName
	}

	$resolveParams = @{
		InputObject             = $Project
		OptionList              = $Configuration.ProjectTerminals.Name
		MenuTitle               = "[Available Project Terminals]"
		AllowMultipleSelections = $true
	}

	$terminals = Resolve-Selection @resolveParams

	# Prefer the exact caller WT window when available. Window ID 0 can resolve to
	# a different existing window, while WT_WINDOW_ID points to the current window.
	$callerWindowId = if ($env:WT_WINDOW_ID) { $env:WT_WINDOW_ID } else { "0" }

	# Determine window ID strategy based on InSameShell and InSameGroup
	# InSameShell + InSameGroup   => all tabs in current caller window
	# InSameShell + !InSameGroup  => each project in its own new window (GUID per project)
	# !InSameShell + InSameGroup  => all projects in one new window (single GUID for all)
	# !InSameShell + !InSameGroup => every tab in its own new window (GUID per tab)
	$sharedWindowId = $null
	if ($InSameShell -and $InSameGroup) {
		$sharedWindowId = $callerWindowId
	}
	elseif (-not $InSameShell -and $InSameGroup) {
		$sharedWindowId = [guid]::NewGuid().ToString()
	}
	# Other cases are handled per-project or per-tab inside the loop

	# Track tab names and their relative positions for focus functionality
	$tabNamesList = @()
	$totalTabsCreated = 0

	foreach ($terminal in $terminals) {
		try {
			$mapping = $Configuration.ProjectTerminals | Where-Object { $_.Name -eq $terminal }

			if (-not $mapping) {
				Write-LogError "Error: Project [$terminal] not found in configuration!"
				continue
			}

			$expectedTabNames = @()
			foreach ($pathEntry in $mapping.Paths) {
				if ($pathEntry -is [hashtable]) {
					$expectedTabNames += "$terminal.$($pathEntry.Key)"
				}
				else {
					$expectedTabNames += "$terminal.$pathEntry"
				}
			}

			Write-LogStep "Opening [$terminal] project terminals..."

			$tabCheckResult = Test-TerminalTabsAlreadyOpen -ExpectedTabNames $expectedTabNames -ProjectName $terminal
			if ($tabCheckResult.AllOpen -and -not $Force) {
				continue
			}

			# Determine which tabs still need to be opened
			$alreadyOpenTabs = @($tabCheckResult.FoundTabs)
			$hasPartialTabs = $alreadyOpenTabs.Count -gt 0

			# Determine the window ID for this project
			# When some tabs already exist in the current window, open missing tabs
			# in the caller window so they join the existing ones
			# Exception: when Force is specified, ignore partial tabs and use configured window strategy
			$projectWindowId = if ($hasPartialTabs -and -not $Force) {
				$callerWindowId
			}
			elseif ($sharedWindowId) {
				$sharedWindowId
			}
			elseif ($InSameShell -and -not $InSameGroup) {
				# Each project gets its own new window
				[guid]::NewGuid().ToString()
			}
			else {
				# !InSameShell + !InSameGroup => new GUID per tab (handled below)
				$null
			}

			# Batch consecutive pwsh tabs into ONE Open-Terminal call, which chains them into a
			# single ordered wt invocation - the old one-spawn-per-tab pattern paid a process
			# spawn + 25ms sleep per tab and still had no cross-spawn ordering guarantee.
			# WSL tabs use a different WT profile and are spawned directly; they flush the
			# batch first so the on-screen tab order matches the configured order.
			$pendingTabCommands = [System.Collections.Generic.List[string]]::new()
			$pendingTabTitles = [System.Collections.Generic.List[string]]::new()

			$flushPendingTabs = {
				if ($pendingTabCommands.Count -eq 0) { return }
				$batchWindowId = if ($projectWindowId) { $projectWindowId } else { [guid]::NewGuid().ToString() }
				Open-Terminal -Command $pendingTabCommands.ToArray() -WindowId $batchWindowId -TabTitles $pendingTabTitles.ToArray()
				$pendingTabCommands.Clear()
				$pendingTabTitles.Clear()
				# Small settle between separate wt invocations targeting the same window
				# (one per batch, not per tab).
				Start-Sleep -Milliseconds 25
			}

			$queueTab = {
				param([string]$TabCommand, [string]$TabTitle)
				$pendingTabCommands.Add($TabCommand)
				$pendingTabTitles.Add($TabTitle)
				# Without a shared project window every tab gets its OWN window - flush each
				# immediately so every batch mints its own window GUID.
				if (-not $projectWindowId) { & $flushPendingTabs }
			}

			# Iterate through each path entry and open tabs sequentially to preserve order
			foreach ($pathEntry in $mapping.Paths) {
				# Determine tab name and path type based on entry format
				# Supported formats:
				#   "PathKey"                              - Resolves from PathTemplates
				#   "DEFAULT"                              - Plain tab at default directory
				#   "WSL"                                  - WSL tab
				#   @{ Key = "Name"; Path = "C:\path" }    - Custom explicit path
				#   @{ Key = "Name" }                       - Plain tab with custom name
				if ($pathEntry -is [hashtable]) {
					$pathKey = $pathEntry.Key
					$customPath = $pathEntry.Path
					$isCustomEntry = $true
				}
				else {
					$pathKey = $pathEntry
					$customPath = $null
					$isCustomEntry = $false
				}

				$tabName = "$terminal.$pathKey"

				# Skip tabs that are already open (unless Force is specified)
				if ($Force -eq $false -and $alreadyOpenTabs -contains $tabName) {
					Write-LogWarning "  Skipping [$tabName] (already open)" -NoLeadingNewline
					continue
				}

				# Handle WSL as a special case
				if ($pathKey -eq "WSL") {
					$distro = $Configuration.DefaultWSLDistribution

					try {
						# Preserve on-screen ordering: everything queued so far must exist
						# before the WSL tab is spawned.
						& $flushPendingTabs

						$wslWindowId = if ($projectWindowId) { $projectWindowId } else { [guid]::NewGuid().ToString() }
						Start-Process wt -ArgumentList @("-w", $wslWindowId, "new-tab", "-p", $distro, "--title", $tabName) -WindowStyle Hidden

						# Wait briefly for Windows Terminal to process the new-tab command
						# This prevents race conditions when opening multiple tabs in succession
						Start-Sleep -Milliseconds 25

						# Track tab names in order
						$tabNamesList += $tabName
						$totalTabsCreated++
					}
					catch {
						Write-LogError "Error opening WSL tab: [$_]" -NoLeadingNewline
					}
				}
				# Handle DEFAULT - opens a plain tab at the terminal's default starting directory
				elseif ($pathKey -eq "DEFAULT" -or ($isCustomEntry -and -not $customPath)) {
					try {
						& $queueTab "" $tabName

						# Track tab names in order
						$tabNamesList += $tabName
						$totalTabsCreated++
					}
					catch {
						Write-LogError "Error opening DEFAULT tab: [$_]" -NoLeadingNewline
					}
				}
				# Handle custom path entries (hashtable with Key and Path)
				elseif ($isCustomEntry -and $customPath) {
					$cmd = "Set-Location -Path '$customPath'"
					if ($InvokeOnefetch) { $cmd += "; onefetch" }

					& $queueTab $cmd $tabName

					# Track tab names in order
					$tabNamesList += $tabName
					$totalTabsCreated++
				}
				else {
					# Handle regular path - resolve from PathTemplates
					$path = Resolve-ProjectPath -ProjectName $terminal -PathKey $pathKey

					$cmd = "Set-Location -Path '$path'"
					if ($InvokeOnefetch) { $cmd += "; onefetch" }

					& $queueTab $cmd $tabName

					# Track tab names in order
					$tabNamesList += $tabName
					$totalTabsCreated++
				}
			}

			# Open whatever is still queued for this project in one wt invocation.
			& $flushPendingTabs

			Write-LogSuccess "Project [$terminal] terminals opened!"
		}
		catch {
			Write-LogError "Error: $($_.Exception.Message)" -BlankLineAfter
		}
	}

	# Focus tab based on FocusTab parameter (only when tabs share a window)
	$focusWindowId = $sharedWindowId
	if ($FocusTab -and $focusWindowId) {

		if ($FocusTab -eq "origin" -and $originTabName) {
			# Focus by tab name (origin tab)
			Start-Process wt -ArgumentList @("-w", $focusWindowId, "focus-tab", "-n", $originTabName) -WindowStyle Hidden
		}
		elseif ($FocusTab -match '^\d+$') {
			# Focus by tab index (numeric string)
			Start-Process wt -ArgumentList @("-w", $focusWindowId, "focus-tab", "-t", $FocusTab) -WindowStyle Hidden
		}
		elseif ($tabNamesList -contains $FocusTab) {
			# Focus by tracked tab name (navigate relative to last created tab)
			# The last created tab is currently active, find how many tabs back we need to go
			$targetPosition = $tabNamesList.IndexOf($FocusTab)
			$lastPosition = $tabNamesList.Count - 1
			$stepsBack = $lastPosition - $targetPosition

			if ($stepsBack -gt 0) {
				# Use keyboard shortcuts to navigate backwards through tabs
				# Load Windows Forms for SendKeys
				Add-Type -AssemblyName System.Windows.Forms

				# Focus the Windows Terminal window first
				$wtProcess = Get-Process | Where-Object { $_.ProcessName -eq "WindowsTerminal" } | Select-Object -First 1
				if ($wtProcess) {
					# Bring Windows Terminal to foreground
					[void][System.Reflection.Assembly]::LoadWithPartialName("Microsoft.VisualBasic")
					try {
						[Microsoft.VisualBasic.Interaction]::AppActivate($wtProcess.Id)
					}
					catch {
						# Process may have exited or lacks a visible window - fall back to window handle
						$wtWindow = Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue | Select-Object -First 1
						if ($wtWindow) {
							[void][WindowModule.Native]::SetForegroundWindow($wtWindow.Handle)
						}
					}

					# Send Ctrl+Shift+Tab to move backwards through tabs
					for ($i = 0; $i -lt $stepsBack; $i++) {
						Send-TerminalKeys "^+{TAB}"
					}
				}
			}
			# If stepsBack is 0, the tab is already active (it's the last created tab)
		}
		else {
			Write-LogWarning "Warning: Tab [$FocusTab] not found in opened tabs!"
		}
	}
}
