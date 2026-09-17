#Requires -Modules Pester

BeforeAll {
	$ConfigFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Configuration\Functions"
	. "$ConfigFunctionsPath\Test-ConfigurationKeyPath.ps1"
	. "$ConfigFunctionsPath\Test-ConfigurationSchema.ps1"
	. (Join-Path (Get-RepositoryPath).Modules "Helper\Functions\Test-ConfigValue.ps1")
}

Describe "Test-ConfigurationSchema" {
	BeforeEach {
		Mock Write-Warning { }
	}

	It "writes warning when required keys are missing in non-strict mode" {
		$config = @{ }

		Test-ConfigurationSchema -Configuration $config

		Should -Invoke Write-Warning -Times 1 -Exactly
	}

	It "throws when required keys are missing in strict mode" {
		$config = @{ }

		{ Test-ConfigurationSchema -Configuration $config -Strict } | Should -Throw
	}

	It "passes without warning when all required keys are present" {
		$config = @{
			ValidMachineTypes     = @('PC')
			HostnameToMachineType = @{ 'PC1' = 'PC' }
			DefaultMachineType    = 'PC'
			LaptopChassisTypes    = @('9')
			BasePaths             = @{ Dev = 'C:\\Dev' }
			PathTemplates         = @{ Root = '{Dev}'; Projects = @{ Self = @{ Root = '{RepoRoot}' } }; SymbolicLinks = @{ } }
			GitConfig             = @{ UserName = 'ExampleUser'; UserEmail = 'x@y.z'; WingetPackageId = 'Git.Git' }
			Locales               = @(@{ 'en-US' = @{ Code = 'en-US'; GeoId = 244 } })
			DefaultLocale         = 'en-US'
			KeyboardLayouts       = @{ Default = @('0409:00000409') }
			BrowserGroups         = @(@{ Work = @('https://example.com') })
			RepositoryGroups      = @(@{ Private = @(@{ Name = 'WinuX'; UrlPath = 'Universal.GitHub.Private.WinuX'; LocalPath = 'Projects.Self.Root' }) })
		}

		Test-ConfigurationSchema -Configuration $config

		Should -Invoke Write-Warning -Times 0
	}

	Context "ordered section shapes" {
		BeforeEach {
			$script:ValidConfig = @{
				ValidMachineTypes     = @('PC')
				HostnameToMachineType = @{ 'PC1' = 'PC' }
				DefaultMachineType    = 'PC'
				LaptopChassisTypes    = @('9')
				BasePaths             = @{ Dev = 'C:\Dev' }
				PathTemplates         = @{ Root = '{Dev}'; Projects = @{ Self = @{ Root = '{RepoRoot}' } }; SymbolicLinks = @{ } }
				GitConfig             = @{ UserName = 'ExampleUser'; UserEmail = 'x@y.z'; WingetPackageId = 'Git.Git' }
				BrowserGroups         = @(@{ Work = @('https://example.com') })
				RepositoryGroups      = @(@{ Private = @(@{ Name = 'WinuX'; UrlPath = 'Universal.GitHub.Private.WinuX'; LocalPath = 'Projects.Self.Root' }) })
			}
		}

		It "accepts an ordered section written as an array of single-key hashtables" {
			$script:ValidConfig.WorkspaceActions = @(
				@{ Default = @(@{ Action = 'Open-Browser' }) }
				@{ WinuX = @(@{ Action = 'Open-VSCode' }) }
			)

			Test-ConfigurationSchema -Configuration $script:ValidConfig

			Should -Invoke Write-Warning -Times 0
		}

		It "reports an ordered section still written as a hashtable" {
			# The one place a fork is told its menu order is being lost, rather than every
			# menu repeating it.
			$script:ValidConfig.WorkspaceActions = @{ Default = @(@{ Action = 'Open-Browser' }) }

			Test-ConfigurationSchema -Configuration $script:ValidConfig

			Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -match 'WorkspaceActions is a hashtable' }
		}

		It "reports an entry that is not a single-key hashtable" {
			$script:ValidConfig.CampaignResources = @(
				@{ Habajec = @{ Pdf = 'Wilius' }; Hrkovac = @{ Pdf = 'Jin' } }
			)

			Test-ConfigurationSchema -Configuration $script:ValidConfig

			Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -match 'CampaignResources has 1 entr' }
		}

		It "says nothing about an ordered section that ships empty" {
			$script:ValidConfig.WakeOnLanConfig = @()
			$script:ValidConfig.NerdFonts = @()

			Test-ConfigurationSchema -Configuration $script:ValidConfig

			Should -Invoke Write-Warning -Times 0
		}
	}
}
