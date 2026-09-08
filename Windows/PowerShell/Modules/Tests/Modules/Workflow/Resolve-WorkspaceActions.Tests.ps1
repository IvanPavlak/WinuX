#Requires -Modules Pester

BeforeAll {
	$script:OriginalConfiguration = $global:Configuration
	$script:OriginalMachineType = $global:MachineType

	$ModuleRoot = (Get-RepositoryPath).Modules
	# The real gate, not a stub: the token rules under test here ARE Test-MachineTypeScope's rules
	# (validation, "All", case-insensitivity), now reached through the two scope keys.
	. "$ModuleRoot\Bootstrap\Functions\Test-MachineTypeScope.ps1"
	. "$ModuleRoot\Workflow\Functions\Resolve-WorkspaceActions.ps1"

	# Cross-module command the resolver calls lazily; the Window module's real one measures the
	# monitors, so a stub stands in for Mock to attach to.
	function Get-LayoutMachineType { param($MonitorInfo) 'PC' }
}

AfterAll {
	$global:Configuration = $script:OriginalConfiguration
	$global:MachineType = $script:OriginalMachineType
}

Describe "Resolve-WorkspaceActions" {
	BeforeEach {
		$global:Configuration = @{
			ValidMachineTypes          = @('PC', 'Laptop', 'Work', 'Test')
			LayoutMachineTypeOverrides = @{ PC = ''; Laptop = ''; Work = ''; Test = '' }
			SmallDisplayMachineType    = ''
		}
		$global:MachineType = 'PC'

		Mock Write-Host { }
		Mock Write-LogError { }
		Mock Write-LogWarning { }
		Mock Write-LogDebug { }
		Mock Get-LayoutMachineType { 'PC' }

		# The shape this exists for: one workspace, two browser openers, one per layout set.
		$script:leagueActions = @(
			@{ Action = 'Open-LeagueOfLegends' }
			@{ Action = 'Open-Browser'; Parameters = @{ Groups = @('Google'); Instances = 2 }; LayoutMachine = 'PC' }
			@{ Action = 'Open-Browser'; Parameters = @{ Groups = @('Google') }; LayoutMachine = 'Laptop/Work' }
			@{ Action = 'Set-WorkspaceWindowLayout'; Parameters = @{ WorkspaceName = 'LeagueOfLegends' } }
		)
	}

	It "returns every entry, unchanged and in order, when none carries a scope" {
		$plain = @(@{ Action = 'A' }, @{ Action = 'B'; Parameters = @{ X = 1 } })

		$result = @(Resolve-WorkspaceActions -Actions $plain -Workspace 'W')

		$result.Count | Should -Be 2
		[object]::ReferenceEquals($result[0], $plain[0]) | Should -BeTrue
		[object]::ReferenceEquals($result[1], $plain[1]) | Should -BeTrue
		Should -Invoke Get-LayoutMachineType -Times 0
		Should -Invoke Write-LogWarning -Times 0
		Should -Invoke Write-LogError -Times 0
	}

	It "returns an empty array for null or empty input, without warning" {
		@(Resolve-WorkspaceActions -Actions $null -Workspace 'W').Count | Should -Be 0
		@(Resolve-WorkspaceActions -Actions @() -Workspace 'W').Count | Should -Be 0
		Should -Invoke Write-LogWarning -Times 0
	}

	Context "Machine scope - the detected machine type" {
		It "keeps the entries whose scope covers the detected type and drops the others, in order" {
			$scoped = @(
				@{ Action = 'A'; Machine = 'PC/Work' }
				@{ Action = 'B'; Machine = 'Laptop' }
				@{ Action = 'C'; Machine = 'All' }
				@{ Action = 'D' }
			)

			$result = @(Resolve-WorkspaceActions -Actions $scoped -Workspace 'W')

			@($result | ForEach-Object { $_.Action }) | Should -Be @('A', 'C', 'D')
			Should -Invoke Write-LogDebug -Times 1 -Exactly -ParameterFilter { $Message -like '*Skipping [[]B]*' -and $Message -like '*Machine [[]Laptop]*' -and $Message -like '*machine type [[]PC]*' }
			Should -Invoke Get-LayoutMachineType -Times 0
		}

		It "defaults the machine type to the global one and honours an explicit -MachineType" {
			$scoped = @(@{ Action = 'A'; Machine = 'Laptop' })

			@(Resolve-WorkspaceActions -Actions $scoped -Workspace 'W').Count | Should -Be 0
			@(Resolve-WorkspaceActions -Actions $scoped -Workspace 'W' -MachineType 'Laptop').Count | Should -Be 1
		}

		It "treats a blank scope as All, accepts an array of tokens and matches case-insensitively" {
			$scoped = @(
				@{ Action = 'A'; Machine = '' }
				@{ Action = 'B'; Machine = @('Laptop', 'PC') }
				@{ Action = 'C'; Machine = 'pc' }
				@{ Action = 'D'; Machine = '   ' }
			)

			@(Resolve-WorkspaceActions -Actions $scoped -Workspace 'W' | ForEach-Object { $_.Action }) | Should -Be @('A', 'B', 'C', 'D')
			Should -Invoke Write-LogError -Times 0
		}
	}

	Context "LayoutMachine scope - the layout set" {
		It "matches against the layout set Get-LayoutMachineType resolves, not the detected type" {
			# The PC redirected to the Work layouts: one Google window, like LeagueOfLegends_Work.psd1.
			Mock Get-LayoutMachineType { 'Work' }

			$result = @(Resolve-WorkspaceActions -Actions $script:leagueActions -Workspace 'LeagueOfLegends')

			$result.Count | Should -Be 3
			$result[1].Action | Should -Be 'Open-Browser'
			$result[1].Parameters.ContainsKey('Instances') | Should -BeFalse
			$result[2].Action | Should -Be 'Set-WorkspaceWindowLayout'
			Should -Invoke Get-LayoutMachineType -Times 1 -Exactly
		}

		It "keeps the two-window opener on the PC's own layout set" {
			$result = @(Resolve-WorkspaceActions -Actions $script:leagueActions -Workspace 'LeagueOfLegends')

			$result.Count | Should -Be 3
			$result[1].Parameters.Instances | Should -Be 2
		}

		It "uses an explicit -LayoutMachineType and never asks Get-LayoutMachineType then" {
			$result = @(Resolve-WorkspaceActions -Actions $script:leagueActions -Workspace 'LeagueOfLegends' -LayoutMachineType 'Laptop')

			$result.Count | Should -Be 3
			$result[1].LayoutMachine | Should -Be 'Laptop/Work'
			Should -Invoke Get-LayoutMachineType -Times 0
		}

		It "resolves the layout set once per call, and only when an entry carries LayoutMachine" {
			@(Resolve-WorkspaceActions -Actions $script:leagueActions -Workspace 'LeagueOfLegends') | Out-Null
			Should -Invoke Get-LayoutMachineType -Times 1 -Exactly

			@(Resolve-WorkspaceActions -Actions @(@{ Action = 'A'; Machine = 'PC' }) -Workspace 'W') | Out-Null
			Should -Invoke Get-LayoutMachineType -Times 1 -Exactly
		}

		It "falls back to the machine type as the layout set when Get-LayoutMachineType is not available" {
			Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Get-LayoutMachineType' }

			$result = @(Resolve-WorkspaceActions -Actions $script:leagueActions -Workspace 'LeagueOfLegends' -MachineType 'Work')

			$result.Count | Should -Be 3
			$result[1].LayoutMachine | Should -Be 'Laptop/Work'
			Should -Invoke Get-LayoutMachineType -Times 0
		}

		It "accepts a layout set named by LayoutMachineTypeOverrides or SmallDisplayMachineType as a token" {
			$global:Configuration.LayoutMachineTypeOverrides = @{ PC = 'Temp'; Laptop = '' }
			$global:Configuration.SmallDisplayMachineType = 'Compact'
			Mock Get-LayoutMachineType { 'Temp' }
			$scoped = @(
				@{ Action = 'A'; LayoutMachine = 'Temp' }
				@{ Action = 'B'; LayoutMachine = 'Compact' }
				@{ Action = 'C'; LayoutMachine = 'PC' }
			)

			@(Resolve-WorkspaceActions -Actions $scoped -Workspace 'W' | ForEach-Object { $_.Action }) | Should -Be @('A')
			Should -Invoke Write-LogError -Times 0
		}

		It "reads the layout-set tokens from the configuration handed over, not the global one" {
			$handedOver = @{
				LayoutMachineTypeOverrides = @{ PC = 'Temp' }
				SmallDisplayMachineType    = ''
			}
			$scoped = @(@{ Action = 'A'; LayoutMachine = 'Temp' })

			# The global configuration knows no "Temp" layout set: the token is unknown there...
			@(Resolve-WorkspaceActions -Actions $scoped -Workspace 'W' -LayoutMachineType 'Temp').Count | Should -Be 0
			Should -Invoke Write-LogError -Times 1 -Exactly -ParameterFilter { $Message -like '*[[]Temp]*' }

			# ...and valid under the configuration that defines it.
			@(Resolve-WorkspaceActions -Actions $scoped -Workspace 'W' -LayoutMachineType 'Temp' -Configuration $handedOver).Count | Should -Be 1
			Should -Invoke Write-LogError -Times 1 -Exactly
		}
	}

	Context "both scopes, reporting and entry shapes" {
		It "requires both scopes to match" {
			$scoped = @(@{ Action = 'A'; Machine = 'PC'; LayoutMachine = 'Work' })

			@(Resolve-WorkspaceActions -Actions $scoped -Workspace 'W').Count | Should -Be 0

			Mock Get-LayoutMachineType { 'Work' }
			@(Resolve-WorkspaceActions -Actions $scoped -Workspace 'W').Count | Should -Be 1
			@(Resolve-WorkspaceActions -Actions $scoped -Workspace 'W' -MachineType 'Laptop').Count | Should -Be 0
		}

		It "reports an unknown token with the workspace and action named, and skips that entry" {
			$scoped = @(@{ Action = 'Open-Browser'; Machine = 'Labtop' }, @{ Action = 'B' })

			$result = @(Resolve-WorkspaceActions -Actions $scoped -Workspace 'Trading')

			@($result | ForEach-Object { $_.Action }) | Should -Be @('B')
			Should -Invoke Write-LogError -Times 1 -Exactly -ParameterFilter { $Message -like '*[[]Labtop]*' -and $Message -like '*WorkspaceActions.Trading [[]Open-Browser]*' }
		}

		It "warns once, naming the machine type and the layout set, when every entry is scoped out" {
			Mock Get-LayoutMachineType { 'Work' }
			$scoped = @(@{ Action = 'A'; Machine = 'Laptop' }, @{ Action = 'B'; LayoutMachine = 'PC' })

			@(Resolve-WorkspaceActions -Actions $scoped -Workspace 'W').Count | Should -Be 0

			Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like '*[[]W]*' -and $Message -like '*machine type [[]PC]*' -and $Message -like '*layout set [[]Work]*' }
		}

		It "names only the machine type in the warning when no entry used LayoutMachine" {
			$scoped = @(@{ Action = 'A'; Machine = 'Laptop' })

			@(Resolve-WorkspaceActions -Actions $scoped -Workspace 'W').Count | Should -Be 0

			Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like '*machine type [[]PC]*' -and $Message -notlike '*layout set*' }
			Should -Invoke Get-LayoutMachineType -Times 0
		}

		It "accepts object entries as well as hashtables" {
			$objects = @(
				[PSCustomObject]@{ Action = 'A'; Machine = 'PC' }
				[PSCustomObject]@{ Action = 'B'; Machine = 'Laptop' }
				[PSCustomObject]@{ Action = 'C' }
			)

			@(Resolve-WorkspaceActions -Actions $objects -Workspace 'W' | ForEach-Object { $_.Action }) | Should -Be @('A', 'C')
		}
	}
}
