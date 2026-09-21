#Requires -Modules Pester

BeforeAll {
	$script:OriginalMachineSpecificPaths = $global:MachineSpecificPaths
	$script:OriginalConfiguration = $global:Configuration
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Open-Obsidian.ps1"
	# The helpers Open-Obsidian calls - loaded so they exist to be mocked.
	. "$AppFunctionsPath\Get-ObsidianCliPath.ps1"
	. "$AppFunctionsPath\Get-ObsidianWorkspaceNames.ps1"
	. "$AppFunctionsPath\Invoke-ObsidianCli.ps1"
	# The checked load Open-Obsidian now shares with the deferred path, and the drain itself -
	# real, not mocked: what they do with the CLI answer is part of this behaviour.
	. "$AppFunctionsPath\Invoke-ObsidianWorkspaceLoad.ps1"
	. "$AppFunctionsPath\Complete-ObsidianWorkspaceLoad.ps1"
	# The deferral registry the opener queues into and the flow drains - real too, so the tests
	# run the queued tail exactly as Open-Workspace would.
	$HelperFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Helper\Functions"
	. "$HelperFunctionsPath\Register-DeferredAction.ps1"
	. "$HelperFunctionsPath\Complete-DeferredActions.ps1"
	. "$AppFunctionsPath\Start-ObsidianDetached.ps1"
	. "$AppFunctionsPath\Wait-ObsidianCli.ps1"

	# A vault directory with the saved workspaces the tests reason about.
	$script:VaultDirectory = Join-Path $TestDrive 'Obsidian'
	New-Item -ItemType Directory -Path (Join-Path $script:VaultDirectory '.obsidian') -Force | Out-Null
	@{
		workspaces = @{
			Empty  = @{ main = @{} }
			Server = @{ main = @{} }
			DSA    = @{ main = @{} }
		}
		active     = 'Server'
	} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $script:VaultDirectory '.obsidian\workspaces.json')
}

AfterAll {
	$global:MachineSpecificPaths = $script:OriginalMachineSpecificPaths
	$global:Configuration = $script:OriginalConfiguration
}

Describe "Open-Obsidian" {
	BeforeEach {
		$global:MachineSpecificPaths = @{ ObsidianDirectory = $script:VaultDirectory }
		$global:Configuration = @{ Obsidian = @{ DefaultWorkspace = ''; Vault = '' } }

		$script:cliCalls = @()
		$script:obsidianRunning = $false

		$script:cliAnswer = @()
		# Registry state: a tail queued by one test must never run in the next.
		$script:DeferredActions = $null

		Mock Invoke-ObsidianCli { $script:cliCalls += , @($Arguments); $script:cliAnswer }
		Mock Get-ObsidianCliPath { 'C:\Apps\Obsidian\Obsidian.com' }
		Mock Wait-ObsidianCli { $true }
		Mock Start-ObsidianDetached { }
		Mock Resolve-Selection { 'DSA' }
		Mock Get-Process { if ($script:obsidianRunning) { [PSCustomObject]@{ Name = 'obsidian'; MainWindowHandle = 42 } } } -ParameterFilter { $Name -eq 'obsidian' }
		Mock Write-LogWarning { }
		Mock Write-LogError { }
		Mock Write-LogStep { }
		Mock Write-LogSuccess { }
		Mock Write-LogDebug { }
	}

	Context "cold start" {
		It "launches detached with the vault derived from ObsidianDirectory and loads nothing with -Default" {
			Open-Obsidian -Default

			Should -Invoke Resolve-Selection -Times 0

			Should -Invoke Start-ObsidianDetached -Times 1 -Exactly -ParameterFilter { $Vault -eq 'Obsidian' }
			$script:cliCalls.Count | Should -Be 0
			Should -Invoke Wait-ObsidianCli -Times 0
		}

		It "launches, waits for the CLI to answer, then loads an explicit -Workspace" {
			Open-Obsidian -Workspace Server

			Should -Invoke Start-ObsidianDetached -Times 1 -Exactly -ParameterFilter { $Vault -eq 'Obsidian' }
			Should -Invoke Wait-ObsidianCli -Times 1 -Exactly -ParameterFilter { $Vault -eq 'Obsidian' -and $TimeoutSeconds -eq 10 }
			$script:cliCalls.Count | Should -Be 1
			$script:cliCalls[0] | Should -Be @('vault=Obsidian', 'workspace:load', 'name=Server')
		}

		It "loads the same-named Obsidian workspace for the injected CurrentWorkspace" {
			Open-Obsidian -CurrentWorkspace Server

			$script:cliCalls[0] | Should -Be @('vault=Obsidian', 'workspace:load', 'name=Server')
		}

		It "loads nothing when CurrentWorkspace has no same-named Obsidian workspace" {
			Open-Obsidian -CurrentWorkspace Trading

			Should -Invoke Start-ObsidianDetached -Times 1 -Exactly
			$script:cliCalls.Count | Should -Be 0
			Should -Invoke Write-LogWarning -Times 0
		}

		It "falls back to Obsidian.DefaultWorkspace when nothing else resolves" {
			$global:Configuration.Obsidian.DefaultWorkspace = 'Empty'

			Open-Obsidian -Default

			$script:cliCalls[0] | Should -Be @('vault=Obsidian', 'workspace:load', 'name=Empty')
		}

		It "prefers an explicit -Workspace over CurrentWorkspace and the default" {
			$global:Configuration.Obsidian.DefaultWorkspace = 'Empty'

			Open-Obsidian -Workspace DSA -CurrentWorkspace Server

			$script:cliCalls.Count | Should -Be 1
			$script:cliCalls[0] | Should -Be @('vault=Obsidian', 'workspace:load', 'name=DSA')
		}

		It "uses Obsidian.Vault over the folder-derived name when set" {
			$global:Configuration.Obsidian.Vault = 'MyVault'

			Open-Obsidian -Workspace Server

			Should -Invoke Start-ObsidianDetached -Times 1 -Exactly -ParameterFilter { $Vault -eq 'MyVault' }
			$script:cliCalls[0] | Should -Be @('vault=MyVault', 'workspace:load', 'name=Server')
		}

		It "warns about an unknown workspace name and still attempts it" {
			Open-Obsidian -Workspace Typo

			Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like '*[[]Typo[]]*not saved*' }
			$script:cliCalls[0] | Should -Be @('vault=Obsidian', 'workspace:load', 'name=Typo')
		}

		It "does not load when the CLI never answers, and says so" {
			Mock Wait-ObsidianCli { $false }

			Open-Obsidian -Workspace Server

			Should -Invoke Start-ObsidianDetached -Times 1 -Exactly
			$script:cliCalls.Count | Should -Be 0
			Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like '*did not answer within 10 seconds*' }
		}

		It "still opens Obsidian when the CLI is missing and explains how to register it" {
			Mock Get-ObsidianCliPath { $null }

			Open-Obsidian -Workspace Server

			Should -Invoke Start-ObsidianDetached -Times 1 -Exactly -ParameterFilter { $Vault -eq 'Obsidian' }
			$script:cliCalls.Count | Should -Be 0
			Should -Invoke Wait-ObsidianCli -Times 0
			Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like '*Obsidian CLI not found*Command line interface*' }
		}

		It "opens silently when the CLI is missing and no workspace was requested" {
			Mock Get-ObsidianCliPath { $null }

			Open-Obsidian -Default

			Should -Invoke Start-ObsidianDetached -Times 1 -Exactly
			Should -Invoke Write-LogWarning -Times 0
		}

		It "reports a refused load instead of claiming the workspace when the CLI is not enabled on this machine" {
			$script:cliAnswer = @('Command line interface is not enabled. Please turn it on in Settings > General > Advanced.')

			Open-Obsidian -Workspace Server

			Should -Invoke Start-ObsidianDetached -Times 1 -Exactly
			$script:cliCalls[0] | Should -Be @('vault=Obsidian', 'workspace:load', 'name=Server')
			Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like '*[[]Server[]] not loaded*not enabled*Enable-ObsidianCli*' }
			Should -Invoke Write-LogSuccess -Times 0 -ParameterFilter { $Message -like '*opened in workspace*' }
			Should -Invoke Write-LogSuccess -Times 1 -Exactly -ParameterFilter { $Message -eq 'Obsidian opened!' }
		}

		It "reports a refused load for the injected CurrentWorkspace too" {
			$script:cliAnswer = @('Command line interface is not enabled. Please turn it on in Settings > General > Advanced.')

			Open-Obsidian -CurrentWorkspace Server

			Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like '*[[]Server[]] not loaded*' }
			Should -Invoke Write-LogSuccess -Times 0 -ParameterFilter { $Message -like '*opened in workspace*' }
		}

		It "claims the workspace only when the CLI answered the load cleanly" {
			$script:cliAnswer = @()

			Open-Obsidian -Workspace Server

			Should -Invoke Write-LogWarning -Times 0
			Should -Invoke Write-LogSuccess -Times 1 -Exactly -ParameterFilter { $Message -like '*opened in workspace [[]Server[]]*' }
		}

		It "offers the saved workspaces as a menu on a bare call, like the other openers" {
			Open-Obsidian

			Should -Invoke Resolve-Selection -Times 1 -Exactly -ParameterFilter {
				@($OptionList) -contains 'Empty' -and @($OptionList) -contains 'Server' -and @($OptionList) -contains 'DSA' -and $AllowEmptyPromptResponse
			}
			$script:cliCalls[0] | Should -Be @('vault=Obsidian', 'workspace:load', 'name=DSA')
		}

		It "opens plainly when the menu is skipped and no default is configured" {
			Mock Resolve-Selection { $null }

			Open-Obsidian

			Should -Invoke Start-ObsidianDetached -Times 1 -Exactly
			$script:cliCalls.Count | Should -Be 0
			Should -Invoke Write-LogSuccess -Times 1 -Exactly -ParameterFilter { $Message -eq 'Obsidian opened!' }
		}

		It "falls back to Obsidian.DefaultWorkspace when the menu is skipped on a cold start" {
			Mock Resolve-Selection { $null }
			$global:Configuration.Obsidian.DefaultWorkspace = 'Empty'

			Open-Obsidian

			$script:cliCalls[0] | Should -Be @('vault=Obsidian', 'workspace:load', 'name=Empty')
		}

		It "never prompts when CurrentWorkspace is injected, even without a same-named match" {
			Open-Obsidian -CurrentWorkspace Trading

			Should -Invoke Resolve-Selection -Times 0
		}

		It "skips the menu with -Default" {
			Open-Obsidian -Default

			Should -Invoke Resolve-Selection -Times 0
			$script:cliCalls.Count | Should -Be 0
		}

		It "shows no menu when the vault has no saved workspaces" {
			Mock Get-ObsidianWorkspaceNames { @() }

			Open-Obsidian

			Should -Invoke Resolve-Selection -Times 0
			Should -Invoke Start-ObsidianDetached -Times 1 -Exactly
		}

		It "reports a missing vault configuration and launches nothing" {
			$global:MachineSpecificPaths = @{ ObsidianDirectory = '' }

			Open-Obsidian

			Should -Invoke Write-LogError -Times 1 -Exactly
			$script:cliCalls.Count | Should -Be 0
			Should -Invoke Start-ObsidianDetached -Times 0
		}
	}

	Context "already running" {
		BeforeEach {
			$script:obsidianRunning = $true
		}

		It "leaves Obsidian alone with -Default" {
			Open-Obsidian -Default

			$script:cliCalls.Count | Should -Be 0
			Should -Invoke Start-ObsidianDetached -Times 0
			Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like '*already running*' }
		}

		It "switches the running instance with a single workspace:load and no launch" {
			Open-Obsidian -Workspace DSA

			$script:cliCalls.Count | Should -Be 1
			$script:cliCalls[0] | Should -Be @('vault=Obsidian', 'workspace:load', 'name=DSA')
			Should -Invoke Wait-ObsidianCli -Times 0
			Should -Invoke Start-ObsidianDetached -Times 0
		}

		It "switches to the same-named workspace for the injected CurrentWorkspace" {
			Open-Obsidian -CurrentWorkspace Server

			$script:cliCalls[0] | Should -Be @('vault=Obsidian', 'workspace:load', 'name=Server')
		}

		It "offers the menu on a bare call and switches the running instance to the pick" {
			Open-Obsidian

			Should -Invoke Resolve-Selection -Times 1 -Exactly
			$script:cliCalls[0] | Should -Be @('vault=Obsidian', 'workspace:load', 'name=DSA')
			Should -Invoke Start-ObsidianDetached -Times 0
		}

		It "leaves Obsidian alone when the menu is skipped" {
			Mock Resolve-Selection { $null }

			Open-Obsidian

			$script:cliCalls.Count | Should -Be 0
			Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like '*already running*' }
		}

		It "ignores Obsidian.DefaultWorkspace - the default is for cold starts only" {
			$global:Configuration.Obsidian.DefaultWorkspace = 'Empty'

			Open-Obsidian -Default

			$script:cliCalls.Count | Should -Be 0
		}

		It "warns instead of switching when the CLI is missing" {
			Mock Get-ObsidianCliPath { $null }

			Open-Obsidian -Workspace DSA

			$script:cliCalls.Count | Should -Be 0
			Should -Invoke Start-ObsidianDetached -Times 0
			Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like '*Obsidian CLI not found*' }
		}

		It "reports a refused switch instead of claiming the workspace when the CLI is not enabled" {
			$script:cliAnswer = @('Command line interface is not enabled. Please turn it on in Settings > General > Advanced.')

			Open-Obsidian -Workspace DSA

			$script:cliCalls.Count | Should -Be 1
			Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like '*[[]DSA[]] not loaded*not enabled*' }
			Should -Invoke Write-LogSuccess -Times 0
		}

		It "reports the CLI losing Obsidian between poll and load" {
			$script:cliAnswer = @('The CLI is unable to find Obsidian. Please make sure Obsidian is running and try again.')

			Open-Obsidian -Workspace DSA

			Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like '*[[]DSA[]] not loaded*unable to find Obsidian*' }
			Should -Invoke Write-LogSuccess -Times 0
		}
	}

	Context "deferred load (-Deferred, queued for Complete-DeferredActions)" {
		It "queues a cold start instead of waiting for the CLI, and launches Obsidian anyway" {
			Open-Obsidian -Workspace Server -Deferred

			Should -Invoke Start-ObsidianDetached -Times 1 -Exactly -ParameterFilter { $Vault -eq 'Obsidian' }
			# The whole point: neither the readiness poll nor the load runs while the action is on the
			# clock, so every opener queued behind it starts immediately.
			Should -Invoke Wait-ObsidianCli -Times 0
			$script:cliCalls.Count | Should -Be 0
		}

		It "drains the queued cold start, polling the CLI first and then loading" {
			Open-Obsidian -Workspace Server -Deferred

			Complete-DeferredActions | Should -Be 1

			Should -Invoke Wait-ObsidianCli -Times 1 -Exactly -ParameterFilter { $Vault -eq 'Obsidian' }
			$script:cliCalls.Count | Should -Be 1
			$script:cliCalls[0] | Should -Be @('vault=Obsidian', 'workspace:load', 'name=Server')
		}

		It "does not poll the CLI when the queued load was against an already-running Obsidian" {
			$script:obsidianRunning = $true

			Open-Obsidian -Workspace DSA -Deferred
			$script:cliCalls.Count | Should -Be 0

			Complete-DeferredActions | Should -Be 1

			# It answered before the open began; a poll would be a wasted process launch.
			Should -Invoke Wait-ObsidianCli -Times 0
			$script:cliCalls[0] | Should -Be @('vault=Obsidian', 'workspace:load', 'name=DSA')
		}

		It "queues the load once, so a second drain in the same open loads nothing" {
			Open-Obsidian -Workspace Server -Deferred

			Complete-DeferredActions | Should -Be 1
			Complete-DeferredActions | Should -Be 0

			$script:cliCalls.Count | Should -Be 1
		}

		It "reports a refused deferred load instead of claiming the workspace opened" {
			$script:cliAnswer = @('Command line interface is not enabled')

			Open-Obsidian -Workspace Server -Deferred
			Complete-DeferredActions | Should -Be 1

			Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -match 'not loaded' }
			# Obsidian did open, so that line stands; the claim that the WORKSPACE loaded must not.
			Should -Invoke Write-LogSuccess -Times 1 -Exactly -ParameterFilter { $Message -eq 'Obsidian opened!' }
			Should -Invoke Write-LogSuccess -Times 0 -ParameterFilter { $Message -match 'in workspace' }
		}

		It "warns and loads nothing when the CLI never answers for a queued cold start" {
			Mock Wait-ObsidianCli { $false }

			Open-Obsidian -Workspace Server -Deferred
			Complete-DeferredActions | Should -Be 1

			$script:cliCalls.Count | Should -Be 0
			Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -match 'did not answer' }
		}

		It "queues nothing when there is no workspace to load, so the drain is a no-op" {
			Open-Obsidian -Default -Deferred

			Complete-DeferredActions | Should -Be 0
			$script:cliCalls.Count | Should -Be 0
		}
	}
}
