#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\ProcessGroupRecursive.ps1"
	. "$FunctionsPath\Resolve-Selection.ps1"

	# Stub Custom-ReadHost for interactive prompts
	function Custom-ReadHost { param($Prompt, [switch]$AddNewLine) "" }
}

Describe "Resolve-Selection" {
	Context "When InputObject is provided with flat OptionList" {
		It "Should resolve valid numeric input to option names" {
			$result = Resolve-Selection -InputObject @("1") -OptionList @("Alpha", "Beta", "Gamma")
			$result | Should -Be "Alpha"
		}

		It "Should resolve valid name input (case-insensitive)" {
			$result = Resolve-Selection -InputObject @("beta") -OptionList @("Alpha", "Beta", "Gamma")
			$result | Should -Be "Beta"
		}

		It "Should resolve multiple inputs" {
			$result = Resolve-Selection -InputObject @("1", "3") -OptionList @("Alpha", "Beta", "Gamma")
			$result | Should -Contain "Alpha"
			$result | Should -Contain "Gamma"
		}

		It "Should return unique results" {
			$result = Resolve-Selection -InputObject @("1", "Alpha") -OptionList @("Alpha", "Beta")
			$result.Count | Should -Be 1
			$result | Should -Be "Alpha"
		}

		It "Should return null for empty input when no valid items" {
			$result = Resolve-Selection -InputObject @("", " ")
			$result | Should -BeNullOrEmpty
		}
	}

	Context "When InputObject contains invalid selections" {
		It "Should warn about invalid selections and return valid ones" {
			Mock Write-Host { }

			$result = Resolve-Selection -InputObject @("1", "99") -OptionList @("Alpha", "Beta")

			$result | Should -Contain "Alpha"
		}
	}

	Context "When using hierarchical GroupsConfig" {
		BeforeAll {
			$testGroupsConfig = @(
				@{
					"Tools" = @(
						@{ Name = "Swagger"; Url = "http://localhost/swagger" },
						@{ Name = "Health"; Url = "http://localhost/health" }
					)
				}
			)
		}

		It "Should resolve numeric index path in hierarchical mode" {
			$result = Resolve-Selection -InputObject @("1.1") -GroupsConfig $testGroupsConfig

			$result | Should -Not -BeNullOrEmpty
			$result.PathNames | Should -Contain "Swagger"
		}

		It "Should resolve by group name in hierarchical mode" {
			$result = Resolve-Selection -InputObject @("Swagger") -GroupsConfig $testGroupsConfig

			$result | Should -Not -BeNullOrEmpty
		}

		It "Should expand parent selection to children for NameUrl groups" {
			# Selecting "Tools" (index 1) should expand to its children
			$result = Resolve-Selection -InputObject @("Tools") -GroupsConfig $testGroupsConfig

			# Tools group has NameUrl children, so selecting parent expands to children
			$result | Should -Not -BeNullOrEmpty
		}
	}

	Context "When AllowEmptyPromptResponse is set" {
		It "Should return null for empty interactive input" {
			Mock Custom-ReadHost { "" }

			$result = Resolve-Selection -AllowEmptyPromptResponse -OptionList @("A", "B")

			$result | Should -BeNullOrEmpty
		}
	}
}
