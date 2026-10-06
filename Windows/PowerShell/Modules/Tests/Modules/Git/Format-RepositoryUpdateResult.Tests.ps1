#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules

	. "$ModuleRoot\Git\Functions\Format-RepositoryUpdateResult.ps1"
}

Describe "Format-RepositoryUpdateResult" {
	BeforeEach {
		$script:Result = [pscustomobject]@{
			Name                 = "MyRepo"
			Branch               = "feature"
			Outcome              = "UpToDate"
			DefaultBranch        = $null
			DefaultBranchOutcome = $null
			StashName            = $null
		}
	}

	Context "category and level" {
		It "counts <Outcome> as <Category> at <Level>" -ForEach @(
			@{ Outcome = "Updated"; Category = "Updated"; Level = "Success" }
			@{ Outcome = "Cloned"; Category = "Updated"; Level = "Success" }
			@{ Outcome = "UpToDate"; Category = "UpToDate"; Level = "Success" }
			@{ Outcome = "NotCloned"; Category = "Skipped"; Level = "Success" }
			@{ Outcome = "NotConfigured"; Category = "Skipped"; Level = "Success" }
			@{ Outcome = "NoUpstream"; Category = "Skipped"; Level = "Success" }
			@{ Outcome = "FetchFailed"; Category = "Attention"; Level = "Warning" }
			@{ Outcome = "Detached"; Category = "Skipped"; Level = "Success" }
			@{ Outcome = "Busy"; Category = "Attention"; Level = "Warning" }
			@{ Outcome = "NotARepository"; Category = "Attention"; Level = "Warning" }
			@{ Outcome = "StashMissing"; Category = "Attention"; Level = "Warning" }
			@{ Outcome = "Conflict"; Category = "Attention"; Level = "Warning" }
			@{ Outcome = "StashFailed"; Category = "Attention"; Level = "Warning" }
			@{ Outcome = "StashConflict"; Category = "Attention"; Level = "Warning" }
			@{ Outcome = "Error"; Category = "Attention"; Level = "Warning" }
		) {
			$script:Result.Outcome = $Outcome

			$line = Format-RepositoryUpdateResult -Result $script:Result

			$line.Category | Should -Be $Category
			$line.Level | Should -Be $Level
		}

		It "needs attention when the default branch is <DefaultBranchOutcome>, even if the branch itself is fine" -ForEach @(
			@{ DefaultBranchOutcome = "Diverged" }
			@{ DefaultBranchOutcome = "Failed" }
			@{ DefaultBranchOutcome = "Unresolved" }
		) {
			$script:Result.DefaultBranch = "master"
			$script:Result.DefaultBranchOutcome = $DefaultBranchOutcome

			$line = Format-RepositoryUpdateResult -Result $script:Result

			$line.Category | Should -Be "Attention"
			$line.Level | Should -Be "Warning"
		}

		It "keeps the branch's own category when the default branch is <DefaultBranchOutcome>" -ForEach @(
			@{ DefaultBranchOutcome = "Updated" }
			@{ DefaultBranchOutcome = "UpToDate" }
			@{ DefaultBranchOutcome = "Current" }
			@{ DefaultBranchOutcome = "Missing" }
		) {
			$script:Result.DefaultBranch = "master"
			$script:Result.DefaultBranchOutcome = $DefaultBranchOutcome

			(Format-RepositoryUpdateResult -Result $script:Result).Category | Should -Be "UpToDate"
		}
	}

	Context "message" {
		It "names the repository and its branch" {
			(Format-RepositoryUpdateResult -Result $script:Result).Message | Should -Match "^\[MyRepo\] feature\b"
		}

		It "names only the repository when there is no branch" {
			$script:Result.Branch = $null
			$script:Result.Outcome = "NotCloned"

			(Format-RepositoryUpdateResult -Result $script:Result).Message | Should -Match "^\[MyRepo\] [^-]"
		}

		It "mentions a fast-forwarded default branch by name" {
			$script:Result.DefaultBranch = "master"
			$script:Result.DefaultBranchOutcome = "Updated"

			(Format-RepositoryUpdateResult -Result $script:Result).Message | Should -Match "master"
		}

		It "names a default branch that differs from the checked-out one even when it had nothing to do" {
			$script:Result.DefaultBranch = "master"
			$script:Result.DefaultBranchOutcome = "UpToDate"

			(Format-RepositoryUpdateResult -Result $script:Result).Message | Should -Match "master up to date"
		}

		It "names a default branch that has no local branch" {
			$script:Result.DefaultBranch = "master"
			$script:Result.DefaultBranchOutcome = "Missing"

			(Format-RepositoryUpdateResult -Result $script:Result).Message | Should -Match "no local master"
		}

		It "mentions the branch once when the default branch is the checked-out one" {
			$script:Result.Branch = "master"
			$script:Result.DefaultBranch = "master"
			$script:Result.DefaultBranchOutcome = "Current"

			$message = (Format-RepositoryUpdateResult -Result $script:Result).Message
			([regex]::Matches($message, "master")).Count | Should -Be 1
		}

		It "says nothing about the default branch when the step did not run" {
			(Format-RepositoryUpdateResult -Result $script:Result).Message | Should -Not -Match ","
		}

		It "names the kept stash so it can be found" {
			$script:Result.Outcome = "StashConflict"
			$script:Result.StashName = "feature_2026-01-01_09-00-00"

			(Format-RepositoryUpdateResult -Result $script:Result).Message | Should -Match "feature_2026-01-01_09-00-00"
		}
	}
}
