#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Git\Functions"

	. "$FunctionsPath\GitMergeM.ps1"
}

Describe "GitMergeM" {
	BeforeEach {
		Mock git { }
		Mock BranchExists { $false }
		Mock Write-Host { }
		Mock Write-LogError { }
	}

	It "merges master when master exists" {
		Mock BranchExists {
			param([string]$BranchName)
			$BranchName -eq "master"
		}

		GitMergeM

		Should -Invoke git -Times 1 -ParameterFilter { $args[0] -eq "merge" -and $args[1] -eq "master" }
	}

	It "merges main when master does not exist and main exists" {
		Mock BranchExists {
			param([string]$BranchName)
			$BranchName -eq "main"
		}

		GitMergeM

		Should -Invoke git -Times 1 -ParameterFilter { $args[0] -eq "merge" -and $args[1] -eq "main" }
	}

	It "reports when neither master nor main exists" {
		GitMergeM

		Should -Invoke Write-LogError -Times 1
		Should -Invoke git -Times 0 -ParameterFilter { $args[0] -eq "merge" }
	}
}
