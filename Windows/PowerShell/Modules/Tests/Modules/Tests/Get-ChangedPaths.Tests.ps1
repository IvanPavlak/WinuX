#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. (Join-Path $ModuleRoot "Tests\Get-ChangedPaths.ps1")
	. (Join-Path $ModuleRoot "Tests\Get-WorkingTreeFingerprint.ps1")

	# Real git in a throwaway repository: what is under test is exactly what git reports as changed.
	$script:Identity = @('-c', 'user.name=Test', '-c', 'user.email=test@example.com', '-c', 'core.autocrlf=false')

	function New-TestRepository {
		$repo = Join-Path $TestDrive ("repo_{0}" -f [guid]::NewGuid().ToString('N'))
		git -c init.defaultBranch=master init --quiet $repo
		Set-Content -LiteralPath (Join-Path $repo 'base.txt') -Value 'base'
		Set-Content -LiteralPath (Join-Path $repo 'gone.txt') -Value 'gone'
		Set-Content -LiteralPath (Join-Path $repo '.gitignore') -Value 'ignored.txt'
		git -C $repo add -A
		git -C $repo @script:Identity commit --quiet -m base
		$repo
	}
}

Describe "Get-ChangedPaths" -Tag 'Integration' {
	It "reports nothing on a clean master" {
		$repo = New-TestRepository
		$result = Get-ChangedPaths -RepositoryRoot $repo
		$result.Error | Should -BeNullOrEmpty
		$result.BaseRef | Should -Be 'master'
		@($result.Paths).Count | Should -Be 0
	}

	It "reports the branch's commits, staged and unstaged edits, deletions and untracked files - never ignored ones" {
		$repo = New-TestRepository
		git -C $repo switch --quiet -c feature
		Set-Content -LiteralPath (Join-Path $repo 'committed.txt') -Value 'c'
		git -C $repo add committed.txt
		git -C $repo @script:Identity commit --quiet -m feature
		Set-Content -LiteralPath (Join-Path $repo 'base.txt') -Value 'edited'
		Remove-Item -LiteralPath (Join-Path $repo 'gone.txt')
		Set-Content -LiteralPath (Join-Path $repo 'untracked.txt') -Value 'u'
		Set-Content -LiteralPath (Join-Path $repo 'ignored.txt') -Value 'i'

		$result = Get-ChangedPaths -RepositoryRoot $repo
		@($result.Paths | Sort-Object) | Should -Be @('base.txt', 'committed.txt', 'gone.txt', 'untracked.txt')
		@($result.Added | Sort-Object) | Should -Be @('committed.txt', 'untracked.txt')
		@($result.Deleted) | Should -Be @('gone.txt')
	}

	It "compares against the merge base, not the tip of the base branch" {
		$repo = New-TestRepository
		git -C $repo switch --quiet -c feature
		Set-Content -LiteralPath (Join-Path $repo 'mine.txt') -Value 'm'
		git -C $repo add mine.txt
		git -C $repo @script:Identity commit --quiet -m mine
		git -C $repo switch --quiet master
		Set-Content -LiteralPath (Join-Path $repo 'theirs.txt') -Value 't'
		git -C $repo add theirs.txt
		git -C $repo @script:Identity commit --quiet -m theirs
		git -C $repo switch --quiet feature

		@((Get-ChangedPaths -RepositoryRoot $repo).Paths) | Should -Be @('mine.txt')
	}

	It "honours -Since" {
		$repo = New-TestRepository
		git -C $repo tag start
		Set-Content -LiteralPath (Join-Path $repo 'later.txt') -Value 'l'
		git -C $repo add later.txt
		git -C $repo @script:Identity commit --quiet -m later
		@((Get-ChangedPaths -RepositoryRoot $repo -Since start).Paths) | Should -Be @('later.txt')
	}

	It "returns an error instead of throwing outside a repository or for an unknown ref" {
		$plain = Join-Path $TestDrive ("plain_{0}" -f [guid]::NewGuid().ToString('N'))
		New-Item -ItemType Directory -Path $plain | Out-Null
		(Get-ChangedPaths -RepositoryRoot $plain).Error | Should -Not -BeNullOrEmpty

		$repo = New-TestRepository
		(Get-ChangedPaths -RepositoryRoot $repo -Since 'no-such-ref').Error | Should -Not -BeNullOrEmpty
	}
}

Describe "Get-WorkingTreeFingerprint" -Tag 'Integration' {
	It "is stable while nothing changes and changes on any edit, addition or deletion" {
		$repo = New-TestRepository
		$clean = (Get-WorkingTreeFingerprint -RepositoryRoot $repo).Fingerprint
		(Get-WorkingTreeFingerprint -RepositoryRoot $repo).Fingerprint | Should -Be $clean

		Set-Content -LiteralPath (Join-Path $repo 'base.txt') -Value 'edited'
		$edited = (Get-WorkingTreeFingerprint -RepositoryRoot $repo).Fingerprint
		$edited | Should -Not -Be $clean

		Set-Content -LiteralPath (Join-Path $repo 'base.txt') -Value 'edited again'
		(Get-WorkingTreeFingerprint -RepositoryRoot $repo).Fingerprint | Should -Not -Be $edited

		Set-Content -LiteralPath (Join-Path $repo 'base.txt') -Value 'base'
		(Get-WorkingTreeFingerprint -RepositoryRoot $repo).Fingerprint | Should -Be $clean

		Set-Content -LiteralPath (Join-Path $repo 'new.txt') -Value 'n'
		(Get-WorkingTreeFingerprint -RepositoryRoot $repo).Fingerprint | Should -Not -Be $clean
	}

	It "ignores ignored files" {
		$repo = New-TestRepository
		$clean = (Get-WorkingTreeFingerprint -RepositoryRoot $repo).Fingerprint
		Set-Content -LiteralPath (Join-Path $repo 'ignored.txt') -Value 'i'
		(Get-WorkingTreeFingerprint -RepositoryRoot $repo).Fingerprint | Should -Be $clean
	}

	It "changes with HEAD" {
		$repo = New-TestRepository
		$before = Get-WorkingTreeFingerprint -RepositoryRoot $repo
		git -C $repo @script:Identity commit --quiet --allow-empty -m next
		$after = Get-WorkingTreeFingerprint -RepositoryRoot $repo
		$after.Head | Should -Not -Be $before.Head
		$after.Fingerprint | Should -Not -Be $before.Fingerprint
	}

	It "returns nothing outside a repository" {
		$plain = Join-Path $TestDrive ("plain_{0}" -f [guid]::NewGuid().ToString('N'))
		New-Item -ItemType Directory -Path $plain | Out-Null
		Get-WorkingTreeFingerprint -RepositoryRoot $plain | Should -BeNullOrEmpty
	}
}
