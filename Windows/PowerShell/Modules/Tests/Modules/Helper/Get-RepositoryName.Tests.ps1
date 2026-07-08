#Requires -Modules Pester

BeforeAll {
	$HelperFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Helper\Functions"
	. "$HelperFunctionsPath\Get-RepositoryName.ps1"
}

Describe "Get-RepositoryName" {
	Context "HTTPS URLs" {
		It "Should extract repository name from standard GitHub HTTPS URL" {
			$result = Get-RepositoryName -RepositoryUrl "https://github.com/user/MyRepo.git"

			$result | Should -Be "MyRepo"
		}

		It "Should extract repository name from HTTPS URL without .git suffix" {
			$result = Get-RepositoryName -RepositoryUrl "https://github.com/user/MyRepo"

			$result | Should -Be "MyRepo"
		}

		It "Should extract repository name from Azure DevOps HTTPS URL" {
			$result = Get-RepositoryName -RepositoryUrl "https://dev.azure.com/org/project/_git/MyRepo"

			$result | Should -Be "MyRepo"
		}

		It "Should extract repository name with hyphens" {
			$result = Get-RepositoryName -RepositoryUrl "https://github.com/user/my-awesome-repo.git"

			$result | Should -Be "my-awesome-repo"
		}

		It "Should extract repository name with dots" {
			$result = Get-RepositoryName -RepositoryUrl "https://github.com/user/My.Project.Name.git"

			$result | Should -Be "My.Project.Name"
		}
	}

	Context "SSH URLs" {
		It "Should extract repository name from SSH URL" {
			$result = Get-RepositoryName -RepositoryUrl "git@github.com:user/MyRepo.git"

			$result | Should -Be "MyRepo"
		}

		It "Should extract repository name from SSH URL without .git suffix" {
			$result = Get-RepositoryName -RepositoryUrl "git@github.com:user/MyRepo"

			$result | Should -Be "MyRepo"
		}
	}

	Context "Git Protocol URLs" {
		It "Should extract repository name from git:// URL" {
			$result = Get-RepositoryName -RepositoryUrl "git://github.com/user/MyRepo.git"

			$result | Should -Be "MyRepo"
		}
	}

	Context "Edge Cases" {
		It "Should return empty string for null input" {
			$result = Get-RepositoryName -RepositoryUrl $null

			$result | Should -Be ""
		}

		It "Should return empty string for empty string input" {
			$result = Get-RepositoryName -RepositoryUrl ""

			$result | Should -Be ""
		}

		It "Should return empty string for whitespace-only input" {
			$result = Get-RepositoryName -RepositoryUrl "   "

			$result | Should -Be ""
		}

		It "Should return empty string for invalid URL format" {
			$result = Get-RepositoryName -RepositoryUrl "not-a-valid-url"

			$result | Should -Be ""
		}
	}
}
