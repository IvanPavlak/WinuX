#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Git\Functions"
	$HelperFunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$HelperFunctionsPath\Initialize-Directory.ps1"
	. "$HelperFunctionsPath\Get-RepositoryName.ps1"
	. "$FunctionsPath\Initialize-Repository.ps1"
}

Describe "Initialize-Repository" {
	BeforeAll {
		$TestRepoPath = Join-Path $TestDrive "repos\TestRepo"
	}

	BeforeEach {
		Mock git { }
		Mock Write-Host { }
		Mock takeown { } -ErrorAction SilentlyContinue
	}

	Context "When repository doesn't exist yet" {
		It "Should clone the repository to the specified path" {
			Initialize-Repository -RepositoryUrl "https://github.com/user/TestRepo.git" -LocalPath $TestRepoPath

			Should -Invoke git -ParameterFilter { $args[0] -eq "clone" -and $args[1] -eq "https://github.com/user/TestRepo.git" -and $args[2] -eq $TestRepoPath }
		}

		It "Should create the parent directory if needed" {
			$parentPath = Split-Path -Path $TestRepoPath -Parent

			Initialize-Repository -RepositoryUrl "https://github.com/user/TestRepo.git" -LocalPath $TestRepoPath

			Test-Path $parentPath | Should -BeTrue
		}

		It "Should use authenticated URL when token is provided" {
			Initialize-Repository -RepositoryUrl "https://github.com/user/TestRepo.git" -LocalPath $TestRepoPath -Token "ghp_abc123"

			Should -Invoke git -ParameterFilter { $args[0] -eq "clone" -and $args[1] -eq "https://ghp_abc123@github.com/user/TestRepo.git" }
		}

		It "Should sanitize existing credentials from URL before inserting token" {
			Initialize-Repository -RepositoryUrl "https://oldtoken@github.com/user/TestRepo.git" -LocalPath $TestRepoPath -Token "newtoken"

			Should -Invoke git -ParameterFilter { $args[0] -eq "clone" -and $args[1] -eq "https://newtoken@github.com/user/TestRepo.git" }
		}

		It "Should reset the origin remote to the credential-free URL after an authenticated clone" {
			# The scrub only runs when the clone actually produced a repository, so this mock
			# materializes the .git folder the way a real clone would.
			Mock git { if ($args[0] -eq "clone") { New-Item -ItemType Directory -Path (Join-Path "$($args[-1])" ".git") -Force | Out-Null } }
			$scrubPath = Join-Path $TestDrive "repos\ScrubRepo"

			Initialize-Repository -RepositoryUrl "https://github.com/user/ScrubRepo.git" -LocalPath $scrubPath -Token "ghp_abc123"

			Should -Invoke git -Times 1 -Exactly -ParameterFilter { $args[0] -eq "-C" -and $args[2] -eq "remote" -and $args[3] -eq "set-url" -and $args[4] -eq "origin" -and $args[5] -eq "https://github.com/user/ScrubRepo.git" }
		}

		It "Should not touch the remote when no token was used" {
			Mock git { if ($args[0] -eq "clone") { New-Item -ItemType Directory -Path (Join-Path "$($args[-1])" ".git") -Force | Out-Null } }
			$plainPath = Join-Path $TestDrive "repos\PlainRepo"

			Initialize-Repository -RepositoryUrl "https://github.com/user/PlainRepo.git" -LocalPath $plainPath

			Should -Invoke git -Times 0 -ParameterFilter { $args -contains "set-url" }
		}

		It "Should use shallow clone for Obsidian repositories" {
			$obsidianPath = Join-Path $TestDrive "repos\Obsidian"

			Initialize-Repository -RepositoryUrl "https://github.com/user/Obsidian.git" -LocalPath $obsidianPath

			Should -Invoke git -ParameterFilter { $args[0] -eq "clone" -and $args[1] -eq "--depth" -and $args[2] -eq "1" }
		}
	}

	Context "When repository already exists" {
		It "Should pull latest changes instead of cloning" {
			New-Item -ItemType Directory -Path $TestRepoPath -Force | Out-Null

			Initialize-Repository -RepositoryUrl "https://github.com/user/TestRepo.git" -LocalPath $TestRepoPath

			Should -Invoke git -ParameterFilter { $args[0] -eq "pull" }
			Should -Invoke git -Times 0 -ParameterFilter { $args[0] -eq "clone" }
		}
	}
}
