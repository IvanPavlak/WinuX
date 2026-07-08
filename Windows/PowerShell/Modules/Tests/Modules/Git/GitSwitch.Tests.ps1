#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Git\Functions"
	$HelperFunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$HelperFunctionsPath\BranchExists.ps1"
	. "$FunctionsPath\GitSwitch.ps1"
}

Describe "GitSwitch" {
	BeforeEach {
		Mock git { } -Verifiable
		Mock Write-Host { }
		Mock Write-LogError { }
	}

	Context "When no branch name is provided" {
		It "Should switch to 'master' when master exists" {
			Mock BranchExists { $Branch -eq "master" }

			GitSwitch

			Should -Invoke git -ParameterFilter { $args[0] -eq "switch" -and $args[1] -eq "master" }
		}

		It "Should switch to 'main' when master doesn't exist but main does" {
			Mock BranchExists { $Branch -eq "main" }

			GitSwitch

			Should -Invoke git -ParameterFilter { $args[0] -eq "switch" -and $args[1] -eq "main" }
		}

		It "Should show error when neither master nor main exists" {
			Mock BranchExists { $false }

			GitSwitch

			Should -Invoke Write-LogError -ParameterFilter { $Message -match "Neither 'master' nor 'main'" }
			Should -Invoke git -Times 0
		}
	}

	Context "When a branch name is provided" {
		It "Should switch to the specified branch when it exists" {
			Mock BranchExists { $Branch -eq "feature/my-branch" }

			GitSwitch -BranchName "feature/my-branch"

			Should -Invoke git -ParameterFilter { $args[0] -eq "switch" -and $args[1] -eq "feature/my-branch" }
		}

		It "Should show error when specified branch doesn't exist" {
			Mock BranchExists { $false }

			GitSwitch -BranchName "nonexistent"

			Should -Invoke Write-LogError -ParameterFilter { $Message -match "does not exist" }
			Should -Invoke git -Times 0
		}
	}
}
