#Requires -Modules Pester

BeforeAll {
	$script:OriginalConfiguration = $global:Configuration
	$script:OriginalMachineType = $global:MachineType

	$ModuleRoot = (Get-RepositoryPath).Modules
	# The real gate, not a stub: the row keys are Test-MachineTypeScope's machine-scope strings.
	. "$ModuleRoot\Bootstrap\Functions\Test-MachineTypeScope.ps1"
	. "$ModuleRoot\AI\Functions\Resolve-AiPluginConfigs.ps1"
}

AfterAll {
	$global:Configuration = $script:OriginalConfiguration
	$global:MachineType = $script:OriginalMachineType
}

Describe "Resolve-AiPluginConfigs" {
	BeforeEach {
		Mock Write-LogError { }
		Mock Write-LogDebug { }

		$global:Configuration = @{
			ValidMachineTypes = @('PC', 'Laptop', 'Work', 'Test')
			AiMarketplaces    = @{
				PluginConfigs = @{
					"my-plugin" = @{
						options = @{ theme = "dark"; pulse = $true; size = 3 }
						other   = "kept"
					}
				}
			}
		}
		$global:MachineType = 'PC'
	}

	It "returns PluginConfigs as they are when no machine table is configured" {
		$result = Resolve-AiPluginConfigs

		$result.Keys | Should -Be @("my-plugin")
		$result.'my-plugin'.options.theme | Should -Be "dark"
		$result.'my-plugin'.options.pulse | Should -BeTrue
		$result.'my-plugin'.other | Should -Be "kept"
	}

	It "returns an empty hashtable when the section names no plugin" {
		$global:Configuration.AiMarketplaces = @{}

		$result = Resolve-AiPluginConfigs

		$result | Should -BeOfType [hashtable]
		$result.Count | Should -Be 0
	}

	It "merges the row of this machine type over the defaults, key by key" {
		$global:Configuration.AiMarketplaces.MachinePluginConfigs = @{
			PC = @{ "my-plugin" = @{ options = @{ theme = "light"; glyph = "x" } } }
		}

		$options = (Resolve-AiPluginConfigs).'my-plugin'.options

		$options.theme | Should -Be "light"
		$options.glyph | Should -Be "x"
		$options.pulse | Should -BeTrue -Because "an option the row does not name keeps its default"
		$options.size | Should -Be 3
	}

	It "leaves the defaults alone on a machine type no row covers" {
		$global:Configuration.AiMarketplaces.MachinePluginConfigs = @{
			PC = @{ "my-plugin" = @{ options = @{ theme = "light" } } }
		}

		(Resolve-AiPluginConfigs -MachineType Laptop).'my-plugin'.options.theme | Should -Be "dark"
	}

	It "matches a row naming several machine types, case-insensitively" {
		$global:Configuration.AiMarketplaces.MachinePluginConfigs = @{
			"laptop/Work" = @{ "my-plugin" = @{ options = @{ theme = "light" } } }
		}

		(Resolve-AiPluginConfigs -MachineType Laptop).'my-plugin'.options.theme | Should -Be "light"
		(Resolve-AiPluginConfigs -MachineType Work).'my-plugin'.options.theme | Should -Be "light"
		(Resolve-AiPluginConfigs -MachineType PC).'my-plugin'.options.theme | Should -Be "dark"
	}

	It "applies the All row first, then the other matching rows in alphabetical order" {
		$global:Configuration.AiMarketplaces.MachinePluginConfigs = @{
			"PC/Work" = @{ "my-plugin" = @{ options = @{ theme = "second" } } }
			"PC"      = @{ "my-plugin" = @{ options = @{ theme = "first"; size = 5 } } }
			"All"     = @{ "my-plugin" = @{ options = @{ theme = "all"; glyph = "x" } } }
		}

		$options = (Resolve-AiPluginConfigs).'my-plugin'.options

		$options.theme | Should -Be "second" -Because "[PC/Work] sorts after [PC]"
		$options.size | Should -Be 5
		$options.glyph | Should -Be "x"
	}

	It "removes an option a row sets to null" {
		$global:Configuration.AiMarketplaces.MachinePluginConfigs = @{
			PC = @{ "my-plugin" = @{ options = @{ pulse = $null }; other = $null } }
		}

		$entry = (Resolve-AiPluginConfigs).'my-plugin'

		$entry.options.ContainsKey('pulse') | Should -BeFalse
		$entry.options.theme | Should -Be "dark"
		$entry.ContainsKey('other') | Should -BeFalse
	}

	It "gives a plugin only a row names its options on those machines only" {
		$global:Configuration.AiMarketplaces.MachinePluginConfigs = @{
			Work = @{ "other-plugin" = @{ options = @{ size = "big" } } }
		}

		(Resolve-AiPluginConfigs -MachineType Work).'other-plugin'.options.size | Should -Be "big"
		(Resolve-AiPluginConfigs -MachineType PC).ContainsKey('other-plugin') | Should -BeFalse
	}

	It "never modifies the configuration" {
		$global:Configuration.AiMarketplaces.MachinePluginConfigs = @{
			PC = @{ "my-plugin" = @{ options = @{ theme = "light"; pulse = $null } } }
		}

		$result = Resolve-AiPluginConfigs
		$result.'my-plugin'.options.size = 99

		$defaults = $global:Configuration.AiMarketplaces.PluginConfigs.'my-plugin'.options
		$defaults.theme | Should -Be "dark"
		$defaults.pulse | Should -BeTrue
		$defaults.size | Should -Be 3
	}

	It "reports an unknown machine type in a row key and never applies the row" {
		$global:Configuration.AiMarketplaces.MachinePluginConfigs = @{
			Labtop = @{ "my-plugin" = @{ options = @{ theme = "light" } } }
		}

		(Resolve-AiPluginConfigs -MachineType Laptop).'my-plugin'.options.theme | Should -Be "dark"
		Should -Invoke Write-LogError -ParameterFilter { $Message -like "Unknown machine type [[]Labtop] in [[]AiMarketplaces.MachinePluginConfigs]*" }
	}

	It "reports a row that is not a hashtable and applies the others" {
		$global:Configuration.AiMarketplaces.MachinePluginConfigs = @{
			All = "light"
			PC  = @{ "my-plugin" = @{ options = @{ size = 5 } } }
		}

		(Resolve-AiPluginConfigs).'my-plugin'.options.size | Should -Be 5
		Should -Invoke Write-LogError -ParameterFilter { $Message -like "AiMarketplaces.MachinePluginConfigs row [[]All] must be a hashtable of plugin options (got [[]String])*" }
	}

	It "reports a machine table that is not a hashtable and returns the defaults" {
		$global:Configuration.AiMarketplaces.MachinePluginConfigs = @("PC")

		(Resolve-AiPluginConfigs).'my-plugin'.options.theme | Should -Be "dark"
		Should -Invoke Write-LogError -ParameterFilter { $Message -like "AiMarketplaces.MachinePluginConfigs must be a hashtable of machine scope => plugin options*" }
	}
}
