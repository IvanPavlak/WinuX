#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Resolve-WorkspaceTemplate.ps1"
	. "$FunctionsPath\Expand-WorkspaceTemplates.ps1"
	. "$FunctionsPath\Get-OrderedNames.ps1"
}

Describe "Expand-WorkspaceTemplates" {
	BeforeEach {
		Mock Write-Host { }
		Mock Write-LogError { }

		$script:Templates = @{
			Project = @{
				Variables = @{ Repository = '{Workspace}Repository' }
				Actions   = @(
					@{ Action = 'Open-Project'; Parameters = @{ Project = '{Workspace}' } }
					@{ Action = 'Open-Browser'; Parameters = @{ Groups = @('{Repository}') } }
				)
			}
		}

		$script:PlainUntouched = @(@{ Action = 'Open-Rider' })
		$script:PlainWithToken = @(@{ Action = 'Set-WorkspaceWindowLayout'; Parameters = @{ WorkspaceName = '{Workspace}' } })
		$script:Templated = @{ Template = 'Project' }
		$script:Broken = @{ Template = 'Missing' }

		# The ordered-array shape, deliberately not alphabetical.
		$script:Configuration = @{
			WorkspaceTemplates = $script:Templates
			WorkspaceActions   = @(
				@{ Zulu = $script:PlainUntouched }
				@{ MyProject = $script:Templated }
				@{ Alpha = $script:PlainWithToken }
				@{ Broken = $script:Broken }
			)
		}
	}

	It "expands a templated entry in place in an ordered-array section" {
		Expand-WorkspaceTemplates -Configuration $script:Configuration | Out-Null

		$actions = $script:Configuration.WorkspaceActions[1].MyProject
		@($actions | ForEach-Object { $_.Action }) | Should -Be @('Open-Project', 'Open-Browser')
		$actions[0].Parameters.Project | Should -Be 'MyProject'
		@($actions[1].Parameters.Groups) | Should -Be @('MyProjectRepository')
	}

	It "keeps the menu order of the section" {
		Expand-WorkspaceTemplates -Configuration $script:Configuration | Out-Null

		@(Get-OrderedNames $script:Configuration.WorkspaceActions) | Should -Be @('Zulu', 'MyProject', 'Alpha', 'Broken')
	}

	It "substitutes {Workspace} in a plain entry and leaves a plain entry without the token as the same object" {
		Expand-WorkspaceTemplates -Configuration $script:Configuration | Out-Null

		[object]::ReferenceEquals($script:Configuration.WorkspaceActions[0].Zulu, $script:PlainUntouched) | Should -BeTrue
		$script:Configuration.WorkspaceActions[2].Alpha[0].Parameters.WorkspaceName | Should -Be 'Alpha'
		$script:PlainWithToken[0].Parameters.WorkspaceName | Should -Be '{Workspace}'
	}

	It "stores the raw templated definitions under WorkspaceTemplateEntries, ordered and case-insensitive" {
		Expand-WorkspaceTemplates -Configuration $script:Configuration | Out-Null

		$entries = $script:Configuration.WorkspaceTemplateEntries
		($entries -is [System.Collections.Specialized.OrderedDictionary]) | Should -BeTrue
		@($entries.Keys) | Should -Be @('MyProject', 'Broken')
		[object]::ReferenceEquals($entries['myproject'], $script:Templated) | Should -BeTrue
		$entries.Contains('Zulu') | Should -BeFalse
		$entries.Contains('Alpha') | Should -BeFalse
	}

	It "turns a broken entry into an empty action list, returns its error and logs it" {
		$summary = Expand-WorkspaceTemplates -Configuration $script:Configuration

		@($script:Configuration.WorkspaceActions[3].Broken).Count | Should -Be 0
		@($summary.Expanded) | Should -Be @('MyProject')
		@($summary.Errors).Count | Should -Be 1
		$summary.Errors[0] | Should -BeLike 'WorkspaceActions.Broken*'
		Should -Invoke Write-LogError -Times 1 -Exactly
	}

	It "records the problems under WorkspaceTemplateErrors for Test-ConfigurationSchema" {
		$summary = Expand-WorkspaceTemplates -Configuration $script:Configuration -Quiet

		@($script:Configuration.WorkspaceTemplateErrors) | Should -Be @($summary.Errors)
		@($script:Configuration.WorkspaceTemplateErrors).Count | Should -Be 1
	}

	It "returns the error but logs nothing with -Quiet" {
		$summary = Expand-WorkspaceTemplates -Configuration $script:Configuration -Quiet

		@($summary.Errors).Count | Should -Be 1
		@($script:Configuration.WorkspaceActions[3].Broken).Count | Should -Be 0
		Should -Invoke Write-LogError -Times 0
	}

	It "expands entries of a legacy hashtable section too" {
		$configuration = @{
			WorkspaceTemplates = $script:Templates
			WorkspaceActions   = @{ MyProject = @{ Template = 'Project' }; Plain = $script:PlainUntouched }
		}

		$summary = Expand-WorkspaceTemplates -Configuration $configuration

		@($summary.Expanded) | Should -Be @('MyProject')
		$configuration.WorkspaceActions.MyProject[0].Parameters.Project | Should -Be 'MyProject'
		[object]::ReferenceEquals($configuration.WorkspaceActions.Plain, $script:PlainUntouched) | Should -BeTrue
		$configuration.WorkspaceTemplateEntries.Contains('MyProject') | Should -BeTrue
	}

	It "writes an empty WorkspaceTemplateEntries map when nothing is templated" {
		$configuration = @{ WorkspaceActions = @(@{ Zulu = $script:PlainUntouched }) }

		$summary = Expand-WorkspaceTemplates -Configuration $configuration

		$configuration.ContainsKey('WorkspaceTemplateEntries') | Should -BeTrue
		$configuration.WorkspaceTemplateEntries.Count | Should -Be 0
		$configuration.ContainsKey('WorkspaceTemplateErrors') | Should -BeTrue
		@($configuration.WorkspaceTemplateErrors).Count | Should -Be 0
		@($summary.Expanded).Count | Should -Be 0
		@($summary.Errors).Count | Should -Be 0
	}

	It "returns an empty summary for a null configuration" {
		$summary = Expand-WorkspaceTemplates -Configuration $null

		@($summary.Expanded).Count | Should -Be 0
		@($summary.Errors).Count | Should -Be 0
		Should -Invoke Write-LogError -Times 0
	}
}
