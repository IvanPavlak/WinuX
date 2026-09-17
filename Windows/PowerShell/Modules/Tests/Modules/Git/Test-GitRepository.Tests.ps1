#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules

	. "$ModuleRoot\Git\Functions\Test-GitRepository.ps1"
}

Describe "Test-GitRepository" {
	BeforeEach {
		# A real directory tree on TestDrive rather than a mocked Test-Path: the whole function is
		# the walk, so mocking the only thing it calls would test nothing.
		$script:Repo = Join-Path $TestDrive "repo"
		$script:Nested = Join-Path $script:Repo "src\deep\deeper"
		$script:Outside = Join-Path $TestDrive "not-a-repo\sub"
		New-Item -ItemType Directory -Path $script:Nested -Force | Out-Null
		New-Item -ItemType Directory -Path $script:Outside -Force | Out-Null
	}

	Context "a .git directory - an ordinary clone" {
		BeforeEach { New-Item -ItemType Directory -Path (Join-Path $script:Repo ".git") -Force | Out-Null }

		It "finds it at the repository root" {
			Test-GitRepository -Path $script:Repo | Should -BeTrue
		}

		It "finds it from a directory several levels below the root" {
			Test-GitRepository -Path $script:Nested | Should -BeTrue
		}

		It "finds it from a file inside the repository, by starting at the file's directory" {
			$file = Join-Path $script:Nested "Program.cs"
			Set-Content -LiteralPath $file -Value "// nothing"

			Test-GitRepository -Path $file | Should -BeTrue
		}
	}

	Context "a .git file - a worktree or a submodule" {
		It "counts a .git FILE, not only a directory" {
			# A worktree's .git is a one-line `gitdir: ...` pointer, and a shell standing in one is
			# just as much inside a repository as one standing in a normal clone.
			Set-Content -LiteralPath (Join-Path $script:Repo ".git") -Value "gitdir: C:\somewhere\.git\worktrees\wt"

			Test-GitRepository -Path $script:Nested | Should -BeTrue
		}
	}

	Context "no .git anywhere above" {
		It "returns false for a directory with no repository above it" {
			Test-GitRepository -Path $script:Outside | Should -BeFalse
		}

		It "returns false rather than throwing for a path that does not exist" {
			# A stale $PWD must not make the greeting throw at the prompt.
			Test-GitRepository -Path (Join-Path $TestDrive "gone\missing") | Should -BeFalse
		}

		It "returns false for an empty path instead of walking from nowhere" {
			Test-GitRepository -Path "" | Should -BeFalse
		}

		It "terminates at a drive root instead of looping" {
			# The walk ends when Split-Path stops changing the path. A bug here hangs the prompt on
			# every greeting, so what this asserts is that the call returns at all.
			{ Test-GitRepository -Path ([IO.Path]::GetPathRoot($TestDrive)) } | Should -Not -Throw
		}

		It "returns false for a bare drive qualifier, which Split-Path -Parent throws on" {
			# "C:" without a separator is what Split-Path -Qualifier hands back, so a caller can
			# pass it. Split-Path -Parent throws on it rather than returning "" the way it does for
			# "C:\", and a greeting must not surface that at the prompt.
			{ Test-GitRepository -Path (Split-Path -Qualifier $TestDrive) } | Should -Not -Throw
			Test-GitRepository -Path (Split-Path -Qualifier $TestDrive) | Should -BeFalse
		}
	}

	Context "the default path" {
		It "tests the current location when -Path is not given" {
			New-Item -ItemType Directory -Path (Join-Path $script:Repo ".git") -Force | Out-Null

			Push-Location $script:Nested
			try { Test-GitRepository | Should -BeTrue }
			finally { Pop-Location }
		}
	}
}
