#Requires -Modules Pester

BeforeAll {
	$ConfigFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Configuration\Functions"
	. "$ConfigFunctionsPath\Test-ConfigurationKeyPath.ps1"
	. "$ConfigFunctionsPath\Test-ConfigurationSchema.ps1"
	. (Join-Path (Get-RepositoryPath).Modules "Helper\Functions\Test-ConfigValue.ps1")
	. (Join-Path (Get-RepositoryPath).Modules "Helper\Functions\Resolve-WorkspaceTemplate.ps1")
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

	Context "workspace templates" {
		BeforeEach {
			$script:TemplateConfig = @{
				ValidMachineTypes     = @('PC')
				HostnameToMachineType = @{ 'PC1' = 'PC' }
				DefaultMachineType    = 'PC'
				LaptopChassisTypes    = @('9')
				BasePaths             = @{ Dev = 'C:\Dev' }
				PathTemplates         = @{ Root = '{Dev}'; Projects = @{ Self = @{ Root = '{RepoRoot}' } }; SymbolicLinks = @{ } }
				GitConfig             = @{ UserName = 'ExampleUser'; UserEmail = 'x@y.z'; WingetPackageId = 'Git.Git' }
				BrowserGroups         = @(@{ Work = @('https://example.com') })
				RepositoryGroups      = @(@{ Private = @(@{ Name = 'WinuX'; UrlPath = 'Universal.GitHub.Private.WinuX'; LocalPath = 'Projects.Self.Root' }) })
				WorkspaceTemplates    = @{
					Project = @{
						Variables = @{ Repository = '{Workspace}Repository' }
						Actions   = @(@{ Action = 'Open-Browser'; Parameters = @{ Groups = @('{Repository}') } })
					}
				}
				WorkspaceActions      = @(
					@{ Default = @(@{ Action = 'Open-Browser' }) }
				)
			}
		}

		It "accepts clean templates and a templated entry that expands" {
			$script:TemplateConfig.WorkspaceActions += @{ MyProject = @{ Template = 'Project' } }

			Test-ConfigurationSchema -Configuration $script:TemplateConfig

			Should -Invoke Write-Warning -Times 0
		}

		It "reports WorkspaceTemplates that is not a hashtable" {
			$script:TemplateConfig.WorkspaceTemplates = @('Project')

			Test-ConfigurationSchema -Configuration $script:TemplateConfig

			Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -match 'WorkspaceTemplates must be a hashtable' }
		}

		It "reports a template without Actions" {
			$script:TemplateConfig.WorkspaceTemplates.Empty = @{ Variables = @{ X = 1 } }

			Test-ConfigurationSchema -Configuration $script:TemplateConfig

			Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -match 'WorkspaceTemplates\.Empty' }
		}

		It "reports the problems Expand-WorkspaceTemplates recorded under WorkspaceTemplateErrors" {
			$script:TemplateConfig.WorkspaceTemplateErrors = @('WorkspaceActions.Broken - unknown template [Missing]', '')

			Test-ConfigurationSchema -Configuration $script:TemplateConfig

			Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -match '1 issue' -and $Message -match 'WorkspaceActions\.Broken' }
		}

		It "resolves a templated entry still present as a raw dictionary and reports its errors" {
			$script:TemplateConfig.WorkspaceActions += @{ Broken = @{ Template = 'Missing' } }

			Test-ConfigurationSchema -Configuration $script:TemplateConfig

			Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -match 'WorkspaceActions\.Broken' }
		}

		It "resolves raw templated entries of a legacy hashtable section too" {
			$script:TemplateConfig.WorkspaceActions = @{ Broken = @{ Template = 'Project'; Overrides = @{ 'Open-Nothing' = $null } } }

			Test-ConfigurationSchema -Configuration $script:TemplateConfig

			Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -match 'WorkspaceActions\.Broken' }
		}

		It "does not re-resolve entries already expanded at load" {
			# Expanded at load: WorkspaceActions holds the action list, the raw entry sits in
			# WorkspaceTemplateEntries, and its (absent) problems in WorkspaceTemplateErrors.
			$script:TemplateConfig.WorkspaceActions += @{ MyProject = @(@{ Action = 'Open-Browser' }) }
			$script:TemplateConfig.WorkspaceTemplateEntries = [ordered]@{ MyProject = @{ Template = 'Missing' } }
			$script:TemplateConfig.WorkspaceTemplateErrors = @()
			Mock Resolve-WorkspaceTemplate { [PSCustomObject]@{ Errors = @('should not be called') } }

			Test-ConfigurationSchema -Configuration $script:TemplateConfig

			Should -Invoke Resolve-WorkspaceTemplate -Times 0
			Should -Invoke Write-Warning -Times 0
		}

		It "throws on a templated entry error with -Strict" {
			$script:TemplateConfig.WorkspaceActions += @{ Broken = @{ Template = 'Missing' } }

			{ Test-ConfigurationSchema -Configuration $script:TemplateConfig -Strict } | Should -Throw '*WorkspaceActions.Broken*'
		}
	}

	Context "AI artifact sections" {
		BeforeEach {
			$script:AiConfig = @{
				ValidMachineTypes     = @('PC')
				HostnameToMachineType = @{ 'PC1' = 'PC' }
				DefaultMachineType    = 'PC'
				LaptopChassisTypes    = @('9')
				BasePaths             = @{ Dev = 'C:\Dev' }
				PathTemplates         = @{ Root = '{Dev}'; Projects = @{ Self = @{ Root = '{RepoRoot}' } }; SymbolicLinks = @{ } }
				GitConfig             = @{ UserName = 'ExampleUser'; UserEmail = 'x@y.z'; WingetPackageId = 'Git.Git' }
				BrowserGroups         = @(@{ Work = @('https://example.com') })
				RepositoryGroups      = @(@{ Private = @(@{ Name = 'WinuX'; UrlPath = 'Universal.GitHub.Private.WinuX'; LocalPath = 'Projects.Self.Root' }) })
				AiHarnesses           = @{
					"claude-code" = @{ WSL = $true; Destinations = @(@{ Kind = "Skills"; Placement = "Each"; Files = @("."); Path = "{User}\.claude\skills" }) }
				}
				AiArtifacts           = @{
					Root    = "{RepoRoot}\AI"
					Exclude = @("skills/tdd", @{ Item = "rules/example/CoreAiRules"; Machine = "PC" })
					Use     = @{ Rules = "CoreAiRules" }
					Deploy  = @{ Default = @("claude-code") }
				}
			}
		}

		It "accepts well-formed AiArtifacts and AiHarnesses" {
			Test-ConfigurationSchema -Configuration $script:AiConfig

			Should -Invoke Write-Warning -Times 0
		}

		It "reports each malformed entry and throws under -Strict" -TestCases @(
			@{ Case = "an unknown harness in Deploy"; Change = { param($c) $c.AiArtifacts.Deploy = @{ Default = @("t3") } } }
			@{ Case = "a Use key that is no kind"; Change = { param($c) $c.AiArtifacts.Use = @{ Widgets = "X" } } }
			@{ Case = "an Exclude without a kind"; Change = { param($c) $c.AiArtifacts.Exclude = @("tdd") } }
			@{ Case = "an Exclude with an unknown kind"; Change = { param($c) $c.AiArtifacts.Exclude = @("widgets/tdd") } }
			@{ Case = "a destination with an unknown Kind"; Change = { param($c) $c.AiHarnesses['claude-code'].Destinations[0].Kind = "Widgets" } }
			@{ Case = "a destination with an unknown Placement"; Change = { param($c) $c.AiHarnesses['claude-code'].Destinations[0].Placement = "Link" } }
			@{ Case = "a destination without Files"; Change = { param($c) $c.AiHarnesses['claude-code'].Destinations[0].Files = @() } }
			@{ Case = "a destination without Path"; Change = { param($c) $c.AiHarnesses['claude-code'].Destinations[0].Remove('Path') } }
			@{ Case = "a Deploy that is not a hashtable"; Change = { param($c) $c.AiArtifacts.Deploy = @("claude-code") } }
		) {
			param($Case, $Change)
			& $Change $script:AiConfig

			Test-ConfigurationSchema -Configuration $script:AiConfig
			Should -Invoke Write-Warning -Times 1 -Exactly

			{ Test-ConfigurationSchema -Configuration $script:AiConfig -Strict } | Should -Throw
		}
	}

	Context "deprecated configuration" {
		It "stays silent for a configuration that uses no deprecated key" {
			$config = @{
				ValidMachineTypes     = @('PC')
				HostnameToMachineType = @{ 'PC1' = 'PC' }
				DefaultMachineType    = 'PC'
				LaptopChassisTypes    = @('9')
				BasePaths             = @{ Dev = 'C:\Dev' }
				PathTemplates         = @{ Root = '{Dev}'; Projects = @{ Self = @{ Root = '{RepoRoot}' } }; SymbolicLinks = @{ } }
				GitConfig             = @{ UserName = 'ExampleUser'; UserEmail = 'x@y.z'; WingetPackageId = 'Git.Git' }
				BrowserGroups         = @(@{ Work = @('https://example.com') })
				RepositoryGroups      = @(@{ Private = @(@{ Name = 'WinuX'; UrlPath = 'Universal.GitHub.Private.WinuX'; LocalPath = 'Projects.Self.Root' }) })
				BootstrapConfig       = @{ Steps = @{ WSL = $true } }
			}

			Test-ConfigurationSchema -Configuration $config

			Should -Invoke Write-Warning -Times 0
		}

		Context "RepositoryUpdate.Startup.Enabled" {
			BeforeEach {
				$script:DeprecationConfig = @{
					ValidMachineTypes     = @('PC')
					HostnameToMachineType = @{ 'PC1' = 'PC' }
					DefaultMachineType    = 'PC'
					LaptopChassisTypes    = @('9')
					BasePaths             = @{ Dev = 'C:\Dev' }
					PathTemplates         = @{ Root = '{Dev}'; Projects = @{ Self = @{ Root = '{RepoRoot}' } }; SymbolicLinks = @{ } }
					GitConfig             = @{ UserName = 'ExampleUser'; UserEmail = 'x@y.z'; WingetPackageId = 'Git.Git' }
					BrowserGroups         = @(@{ Work = @('https://example.com') })
					RepositoryGroups      = @(@{ Private = @(@{ Name = 'WinuX'; UrlPath = 'Universal.GitHub.Private.WinuX'; LocalPath = 'Projects.Self.Root' }) })
					RepositoryUpdate      = @{ IncludeDefaultBranch = $false; Startup = @{ Enabled = $false; Schedule = 'Daily'; DayStartHour = 6; IntervalHours = 24 } }
				}
			}

			It "stays silent while the key keeps the shipped default" {
				Test-ConfigurationSchema -Configuration $script:DeprecationConfig

				Should -Invoke Write-Warning -Times 0
			}

			It "stays silent when <Case>" -TestCases @(
				@{ Case = "the Startup block has no Enabled key"; Change = { param($c) $c.RepositoryUpdate.Startup.Remove('Enabled') } }
				@{ Case = "RepositoryUpdate has no Startup block"; Change = { param($c) $c.RepositoryUpdate.Remove('Startup') } }
				@{ Case = "there is no RepositoryUpdate section"; Change = { param($c) $c.Remove('RepositoryUpdate') } }
				@{ Case = "only the other Startup keys differ from the base"; Change = { param($c) $c.RepositoryUpdate.Startup.Schedule = 'Interval'; $c.RepositoryUpdate.Startup.IntervalHours = 4 } }
			) {
				param($Case, $Change)
				& $Change $script:DeprecationConfig

				Test-ConfigurationSchema -Configuration $script:DeprecationConfig

				Should -Invoke Write-Warning -Times 0
			}

			It "warns once when the key is switched on" {
				$script:DeprecationConfig.RepositoryUpdate.Startup.Enabled = $true

				Test-ConfigurationSchema -Configuration $script:DeprecationConfig

				Should -Invoke Write-Warning -Times 1 -Exactly
				Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -match 'RepositoryUpdate\.Startup\.Enabled' }
			}

			It "never counts the deprecated key as a failure, even with -Strict" {
				$script:DeprecationConfig.RepositoryUpdate.Startup.Enabled = $true

				{ Test-ConfigurationSchema -Configuration $script:DeprecationConfig -Strict } | Should -Not -Throw

				Should -Invoke Write-Warning -Times 1 -Exactly
			}

			It "reports the deprecated key on its own, next to a real failure" {
				$script:DeprecationConfig.RepositoryUpdate.Startup.Enabled = $true
				$script:DeprecationConfig.Remove('BasePaths')

				Test-ConfigurationSchema -Configuration $script:DeprecationConfig

				Should -Invoke Write-Warning -Times 2 -Exactly
				Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -match 'RepositoryUpdate\.Startup\.Enabled' }
				{ Test-ConfigurationSchema -Configuration $script:DeprecationConfig -Strict } | Should -Throw
			}
		}
	}

	Context "Startup section" {
		BeforeEach {
			$script:StartupConfig = @{
				ValidMachineTypes     = @('PC')
				HostnameToMachineType = @{ 'PC1' = 'PC' }
				DefaultMachineType    = 'PC'
				LaptopChassisTypes    = @('9')
				BasePaths             = @{ Dev = 'C:\Dev' }
				PathTemplates         = @{ Root = '{Dev}'; Projects = @{ Self = @{ Root = '{RepoRoot}' } }; SymbolicLinks = @{ } }
				GitConfig             = @{ UserName = 'ExampleUser'; UserEmail = 'x@y.z'; WingetPackageId = 'Git.Git' }
				BrowserGroups         = @(@{ Work = @('https://example.com') })
				RepositoryGroups      = @(@{ Private = @(@{ Name = 'WinuX'; UrlPath = 'Universal.GitHub.Private.WinuX'; LocalPath = 'Projects.Self.Root' }) })
				Startup               = @{
					Tasks         = @()
					Conditions    = @{ Network = @{ Test = '$true'; Timeout = 60; Interval = 2 } }
					FailureReport = 'Tab'
				}
			}
		}

		It "accepts the shape the base ships: no task and one condition" {
			Test-ConfigurationSchema -Configuration $script:StartupConfig

			Should -Invoke Write-Warning -Times 0
		}

		It "accepts tasks written as hashtables" {
			$script:StartupConfig.Startup.Tasks = @(
				@{ Name = 'MyUpdate'; Command = 'Update-Repositories -All -NoClone -Quiet'; Trigger = @('SignIn', 'TerminalOpen'); Requires = @('Network') }
				@{ Name = 'MyWorkspace'; Command = 'Open-Workspace MyWorkspace'; Trigger = 'SignIn' }
			)

			Test-ConfigurationSchema -Configuration $script:StartupConfig

			Should -Invoke Write-Warning -Times 0
		}

		It "accepts a Startup section that holds only some of its keys" {
			$script:StartupConfig.Startup = @{ FailureReport = 'None' }

			Test-ConfigurationSchema -Configuration $script:StartupConfig

			Should -Invoke Write-Warning -Times 0
		}

		It "leaves what a task holds to Get-StartupTaskDefinitions" {
			# Only the shape is checked here: this function runs before the first prompt and must
			# not load the module that knows a task's keys.
			$script:StartupConfig.Startup.Tasks = @(@{ Name = 'MyTask'; Trigger = 'Boot'; NoSuchKey = 1 })

			{ Test-ConfigurationSchema -Configuration $script:StartupConfig -Strict } | Should -Not -Throw

			Should -Invoke Write-Warning -Times 0
		}

		It "reports <Case> and throws under -Strict" -TestCases @(
			@{ Case = "a Startup that is not a hashtable"; Change = { param($c) $c.Startup = @('Tasks', 'Conditions') } }
			@{ Case = "a task that is not a hashtable"; Change = { param($c) $c.Startup.Tasks = @(@{ Name = 'MyTask'; Trigger = 'SignIn' }, 'Update-Repositories -All') } }
			@{ Case = "Conditions that is not a hashtable"; Change = { param($c) $c.Startup.Conditions = @('Network') } }
			@{ Case = "a condition that is not a hashtable"; Change = { param($c) $c.Startup.Conditions.Network = 'Test-Connection example.com -Quiet' } }
		) {
			param($Case, $Change)
			& $Change $script:StartupConfig

			Test-ConfigurationSchema -Configuration $script:StartupConfig
			Should -Invoke Write-Warning -Times 1 -Exactly

			{ Test-ConfigurationSchema -Configuration $script:StartupConfig -Strict } | Should -Throw
		}
	}
}
