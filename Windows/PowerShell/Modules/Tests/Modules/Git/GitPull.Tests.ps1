#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Git\Functions"

	. "$FunctionsPath\GitPull.ps1"
}

Describe "GitPull" {
	BeforeEach {
		Mock git { }
	}

	It "runs git pull" {
		GitPull

		Should -Invoke git -Times 1 -ParameterFilter { $args[0] -eq "pull" }
	}
}
