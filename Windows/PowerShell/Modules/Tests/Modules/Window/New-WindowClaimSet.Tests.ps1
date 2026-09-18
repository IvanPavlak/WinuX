#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. (Join-Path $ModuleRoot "Window\Functions\New-WindowClaimSet.ps1")
}

Describe "New-WindowClaimSet" {
	It "builds typed handle sets from IntPtrs, integers and window objects, dropping nulls and zero" {
		$claims = New-WindowClaimSet -Existing @([IntPtr]4, 8, [PSCustomObject]@{ Handle = 12 }, $null, [IntPtr]::Zero)

		$claims.Existing.Count | Should -Be 3
		$claims.Existing.Contains([IntPtr]8) | Should -BeTrue
		$claims.Existing.Contains([IntPtr]12) | Should -BeTrue
	}

	It "has no candidate restriction unless -Candidates is given, and treats an empty candidate list as 'claim nothing'" {
		(New-WindowClaimSet).HasCandidates | Should -BeFalse
		(New-WindowClaimSet).Candidates | Should -BeNullOrEmpty

		$restricted = New-WindowClaimSet -Candidates @()
		$restricted.HasCandidates | Should -BeTrue
		$restricted.TestClaimable([IntPtr]4) | Should -BeFalse
	}

	Context "TestClaimable" {
		BeforeEach {
			$script:claims = New-WindowClaimSet -Existing @(4, 8) -Protected @(16) -Excluded @(20)
		}

		It "refuses protected and excluded windows" {
			$script:claims.TestClaimable([IntPtr]16) | Should -BeFalse
			$script:claims.TestClaimable([IntPtr]20) | Should -BeFalse
		}

		It "allows an existing window in plain mode and refuses it in alongside mode" {
			$script:claims.TestClaimable([IntPtr]4) | Should -BeTrue

			$alongside = New-WindowClaimSet -Existing @(4, 8) -SkipExisting
			$alongside.TestClaimable([IntPtr]4) | Should -BeFalse
			$alongside.TestClaimable([IntPtr]24) | Should -BeTrue
		}

		It "with candidates, allows only a candidate that passes every other rule" {
			$narrow = $script:claims.WithCandidates(@(8, 16, 24))

			$narrow.TestClaimable([IntPtr]8) | Should -BeTrue
			$narrow.TestClaimable([IntPtr]24) | Should -BeTrue
			$narrow.TestClaimable([IntPtr]16) | Should -BeFalse   # protected wins
			$narrow.TestClaimable([IntPtr]28) | Should -BeFalse   # not a candidate
			# the original is untouched
			$script:claims.HasCandidates | Should -BeFalse
		}

		It "refuses a zero handle" {
			$script:claims.TestClaimable([IntPtr]::Zero) | Should -BeFalse
		}
	}

	Context "What the wait derives" {
		It "in plain mode, existing windows are pre-existing (stable on sight) and only protected ones are excluded" {
			$claims = New-WindowClaimSet -Existing @(4, 8) -Protected @(16)

			@($claims.WaitPreExisting()) | Should -Be @([IntPtr]4, [IntPtr]8)
			@($claims.WaitExcluded()) | Should -Be @([IntPtr]16)
		}

		It "in alongside mode, existing windows are excluded from the wait and nothing is pre-existing" {
			$claims = New-WindowClaimSet -Existing @(4, 8) -SkipExisting -Protected @(16)

			$claims.WaitPreExisting().Count | Should -Be 0
			$claims.WaitExcluded().Count | Should -Be 3
		}
	}

	It "keeps a pinned map only when it has entries" {
		(New-WindowClaimSet -PinnedMap @{}).PinnedMap | Should -BeNullOrEmpty
		(New-WindowClaimSet -PinnedMap @{ 'D1:Left' = @{ Handle = 4 } }).PinnedMap.Count | Should -Be 1
	}

	It "exposes live sets so a per-desktop pass can mark its placed windows as excluded" {
		$claims = New-WindowClaimSet
		[void]$claims.Excluded.Add([IntPtr]32)

		$claims.TestClaimable([IntPtr]32) | Should -BeFalse
	}
}
