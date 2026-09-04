#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Workflow\Functions"
	$SystemFunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Open-Workspace.ps1"
	. "$SystemFunctionsPath\Terminate-WindowsTerminalTabs.ps1"

	function Resolve-Selection {
		param(
			$InputObject,
			$OptionList,
			$MenuTitle,
			$PromptMessage,
			[switch]$AllowEmptyPromptResponse,
			[switch]$AllowMultipleSelections
		)
		$InputObject
	}

	function Get-FilteredParams {
		param(
			$CommandName,
			$Params
		)
		$Params
	}

	function Get-WindowHandle { param($ProcessName) @() }
	function Get-TerminalTabSnapshot { param([switch]$EnsureVisible) @{} }
	function Save-WorkspaceState {
		param($Workspace, $ExistingWindowHandles, $ExistingTerminalTabs, $DesktopOffset, [switch]$Alongside, [switch]$AdoptUnclaimed, [switch]$Append, $PreserveEntry, $ProtectedWindowHandles, $Entry, $StatePath)
	}
	# Required for hermeticity: the Workflow module is bootstrap-imported, so without this stub
	# every plain open in these tests would run the REAL Get-WorkspaceOpenProtection against the
	# machine's actual tracker file.
	function Get-WorkspaceOpenProtection { $null }
	function Get-NextAvailableDesktopIndex { 0 }
	function Reset-KeyboardModifiers { param([switch]$IncludeMouseButton) @() }
	function Test-BrowserGroupAlreadyOpen { $false }
	function Open-Browser { param($Groups, $Browser) }
	function Open-Terminal { param($Command, [switch]$Administrator, [switch]$InSameShell, $WindowId, $TabTitles) }
	function Set-WorkspaceWindowLayout { param($WorkspaceName, $PreCapturedExistingWindows, $DesktopOffset, [switch]$Alongside, $ProtectedWindowHandles, [switch]$PrepareOnly) }
	# The benchmark writer and the layout phase getter are real module functions in a
	# bootstrap-imported session; stub them so no test run appends rows to the machine's
	# benchmark file or reads a real layout record.
	function Write-WorkspaceBenchmark { param($Workspace, $TotalSeconds, $ActionTimings, $LayoutTimings, [switch]$Alongside, $BenchmarkPath, [switch]$Quiet, [switch]$PassThru) }
	function Get-WorkspaceLayoutTimings { $null }
	function Get-WorkspaceBenchmark { param($Workspace, $Last, [switch]$Summary, [switch]$Formatted, $BenchmarkPath) }
	# The rerun-command store is real module state in a bootstrap-imported session; stub it so
	# these tests observe the calls without touching the module's record.
	function Set-WorkspaceRerunCommand { param([string]$Command, [switch]$Clear) }

	# Reads both variables while an open is running - the point of the in-process timer and
	# rerun record is that nothing spawned by the open can inherit them.
	function Test-CaptureEnvironmentAction {
		param()
		$script:envDuringOpen = [PSCustomObject]@{
			Timer        = [Environment]::GetEnvironmentVariable('OPEN_WORKSPACE_START_UTC', 'Process')
			RerunCommand = [Environment]::GetEnvironmentVariable('WORKSPACE_RERUN_COMMAND', 'Process')
		}
	}

	function Open-Project {
		param($Project)
		$Project
	}

	function Open-ProjectSwagger { param($Project, $Browser) }

	function Test-ActionOne {
		param($Alpha)
		$script:invokedActions += [PSCustomObject]@{ Name = 'Test-ActionOne'; Alpha = $Alpha }
	}

	function Test-ActionTwo {
		param($Beta)
		$script:invokedActions += [PSCustomObject]@{ Name = 'Test-ActionTwo'; Beta = $Beta }
	}

	function Test-ShellAwareAction {
		param($Alpha, [switch]$InSameShell)
		$script:invokedActions += [PSCustomObject]@{ Name = 'Test-ShellAwareAction'; Alpha = $Alpha; InSameShell = [bool]$InSameShell }
	}

	function Test-ThrowingAction {
		param()
		throw 'intentional action failure'
	}
}

Describe "Open-Workspace" {
	BeforeEach {
		$script:invokedActions = @()
		$script:terminateCalls = @()
		$script:browserCalls = @()
		$script:swaggerCalls = @()
		$script:setLayoutCalls = @()
		$script:prepareLayoutCalls = @()
		$script:openTerminalCalls = @()

		$script:resolveSelectionCalls = @()
		$script:workspaceStateCalls = @()
		$script:benchmarkCalls = @()
		$script:rerunCommandCalls = @()
		$script:envDuringOpen = $null
		Mock Set-WorkspaceRerunCommand {
			$script:rerunCommandCalls += [PSCustomObject]@{ Command = $Command; Clear = [bool]$Clear }
		}

		Mock Write-Host { }
		Mock Get-WorkspaceLayoutTimings { $null }
		Mock Get-WorkspaceBenchmark { }
		Mock Write-WorkspaceBenchmark {
			param($Workspace, $TotalSeconds, $ActionTimings, $LayoutTimings, [switch]$Alongside, $BenchmarkPath, [switch]$Quiet, [switch]$PassThru)
			$script:benchmarkCalls += [PSCustomObject]@{
				Workspace     = $Workspace
				TotalSeconds  = $TotalSeconds
				ActionTimings = @($ActionTimings)
				LayoutTimings = $LayoutTimings
				Alongside     = [bool]$Alongside
				Quiet         = [bool]$Quiet
			}
		}
		Mock Get-TerminalTabSnapshot { param([switch]$EnsureVisible) @{} }
		Mock Save-WorkspaceState {
			param($Workspace, $ExistingWindowHandles, $ExistingTerminalTabs, $PreCapturedTerminalTabs, $DesktopOffset, [switch]$Alongside, [switch]$AdoptUnclaimed, [switch]$Append, $PreserveEntry, $ProtectedWindowHandles, $Entry, $StatePath)
			$script:workspaceStateCalls += [PSCustomObject]@{
				Workspace                    = $Workspace
				DesktopOffset                = $DesktopOffset
				Alongside                    = [bool]$Alongside
				AdoptUnclaimed               = [bool]$AdoptUnclaimed
				Append                       = [bool]$Append
				PreCapturedTerminalTabs      = $PreCapturedTerminalTabs
				PreserveEntry                = $PreserveEntry
				ProtectedWindowHandles       = $ProtectedWindowHandles
				# "Not bound" is the assertion the null-protection test needs - a null VALUE
				# cannot distinguish "omitted" from "bound to $null".
				PreserveEntryBound           = $PSBoundParameters.ContainsKey('PreserveEntry')
				ProtectedWindowHandlesBound  = $PSBoundParameters.ContainsKey('ProtectedWindowHandles')
			}
		}
		Mock Get-WorkspaceOpenProtection { $null }
		# Capture PromptMessage too: the prompt advertises what [Enter] does, so the tests
		# below assert the string and the behaviour agree instead of only the behaviour.
		Mock Resolve-Selection {
			param(
				$InputObject,
				$OptionList,
				$MenuTitle,
				$PromptMessage,
				[switch]$AllowEmptyPromptResponse,
				[switch]$AllowMultipleSelections
			)
			$script:resolveSelectionCalls += [PSCustomObject]@{ InputObject = $InputObject; PromptMessage = $PromptMessage }
			$InputObject
		}
		Mock Get-WindowHandle { @() }
		# Mirror the real Get-FilteredParams contract: only parameters the target command
		# declares survive. Open-Workspace force-injects InSameShell in the relaunched
		# alongside shell and relies on this filtering to drop it from actions that do
		# not support it (e.g. Terminate-WindowsTerminalTabs).
		Mock Get-FilteredParams {
			param($CommandName, $Params)
			$cmdInfo = Get-Command $CommandName -ErrorAction SilentlyContinue
			if (-not $cmdInfo) { return $Params }
			$filtered = @{}
			foreach ($key in $Params.Keys) {
				if ($cmdInfo.Parameters.Keys -contains $key) {
					$filtered[$key] = $Params[$key]
				}
			}
			return $filtered
		}
		Mock Get-NextAvailableDesktopIndex { 3 }
		Mock Open-Project { param($Project) $Project }
		Mock Open-Browser {
			param($Groups, $Browser)
			$script:browserCalls += [PSCustomObject]@{ Groups = @($Groups); Browser = $Browser }
		}
		Mock Open-ProjectSwagger {
			param($Project, $Browser)
			$script:swaggerCalls += [PSCustomObject]@{ Project = @($Project); Browser = $Browser }
		}
		Mock Set-WorkspaceWindowLayout {
			param($WorkspaceName, $PreCapturedExistingWindows, $DesktopOffset, [switch]$Alongside, $ProtectedWindowHandles, [switch]$PrepareOnly)
			$layoutCall = [PSCustomObject]@{
				WorkspaceName               = $WorkspaceName
				PreCapturedExistingWindows  = $PreCapturedExistingWindows
				DesktopOffset               = $DesktopOffset
				Alongside                   = [bool]$Alongside
				ProtectedWindowHandles      = $ProtectedWindowHandles
				ProtectedWindowHandlesBound = $PSBoundParameters.ContainsKey('ProtectedWindowHandles')
				ActionsRunBefore            = @($script:invokedActions).Count
			}
			# The early preparation (-PrepareOnly) is recorded apart from the layout action, so
			# every count on $script:setLayoutCalls still means "the layout action ran".
			if ($PrepareOnly) { $script:prepareLayoutCalls += $layoutCall } else { $script:setLayoutCalls += $layoutCall }
		}
		Mock Terminate-WindowsTerminalTabs { param([switch]$OnlyCurrent) $script:terminateCalls += [PSCustomObject]@{ OnlyCurrent = [bool]$OnlyCurrent } }
		Mock Test-BrowserGroupAlreadyOpen { $false }
		Mock Open-Terminal {
			param($Command, [switch]$Administrator, [switch]$InSameShell, $WindowId, $TabTitles)
			$script:openTerminalCalls += [PSCustomObject]@{ Command = $Command; WindowId = $WindowId }
		}
		Mock Test-ActionOne { param($Alpha) $script:invokedActions += [PSCustomObject]@{ Name = 'Test-ActionOne'; Alpha = $Alpha } }
		Mock Test-ActionTwo { param($Beta) $script:invokedActions += [PSCustomObject]@{ Name = 'Test-ActionTwo'; Beta = $Beta } }
		Mock Test-ShellAwareAction { param($Alpha, [switch]$InSameShell) $script:invokedActions += [PSCustomObject]@{ Name = 'Test-ShellAwareAction'; Alpha = $Alpha; InSameShell = [bool]$InSameShell } }
		Mock Test-ThrowingAction { throw 'intentional action failure' }

		$script:Configuration = @{
			Workspaces         = @('TestWorkspace')
			DefaultWorkspace   = ''
			WorkspaceActions   = @{}
			ProjectTerminals   = @()
			BrowserGroups      = @()
			Universal          = @{ DefaultBrowser = 'Firefox' }
			# The shipped default: measurement is opt-in.
			WorkspaceBenchmark = @{ Enabled = $false; Display = 'Table'; Last = 10 }
		}

		$script:previousWtProjectTab = $env:WT_PROJECT_TAB
		Remove-Item Env:WT_PROJECT_TAB -ErrorAction SilentlyContinue

		$script:previousAlongsideShellMarker = $env:OPEN_WORKSPACE_ALONGSIDE_SHELL
		Remove-Item Env:OPEN_WORKSPACE_ALONGSIDE_SHELL -ErrorAction SilentlyContinue
	}

	AfterEach {
		if ($null -ne $script:previousWtProjectTab) {
			$env:WT_PROJECT_TAB = $script:previousWtProjectTab
		}
		else {
			Remove-Item Env:WT_PROJECT_TAB -ErrorAction SilentlyContinue
		}

		if ($null -ne $script:previousAlongsideShellMarker) {
			$env:OPEN_WORKSPACE_ALONGSIDE_SHELL = $script:previousAlongsideShellMarker
		}
		else {
			Remove-Item Env:OPEN_WORKSPACE_ALONGSIDE_SHELL -ErrorAction SilentlyContinue
		}
	}

	It "executes configured actions in order" {
		$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
			@{ Action = 'Test-ActionOne'; Parameters = @{ Alpha = 1 } },
			@{ Action = 'Test-ActionTwo'; Parameters = @{ Beta = 2 } }
		)

		Open-Workspace -Workspace 'TestWorkspace'

		$script:invokedActions.Count | Should -Be 2
		$script:invokedActions[0].Name | Should -Be 'Test-ActionOne'
		$script:invokedActions[0].Alpha | Should -Be 1
		$script:invokedActions[1].Name | Should -Be 'Test-ActionTwo'
		$script:invokedActions[1].Beta | Should -Be 2
	}

	Context "workspace benchmark" {
		BeforeEach {
			# Opt in for this context; Display None keeps the tests free of console rendering.
			$script:Configuration.WorkspaceBenchmark = @{ Enabled = $true; Display = 'None'; Last = 10 }
		}

		It "records nothing while WorkspaceBenchmark.Enabled is off, which is the shipped default" {
			$script:Configuration.WorkspaceBenchmark = @{ Enabled = $false; Display = 'Table'; Last = 10 }
			$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
				@{ Action = 'Test-ActionOne'; Parameters = @{ Alpha = 1 } }
			)

			Open-Workspace -Workspace 'TestWorkspace'

			$script:invokedActions.Count | Should -Be 1
			$script:benchmarkCalls.Count | Should -Be 0
			Should -Invoke Get-WorkspaceBenchmark -Times 0
		}

		It "shows the workspace's recent runs as a table after the row is written when Display is Table" {
			$script:Configuration.WorkspaceBenchmark = @{ Enabled = $true; Display = 'Table'; Last = 5 }
			$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
				@{ Action = 'Test-ActionOne'; Parameters = @{ Alpha = 1 } }
			)

			Open-Workspace -Workspace 'TestWorkspace'

			$script:benchmarkCalls.Count | Should -Be 1
			# The one-line summary is suppressed in favour of the table.
			$script:benchmarkCalls[0].Quiet | Should -BeTrue
			Should -Invoke Get-WorkspaceBenchmark -Times 1 -Exactly -ParameterFilter { $Workspace -eq 'TestWorkspace' -and $Last -eq 5 -and $Formatted }
		}

		It "prints the one-line summary instead of the table when Display is Line" {
			$script:Configuration.WorkspaceBenchmark = @{ Enabled = $true; Display = 'Line' }
			$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
				@{ Action = 'Test-ActionOne'; Parameters = @{ Alpha = 1 } }
			)

			Open-Workspace -Workspace 'TestWorkspace'

			$script:benchmarkCalls.Count | Should -Be 1
			$script:benchmarkCalls[0].Quiet | Should -BeFalse
			Should -Invoke Get-WorkspaceBenchmark -Times 0
		}

		It "records one benchmark row per workspace with every executed action timed, in order" {
			$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
				@{ Action = 'Test-ActionOne'; Parameters = @{ Alpha = 1 } },
				@{ Action = 'Test-ActionTwo'; Parameters = @{ Beta = 2 } }
			)

			Open-Workspace -Workspace 'TestWorkspace'

			$script:benchmarkCalls.Count | Should -Be 1
			$script:benchmarkCalls[0].Workspace | Should -Be 'TestWorkspace'
			$script:benchmarkCalls[0].Alongside | Should -BeFalse
			@($script:benchmarkCalls[0].ActionTimings.Action) | Should -Be @('Test-ActionOne', 'Test-ActionTwo')
			$script:benchmarkCalls[0].TotalSeconds | Should -BeGreaterOrEqual 0
			# No layout action ran, so no layout record is attached.
			$script:benchmarkCalls[0].LayoutTimings | Should -BeNullOrEmpty
		}

		It "times the Open-Project action too and writes one row per workspace of a multi-workspace run" {
			$script:Configuration.Workspaces = @('TestWorkspace', 'SecondWorkspace')
			$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
				@{ Action = 'Open-Project'; Parameters = @{ Project = 'ProjectA' } }
			)
			$script:Configuration.WorkspaceActions['SecondWorkspace'] = @(
				@{ Action = 'Test-ActionOne'; Parameters = @{ Alpha = 1 } }
			)

			Open-Workspace -Workspace 'TestWorkspace', 'SecondWorkspace'

			$script:benchmarkCalls.Count | Should -Be 2
			@($script:benchmarkCalls[0].ActionTimings.Action) | Should -Be @('Open-Project')
			$script:benchmarkCalls[1].Workspace | Should -Be 'SecondWorkspace'
		}

		It "attaches the layout phase record only when it was produced by this open" {
			$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
				@{ Action = 'Set-WorkspaceWindowLayout'; Parameters = @{ WorkspaceName = 'TestWorkspace' } }
			)
			# A record left by an earlier open in the same session must not be attributed to this one.
			Mock Get-WorkspaceLayoutTimings { [PSCustomObject]@{ Workspace = 'Stale'; RecordedAt = [DateTimeOffset]::Now.AddMinutes(-5) } }

			Open-Workspace -Workspace 'TestWorkspace'

			$script:benchmarkCalls.Count | Should -Be 1
			$script:benchmarkCalls[0].LayoutTimings | Should -BeNullOrEmpty

			Mock Get-WorkspaceLayoutTimings { [PSCustomObject]@{ Workspace = 'TestWorkspace'; RecordedAt = [DateTimeOffset]::Now.AddMinutes(5) } }
			$script:benchmarkCalls = @()

			Open-Workspace -Workspace 'TestWorkspace'

			$script:benchmarkCalls.Count | Should -Be 1
			$script:benchmarkCalls[0].LayoutTimings.Workspace | Should -Be 'TestWorkspace'
		}

		It "writes the row before a terminating Terminate-WindowsTerminalTabs action ends the process" {
			$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
				@{ Action = 'Test-ActionOne'; Parameters = @{ Alpha = 1 } },
				@{ Action = 'Terminate-WindowsTerminalTabs'; Parameters = @{ OnlyCurrent = $true } }
			)

			Open-Workspace -Workspace 'TestWorkspace'

			$script:terminateCalls.Count | Should -Be 1
			$script:benchmarkCalls.Count | Should -Be 1
			@($script:benchmarkCalls[0].ActionTimings.Action) | Should -Be @('Test-ActionOne')
		}
	}

	Context "default workspace on empty selection" {
		It "opens the configured DefaultWorkspace when the menu response is empty" {
			$script:Configuration.Workspaces = @('TestWorkspace', 'FallbackWorkspace')
			$script:Configuration.DefaultWorkspace = 'FallbackWorkspace'
			$script:Configuration.WorkspaceActions['FallbackWorkspace'] = @(
				@{ Action = 'Test-ActionOne'; Parameters = @{ Alpha = 11 } }
			)

			# No -Workspace argument: the mocked Resolve-Selection returns its (empty)
			# InputObject, which is exactly what the real one returns for a bare [Enter].
			Open-Workspace

			$script:invokedActions.Count | Should -Be 1
			$script:invokedActions[0].Name | Should -Be 'Test-ActionOne'
			$script:invokedActions[0].Alpha | Should -Be 11
		}

		It "advertises the configured DefaultWorkspace by name in the prompt" {
			$script:Configuration.Workspaces = @('TestWorkspace', 'FallbackWorkspace')
			$script:Configuration.DefaultWorkspace = 'FallbackWorkspace'
			$script:Configuration.WorkspaceActions['FallbackWorkspace'] = @(
				@{ Action = 'Test-ActionOne'; Parameters = @{ Alpha = 11 } }
			)

			Open-Workspace

			$script:resolveSelectionCalls.Count | Should -Be 1
			$script:resolveSelectionCalls[0].PromptMessage | Should -Match 'press \[Enter\] to open default workspace => FallbackWorkspace$'
		}

		It "offers to cancel and opens nothing when no DefaultWorkspace is configured" {
			$script:Configuration.DefaultWorkspace = ''
			$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
				@{ Action = 'Test-ActionOne'; Parameters = @{ Alpha = 1 } }
			)

			Open-Workspace

			$script:invokedActions.Count | Should -Be 0
			$script:resolveSelectionCalls[0].PromptMessage | Should -Match 'press \[Enter\] to cancel$'
			$script:resolveSelectionCalls[0].PromptMessage | Should -Not -BeLike '*default workspace*'
		}

		It "falls back to the cancel prompt when DefaultWorkspace has no WorkspaceActions entry" {
			# Advertising a default whose open could only log "No actions configured" would be
			# the same broken promise the config key exists to fix.
			$script:Configuration.DefaultWorkspace = 'GhostWorkspace'

			Open-Workspace

			$script:invokedActions.Count | Should -Be 0
			$script:resolveSelectionCalls[0].PromptMessage | Should -Match 'press \[Enter\] to cancel$'
		}

		It "does not fall back to the default when an explicit -Workspace argument resolves to nothing" {
			$script:Configuration.Workspaces = @('TestWorkspace', 'FallbackWorkspace')
			$script:Configuration.DefaultWorkspace = 'FallbackWorkspace'
			$script:Configuration.WorkspaceActions['FallbackWorkspace'] = @(
				@{ Action = 'Test-ActionOne'; Parameters = @{ Alpha = 11 } }
			)
			# A mistyped name is dropped by Resolve-Selection's InputObject path. That is a bad
			# argument, not a request for the default - only the interactive [Enter] falls back.
			Mock Resolve-Selection { @() }

			Open-Workspace -Workspace 'Mistyped'

			$script:invokedActions.Count | Should -Be 0
		}

		It "opens the explicitly named workspace rather than the default" {
			$script:Configuration.Workspaces = @('TestWorkspace', 'FallbackWorkspace')
			$script:Configuration.DefaultWorkspace = 'FallbackWorkspace'
			$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
				@{ Action = 'Test-ActionOne'; Parameters = @{ Alpha = 1 } }
			)
			$script:Configuration.WorkspaceActions['FallbackWorkspace'] = @(
				@{ Action = 'Test-ActionTwo'; Parameters = @{ Beta = 2 } }
			)

			Open-Workspace -Workspace 'TestWorkspace'

			$script:invokedActions.Count | Should -Be 1
			$script:invokedActions[0].Name | Should -Be 'Test-ActionOne'
		}
	}

	It "forwards ExtraArgs to actions only when parameter is not already configured" {
		$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
			@{ Action = 'Test-ActionOne'; Parameters = @{} },
			@{ Action = 'Test-ActionTwo'; Parameters = @{ Beta = 2 } }
		)

		Open-Workspace -Workspace 'TestWorkspace' -Alpha 77 -Beta 99

		$script:invokedActions.Count | Should -Be 2
		$script:invokedActions[0].Name | Should -Be 'Test-ActionOne'
		$script:invokedActions[0].Alpha | Should -Be 77
		$script:invokedActions[1].Name | Should -Be 'Test-ActionTwo'
		$script:invokedActions[1].Beta | Should -Be 2
	}

	It "relaunches -Alongside into a new shell window without running any actions" {
		$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
			@{ Action = 'Test-ActionOne'; Parameters = @{ Alpha = 1 } }
		)

		Open-Workspace -Workspace 'TestWorkspace' -Alongside

		$script:invokedActions.Count | Should -Be 0
		Should -Invoke Get-NextAvailableDesktopIndex -Times 0 -Exactly
		$script:openTerminalCalls.Count | Should -Be 1
		$command = $script:openTerminalCalls[0].Command
		$command | Should -BeLike "*`$env:WT_PROJECT_TAB = `$null;*"
		$command | Should -BeLike "*`$env:OPEN_WORKSPACE_START_UTC = '*'*"
		$command | Should -BeLike "*`$env:OPEN_WORKSPACE_ALONGSIDE_SHELL = '1';*"
		$command | Should -BeLike "*Open-Workspace -Workspace 'TestWorkspace' -Alongside"
	}

	It "creates the relaunch window under an explicit ID and hands it to the child via WT_WINDOW_ID" {
		$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
			@{ Action = 'Test-ActionOne'; Parameters = @{ Alpha = 1 } }
		)

		Open-Workspace -Workspace 'TestWorkspace' -Alongside

		$script:openTerminalCalls.Count | Should -Be 1
		$windowId = $script:openTerminalCalls[0].WindowId
		$windowId | Should -Not -BeNullOrEmpty
		{ [guid]::Parse($windowId) } | Should -Not -Throw
		$script:openTerminalCalls[0].Command | Should -BeLike "*`$env:WT_WINDOW_ID = '$windowId';*"
	}

	It "forwards Project and ExtraArgs in the relaunch command" {
		$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
			@{ Action = 'Test-ActionOne'; Parameters = @{ Alpha = 1 } }
		)

		Open-Workspace -Workspace 'TestWorkspace' -Project 'ProjectA' -Alongside -Override -CustomParam 'some value'

		$script:openTerminalCalls.Count | Should -Be 1
		$script:openTerminalCalls[0].Command |
			Should -BeLike "*Open-Workspace -Workspace 'TestWorkspace' -Project 'ProjectA' -Alongside -Override -CustomParam 'some value'"
	}

	It "runs Terminate-WindowsTerminalTabs -OnlyCurrent inside the relaunched alongside shell" {
		$env:OPEN_WORKSPACE_ALONGSIDE_SHELL = '1'
		$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
			@{ Action = 'Terminate-WindowsTerminalTabs'; Parameters = @{ OnlyCurrent = $true } }
		)

		Open-Workspace -Workspace 'TestWorkspace' -Alongside

		$script:openTerminalCalls.Count | Should -Be 0
		$script:terminateCalls.Count | Should -Be 1
		$script:terminateCalls[0].OnlyCurrent | Should -BeTrue
		Should -Invoke Get-NextAvailableDesktopIndex -Times 1 -Exactly
	}

	It "skips the alongside open when the next desktop index cannot be determined" {
		$env:OPEN_WORKSPACE_ALONGSIDE_SHELL = '1'
		$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
			@{ Action = 'Test-ActionOne'; Parameters = @{ Alpha = 1 } }
		)
		# Desktop enumeration failed (stale RPC): the offset is unknown. Proceeding with
		# offset 0 would open this workspace ON TOP of the existing one - the exact thing
		# -Alongside exists to prevent - so the workspace must be skipped entirely.
		Mock Get-NextAvailableDesktopIndex { $null }

		Open-Workspace -Workspace 'TestWorkspace' -Alongside

		$script:invokedActions.Count | Should -Be 0
	}

	It "forces InSameShell on actions inside the relaunched alongside shell and consumes the marker" {
		$env:OPEN_WORKSPACE_ALONGSIDE_SHELL = '1'
		$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
			@{ Action = 'Test-ShellAwareAction'; Parameters = @{ Alpha = 5 } }
		)

		Open-Workspace -Workspace 'TestWorkspace' -Alongside

		$script:openTerminalCalls.Count | Should -Be 0
		$script:invokedActions.Count | Should -Be 1
		$script:invokedActions[0].Name | Should -Be 'Test-ShellAwareAction'
		$script:invokedActions[0].Alpha | Should -Be 5
		$script:invokedActions[0].InSameShell | Should -BeTrue
		$env:OPEN_WORKSPACE_ALONGSIDE_SHELL | Should -BeNullOrEmpty
	}

	It "does not force InSameShell when opening without Alongside" {
		$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
			@{ Action = 'Test-ShellAwareAction'; Parameters = @{ Alpha = 6 } }
		)

		Open-Workspace -Workspace 'TestWorkspace'

		$script:openTerminalCalls.Count | Should -Be 0
		$script:invokedActions.Count | Should -Be 1
		$script:invokedActions[0].InSameShell | Should -BeFalse
	}

	It "skips Terminate-WindowsTerminalTabs -OnlyCurrent when caller tab belongs to same workspace project" {
		$script:Configuration.ProjectTerminals = @(
			@{ Name = 'ProjectA'; Paths = @('Api') }
		)
		$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
			@{ Action = 'Open-Project'; Parameters = @{ Project = 'ProjectA' } },
			@{ Action = 'Terminate-WindowsTerminalTabs'; Parameters = @{ OnlyCurrent = $true } }
		)
		$env:WT_PROJECT_TAB = 'ProjectA.Api'

		Open-Workspace -Workspace 'TestWorkspace'

		$script:terminateCalls.Count | Should -Be 0
	}

	It "does not skip Terminate-WindowsTerminalTabs -OnlyCurrent when caller tab is from a different workspace" {
		$script:Configuration.ProjectTerminals = @(
			@{ Name = 'ProjectA'; Paths = @('Api') }
		)
		$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
			@{ Action = 'Open-Project'; Parameters = @{ Project = 'ProjectA' } },
			@{ Action = 'Terminate-WindowsTerminalTabs'; Parameters = @{ OnlyCurrent = $true } }
		)
		$env:WT_PROJECT_TAB = 'OtherWorkspace.Api'

		Open-Workspace -Workspace 'TestWorkspace'

		$script:terminateCalls.Count | Should -Be 1
		$script:terminateCalls[0].OnlyCurrent | Should -BeTrue
	}

	It "continues executing later actions when one action throws" {
		$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
			@{ Action = 'Test-ThrowingAction'; Parameters = @{} },
			@{ Action = 'Test-ActionTwo'; Parameters = @{ Beta = 42 } }
		)

		Open-Workspace -Workspace 'TestWorkspace'

		$script:invokedActions.Count | Should -Be 1
		$script:invokedActions[0].Name | Should -Be 'Test-ActionTwo'
		$script:invokedActions[0].Beta | Should -Be 42
	}

	It "short-circuits remaining actions when Return action is encountered" {
		$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
			@{ Action = 'Return'; Parameters = @{} },
			@{ Action = 'Test-ActionOne'; Parameters = @{ Alpha = 7 } }
		)

		Open-Workspace -Workspace 'TestWorkspace'

		$script:invokedActions.Count | Should -Be 0
	}

	Context "teardown tracking" {
		It "records what the open produced so Close-Workspace can close it" {
			$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
				@{ Action = 'Test-ActionOne'; Parameters = @{ Alpha = 1 } }
			)

			Open-Workspace -Workspace 'TestWorkspace'

			$script:workspaceStateCalls.Count | Should -Be 1
			$script:workspaceStateCalls[0].Workspace | Should -Be 'TestWorkspace'
			$script:workspaceStateCalls[0].Alongside | Should -BeFalse
		}

		It "captures the terminal tab strip before the actions run" {
			# Tabs are not top-level windows, so the window capture cannot see them; without this
			# snapshot every tab in every terminal would look newly created.
			$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
				@{ Action = 'Test-ActionOne'; Parameters = @{ Alpha = 1 } }
			)

			Open-Workspace -Workspace 'TestWorkspace'

			Should -Invoke Get-TerminalTabSnapshot -Times 1
		}

		It "captures the tab strip again before the layout parks the terminal, and records that one" {
			# The layout action is what moves the terminal onto one of the workspace's own desktops,
			# and Windows Terminal shows no tab strip while its desktop is off screen. Reading it at
			# record time therefore costs a desktop round trip - which the user sees as the view
			# jumping to the terminal and back AFTER the workspace's final Focus-VirtualDesktop
			# landing. Each mocked read is labelled so the snapshot handed to the recorder identifies
			# itself: it must be the second (pre-layout) one, and there must be no third.
			$script:tabSnapshotReads = 0
			Mock Get-TerminalTabSnapshot {
				param([switch]$EnsureVisible)
				$script:tabSnapshotReads++
				@{ 777 = @("read$script:tabSnapshotReads") }
			}

			$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
				@{ Action = 'Set-WorkspaceWindowLayout'; Parameters = @{ WorkspaceName = 'TestWorkspace' } }
			)

			Open-Workspace -Workspace 'TestWorkspace'

			$script:tabSnapshotReads | Should -Be 2
			@($script:workspaceStateCalls[0].PreCapturedTerminalTabs[777]) | Should -Be @('read2')
		}

		It "forwards no pre-captured tab strip when the workspace has no layout action" {
			# Nothing moved the terminal, so there is nothing to pre-capture and the recorder is left
			# to read the tab strip itself - which costs no desktop switch either.
			$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
				@{ Action = 'Test-ActionOne'; Parameters = @{ Alpha = 1 } }
			)

			Open-Workspace -Workspace 'TestWorkspace'

			$script:workspaceStateCalls[0].PreCapturedTerminalTabs | Should -BeNullOrEmpty
		}

		It "records one entry per selected workspace" {
			$script:Configuration.Workspaces = @('WorkspaceA', 'WorkspaceB')
			$script:Configuration.WorkspaceActions['WorkspaceA'] = @(@{ Action = 'Test-ActionOne'; Parameters = @{ Alpha = 1 } })
			$script:Configuration.WorkspaceActions['WorkspaceB'] = @(@{ Action = 'Test-ActionTwo'; Parameters = @{ Beta = 2 } })

			Open-Workspace -Workspace @('WorkspaceA', 'WorkspaceB')

			@($script:workspaceStateCalls.Workspace) | Should -Be @('WorkspaceA', 'WorkspaceB')
		}

		It "lets a plain open claim what is already on screen" {
			# Otherwise an app that was already running produced no new window, is never recorded,
			# and survives every teardown from then on.
			$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
				@{ Action = 'Test-ActionOne'; Parameters = @{ Alpha = 1 } }
			)

			Open-Workspace -Workspace 'TestWorkspace'

			$script:workspaceStateCalls[0].AdoptUnclaimed | Should -BeTrue
			$script:workspaceStateCalls[0].Append | Should -BeFalse
		}

		It "only lets the first workspace of a plain run claim, and appends the rest" {
			# Adopting twice would have both entries claim the same windows, and each would then
			# protect them from the other's teardown.
			$script:Configuration.Workspaces = @('WorkspaceA', 'WorkspaceB')
			$script:Configuration.WorkspaceActions['WorkspaceA'] = @(@{ Action = 'Test-ActionOne'; Parameters = @{ Alpha = 1 } })
			$script:Configuration.WorkspaceActions['WorkspaceB'] = @(@{ Action = 'Test-ActionTwo'; Parameters = @{ Beta = 2 } })

			Open-Workspace -Workspace @('WorkspaceA', 'WorkspaceB')

			@($script:workspaceStateCalls.AdoptUnclaimed) | Should -Be @($true, $false)
			@($script:workspaceStateCalls.Append) | Should -Be @($false, $true)
		}

		It "never claims on an alongside open, which would steal another workspace's windows" {
			$env:OPEN_WORKSPACE_ALONGSIDE_SHELL = '1'
			$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
				@{ Action = 'Test-ActionOne'; Parameters = @{ Alpha = 1 } }
			)

			Open-Workspace -Workspace 'TestWorkspace' -Alongside

			$script:workspaceStateCalls[0].AdoptUnclaimed | Should -BeFalse
		}

		It "records the alongside mode and desktop offset the open ran with" {
			$env:OPEN_WORKSPACE_ALONGSIDE_SHELL = '1'
			$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
				@{ Action = 'Test-ActionOne'; Parameters = @{ Alpha = 1 } }
			)

			Open-Workspace -Workspace 'TestWorkspace' -Alongside

			$script:workspaceStateCalls.Count | Should -Be 1
			$script:workspaceStateCalls[0].Alongside | Should -BeTrue
			$script:workspaceStateCalls[0].DesktopOffset | Should -Be 3
		}

		It "records before a terminating action exits the process" {
			# Terminate-WindowsTerminalTabs -OnlyCurrent ends the process, so a record written after
			# the action loop would never happen and the workspace would be untrackable.
			$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
				@{ Action = 'Test-ActionOne'; Parameters = @{ Alpha = 1 } },
				@{ Action = 'Terminate-WindowsTerminalTabs'; Parameters = @{ OnlyCurrent = $true } }
			)

			Open-Workspace -Workspace 'TestWorkspace'

			$script:workspaceStateCalls.Count | Should -Be 1
			$script:workspaceStateCalls[0].Workspace | Should -Be 'TestWorkspace'
		}

		It "records exactly once when a terminating action is present" {
			$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
				@{ Action = 'Terminate-WindowsTerminalTabs'; Parameters = @{ IncludeCurrent = $true } }
			)

			Open-Workspace -Workspace 'TestWorkspace'

			$script:workspaceStateCalls.Count | Should -Be 1
		}

		It "records nothing when a Return action aborts the open" {
			$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
				@{ Action = 'Return'; Parameters = @{} },
				@{ Action = 'Test-ActionOne'; Parameters = @{ Alpha = 1 } }
			)

			Open-Workspace -Workspace 'TestWorkspace'

			$script:workspaceStateCalls.Count | Should -Be 0
		}

		It "records nothing when the workspace has no configured actions" {
			$script:Configuration.WorkspaceActions = @{}

			Open-Workspace -Workspace 'TestWorkspace'

			$script:workspaceStateCalls.Count | Should -Be 0
		}

		It "records nothing for an -Alongside invocation that only relaunches" {
			$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
				@{ Action = 'Test-ActionOne'; Parameters = @{ Alpha = 1 } }
			)

			Open-Workspace -Workspace 'TestWorkspace' -Alongside

			$script:workspaceStateCalls.Count | Should -Be 0
		}
	}

	Context "preserving alongside workspaces on a plain open" {
		BeforeEach {
			$protectedHandles = New-Object 'System.Collections.Generic.HashSet[IntPtr]'
			[void]$protectedHandles.Add([IntPtr]60)
			$script:testProtection = [PSCustomObject]@{
				Entries       = @([ordered]@{ Workspace = 'AlongsideB'; Alongside = $true; DesktopOffset = 3; Windows = @() })
				WindowHandles = $protectedHandles
			}
		}

		It "threads the protected handles to the layout action and the preserved entries to the tracker write" {
			Mock Get-WorkspaceOpenProtection { $script:testProtection }
			$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
				@{ Action = 'Set-WorkspaceWindowLayout'; Parameters = @{ WorkspaceName = 'TestWorkspace' } }
			)

			Open-Workspace -Workspace 'TestWorkspace'

			$script:setLayoutCalls.Count | Should -Be 1
			$script:setLayoutCalls[0].ProtectedWindowHandles.Contains([IntPtr]60) | Should -BeTrue
			$script:workspaceStateCalls.Count | Should -Be 1
			@($script:workspaceStateCalls[0].PreserveEntry).Count | Should -Be 1
			$script:workspaceStateCalls[0].PreserveEntry[0].Workspace | Should -Be 'AlongsideB'
			$script:workspaceStateCalls[0].ProtectedWindowHandles.Contains([IntPtr]60) | Should -BeTrue
		}

		It "resolves protection once, before any action can spawn a process" {
			# A window created mid-run must never be mistaken for a protected one, and re-reading
			# the tracker per action would race the very writes this open performs.
			Mock Get-WorkspaceOpenProtection { $script:testProtection }
			$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
				@{ Action = 'Test-ActionOne'; Parameters = @{ Alpha = 1 } },
				@{ Action = 'Test-ActionTwo'; Parameters = @{ Beta = 2 } }
			)

			Open-Workspace -Workspace 'TestWorkspace'

			Should -Invoke Get-WorkspaceOpenProtection -Times 1 -Exactly
		}

		It "never resolves protection for an alongside open, which adds without destroying" {
			$env:OPEN_WORKSPACE_ALONGSIDE_SHELL = '1'
			Mock Get-WorkspaceOpenProtection { $script:testProtection }
			$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
				@{ Action = 'Set-WorkspaceWindowLayout'; Parameters = @{ WorkspaceName = 'TestWorkspace' } }
			)

			Open-Workspace -Workspace 'TestWorkspace' -Alongside

			Should -Invoke Get-WorkspaceOpenProtection -Times 0 -Exactly
			$script:setLayoutCalls[0].ProtectedWindowHandlesBound | Should -BeFalse
		}

		It "binds no protection parameters at all when there is nothing to preserve" {
			# The parameters must be OMITTED, never bound to $null - a bound $null would defeat
			# downstream defaulting (e.g. the layout's self-derive path).
			Mock Get-WorkspaceOpenProtection { $null }
			$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
				@{ Action = 'Set-WorkspaceWindowLayout'; Parameters = @{ WorkspaceName = 'TestWorkspace' } }
			)

			Open-Workspace -Workspace 'TestWorkspace'

			$script:setLayoutCalls[0].ProtectedWindowHandlesBound | Should -BeFalse
			$script:workspaceStateCalls[0].PreserveEntryBound | Should -BeFalse
			$script:workspaceStateCalls[0].ProtectedWindowHandlesBound | Should -BeFalse
		}
	}

	It "stops processing later selected workspaces when an earlier workspace contains Return" {
		$script:Configuration.Workspaces = @('WorkspaceA', 'WorkspaceB')
		$script:Configuration.WorkspaceActions['WorkspaceA'] = @(
			@{ Action = 'Return'; Parameters = @{} }
		)
		$script:Configuration.WorkspaceActions['WorkspaceB'] = @(
			@{ Action = 'Test-ActionOne'; Parameters = @{ Alpha = 5 } }
		)

		Open-Workspace -Workspace @('WorkspaceA', 'WorkspaceB')

		$script:invokedActions.Count | Should -Be 0
	}

	It "continues to later selected workspaces when an earlier one has no configured actions" {
		$script:Configuration.Workspaces = @('WorkspaceA', 'WorkspaceB')
		$script:Configuration.WorkspaceActions['WorkspaceB'] = @(
			@{ Action = 'Test-ActionOne'; Parameters = @{ Alpha = 99 } }
		)

		Open-Workspace -Workspace @('WorkspaceA', 'WorkspaceB')

		$script:invokedActions.Count | Should -Be 1
		$script:invokedActions[0].Name | Should -Be 'Test-ActionOne'
		$script:invokedActions[0].Alpha | Should -Be 99
	}

	It "recomputes desktop offset per selected workspace when opening alongside" {
		$env:OPEN_WORKSPACE_ALONGSIDE_SHELL = '1'
		$script:Configuration.Workspaces = @('WorkspaceA', 'WorkspaceB')
		$script:Configuration.WorkspaceActions['WorkspaceA'] = @(
			@{ Action = 'Set-WorkspaceWindowLayout'; Parameters = @{ WorkspaceName = 'WorkspaceA' } }
		)
		$script:Configuration.WorkspaceActions['WorkspaceB'] = @(
			@{ Action = 'Set-WorkspaceWindowLayout'; Parameters = @{ WorkspaceName = 'WorkspaceB' } }
		)

		$script:nextDesktopValues = @(4, 7)
		Mock Get-NextAvailableDesktopIndex {
			$next = $script:nextDesktopValues[0]
			$script:nextDesktopValues = @($script:nextDesktopValues | Select-Object -Skip 1)
			$next
		}

		Open-Workspace -Workspace @('WorkspaceA', 'WorkspaceB') -Alongside

		Should -Invoke Get-NextAvailableDesktopIndex -Times 2 -Exactly
		$script:setLayoutCalls.Count | Should -Be 2
		$script:setLayoutCalls[0].WorkspaceName | Should -Be 'WorkspaceA'
		$script:setLayoutCalls[0].DesktopOffset | Should -Be 4
		$script:setLayoutCalls[0].Alongside | Should -BeTrue
		$script:setLayoutCalls[1].WorkspaceName | Should -Be 'WorkspaceB'
		$script:setLayoutCalls[1].DesktopOffset | Should -Be 7
		$script:setLayoutCalls[1].Alongside | Should -BeTrue
	}

	It "forwards desktop offset and pre-captured windows to Set-WorkspaceWindowLayout when opening alongside" {
		$env:OPEN_WORKSPACE_ALONGSIDE_SHELL = '1'
		Mock Get-WindowHandle {
			@([PSCustomObject]@{ Handle = [IntPtr]55; Title = 'Existing'; ProcessId = 1 })
		}

		$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
			@{ Action = 'Set-WorkspaceWindowLayout'; Parameters = @{ WorkspaceName = 'TestWorkspace' } }
		)

		Open-Workspace -Workspace 'TestWorkspace' -Alongside

		$script:setLayoutCalls.Count | Should -Be 1
		$script:setLayoutCalls[0].WorkspaceName | Should -Be 'TestWorkspace'
		$script:setLayoutCalls[0].DesktopOffset | Should -Be 3
		$script:setLayoutCalls[0].Alongside | Should -BeTrue
		$script:setLayoutCalls[0].PreCapturedExistingWindows.Count | Should -Be 1
	}

	It "excludes its own hosting terminal window from pre-captured windows in the alongside shell" {
		$env:OPEN_WORKSPACE_ALONGSIDE_SHELL = '1'

		# The title-probe query (-ProcessName WindowsTerminal) sees the probe marker in
		# this shell's own window title; the plain capture query returns both windows.
		Mock Get-WindowHandle {
			param($ProcessName)
			if ($ProcessName -eq 'WindowsTerminal') {
				@([PSCustomObject]@{ Handle = [IntPtr]777; Title = $Host.UI.RawUI.WindowTitle; ProcessId = 42 })
			}
			else {
				@(
					[PSCustomObject]@{ Handle = [IntPtr]555; Title = 'OtherWorkspaceWindow'; ProcessId = 1 },
					[PSCustomObject]@{ Handle = [IntPtr]777; Title = 'BootstrapWindow'; ProcessId = 42 }
				)
			}
		}

		$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
			@{ Action = 'Set-WorkspaceWindowLayout'; Parameters = @{ WorkspaceName = 'TestWorkspace' } }
		)

		Open-Workspace -Workspace 'TestWorkspace' -Alongside

		$script:setLayoutCalls.Count | Should -Be 1
		$script:setLayoutCalls[0].PreCapturedExistingWindows.Contains([IntPtr]555) | Should -BeTrue
		$script:setLayoutCalls[0].PreCapturedExistingWindows.Contains([IntPtr]777) | Should -BeFalse
	}

	It "keeps all pre-captured windows when opening without Alongside" {
		Mock Get-WindowHandle {
			param($ProcessName)
			@([PSCustomObject]@{ Handle = [IntPtr]777; Title = 'SomeWindow'; ProcessId = 42 })
		}

		$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
			@{ Action = 'Set-WorkspaceWindowLayout'; Parameters = @{ WorkspaceName = 'TestWorkspace' } }
		)

		Open-Workspace -Workspace 'TestWorkspace'

		$script:setLayoutCalls.Count | Should -Be 1
		$script:setLayoutCalls[0].PreCapturedExistingWindows.Contains([IntPtr]777) | Should -BeTrue
	}

	Context "project context handoff" {
		It "no longer injects swagger groups into Open-Browser" {
			$script:Configuration.BrowserGroups = @(
				@{
					Swagger = @(
						@{ Name = 'ProjectA'; Url = 'https://localhost:5001/swagger' }
					)
				}
			)
			$script:Configuration.Universal.DefaultBrowser = 'Firefox'
			$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
				@{ Action = 'Open-Project'; Parameters = @{ Project = 'ProjectA' } },
				@{ Action = 'Open-Browser'; Parameters = @{ Groups = @('General'); Browser = 'Firefox' } }
			)

			Open-Workspace -Workspace 'TestWorkspace'

			$script:browserCalls.Count | Should -Be 1
			$script:browserCalls[0].Groups | Should -Contain 'General'
			$script:browserCalls[0].Groups | Should -Not -Contain 'ProjectA'
			Should -Invoke Test-BrowserGroupAlreadyOpen -Times 0
		}

		It "substitutes {SelectedProjects} with the projects returned by Open-Project" {
			$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
				@{ Action = 'Open-Project'; Parameters = @{ Project = 'ProjectA' } },
				@{ Action = 'Test-ActionOne'; Parameters = @{ Alpha = '{SelectedProjects}' } }
			)

			Open-Workspace -Workspace 'TestWorkspace'

			$script:invokedActions.Count | Should -Be 1
			@($script:invokedActions[0].Alpha) | Should -Contain 'ProjectA'
		}

		It "prefers the explicit -Project argument over Open-Project's selection" {
			$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
				@{ Action = 'Open-Project' },
				@{ Action = 'Test-ActionOne'; Parameters = @{ Alpha = '{SelectedProjects}' } }
			)

			Open-Workspace -Workspace 'TestWorkspace' -Project 'CliProject'

			$script:invokedActions.Count | Should -Be 1
			@($script:invokedActions[0].Alpha) | Should -Be @('CliProject')
		}

		It "drops a {SelectedProjects} parameter when no projects resolve" {
			$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
				@{ Action = 'Test-ActionOne'; Parameters = @{ Alpha = '{SelectedProjects}' } }
			)

			Open-Workspace -Workspace 'TestWorkspace'

			$script:invokedActions.Count | Should -Be 1
			$script:invokedActions[0].Alpha | Should -BeNullOrEmpty
		}

		It "runs a configured Open-ProjectSwagger action with the selected projects" {
			$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
				@{ Action = 'Open-Project'; Parameters = @{ Project = 'ProjectA' } },
				@{ Action = 'Open-Browser'; Parameters = @{ Groups = @('General') } },
				@{ Action = 'Open-ProjectSwagger'; Parameters = @{ Project = '{SelectedProjects}' } }
			)

			Open-Workspace -Workspace 'TestWorkspace'

			$script:browserCalls.Count | Should -Be 1
			$script:swaggerCalls.Count | Should -Be 1
			$script:swaggerCalls[0].Project | Should -Contain 'ProjectA'
		}

		It "invokes Open-ProjectSwagger without a Project when the token drops it" {
			$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
				@{ Action = 'Open-ProjectSwagger'; Parameters = @{ Project = '{SelectedProjects}' } }
			)

			Open-Workspace -Workspace 'TestWorkspace'

			# The parameter is dropped, so the (real) action would no-op on its own
			$script:swaggerCalls.Count | Should -Be 1
			$script:swaggerCalls[0].Project | Should -BeNullOrEmpty
		}
	}

	Context "elapsed timer and rerun command stay out of the process environment" {
		# Both used to be process environment variables for the whole open. Every application and
		# terminal tab the open spawned inherited them, so a later Open-Workspace typed into such
		# a tab reported the time since the earlier open (597 s and 704 s in the session logs),
		# and a standalone layout escalation in a project tab would have respawned the whole
		# inherited workspace open.
		BeforeEach {
			$script:successLines = @()
			Mock Write-LogSuccess { $script:successLines += $Message }
			$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
				@{ Action = 'Test-CaptureEnvironmentAction'; Parameters = @{} }
			)
			[Environment]::SetEnvironmentVariable('OPEN_WORKSPACE_START_UTC', $null, 'Process')
			[Environment]::SetEnvironmentVariable('OPEN_WORKSPACE_ALONGSIDE_SHELL', $null, 'Process')
			[Environment]::SetEnvironmentVariable('WORKSPACE_RERUN_COMMAND', $null, 'Process')
		}

		AfterEach {
			[Environment]::SetEnvironmentVariable('OPEN_WORKSPACE_START_UTC', $null, 'Process')
			[Environment]::SetEnvironmentVariable('OPEN_WORKSPACE_ALONGSIDE_SHELL', $null, 'Process')
			[Environment]::SetEnvironmentVariable('WORKSPACE_RERUN_COMMAND', $null, 'Process')
		}

		It "records the resolved invocation through Set-WorkspaceRerunCommand and clears it when the open ends" {
			Open-Workspace -Workspace 'TestWorkspace'

			$script:rerunCommandCalls.Count | Should -BeGreaterOrEqual 2
			$script:rerunCommandCalls[0].Clear | Should -BeFalse
			$script:rerunCommandCalls[0].Command | Should -Be "Open-Workspace -Workspace 'TestWorkspace'"
			$script:rerunCommandCalls[-1].Clear | Should -BeTrue
		}

		It "puts neither the timer nor the rerun command into the environment while actions run" {
			Open-Workspace -Workspace 'TestWorkspace'

			$script:envDuringOpen | Should -Not -BeNullOrEmpty
			$script:envDuringOpen.Timer | Should -BeNullOrEmpty
			$script:envDuringOpen.RerunCommand | Should -BeNullOrEmpty
			[Environment]::GetEnvironmentVariable('OPEN_WORKSPACE_START_UTC', 'Process') | Should -BeNullOrEmpty
		}

		It "ignores an inherited timer start on a plain open and consumes it" {
			# A tab spawned by an earlier open carries that open's start; the summary must not.
			$tenMinutesAgo = [DateTimeOffset]::UtcNow.AddMinutes(-10).ToString('o')
			[Environment]::SetEnvironmentVariable('OPEN_WORKSPACE_START_UTC', $tenMinutesAgo, 'Process')

			Open-Workspace -Workspace 'TestWorkspace'

			$summary = @($script:successLines | Where-Object { $_ -like 'Workspace(s) opened in *' })
			$summary.Count | Should -Be 1
			[double]($summary[0] -replace '[^0-9.]', '') | Should -BeLessThan 60
			[Environment]::GetEnvironmentVariable('OPEN_WORKSPACE_START_UTC', 'Process') | Should -BeNullOrEmpty
		}

		It "carries the handed-over start only inside the relaunched alongside shell, and consumes it" {
			# The bootstrap command sets both markers for the child shell: the reported duration
			# of an alongside open includes the relaunch.
			$fiveMinutesAgo = [DateTimeOffset]::UtcNow.AddMinutes(-5).ToString('o')
			[Environment]::SetEnvironmentVariable('OPEN_WORKSPACE_START_UTC', $fiveMinutesAgo, 'Process')
			[Environment]::SetEnvironmentVariable('OPEN_WORKSPACE_ALONGSIDE_SHELL', '1', 'Process')

			Open-Workspace -Workspace 'TestWorkspace' -Alongside

			$summary = @($script:successLines | Where-Object { $_ -like 'Workspace(s) opened in *' })
			$summary.Count | Should -Be 1
			[double]($summary[0] -replace '[^0-9.]', '') | Should -BeGreaterOrEqual 300
			[Environment]::GetEnvironmentVariable('OPEN_WORKSPACE_START_UTC', 'Process') | Should -BeNullOrEmpty
			# Consumed at entry, so the tabs this open spawns cannot inherit it either.
			$script:envDuringOpen.Timer | Should -BeNullOrEmpty
		}
	}

	Context "layout preparation ahead of the launch actions" {
		# The layout's preamble (RPC probe, layout file, desktop resize, FancyZones zone layouts)
		# depends on no window and used to run after every application had been launched, under
		# their start-up load. It now runs first, as Set-WorkspaceWindowLayout -PrepareOnly.
		BeforeEach {
			$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
				@{ Action = 'Test-ActionOne'; Parameters = @{ Alpha = 1 } },
				@{ Action = 'Set-WorkspaceWindowLayout'; Parameters = @{ WorkspaceName = 'TestWorkspace' } }
			)
		}

		It "prepares the desktops and zone layouts before the first launch action, then runs the layout action as before" {
			Open-Workspace -Workspace 'TestWorkspace'

			$script:prepareLayoutCalls.Count | Should -Be 1
			$script:prepareLayoutCalls[0].WorkspaceName | Should -Be 'TestWorkspace'
			$script:prepareLayoutCalls[0].ActionsRunBefore | Should -Be 0
			($null -ne $script:prepareLayoutCalls[0].PreCapturedExistingWindows) | Should -BeTrue
			$script:setLayoutCalls.Count | Should -Be 1
			$script:setLayoutCalls[0].ActionsRunBefore | Should -Be 1
		}

		It "forwards the desktop offset and the alongside mode to the preparation of an alongside open" {
			$env:OPEN_WORKSPACE_ALONGSIDE_SHELL = '1'

			Open-Workspace -Workspace 'TestWorkspace' -Alongside

			$script:prepareLayoutCalls.Count | Should -Be 1
			$script:prepareLayoutCalls[0].DesktopOffset | Should -Be 3
			$script:prepareLayoutCalls[0].Alongside | Should -BeTrue
		}

		It "forwards the protected handles of a plain open to the preparation" {
			$protectedHandles = New-Object 'System.Collections.Generic.HashSet[IntPtr]'
			[void]$protectedHandles.Add([IntPtr]60)
			Mock Get-WorkspaceOpenProtection { [PSCustomObject]@{ Entries = @(); WindowHandles = $protectedHandles } }

			Open-Workspace -Workspace 'TestWorkspace'

			$script:prepareLayoutCalls.Count | Should -Be 1
			$script:prepareLayoutCalls[0].ProtectedWindowHandles.Contains([IntPtr]60) | Should -BeTrue
		}

		It "skips the preparation when WorkspaceLayoutPrepareEarly is false" {
			$script:Configuration.WorkspaceLayoutPrepareEarly = $false

			Open-Workspace -Workspace 'TestWorkspace'

			$script:prepareLayoutCalls.Count | Should -Be 0
			$script:setLayoutCalls.Count | Should -Be 1
		}

		It "skips the preparation for a workspace without a layout action" {
			$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
				@{ Action = 'Test-ActionOne'; Parameters = @{ Alpha = 1 } }
			)

			Open-Workspace -Workspace 'TestWorkspace'

			$script:prepareLayoutCalls.Count | Should -Be 0
		}

		It "skips the preparation inside a window-only retry, which must leave the desktops alone" {
			[Environment]::SetEnvironmentVariable('WORKSPACE_WINDOW_ONLY_RETRY', '1|1788349256', 'Process')
			try {
				Open-Workspace -Workspace 'TestWorkspace'
			}
			finally {
				[Environment]::SetEnvironmentVariable('WORKSPACE_WINDOW_ONLY_RETRY', $null, 'Process')
			}

			$script:prepareLayoutCalls.Count | Should -Be 0
			$script:setLayoutCalls.Count | Should -Be 1
		}

		It "times the preparation as its own layout action and folds its phases into the layout record of the benchmark row" {
			$script:Configuration.WorkspaceBenchmark = @{ Enabled = $true; Display = 'None'; Last = 10 }
			$script:timingsReads = 0
			Mock Get-WorkspaceLayoutTimings {
				$script:timingsReads++
				if ($script:timingsReads -eq 1) {
					[PSCustomObject]@{ Workspace = 'TestWorkspace'; Outcome = 'Prepared'; Attempts = 0; TotalSeconds = 1.5; Phases = [ordered]@{ Preamble = 0.5; Desktops = 0.4; FancyZones = 0.6 }; RecordedAt = [DateTimeOffset]::Now.AddSeconds(1) }
				}
				else {
					[PSCustomObject]@{ Workspace = 'TestWorkspace'; Outcome = 'Applied'; Attempts = 1; TotalSeconds = 10; Phases = [ordered]@{ Preamble = 0.1; Desktops = 0; FancyZones = 0.1; Wait = 8; Snap = 1.8 }; RecordedAt = [DateTimeOffset]::Now.AddSeconds(2) }
				}
			}

			Open-Workspace -Workspace 'TestWorkspace'

			$script:benchmarkCalls.Count | Should -Be 1
			@($script:benchmarkCalls[0].ActionTimings.Action) | Should -Be @('Set-WorkspaceWindowLayout -PrepareOnly', 'Test-ActionOne', 'Set-WorkspaceWindowLayout')
			$record = $script:benchmarkCalls[0].LayoutTimings
			$record.Outcome | Should -Be 'Applied'
			$record.Attempts | Should -Be 1
			$record.TotalSeconds | Should -Be 11.5
			$record.Phases['Desktops'] | Should -Be 0.4
			$record.Phases['FancyZones'] | Should -Be 0.7
			$record.Phases['Wait'] | Should -Be 8
		}
	}
}
