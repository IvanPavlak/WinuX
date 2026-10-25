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
		BeforeEach {
			$script:DeprecatedConfig = @{
				ValidMachineTypes     = @('PC')
				HostnameToMachineType = @{ 'PC1' = 'PC' }
				DefaultMachineType    = 'PC'
				LaptopChassisTypes    = @('9')
				BasePaths             = @{ Dev = 'C:\Dev' }
				PathTemplates         = @{ Root = '{Dev}'; Projects = @{ Self = @{ Root = '{RepoRoot}' } }; SymbolicLinks = @{ }; ObsidianStartupScript = "" }
				GitConfig             = @{ UserName = 'ExampleUser'; UserEmail = 'x@y.z'; WingetPackageId = 'Git.Git' }
				BrowserGroups         = @(@{ Work = @('https://example.com') })
				RepositoryGroups      = @(@{ Private = @(@{ Name = 'WinuX'; UrlPath = 'Universal.GitHub.Private.WinuX'; LocalPath = 'Projects.Self.Root' }) })
				# The deprecated keys exactly as the base ships them: present, but at their defaults.
				AiSkills              = @{ Root = "{RepoRoot}\AI\Skills"; Harnesses = @("{User}\.claude\skills", "{User}\.agents\skills"); Sources = @{} }
				AiMods                = @{ Root = "{RepoRoot}\AI\Mods"; Harnesses = @("{User}\.claude\mods"); Sources = @{} }
				BootstrapConfig       = @{ Steps = @{ WSL = $true } }
			}
		}

		It "stays silent for the deprecated keys at their shipped defaults" {
			Test-ConfigurationSchema -Configuration $script:DeprecatedConfig

			Should -Invoke Write-Warning -Times 0
		}

		It "warns once, listing every deprecated key in use" -TestCases @(
			@{ Case = "a present key (Present)"; Change = { param($c) $c.BootstrapConfig.WSLSetup = $true } }
			@{ Case = "a present step name (Present)"; Change = { param($c) $c.BootstrapConfig.Steps.CoreAiRules = $false } }
			@{ Case = "a present SymbolicLinks.AI (Present)"; Change = { param($c) $c.PathTemplates.SymbolicLinks.AI = @{} } }
			@{ Case = "a non-empty value (NotEmpty)"; Change = { param($c) $c.AiSkills.Sources = @{ s = @{ Repository = "A/B" } } } }
			@{ Case = "a non-empty scalar (NotEmpty)"; Change = { param($c) $c.PathTemplates.ObsidianStartupScript = "C:\start.ps1" } }
			@{ Case = "a changed scalar (NotDefault)"; Change = { param($c) $c.AiMods.Root = "D:\Mods" } }
			@{ Case = "a changed array (NotDefault)"; Change = { param($c) $c.AiSkills.Harnesses = @("{User}\.claude\skills") } }
		) {
			param($Case, $Change)
			& $Change $script:DeprecatedConfig

			Test-ConfigurationSchema -Configuration $script:DeprecatedConfig

			Should -Invoke Write-Warning -Times 1 -Exactly
		}

		It "puts several deprecated keys into the one warning" {
			$script:DeprecatedConfig.BootstrapConfig.Steps.AiSkills = $true
			$script:DeprecatedConfig.BootstrapConfig.Steps.AiMods = $true
			$script:DeprecatedConfig.AiMods.Sources = @{ m = @{ Repository = "A/B" } }
			$script:Warned = @()
			Mock Write-Warning { $script:Warned += $Message }

			Test-ConfigurationSchema -Configuration $script:DeprecatedConfig

			$script:Warned.Count | Should -Be 1
			@($script:Warned[0] -split "`n" | Where-Object { $_ -like "  - *" }).Count | Should -Be 3
		}

		It "never fails under -Strict for a deprecation" {
			$script:DeprecatedConfig.BootstrapConfig.WSLSetup = $true
			$script:DeprecatedConfig.AiSkills.Sources = @{ s = @{ Repository = "A/B" } }

			{ Test-ConfigurationSchema -Configuration $script:DeprecatedConfig -Strict } | Should -Not -Throw
		}
	}
}
