#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules

	. "$ModuleRoot\System\Functions\Get-WinGetPinnedIds.ps1"
	# Dot-sourced so it exists to Mock: the only call to winget goes through it.
	. "$ModuleRoot\System\Functions\Invoke-PackageManagerCommand.ps1"
}

Describe "Get-WinGetPinnedIds" {
	BeforeEach {
		Mock Invoke-PackageManagerCommand {
			'Name      Id                  Version     Source Pin type'
			'---------------------------------------------------------'
			'Git LFS   Git.GitLFS          3.6.1       winget Blocking'
			'Discord   Discord.Discord     1.0.9257    winget Blocking'
		}
	}

	It "reads every pin with one winget pin list call, whatever the number of apps" {
		Get-WinGetPinnedIds -AppId 'Discord.Discord', 'Git.Git', 'Other.App' | Out-Null

		Should -Invoke Invoke-PackageManagerCommand -Times 1 -Exactly -ParameterFilter {
			$PackageManager -eq 'WinGet' -and ($Arguments[0..1] -join ' ') -eq 'pin list'
		}
	}

	It "returns the given IDs that have a pin" {
		@(Get-WinGetPinnedIds -AppId 'Discord.Discord', 'Other.App') | Should -Be @('Discord.Discord')
	}

	It "matches an ID only as a whole token, never as part of a longer one" {
		# A pin on Git.GitLFS is not a pin on Git.Git: a substring match would unpin the wrong app.
		@(Get-WinGetPinnedIds -AppId 'Git.Git', 'GitLFS') | Should -BeNullOrEmpty
	}

	It "returns nothing when winget reports no pins" {
		Mock Invoke-PackageManagerCommand { 'There are no pins configured.' }

		@(Get-WinGetPinnedIds -AppId 'Discord.Discord') | Should -BeNullOrEmpty
	}

	It "calls nothing for an empty list" {
		@(Get-WinGetPinnedIds -AppId @()) | Should -BeNullOrEmpty

		Should -Invoke Invoke-PackageManagerCommand -Times 0
	}

	It "lets a stalled listing throw, so it never reads as no pins" {
		Mock Invoke-PackageManagerCommand { throw 'stalled' }

		{ Get-WinGetPinnedIds -AppId 'Discord.Discord' } | Should -Throw
	}
}
