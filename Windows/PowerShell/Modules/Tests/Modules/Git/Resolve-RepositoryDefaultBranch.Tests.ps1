#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules

	. "$ModuleRoot\Git\Functions\Resolve-RepositoryDefaultBranch.ps1"
}

Describe "Resolve-RepositoryDefaultBranch" {
	BeforeEach {
		$global:Configuration = @{ RepositoryUpdate = @{ DefaultBranch = "" } }
		$script:RemoteHead = "origin/trunk"
		$script:RemoteHeadExit = 0

		Mock git {
			$global:LASTEXITCODE = $script:RemoteHeadExit
			if ($script:RemoteHeadExit -eq 0) { $script:RemoteHead }
		}
	}

	Context "configured name" {
		It "returns the configured name without asking git" {
			$global:Configuration.RepositoryUpdate.DefaultBranch = "main"

			Resolve-RepositoryDefaultBranch -LocalPath "C:\Repos\MyRepo" | Should -Be "main"
			Should -Invoke git -Times 0 -Exactly
		}

		It "trims whitespace around the configured name" {
			$global:Configuration.RepositoryUpdate.DefaultBranch = "  master  "

			Resolve-RepositoryDefaultBranch -LocalPath "C:\Repos\MyRepo" | Should -Be "master"
		}
	}

	Context "remote's HEAD" {
		It "falls back to origin/HEAD when the configured name is empty, without the origin/ prefix" {
			Resolve-RepositoryDefaultBranch -LocalPath "C:\Repos\MyRepo" | Should -Be "trunk"
		}

		It "reads origin/HEAD of the given repository" {
			Resolve-RepositoryDefaultBranch -LocalPath "C:\Repos\MyRepo" | Out-Null

			Should -Invoke git -Times 1 -Exactly -ParameterFilter {
				$args[0] -eq "-C" -and $args[1] -eq "C:\Repos\MyRepo" -and
				$args -contains "symbolic-ref" -and $args -contains "refs/remotes/origin/HEAD"
			}
		}

		It "falls back to origin/HEAD when the RepositoryUpdate section is absent" {
			$global:Configuration = @{}

			Resolve-RepositoryDefaultBranch -LocalPath "C:\Repos\MyRepo" | Should -Be "trunk"
		}

		It "keeps a slash inside the branch name" {
			$script:RemoteHead = "origin/release/main"

			Resolve-RepositoryDefaultBranch -LocalPath "C:\Repos\MyRepo" | Should -Be "release/main"
		}
	}

	Context "nothing to go on" {
		It "returns null when the remote reports no HEAD" {
			$script:RemoteHeadExit = 1

			Resolve-RepositoryDefaultBranch -LocalPath "C:\Repos\MyRepo" | Should -BeNullOrEmpty
		}

		It "returns null when git answers with nothing" {
			$script:RemoteHead = ""

			Resolve-RepositoryDefaultBranch -LocalPath "C:\Repos\MyRepo" | Should -BeNullOrEmpty
		}
	}
}
