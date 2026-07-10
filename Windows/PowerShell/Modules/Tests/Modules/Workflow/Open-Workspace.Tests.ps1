#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Workflow\Functions"
	$SystemFunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Open-Workspace.ps1"
	. "$FunctionsPath\Resolve-SwaggerBrowserGroup.ps1"
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
	function Get-NextAvailableDesktopIndex { 0 }
	function Test-BrowserGroupAlreadyOpen { $false }
	function Open-Browser { param($Groups, $Browser) }
	function Open-Terminal { param($Command, [switch]$Administrator, [switch]$InSameShell, $WindowId, $TabTitles) }
	function Set-WorkspaceWindowLayout { param($WorkspaceName, $PreCapturedExistingWindows, $DesktopOffset, [switch]$Alongside) }

	function Open-Project {
		param($Project)
		$Project
	}

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
		$script:setLayoutCalls = @()
		$script:openTerminalCalls = @()

		Mock Write-Host { }
		Mock Resolve-Selection { param($InputObject) $InputObject }
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
		Mock Set-WorkspaceWindowLayout {
			param($WorkspaceName, $PreCapturedExistingWindows, $DesktopOffset, [switch]$Alongside)
			$script:setLayoutCalls += [PSCustomObject]@{
				WorkspaceName              = $WorkspaceName
				PreCapturedExistingWindows = $PreCapturedExistingWindows
				DesktopOffset              = $DesktopOffset
				Alongside                  = [bool]$Alongside
			}
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
			Workspaces       = @('TestWorkspace')
			WorkspaceActions = @{}
			ProjectTerminals = @()
			BrowserGroups    = @()
			Universal        = @{ DefaultBrowser = 'Firefox' }
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

	It "adds swagger group to Open-Browser when project swagger is not already open" {
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
		$script:browserCalls[0].Groups | Should -Contain 'ProjectA'
		Should -Invoke Test-BrowserGroupAlreadyOpen -Times 1
	}

	It "does not append swagger group when it is already open" {
		Mock Test-BrowserGroupAlreadyOpen { $true }

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
		Should -Invoke Test-BrowserGroupAlreadyOpen -Times 1
	}
}
