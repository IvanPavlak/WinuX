#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Resolve-WorkspaceTemplate.ps1"
}

Describe "Resolve-WorkspaceTemplate" {
	BeforeEach {
		# The shape the feature exists for: one project-shaped template stamped out per workspace.
		$script:Templates = @{
			Project = @{
				Variables = @{ Repository = '{Workspace}Repository'; Instances = 1 }
				Actions   = @(
					@{ Action = 'Open-Project'; Parameters = @{ Project = '{Workspace}' } }
					@{ Id = 'Browser'; Action = 'Open-Browser'; Parameters = @{ Groups = @('{Repository}', 'AI'); Instances = '{Instances}' } }
					@{ Action = 'Set-WorkspaceWindowLayout'; Parameters = @{ WorkspaceName = '{Workspace}' } }
				)
			}
		}
	}

	Context "Plain entries" {
		It "returns a list without {Workspace} unchanged, the very same action objects, Changed = false" {
			$plain = @(
				@{ Action = 'Open-Browser'; Parameters = @{ Groups = @('AI') } }
				@{ Action = 'Open-Rider' }
			)

			$result = Resolve-WorkspaceTemplate -Name 'MyRepo' -Definition $plain -Templates $script:Templates

			$result.IsTemplated | Should -BeFalse
			$result.Changed | Should -BeFalse
			$result.Template | Should -Be ''
			@($result.Errors).Count | Should -Be 0
			@($result.Actions).Count | Should -Be 2
			[object]::ReferenceEquals($result.Actions[0], $plain[0]) | Should -BeTrue
			[object]::ReferenceEquals($result.Actions[1], $plain[1]) | Should -BeTrue
		}

		It "substitutes {Workspace} and leaves every other brace token alone, without an error" {
			$plain = @(
				@{ Action = 'Open-Project'; Parameters = @{ Project = '{Workspace}'; Projects = '{SelectedProjects}'; Other = 'x {X} y'; Path = '{Dev}\{Workspace}' } }
			)

			$result = Resolve-WorkspaceTemplate -Name 'MyRepo' -Definition $plain -Templates $script:Templates

			$result.IsTemplated | Should -BeFalse
			$result.Changed | Should -BeTrue
			@($result.Errors).Count | Should -Be 0
			$result.Actions[0].Parameters.Project | Should -Be 'MyRepo'
			$result.Actions[0].Parameters.Projects | Should -Be '{SelectedProjects}'
			$result.Actions[0].Parameters.Other | Should -Be 'x {X} y'
			$result.Actions[0].Parameters.Path | Should -Be '{Dev}\MyRepo'
			# The configured list is never written to.
			$plain[0].Parameters.Project | Should -Be '{Workspace}'
		}

		It "resolves a null definition to no actions without an error" {
			$result = Resolve-WorkspaceTemplate -Name 'MyRepo' -Definition $null -Templates $script:Templates

			@($result.Actions).Count | Should -Be 0
			@($result.Errors).Count | Should -Be 0
			$result.IsTemplated | Should -BeFalse
		}
	}

	Context "Templated expansion and variables" {
		It "stamps out the template under the entry's name, defaults referencing {Workspace}" {
			$result = Resolve-WorkspaceTemplate -Name 'MyProject' -Definition @{ Template = 'Project' } -Templates $script:Templates

			$result.IsTemplated | Should -BeTrue
			$result.Template | Should -Be 'Project'
			@($result.Errors).Count | Should -Be 0
			@($result.Actions | ForEach-Object { $_.Action }) | Should -Be @('Open-Project', 'Open-Browser', 'Set-WorkspaceWindowLayout')
			$result.Actions[0].Parameters.Project | Should -Be 'MyProject'
			$result.Actions[1].Parameters.Groups | Should -Be @('MyProjectRepository', 'AI')
			$result.Actions[2].Parameters.WorkspaceName | Should -Be 'MyProject'
			@($result.VariableNames) | Should -Be @('Instances', 'Repository')
		}

		It "finds the template case-insensitively" {
			$result = Resolve-WorkspaceTemplate -Name 'MyProject' -Definition @{ Template = 'project' } -Templates $script:Templates

			@($result.Errors).Count | Should -Be 0
			@($result.Actions).Count | Should -Be 3
		}

		It "hands a whole-value {Name} over as it is - a list stays a list, a number stays a number" {
			$templates = @{
				Lists = @{
					Variables = @{ Groups = @('A', 'B'); Count = 2; Single = @('Only') }
					Actions   = @(@{ Action = 'Open-Browser'; Parameters = @{ Groups = '{Groups}'; Instances = '{Count}'; One = '{Single}' } })
				}
			}

			$result = Resolve-WorkspaceTemplate -Name 'W' -Definition @{ Template = 'Lists' } -Templates $templates

			@($result.Errors).Count | Should -Be 0
			$parameters = $result.Actions[0].Parameters
			, $parameters.Groups | Should -BeOfType [object[]]
			$parameters.Groups | Should -Be @('A', 'B')
			$parameters.Instances | Should -Be 2
			$parameters.Instances | Should -BeOfType [int]
			, $parameters.One | Should -BeOfType [object[]]
			@($parameters.One).Count | Should -Be 1
		}

		It "substitutes the text of a scalar variable embedded in a longer string" {
			$templates = @{
				Text = @{
					Variables = @{ Repository = 'MyRepo'; Count = 3 }
					Actions   = @(@{ Action = 'Open-Terminal'; Parameters = @{ Title = 'Repo {Repository} x{Count} ({Workspace})' } })
				}
			}

			$result = Resolve-WorkspaceTemplate -Name 'W' -Definition @{ Template = 'Text' } -Templates $templates

			$result.Actions[0].Parameters.Title | Should -Be 'Repo MyRepo x3 (W)'
		}

		It "reports a list variable embedded in text and resolves to no actions" {
			$templates = @{
				Text = @{
					Variables = @{ Groups = @('A', 'B') }
					Actions   = @(@{ Action = 'Open-Terminal'; Parameters = @{ Title = 'Groups {Groups}' } })
				}
			}

			$result = Resolve-WorkspaceTemplate -Name 'W' -Definition @{ Template = 'Text' } -Templates $templates

			@($result.Errors).Count | Should -BeGreaterThan 0
			@($result.Actions).Count | Should -Be 0
		}

		It "lets the entry's Variables override the template defaults" {
			$result = Resolve-WorkspaceTemplate -Name 'MyProject' -Definition @{ Template = 'Project'; Variables = @{ Repository = 'OtherGroup' } } -Templates $script:Templates

			$result.Actions[1].Parameters.Groups | Should -Be @('OtherGroup', 'AI')
		}

		It "lets -Variables override declared names only and lists the ones it applied" {
			$result = Resolve-WorkspaceTemplate -Name 'MyProject' -Definition @{ Template = 'Project'; Variables = @{ Repository = 'FromEntry' } } -Templates $script:Templates -Variables @{ Repository = 'FromCommandLine'; Instances = 2; Undeclared = 'ignored' }

			@($result.Errors).Count | Should -Be 0
			$result.Actions[1].Parameters.Groups | Should -Be @('FromCommandLine', 'AI')
			$result.Actions[1].Parameters.Instances | Should -Be 2
			@($result.AppliedVariables | Sort-Object) | Should -Be @('Instances', 'Repository')
			@($result.Actions | ForEach-Object { $_.Parameters.Keys }) | Should -Not -Contain 'Undeclared'
		}

		It "leaves AppliedVariables empty when -Variables sets nothing the template declares" {
			$result = Resolve-WorkspaceTemplate -Name 'MyProject' -Definition @{ Template = 'Project' } -Templates $script:Templates -Variables @{ Undeclared = 'x' }

			@($result.AppliedVariables).Count | Should -Be 0
			$result.Actions[1].Parameters.Groups | Should -Be @('MyProjectRepository', 'AI')
		}

		It "leaves engine tokens untouched for the code that resolves them later" {
			$templates = @{
				Engine = @{
					Actions = @(@{ Action = 'Open-Project'; Parameters = @{ Project = '{SelectedProjects}'; Title = '{ProjectName}-tab'; Path = '{Dev}\{Workspace}'; Machine = '{MachineType}' } })
				}
			}

			$result = Resolve-WorkspaceTemplate -Name 'W' -Definition @{ Template = 'Engine' } -Templates $templates

			@($result.Errors).Count | Should -Be 0
			$parameters = $result.Actions[0].Parameters
			$parameters.Project | Should -Be '{SelectedProjects}'
			$parameters.Title | Should -Be '{ProjectName}-tab'
			$parameters.Path | Should -Be '{Dev}\W'
			$parameters.Machine | Should -Be '{MachineType}'
		}

		It "never aliases the template - changing the output leaves the template as it was" {
			$result = Resolve-WorkspaceTemplate -Name 'MyProject' -Definition @{ Template = 'Project' } -Templates $script:Templates

			$result.Actions[0].Parameters.Project = 'Changed'
			$result.Actions[1].Parameters.Groups[1] = 'Changed'
			$result.Actions[2]['Extra'] = 'x'

			$script:Templates.Project.Actions[0].Parameters.Project | Should -Be '{Workspace}'
			$script:Templates.Project.Actions[1].Parameters.Groups[1] | Should -Be 'AI'
			$script:Templates.Project.Actions[2].ContainsKey('Extra') | Should -BeFalse
			$script:Templates.Project.Actions[1].ContainsKey('Id') | Should -BeTrue
		}

		It "drops the Id key from every output action" {
			$result = Resolve-WorkspaceTemplate -Name 'MyProject' -Definition @{ Template = 'Project'; Add = @(@{ Id = 'Added'; Action = 'Open-Obsidian' }) } -Templates $script:Templates

			@($result.Actions | Where-Object { $_.ContainsKey('Id') }).Count | Should -Be 0
			@($result.Actions).Count | Should -Be 4
		}
	}

	Context "Overrides" {
		It "merges an override by action name over its target" {
			$definition = @{ Template = 'Project'; Overrides = @{ 'Open-Project' = @{ Parameters = @{ Extra = 1 } } } }

			$result = Resolve-WorkspaceTemplate -Name 'MyProject' -Definition $definition -Templates $script:Templates

			@($result.Errors).Count | Should -Be 0
			$result.Actions[0].Parameters.Project | Should -Be 'MyProject'
			$result.Actions[0].Parameters.Extra | Should -Be 1
		}

		It "merges an override by Id and replaces a list instead of merging it" {
			$definition = @{ Template = 'Project'; Overrides = @{ Browser = @{ Parameters = @{ Groups = @('X') } } } }

			$result = Resolve-WorkspaceTemplate -Name 'MyProject' -Definition $definition -Templates $script:Templates

			@($result.Errors).Count | Should -Be 0
			@($result.Actions[1].Parameters.Groups) | Should -Be @('X')
			$result.Actions[1].Parameters.Instances | Should -Be 1
		}

		It "drops the action an override sets to null" {
			$definition = @{ Template = 'Project'; Overrides = @{ 'Open-Project' = $null } }

			$result = Resolve-WorkspaceTemplate -Name 'MyProject' -Definition $definition -Templates $script:Templates

			@($result.Errors).Count | Should -Be 0
			@($result.Actions | ForEach-Object { $_.Action }) | Should -Be @('Open-Browser', 'Set-WorkspaceWindowLayout')
		}

		It "removes a parameter an override sets to null" {
			$definition = @{ Template = 'Project'; Overrides = @{ Browser = @{ Parameters = @{ Groups = $null } } } }

			$result = Resolve-WorkspaceTemplate -Name 'MyProject' -Definition $definition -Templates $script:Templates

			$result.Actions[1].Parameters.ContainsKey('Groups') | Should -BeFalse
			$result.Actions[1].Parameters.ContainsKey('Instances') | Should -BeTrue
		}

		It "replaces a top-level key and removes one an override sets to null" {
			$templates = @{
				Scoped = @{ Actions = @(@{ Action = 'Open-Outlook'; Machine = 'Work'; LayoutMachine = 'Work' }) }
			}
			$definition = @{ Template = 'Scoped'; Overrides = @{ 'Open-Outlook' = @{ Machine = 'PC/Work'; LayoutMachine = $null } } }

			$result = Resolve-WorkspaceTemplate -Name 'W' -Definition $definition -Templates $templates

			$result.Actions[0].Machine | Should -Be 'PC/Work'
			$result.Actions[0].ContainsKey('LayoutMachine') | Should -BeFalse
		}

		It "merges a nested hashtable parameter key by key" {
			$templates = @{
				Nested = @{ Actions = @(@{ Action = 'A'; Parameters = @{ Options = @{ A = 1; B = 2 } } }) }
			}
			$definition = @{ Template = 'Nested'; Overrides = @{ A = @{ Parameters = @{ Options = @{ B = 3; C = 4 } } } } }

			$result = Resolve-WorkspaceTemplate -Name 'W' -Definition $definition -Templates $templates

			$options = $result.Actions[0].Parameters.Options
			$options.A | Should -Be 1
			$options.B | Should -Be 3
			$options.C | Should -Be 4
			$templates.Nested.Actions[0].Parameters.Options.B | Should -Be 2
		}

		It "merges a table override row by row and keeps a null inside a row as data" {
			$templates = @{
				Table = @{ Actions = @(@{ Action = 'Open-Browser'; Parameters = @{ Instances = 1 }; MachineParameters = @{ PC = @{ Width = 100; Height = 200 } } }) }
			}
			$definition = @{
				Template  = 'Table'
				Overrides = @{
					'Open-Browser' = @{
						MachineParameters = @{ PC = @{ Width = $null; Height = 300 }; Laptop = @{ Width = 50 } }
						ProjectParameters = @{ MyProject = @{ Instances = 2 } }
					}
				}
			}

			$result = Resolve-WorkspaceTemplate -Name 'W' -Definition $definition -Templates $templates

			@($result.Errors).Count | Should -Be 0
			$table = $result.Actions[0].MachineParameters
			$table.PC.ContainsKey('Width') | Should -BeTrue
			$table.PC.Width | Should -BeNullOrEmpty
			$table.PC.Height | Should -Be 300
			$table.Laptop.Width | Should -Be 50
			$result.Actions[0].ProjectParameters.MyProject.Instances | Should -Be 2
		}

		It "removes a whole table row an override sets to null" {
			$templates = @{
				Table = @{ Actions = @(@{ Action = 'Open-Browser'; MachineParameters = @{ PC = @{ Width = 100 }; Laptop = @{ Width = 50 } } }) }
			}
			$definition = @{ Template = 'Table'; Overrides = @{ 'Open-Browser' = @{ MachineParameters = @{ PC = $null } } } }

			$result = Resolve-WorkspaceTemplate -Name 'W' -Definition $definition -Templates $templates

			$result.Actions[0].MachineParameters.ContainsKey('PC') | Should -BeFalse
			$result.Actions[0].MachineParameters.Laptop.Width | Should -Be 50
		}

		It "reports an override that tries to change <Key>" -TestCases @(
			@{ Key = 'Action' }
			@{ Key = 'Id' }
		) {
			$definition = @{ Template = 'Project'; Overrides = @{ Browser = @{ $Key = 'Other' } } }

			$result = Resolve-WorkspaceTemplate -Name 'MyProject' -Definition $definition -Templates $script:Templates

			@($result.Errors).Count | Should -BeGreaterThan 0
			@($result.Actions).Count | Should -Be 0
		}

		It "reports an unknown override key" {
			$definition = @{ Template = 'Project'; Overrides = @{ Browser = @{ Paramters = @{ Groups = @('X') } } } }

			$result = Resolve-WorkspaceTemplate -Name 'MyProject' -Definition $definition -Templates $script:Templates

			@($result.Errors).Count | Should -Be 1
			@($result.Actions).Count | Should -Be 0
		}

		It "reports an override that matches no action" {
			$definition = @{ Template = 'Project'; Overrides = @{ 'Open-Nothing' = @{ Parameters = @{ X = 1 } } } }

			$result = Resolve-WorkspaceTemplate -Name 'MyProject' -Definition $definition -Templates $script:Templates

			@($result.Errors).Count | Should -Be 1
			@($result.Actions).Count | Should -Be 0
		}

		It "reports an action name that matches several template actions, and an Id disambiguates" {
			$templates = @{
				Dual = @{
					Actions = @(
						@{ Id = 'First'; Action = 'Open-Browser'; Parameters = @{ Groups = @('A') } }
						@{ Id = 'Second'; Action = 'Open-Browser'; Parameters = @{ Groups = @('B') } }
					)
				}
			}

			$ambiguous = Resolve-WorkspaceTemplate -Name 'W' -Definition @{ Template = 'Dual'; Overrides = @{ 'Open-Browser' = @{ Parameters = @{ Instances = 2 } } } } -Templates $templates
			$byId = Resolve-WorkspaceTemplate -Name 'W' -Definition @{ Template = 'Dual'; Overrides = @{ Second = @{ Parameters = @{ Instances = 2 } } } } -Templates $templates

			@($ambiguous.Errors).Count | Should -Be 1
			@($ambiguous.Actions).Count | Should -Be 0
			@($byId.Errors).Count | Should -Be 0
			$byId.Actions[0].Parameters.ContainsKey('Instances') | Should -BeFalse
			$byId.Actions[1].Parameters.Instances | Should -Be 2
		}

		It "substitutes variables inside override values" {
			$definition = @{ Template = 'Project'; Overrides = @{ 'Open-Project' = @{ Parameters = @{ Title = '{Repository}' } } } }

			$result = Resolve-WorkspaceTemplate -Name 'MyProject' -Definition $definition -Templates $script:Templates

			$result.Actions[0].Parameters.Title | Should -Be 'MyProjectRepository'
		}
	}

	Context "Add" {
		It "inserts an addition just before the template's first Set-WorkspaceWindowLayout by default" {
			$definition = @{ Template = 'Project'; Add = @(@{ Action = 'Open-Obsidian'; Parameters = @{ Vault = '{Workspace}' } }) }

			$result = Resolve-WorkspaceTemplate -Name 'MyProject' -Definition $definition -Templates $script:Templates

			@($result.Errors).Count | Should -Be 0
			@($result.Actions | ForEach-Object { $_.Action }) | Should -Be @('Open-Project', 'Open-Browser', 'Open-Obsidian', 'Set-WorkspaceWindowLayout')
			$result.Actions[2].Parameters.Vault | Should -Be 'MyProject'
		}

		It "keeps several additions in their configured order" {
			$definition = @{ Template = 'Project'; Add = @(@{ Action = 'First' }, @{ Action = 'Second' }) }

			$result = Resolve-WorkspaceTemplate -Name 'MyProject' -Definition $definition -Templates $script:Templates

			@($result.Actions | ForEach-Object { $_.Action }) | Should -Be @('Open-Project', 'Open-Browser', 'First', 'Second', 'Set-WorkspaceWindowLayout')
		}

		It "appends at the end when the template has no Set-WorkspaceWindowLayout" {
			$templates = @{ NoLayout = @{ Actions = @(@{ Action = 'A' }, @{ Action = 'B' }) } }

			$result = Resolve-WorkspaceTemplate -Name 'W' -Definition @{ Template = 'NoLayout'; Add = @(@{ Action = 'C' }) } -Templates $templates

			@($result.Actions | ForEach-Object { $_.Action }) | Should -Be @('A', 'B', 'C')
		}

		It "accepts a single hashtable as the Add value" {
			$result = Resolve-WorkspaceTemplate -Name 'MyProject' -Definition @{ Template = 'Project'; Add = @{ Action = 'Open-Obsidian' } } -Templates $script:Templates

			@($result.Errors).Count | Should -Be 0
			$result.Actions[2].Action | Should -Be 'Open-Obsidian'
		}

		It "places an addition Before an action name and After an Id, and strips the anchor keys" {
			$definition = @{
				Template = 'Project'
				Add      = @(
					@{ Action = 'Start'; Before = 'Open-Project' }
					@{ Action = 'AfterBrowser'; After = 'Browser' }
				)
			}

			$result = Resolve-WorkspaceTemplate -Name 'MyProject' -Definition $definition -Templates $script:Templates

			@($result.Errors).Count | Should -Be 0
			@($result.Actions | ForEach-Object { $_.Action }) | Should -Be @('Start', 'Open-Project', 'Open-Browser', 'AfterBrowser', 'Set-WorkspaceWindowLayout')
			@($result.Actions | Where-Object { $_.ContainsKey('Before') -or $_.ContainsKey('After') }).Count | Should -Be 0
		}

		It "reports an addition that sets both Before and After" {
			$definition = @{ Template = 'Project'; Add = @(@{ Action = 'X'; Before = 'Open-Project'; After = 'Browser' }) }

			$result = Resolve-WorkspaceTemplate -Name 'MyProject' -Definition $definition -Templates $script:Templates

			@($result.Errors).Count | Should -Be 1
			@($result.Actions).Count | Should -Be 0
		}

		It "reports an anchor that matches no action" {
			$definition = @{ Template = 'Project'; Add = @(@{ Action = 'X'; After = 'Open-Nothing' }) }

			$result = Resolve-WorkspaceTemplate -Name 'MyProject' -Definition $definition -Templates $script:Templates

			@($result.Errors).Count | Should -Be 1
			@($result.Actions).Count | Should -Be 0
		}

		It "reports an addition without Action" {
			$result = Resolve-WorkspaceTemplate -Name 'MyProject' -Definition @{ Template = 'Project'; Add = @(@{ Parameters = @{ X = 1 } }) } -Templates $script:Templates

			@($result.Errors).Count | Should -Be 1
			@($result.Actions).Count | Should -Be 0
		}
	}

	Context "Errors" {
		It "reports an unknown template, naming the workspace" {
			$result = Resolve-WorkspaceTemplate -Name 'MyProject' -Definition @{ Template = 'Missing' } -Templates $script:Templates

			$result.IsTemplated | Should -BeTrue
			@($result.Errors).Count | Should -Be 1
			$result.Errors[0] | Should -BeLike 'WorkspaceActions.MyProject*'
			@($result.Actions).Count | Should -Be 0
		}

		It "reports an unknown template when no templates are configured" {
			$result = Resolve-WorkspaceTemplate -Name 'MyProject' -Definition @{ Template = 'Project' } -Templates $null

			@($result.Errors).Count | Should -Be 1
			@($result.Actions).Count | Should -Be 0
		}

		It "reports a hashtable entry without a Template key" {
			$result = Resolve-WorkspaceTemplate -Name 'MyProject' -Definition @{ Variables = @{ Repository = 'X' } } -Templates $script:Templates

			$result.IsTemplated | Should -BeTrue
			@($result.Errors).Count | Should -Be 1
			@($result.Actions).Count | Should -Be 0
		}

		It "reports an unknown entry key" {
			$result = Resolve-WorkspaceTemplate -Name 'MyProject' -Definition @{ Template = 'Project'; Overides = @{} } -Templates $script:Templates

			@($result.Errors).Count | Should -Be 1
			@($result.Actions).Count | Should -Be 0
		}

		It "reports a template with an unknown key" {
			$templates = @{ Child = @{ Extends = 'Project'; Actions = @(@{ Action = 'A' }) } }

			$result = Resolve-WorkspaceTemplate -Name 'W' -Definition @{ Template = 'Child' } -Templates $templates

			@($result.Errors).Count | Should -Be 1
			@($result.Actions).Count | Should -Be 0
		}

		It "reports a template without Actions" {
			$templates = @{ Empty = @{ Variables = @{ X = 1 } } }

			$result = Resolve-WorkspaceTemplate -Name 'W' -Definition @{ Template = 'Empty' } -Templates $templates

			@($result.Errors).Count | Should -Be 1
			@($result.Actions).Count | Should -Be 0
		}

		It "reports a reserved variable name declared by the <Where>" -TestCases @(
			@{ Where = 'template'; TemplateVariables = @{ Workspace = 'x' }; EntryVariables = $null }
			@{ Where = 'entry'; TemplateVariables = @{}; EntryVariables = @{ Dev = 'x' } }
		) {
			$templates = @{ T = @{ Variables = $TemplateVariables; Actions = @(@{ Action = 'A' }) } }
			$definition = @{ Template = 'T' }
			if ($null -ne $EntryVariables) { $definition.Variables = $EntryVariables }

			$result = Resolve-WorkspaceTemplate -Name 'W' -Definition $definition -Templates $templates

			@($result.Errors).Count | Should -Be 1
			@($result.Actions).Count | Should -Be 0
		}

		It "reports a variable cycle" {
			$templates = @{
				Cycle = @{
					Variables = @{ A = '{B}x'; B = '{A}y' }
					Actions   = @(@{ Action = 'Open-Terminal'; Parameters = @{ Title = '{A}' } })
				}
			}

			$result = Resolve-WorkspaceTemplate -Name 'W' -Definition @{ Template = 'Cycle' } -Templates $templates

			@($result.Errors).Count | Should -BeGreaterThan 0
			@($result.Errors | Where-Object { $_ -like '*cycle*' }).Count | Should -BeGreaterThan 0
			@($result.Actions).Count | Should -Be 0
		}

		It "reports a variable declared null that an action uses, and accepts it once the command line sets it" {
			$templates = @{
				Required = @{
					Variables = @{ Token = $null; Unused = $null }
					Actions   = @(@{ Action = 'Open-Terminal'; Parameters = @{ Title = '{Token}' } })
				}
			}

			$missing = Resolve-WorkspaceTemplate -Name 'W' -Definition @{ Template = 'Required' } -Templates $templates
			$set = Resolve-WorkspaceTemplate -Name 'W' -Definition @{ Template = 'Required' } -Templates $templates -Variables @{ Token = 'value' }

			@($missing.Errors).Count | Should -Be 1
			@($missing.Actions).Count | Should -Be 0
			@($set.Errors).Count | Should -Be 0
			$set.Actions[0].Parameters.Title | Should -Be 'value'
		}

		It "reports an unknown {Placeholder} in a templated entry, whole value or embedded" {
			$templates = @{
				Typo = @{
					Variables = @{ Repository = 'X' }
					Actions   = @(@{ Action = 'Open-Browser'; Parameters = @{ Groups = '{Repositroy}'; Title = 'a {Repositroy} b' } })
				}
			}

			$result = Resolve-WorkspaceTemplate -Name 'W' -Definition @{ Template = 'Typo' } -Templates $templates

			@($result.Errors).Count | Should -BeGreaterThan 0
			@($result.Actions).Count | Should -Be 0
		}
	}
}
