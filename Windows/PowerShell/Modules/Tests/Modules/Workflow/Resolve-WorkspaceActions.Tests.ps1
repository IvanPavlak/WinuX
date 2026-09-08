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

	Context "parameter override tables - MachineParameters and LayoutMachineParameters" {
		BeforeEach {
			# The one-line form of the LeagueOfLegends opener: one entry, one row for the PC's own layout set.
			$script:browserEntry = @{
				Action                  = 'Open-Browser'
				Parameters              = @{ Groups = @('Google') }
				LayoutMachineParameters = @{ PC = @{ Instances = 2 } }
			}
		}

		It "applies a LayoutMachineParameters row when the layout set matches, and leaves the parameter out otherwise" {
			$onPC = @(Resolve-WorkspaceActions -Actions @($script:browserEntry) -Workspace 'LeagueOfLegends')
			$onPC.Count | Should -Be 1
			$onPC[0].Parameters.Instances | Should -Be 2
			$onPC[0].Parameters.Groups | Should -Be @('Google')

			Mock Get-LayoutMachineType { 'Work' }
			$onWork = @(Resolve-WorkspaceActions -Actions @($script:browserEntry) -Workspace 'LeagueOfLegends')
			$onWork.Count | Should -Be 1
			$onWork[0].Parameters.ContainsKey('Instances') | Should -BeFalse
			$onWork[0].Parameters.Groups | Should -Be @('Google')
		}

		It "resolves the layout set once for a table alone, and not at all for MachineParameters alone" {
			@(Resolve-WorkspaceActions -Actions @($script:browserEntry) -Workspace 'W') | Out-Null
			Should -Invoke Get-LayoutMachineType -Times 1 -Exactly

			@(Resolve-WorkspaceActions -Actions @(@{ Action = 'A'; Parameters = @{ X = 1 }; MachineParameters = @{ PC = @{ X = 2 } } }) -Workspace 'W') | Out-Null
			Should -Invoke Get-LayoutMachineType -Times 1 -Exactly
		}

		It "matches MachineParameters rows against the detected machine type, including scope-string keys" {
			$entry = @{ Action = 'Open-Project'; Parameters = @{ Project = 'Client'; RunApp = $true }; MachineParameters = @{ 'Laptop/Work' = @{ Project = 'ClientLite' } } }

			$onPC = @(Resolve-WorkspaceActions -Actions @($entry) -Workspace 'W')[0]
			$onPC.Parameters.Project | Should -Be 'Client'

			$onWork = @(Resolve-WorkspaceActions -Actions @($entry) -Workspace 'W' -MachineType 'Work')[0]
			$onWork.Parameters.Project | Should -Be 'ClientLite'
			$onWork.Parameters.RunApp | Should -BeTrue
			Should -Invoke Write-LogError -Times 0
		}

		It "removes a parameter a row sets to null, and only at the top level" {
			$entry = @{
				Action            = 'Open-Project'
				Parameters        = @{ Project = 'Client'; RunApp = $true; Options = @{ Keep = $null; A = 1 } }
				MachineParameters = @{ PC = @{ RunApp = $null } }
			}

			$result = @(Resolve-WorkspaceActions -Actions @($entry) -Workspace 'W')[0]

			$result.Parameters.ContainsKey('RunApp') | Should -BeFalse
			$result.Parameters.Project | Should -Be 'Client'
			$result.Parameters.Options.ContainsKey('Keep') | Should -BeTrue
		}

		It "starts from an empty parameter set when the entry has no Parameters" {
			$entry = @{ Action = 'Open-Outlook'; MachineParameters = @{ PC = @{ Profile = 'Gaming' } } }

			$result = @(Resolve-WorkspaceActions -Actions @($entry) -Workspace 'W')[0]

			$result.Parameters.Profile | Should -Be 'Gaming'
			$result.Parameters.Count | Should -Be 1
		}

		It "deep-merges a nested hashtable parameter without touching the configured one" {
			$entry = @{
				Action            = 'A'
				Parameters        = @{ Options = @{ A = 1; B = 2 } }
				MachineParameters = @{ PC = @{ Options = @{ B = 3 }; Extra = 'x' } }
			}

			$result = @(Resolve-WorkspaceActions -Actions @($entry) -Workspace 'W')[0]

			$result.Parameters.Options.A | Should -Be 1
			$result.Parameters.Options.B | Should -Be 3
			$result.Parameters.Extra | Should -Be 'x'
			[object]::ReferenceEquals($result.Parameters.Options, $entry.Parameters.Options) | Should -BeFalse
			$entry.Parameters.Options.B | Should -Be 2
			$entry.Parameters.ContainsKey('Extra') | Should -BeFalse
		}

		It "applies MachineParameters first and LayoutMachineParameters last, so the layout set wins" {
			Mock Get-LayoutMachineType { 'Work' }
			$entry = @{
				Action                  = 'Open-Browser'
				Parameters              = @{ Instances = 1 }
				MachineParameters       = @{ PC = @{ Instances = 3; Fresh = $true } }
				LayoutMachineParameters = @{ Work = @{ Instances = 2 } }
			}

			$result = @(Resolve-WorkspaceActions -Actions @($entry) -Workspace 'W')[0]

			$result.Parameters.Instances | Should -Be 2
			$result.Parameters.Fresh | Should -BeTrue
		}

		It "applies the All row first and the other matching rows in alphabetical order, naming them" {
			$entry = @{
				Action            = 'A'
				Parameters        = @{ X = 0 }
				MachineParameters = @{ 'PC/Work' = @{ X = 2; Z = 'pw' }; PC = @{ X = 1 }; All = @{ X = -1; Y = 'all' } }
			}

			$result = @(Resolve-WorkspaceActions -Actions @($entry) -Workspace 'W')[0]

			# All => -1, then "PC" => 1, then "PC/Work" => 2 (ordinal order, "PC" before "PC/Work").
			$result.Parameters.X | Should -Be 2
			$result.Parameters.Y | Should -Be 'all'
			$result.Parameters.Z | Should -Be 'pw'
			Should -Invoke Write-LogDebug -Times 3 -Exactly -ParameterFilter { $Message -like '*MachineParameters [[]*]* applied on [[]PC]*' }
			Should -Invoke Write-LogDebug -Times 1 -Exactly -ParameterFilter { $Message -like '*rows applied in order => [[]All], [[]PC], [[]PC/Work]*' }
		}

		It "returns the same object for an entry without tables and a new one for an entry with tables" {
			$plain = @{ Action = 'A'; Parameters = @{ X = 1 } }
			$withTable = @{ Action = 'B'; Parameters = @{ X = 1 }; LayoutMachine = 'PC'; LayoutMachineParameters = @{ PC = @{ X = 2 } } }

			$result = @(Resolve-WorkspaceActions -Actions @($plain, $withTable) -Workspace 'W')

			[object]::ReferenceEquals($result[0], $plain) | Should -BeTrue
			[object]::ReferenceEquals($result[1], $withTable) | Should -BeFalse
			[object]::ReferenceEquals($result[1].Parameters, $withTable.Parameters) | Should -BeFalse
			$result[1].ContainsKey('LayoutMachineParameters') | Should -BeFalse
			$result[1].ContainsKey('MachineParameters') | Should -BeFalse
			$result[1].LayoutMachine | Should -Be 'PC'
			$result[1].Action | Should -Be 'B'
			$result[1].Parameters.X | Should -Be 2
		}

		It "never modifies the configured entry or its parameters" {
			$entry = @{
				Action                  = 'Open-Browser'
				Parameters              = @{ Groups = @('Google'); Nested = @{ Keep = 1 } }
				MachineParameters       = @{ PC = @{ Groups = $null; Nested = @{ Added = 2 } } }
				LayoutMachineParameters = @{ PC = @{ Instances = 2 } }
			}

			@(Resolve-WorkspaceActions -Actions @($entry) -Workspace 'W') | Out-Null

			@($entry.Keys | Sort-Object) | Should -Be @('Action', 'LayoutMachineParameters', 'MachineParameters', 'Parameters')
			@($entry.Parameters.Keys | Sort-Object) | Should -Be @('Groups', 'Nested')
			$entry.Parameters.Groups | Should -Be @('Google')
			@($entry.Parameters.Nested.Keys) | Should -Be @('Keep')
			$entry.MachineParameters.PC.ContainsKey('Groups') | Should -BeTrue
		}

		It "returns an empty Parameters hashtable when every parameter was removed" {
			$entry = @{ Action = 'A'; Parameters = @{ X = 1 }; MachineParameters = @{ PC = @{ X = $null } } }

			$result = @(Resolve-WorkspaceActions -Actions @($entry) -Workspace 'W')[0]

			$result.ContainsKey('Parameters') | Should -BeTrue
			$result.Parameters.Count | Should -Be 0
		}

		It "reports a table that is not a hashtable and a row that is not a hashtable, and keeps the entry" {
			$badTable = @{ Action = 'A'; Parameters = @{ X = 1 }; MachineParameters = 'PC' }
			$badRow = @{ Action = 'B'; Parameters = @{ X = 1 }; MachineParameters = @{ PC = 'not a hashtable' } }

			$result = @(Resolve-WorkspaceActions -Actions @($badTable, $badRow) -Workspace 'W')

			$result.Count | Should -Be 2
			$result[0].Parameters.X | Should -Be 1
			$result[1].Parameters.X | Should -Be 1
			Should -Invoke Write-LogError -Times 1 -Exactly -ParameterFilter { $Message -like '*WorkspaceActions.W [[]A].MachineParameters must be a hashtable*' }
			Should -Invoke Write-LogError -Times 1 -Exactly -ParameterFilter { $Message -like '*WorkspaceActions.W [[]B].MachineParameters row [[]PC] must be a hashtable*' }
		}

		It "reports an unknown or blank row key with the table named, ignores the row and keeps the rest" {
			$entry = @{
				Action                  = 'Open-Browser'
				Parameters              = @{ Instances = 1 }
				LayoutMachineParameters = @{ Labtop = @{ Instances = 5 }; ' ' = @{ Instances = 6 }; PC = @{ Instances = 2 } }
			}

			$result = @(Resolve-WorkspaceActions -Actions @($entry) -Workspace 'Trading')[0]

			$result.Parameters.Instances | Should -Be 2
			Should -Invoke Write-LogError -Times 1 -Exactly -ParameterFilter { $Message -like '*[[]Labtop]*' -and $Message -like '*WorkspaceActions.Trading [[]Open-Browser].LayoutMachineParameters*' }
			Should -Invoke Write-LogError -Times 1 -Exactly -ParameterFilter { $Message -like 'Empty machine scope*WorkspaceActions.Trading [[]Open-Browser].LayoutMachineParameters*' }
		}

		It "accepts a layout set from LayoutMachineTypeOverrides as a row key, and reports it as unknown in MachineParameters" {
			$global:Configuration.LayoutMachineTypeOverrides = @{ PC = 'Temp' }
			Mock Get-LayoutMachineType { 'Temp' }
			$layoutRow = @{ Action = 'A'; Parameters = @{ X = 1 }; LayoutMachineParameters = @{ Temp = @{ X = 2 } } }
			$identityRow = @{ Action = 'B'; Parameters = @{ X = 1 }; MachineParameters = @{ Temp = @{ X = 3 } } }

			$result = @(Resolve-WorkspaceActions -Actions @($layoutRow, $identityRow) -Workspace 'W')

			$result[0].Parameters.X | Should -Be 2
			$result[1].Parameters.X | Should -Be 1
			Should -Invoke Write-LogError -Times 1 -Exactly -ParameterFilter { $Message -like '*[[]Temp]*' -and $Message -like '*[[]B].MachineParameters*' }
		}

		It "honours an explicit -LayoutMachineType for the tables" {
			$result = @(Resolve-WorkspaceActions -Actions @($script:browserEntry) -Workspace 'W' -LayoutMachineType 'Laptop')[0]

			$result.Parameters.ContainsKey('Instances') | Should -BeFalse
			Should -Invoke Get-LayoutMachineType -Times 0
		}

		It "does not report table problems for an action the scope already excluded" {
			$entry = @{ Action = 'A'; Machine = 'Laptop'; MachineParameters = 'broken' }

			@(Resolve-WorkspaceActions -Actions @($entry) -Workspace 'W').Count | Should -Be 0
			Should -Invoke Write-LogError -Times 0
		}

		It "resolves tables on object entries too" {
			$entry = [PSCustomObject]@{ Action = 'Open-Browser'; Parameters = @{ Groups = @('Google') }; LayoutMachineParameters = @{ PC = @{ Instances = 2 } } }

			$result = @(Resolve-WorkspaceActions -Actions @($entry) -Workspace 'W')[0]

			$result.Action | Should -Be 'Open-Browser'
			$result.Parameters.Instances | Should -Be 2
			$result.ContainsKey('LayoutMachineParameters') | Should -BeFalse
		}
	}
}
