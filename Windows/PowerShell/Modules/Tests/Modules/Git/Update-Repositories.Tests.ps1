#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Git\Functions"

	. "$FunctionsPath\Update-Repositories.ps1"
}

Describe "Update-Repositories" {
	BeforeEach {
		$script:Configuration = @{ RepositoryGroups = @() }
		$script:GithubPat = ""

		Mock Test-AdminPrivileges { }
		Mock Resolve-ProjectPath { }
		Mock Resolve-Selection { }
		Mock Get-RepositoryName { "repo" }
		Mock Test-Path { $false }
		Mock Initialize-Repository { }
		Mock Push-Location { }
		Mock Pop-Location { }
		Mock Write-Host { }
	}

	It "initializes repository when custom URL target path is missing" {
		Update-Repositories -RepositoryUrl "https://github.com/user/repo" -LocalPath "C:\Repos\repo"

		Should -Invoke Test-AdminPrivileges -Times 1
		Should -Invoke Initialize-Repository -Times 1 -ParameterFilter {
			$RepositoryUrl -eq "https://github.com/user/repo" -and
			$LocalPath -eq "C:\Repos\repo"
		}
	}
}
