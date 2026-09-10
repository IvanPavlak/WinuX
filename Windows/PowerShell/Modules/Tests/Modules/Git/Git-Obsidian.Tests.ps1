#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Git\Functions"

	. "$FunctionsPath\Git-Obsidian.ps1"

	# One scenario table drives the git double mocked in BeforeEach: the working tree and the
	# unpushed-commit count are the two inputs, the exit codes of commit/push/rev-list the third.
	function script:Set-GitScenario {
		param(
			[string]$Status = "",
			[string]$Unpushed = "0",
			[int]$CommitExitCode = 0,
			[int]$PushExitCode = 0,
			[int]$RevListExitCode = 0
		)

		$script:GitScenario = @{
			Status          = $Status
			Unpushed        = $Unpushed
			CommitExitCode  = $CommitExitCode
			PushExitCode    = $PushExitCode
			RevListExitCode = $RevListExitCode
		}
	}
}

Describe "Git-Obsidian" {
	BeforeEach {
		$script:MachineSpecificPaths = @{ ObsidianDirectory = "C:\Vault" }
		$script:currentDirectory = "C:\Start"

		Mock Set-Location { }
		Mock Write-LogTitle { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }

		Set-GitScenario
		Mock git {
			$scenario = $script:GitScenario
			$global:LASTEXITCODE = 0

			switch ($args[0]) {
				"status" { return $scenario.Status }
				"rev-list" {
					$global:LASTEXITCODE = $scenario.RevListExitCode
					if ($scenario.RevListExitCode -eq 0) {
						return $scenario.Unpushed
					}
					return
				}
				"commit" { $global:LASTEXITCODE = $scenario.CommitExitCode }
				"push" { $global:LASTEXITCODE = $scenario.PushExitCode }
			}
		}
	}

	AfterEach {
		$global:LASTEXITCODE = 0
	}

	Context "working tree has changes" {
		It "commits, pushes and reports success" {
			Set-GitScenario -Status "M note.md" -Unpushed "1"

			Git-Obsidian

			Should -Invoke git -Times 1 -ParameterFilter { $args[0] -eq "add" -and $args[1] -eq "." }
			Should -Invoke git -Times 1 -ParameterFilter { $args[0] -eq "commit" -and $args[1] -eq "-m" -and $args[2] -like "Vault Backup: *" }
			Should -Invoke git -Times 1 -ParameterFilter { $args[0] -eq "push" }
			Should -Invoke Write-LogSuccess -Times 1 -ParameterFilter { $Message -match "Obsidian updated" }
			Should -Invoke Write-LogError -Times 0
		}

		It "reports a failed push as an error, not as success" {
			Set-GitScenario -Status "M note.md" -Unpushed "1" -PushExitCode 128

			Git-Obsidian

			Should -Invoke git -Times 1 -ParameterFilter { $args[0] -eq "push" }
			Should -Invoke Write-LogSuccess -Times 0
			Should -Invoke Write-LogError -Times 1 -ParameterFilter { $Message -match "Push failed" }
			Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match "run Git-Obsidian again" }
		}

		It "does not push when the commit fails" {
			Set-GitScenario -Status "M note.md" -CommitExitCode 1

			Git-Obsidian

			Should -Invoke git -Times 0 -ParameterFilter { $args[0] -eq "push" }
			Should -Invoke Write-LogSuccess -Times 0
			Should -Invoke Write-LogError -Times 1 -ParameterFilter { $Message -match "Commit failed" }
		}
	}

	Context "working tree is clean" {
		It "skips commit and push and reports no changes when nothing is unpushed" {
			Set-GitScenario -Status "" -Unpushed "0"

			Git-Obsidian

			Should -Invoke git -Times 0 -ParameterFilter { $args[0] -eq "add" }
			Should -Invoke git -Times 0 -ParameterFilter { $args[0] -eq "commit" }
			Should -Invoke git -Times 0 -ParameterFilter { $args[0] -eq "push" }
			Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match "No changes to update" }
			Should -Invoke Write-LogSuccess -Times 0
		}

		It "pushes commits an earlier failed run left behind instead of reporting no changes" {
			Set-GitScenario -Status "" -Unpushed "2"

			Git-Obsidian

			Should -Invoke git -Times 0 -ParameterFilter { $args[0] -eq "add" }
			Should -Invoke git -Times 0 -ParameterFilter { $args[0] -eq "commit" }
			Should -Invoke git -Times 1 -ParameterFilter { $args[0] -eq "push" }
			Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match "\[2\] unpushed commit" }
			Should -Invoke Write-LogWarning -Times 0 -ParameterFilter { $Message -match "No changes to update" }
			Should -Invoke Write-LogSuccess -Times 1 -ParameterFilter { $Message -match "Obsidian updated" }
		}

		It "reports an error when pushing the leftover commits fails again" {
			Set-GitScenario -Status "" -Unpushed "1" -PushExitCode 128

			Git-Obsidian

			Should -Invoke git -Times 1 -ParameterFilter { $args[0] -eq "push" }
			Should -Invoke Write-LogSuccess -Times 0
			Should -Invoke Write-LogError -Times 1 -ParameterFilter { $Message -match "Push failed" }
		}

		It "attempts a push and surfaces git's error when the branch has no upstream" {
			Set-GitScenario -Status "" -RevListExitCode 128 -PushExitCode 128

			Git-Obsidian

			Should -Invoke git -Times 1 -ParameterFilter { $args[0] -eq "push" }
			Should -Invoke Write-LogWarning -Times 0 -ParameterFilter { $Message -match "No changes to update" }
			Should -Invoke Write-LogError -Times 1 -ParameterFilter { $Message -match "Push failed" }
		}
	}

	It "counts unpushed commits against the upstream after committing" {
		Set-GitScenario -Status "M note.md" -Unpushed "1"

		Git-Obsidian

		Should -Invoke git -Times 1 -ParameterFilter { $args[0] -eq "rev-list" -and $args[1] -eq "--count" -and $args[2] -eq "@{upstream}..HEAD" }
	}

	Context "spacing under the title" {
		It "puts one blank line between the title and git's output" {
			Set-GitScenario -Status "M note.md" -Unpushed "1"

			Git-Obsidian

			Should -Invoke Write-LogTitle -Times 1 -ParameterFilter { $Message -eq "Git-Obsidian" -and $BlankLineAfter }
		}

		It "puts one blank line between the title and the no-changes message" {
			Set-GitScenario -Status "" -Unpushed "0"

			Git-Obsidian

			Should -Invoke Write-LogTitle -Times 1 -ParameterFilter { $BlankLineAfter }
			Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match "No changes to update" -and $NoLeadingNewline }
		}

		It "puts one blank line between the title and the leftover-commit message, and one before the push output" {
			Set-GitScenario -Status "" -Unpushed "2"

			Git-Obsidian

			Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match "unpushed commit" -and $NoLeadingNewline -and $BlankLineAfter }
		}
	}

	It "restores the original directory" {
		Set-GitScenario -Status "" -Unpushed "0"

		Git-Obsidian

		Should -Invoke Set-Location -Times 1 -ParameterFilter { $Path -eq "C:\Vault" }
		Should -Invoke Set-Location -Times 1 -ParameterFilter { $Path -eq "C:\Start" }
	}
}
