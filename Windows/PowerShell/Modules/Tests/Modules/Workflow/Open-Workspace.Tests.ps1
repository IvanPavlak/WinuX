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

	function Get-WindowHandle { @() }
	function Get-NextAvailableDesktopIndex { 0 }
	function Test-BrowserGroupAlreadyOpen { $false }
	function Open-Browser { param($Groups, $Browser) }
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

		Mock Write-Host { }
		Mock Resolve-Selection { param($InputObject) $InputObject }
		Mock Get-WindowHandle { @() }
		Mock Get-FilteredParams { param($CommandName, $Params) $Params }
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
		Mock Test-ActionOne { param($Alpha) $script:invokedActions += [PSCustomObject]@{ Name = 'Test-ActionOne'; Alpha = $Alpha } }
		Mock Test-ActionTwo { param($Beta) $script:invokedActions += [PSCustomObject]@{ Name = 'Test-ActionTwo'; Beta = $Beta } }
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
	}

	AfterEach {
		if ($null -ne $script:previousWtProjectTab) {
			$env:WT_PROJECT_TAB = $script:previousWtProjectTab
		}
		else {
			Remove-Item Env:WT_PROJECT_TAB -ErrorAction SilentlyContinue
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

	It "skips Terminate-WindowsTerminalTabs -OnlyCurrent when Alongside is used" {
		$script:Configuration.WorkspaceActions['TestWorkspace'] = @(
			@{ Action = 'Terminate-WindowsTerminalTabs'; Parameters = @{ OnlyCurrent = $true } }
		)

		Open-Workspace -Workspace 'TestWorkspace' -Alongside

		$script:terminateCalls.Count | Should -Be 0
		Should -Invoke Get-NextAvailableDesktopIndex -Times 1 -Exactly
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
