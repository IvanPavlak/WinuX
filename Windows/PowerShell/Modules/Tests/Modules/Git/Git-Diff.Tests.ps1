#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Git\Functions"

	. "$FunctionsPath\Git-Diff.ps1"
}

Describe "Git-Diff" {
	BeforeEach {
		Mock git { }
	}

	It "runs git diff against HEAD" {
		Git-Diff

		Should -Invoke git -Times 1 -ParameterFilter { $args[0] -eq "diff" -and $args[1] -eq "HEAD" }
	}
}
