#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules

	. "$ModuleRoot\Git\Functions\Restore-RepositoryStash.ps1"

	# Real git in a throwaway repository: what is under test is exactly which stash git applies and
	# drops, which a mock cannot prove. The identity is per process and put back afterwards.
	$script:SavedIdentity = @{}
	foreach ($name in 'GIT_AUTHOR_NAME', 'GIT_AUTHOR_EMAIL', 'GIT_COMMITTER_NAME', 'GIT_COMMITTER_EMAIL') {
		$script:SavedIdentity[$name] = [Environment]::GetEnvironmentVariable($name)
		[Environment]::SetEnvironmentVariable($name, $(if ($name -like '*EMAIL') { 'test@example.com' } else { 'Test' }))
	}
}

AfterAll {
	# Unset stays unset: [Environment]::SetEnvironmentVariable($name, $null) leaves "" behind in
	# PowerShell, and an empty GIT_AUTHOR_NAME breaks every later commit in this worker.
	foreach ($name in $script:SavedIdentity.Keys) {
		if ($null -eq $script:SavedIdentity[$name]) { Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue }
		else { [Environment]::SetEnvironmentVariable($name, $script:SavedIdentity[$name]) }
	}
}

Describe "Restore-RepositoryStash" -Tag 'Integration' {
	BeforeEach {
		$script:Repo = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
		git -c init.defaultBranch=master init --quiet $script:Repo
		Set-Content -Path (Join-Path $script:Repo "a.txt") -Value "base"
		Set-Content -Path (Join-Path $script:Repo "b.txt") -Value "base"
		git -C $script:Repo add -A
		git -C $script:Repo commit --quiet -m base
		Push-Location $script:Repo
	}

	AfterEach { Pop-Location }

	It "restores the changes, drops that stash and returns Restored" {
		Set-Content -Path a.txt -Value "mine"
		git stash push --quiet
		$stash = git rev-parse refs/stash

		Restore-RepositoryStash -StashCommit $stash -Quiet | Should -Be "Restored"
		Get-Content a.txt | Should -Be "mine"
		@(git stash list).Count | Should -Be 0
	}

	It "restores what was staged as staged" {
		Set-Content -Path a.txt -Value "staged"
		git add a.txt
		Set-Content -Path b.txt -Value "unstaged"
		git stash push --quiet
		$stash = git rev-parse refs/stash

		Restore-RepositoryStash -StashCommit $stash -Quiet | Out-Null

		git diff --cached --name-only | Should -Be "a.txt"
		Get-Content b.txt | Should -Be "unstaged"
	}

	It "restores untracked files" {
		Set-Content -Path new.txt -Value "untracked"
		git stash push --quiet --include-untracked
		$stash = git rev-parse refs/stash

		Restore-RepositoryStash -StashCommit $stash -Quiet | Should -Be "Restored"
		Get-Content new.txt | Should -Be "untracked"
	}

	It "restores its own stash even when another stash was pushed on top of it, and leaves that one alone" {
		Set-Content -Path a.txt -Value "mine"
		git stash push --quiet
		$mine = git rev-parse refs/stash
		Set-Content -Path b.txt -Value "someone else"
		git stash push --quiet -m "OTHER"

		Restore-RepositoryStash -StashCommit $mine -Quiet | Should -Be "Restored"

		Get-Content a.txt | Should -Be "mine"
		Get-Content b.txt | Should -Be "base"
		@(git stash list --format=%gs) | Should -Be @("On master: OTHER")
	}

	It "never touches an unrelated stash when its own is not in the list" {
		Set-Content -Path a.txt -Value "older work"
		git stash push --quiet -m "USER"

		Restore-RepositoryStash -StashCommit ("0" * 40) -Quiet | Should -Be "Missing"

		Get-Content a.txt | Should -Be "base"
		@(git stash list).Count | Should -Be 1
	}

	It "keeps the stash and returns Conflict when the restore conflicts" {
		Set-Content -Path a.txt -Value "mine"
		git stash push --quiet
		$stash = git rev-parse refs/stash
		Set-Content -Path a.txt -Value "theirs"
		git commit --quiet -am theirs

		Restore-RepositoryStash -StashCommit $stash -Quiet | Should -Be "Conflict"

		@(git stash list --format=%H) | Should -Contain $stash
		git show "${stash}:a.txt" | Should -Be "mine"
	}
}
