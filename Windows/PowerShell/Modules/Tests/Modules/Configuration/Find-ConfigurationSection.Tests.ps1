#Requires -Modules Pester

BeforeAll {
	$ConfigurationFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Configuration\Functions"
	. "$ConfigurationFunctionsPath\Find-ConfigurationSection.ps1"
}

Describe "Find-ConfigurationSection" {
	Context "Finding hashtable sections" {
		It "Should find a simple hashtable section" {
			$lines = @(
				'@{'
				'	WorkspaceActions = @{'
				'		Example = @('
				'			@{ Action = "Test" }'
				'		)'
				'	}'
				'}'
			)

			$result = Find-ConfigurationSection -Lines $lines -SectionName "WorkspaceActions"

			$result | Should -Not -BeNullOrEmpty
			$result.StartIndex | Should -Be 1
			$result.EndIndex | Should -Be 5
			$result.BracketType | Should -Be '{'
			$result.Indent | Should -Be "`t"
		}

		It "Should return null for nonexistent section" {
			$lines = @('@{', '	Key = "value"', '}')

			$result = Find-ConfigurationSection -Lines $lines -SectionName "NonExistent"

			$result | Should -BeNullOrEmpty
		}
	}

	Context "Finding array sections" {
		It "Should find an array section" {
			$lines = @(
				'@{'
				'	Workspaces = @('
				'		"Example"'
				'		"Test"'
				'	)'
				'}'
			)

			$result = Find-ConfigurationSection -Lines $lines -SectionName "Workspaces"

			$result | Should -Not -BeNullOrEmpty
			$result.StartIndex | Should -Be 1
			$result.EndIndex | Should -Be 4
			$result.BracketType | Should -Be '('
		}

		It "Should find a single-line array section" {
			$lines = @(
				'@{'
				'	SimpleList = @("A", "B")'
				'}'
			)

			$result = Find-ConfigurationSection -Lines $lines -SectionName "SimpleList"

			$result | Should -Not -BeNullOrEmpty
			$result.StartIndex | Should -Be 1
			$result.EndIndex | Should -Be 1
		}
	}

	Context "Handling brackets in strings" {
		It "Should ignore brackets inside string placeholders" {
			$lines = @(
				'@{'
				'	SymbolicLinks = @{'
				'		Git = @{'
				'			Path   = "{User}\.gitconfig"'
				'			Target = "{RepoRoot}\Git\.gitconfig"'
				'		}'
				'	}'
				'}'
			)

			$result = Find-ConfigurationSection -Lines $lines -SectionName "SymbolicLinks"

			$result | Should -Not -BeNullOrEmpty
			$result.StartIndex | Should -Be 1
			$result.EndIndex | Should -Be 6
		}

		It "Should handle nested mixed brackets" {
			$lines = @(
				'@{'
				'	BrowserGroups = @('
				'		@{ Google = @('
				'			"https://www.google.com/"'
				'		)}'
				'	)'
				'}'
			)

			$result = Find-ConfigurationSection -Lines $lines -SectionName "BrowserGroups"

			$result | Should -Not -BeNullOrEmpty
			$result.StartIndex | Should -Be 1
			$result.EndIndex | Should -Be 5
		}
	}

	Context "Handling comments" {
		It "Should ignore brackets in comments" {
			$lines = @(
				'@{'
				'	Projects = @('
				'		# @{ This is a comment }'
				'		"MyProject"'
				'	)'
				'}'
			)

			$result = Find-ConfigurationSection -Lines $lines -SectionName "Projects"

			$result | Should -Not -BeNullOrEmpty
			$result.EndIndex | Should -Be 4
		}
	}
}
