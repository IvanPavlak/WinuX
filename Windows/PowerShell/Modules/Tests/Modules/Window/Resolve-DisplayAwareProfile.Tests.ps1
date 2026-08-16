#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Resolve-DisplayAwareProfile.ps1"

	# Stubbed so Mock can attach in a dot-sourced unit; both have their own suites.
	function Get-LayoutMachineType { param([object[]]$MonitorInfo) }
	function Test-SmallPrimaryDisplay { param([object[]]$MonitorInfo, [int]$MaxWidthPx) }
}

Describe "Resolve-DisplayAwareProfile" {
	BeforeEach {
		Mock Get-LayoutMachineType { 'Laptop' }
		Mock Test-SmallPrimaryDisplay { $false }
	}

	Context "resolution order" {
		BeforeEach {
			$script:section = @{
				SmallDisplay = 'small'
				Laptop       = 'laptop'
				Default      = 'default'
			}
		}

		It "prefers the SmallDisplay row while a laptop-class panel is primary" {
			# The whole reason the row exists: the machine type is "Laptop" both on the built-in
			# panel and docked to a big display, so only the live measurement separates them.
			Mock Test-SmallPrimaryDisplay { $true }

			Resolve-DisplayAwareProfile -Section $script:section | Should -BeExactly 'small'
		}

		It "falls to the machine type row on a large display" {
			Resolve-DisplayAwareProfile -Section $script:section | Should -BeExactly 'laptop'
		}

		It "falls to Default when the machine type has no row" {
			Mock Get-LayoutMachineType { 'PC' }

			Resolve-DisplayAwareProfile -Section $script:section | Should -BeExactly 'default'
		}

		It "ignores a SmallDisplay row on a large display even with no type row" {
			Mock Get-LayoutMachineType { 'PC' }

			Resolve-DisplayAwareProfile -Section @{ SmallDisplay = 'small'; Default = 'default' } |
				Should -BeExactly 'default'
		}
	}

	Context "no match" {
		It "returns null for a section with no matching row and no Default" {
			Resolve-DisplayAwareProfile -Section @{ PC = 'pc' } | Should -BeNullOrEmpty
		}

		It "returns null for an empty section" {
			Resolve-DisplayAwareProfile -Section @{} | Should -BeNullOrEmpty
		}

		It "returns null when no section is supplied" {
			Resolve-DisplayAwareProfile | Should -BeNullOrEmpty
		}
	}

	Context "monitor snapshot handling" {
		It "does not measure the display when the section has no SmallDisplay row" {
			# Monitors cost a query; a section that cannot use the answer must not pay for it.
			$null = Resolve-DisplayAwareProfile -Section @{ Default = 'default' }

			Should -Invoke Test-SmallPrimaryDisplay -Times 0 -Exactly
		}

		It "forwards a supplied snapshot to both helpers" {
			$monitors = @([PSCustomObject]@{ IsPrimary = $true; Width = 1920; Height = 1080 })

			$null = Resolve-DisplayAwareProfile -Section @{ SmallDisplay = 'small'; Default = 'default' } -MonitorInfo $monitors

			Should -Invoke Test-SmallPrimaryDisplay -Times 1 -Exactly -ParameterFilter { $MonitorInfo.Count -eq 1 }
			Should -Invoke Get-LayoutMachineType -Times 1 -Exactly -ParameterFilter { $MonitorInfo.Count -eq 1 }
		}

		It "leaves the helpers unbound when no snapshot is supplied" {
			# Unbound is not the same as $null: each helper decides for itself whether it needs
			# monitors at all, and only an unbound parameter lets it skip the query.
			$null = Resolve-DisplayAwareProfile -Section @{ SmallDisplay = 'small'; Default = 'default' }

			Should -Invoke Test-SmallPrimaryDisplay -Times 1 -Exactly -ParameterFilter { -not $PSBoundParameters.ContainsKey('MonitorInfo') }
			Should -Invoke Get-LayoutMachineType -Times 1 -Exactly -ParameterFilter { -not $PSBoundParameters.ContainsKey('MonitorInfo') }
		}
	}

	Context "row values" {
		It "returns a hashtable row unchanged" {
			$row = @{ TargetWidthPx = 1376; TargetHeightPx = 700 }

			$result = Resolve-DisplayAwareProfile -Section @{ Default = $row }

			$result | Should -BeOfType [hashtable]
			$result.TargetWidthPx | Should -Be 1376
		}

		It "returns a scalar row unchanged" {
			Resolve-DisplayAwareProfile -Section @{ Default = 70 } | Should -Be 70
		}
	}
}
