#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Git\Functions"

	. "$FunctionsPath\GitStatus.ps1"
}

Describe "GitStatus" {
	BeforeEach {
		Mock git { }
	}

	It "runs git status with verbose and untracked flags" {
		GitStatus

		Should -Invoke git -Times 1 -ParameterFilter {
			$args[0] -eq "status" -and
			$args[1] -eq "-v" -and
			$args[2] -eq "-v" -and
			$args[3] -eq "-u"
		}
	}
}
