#Requires -Modules Pester

BeforeAll {
	$script:SavedState = $global:WinuXRepositoryUpdatePrompt
	$script:SavedExitCode = $global:LASTEXITCODE

	$ModuleRoot = (Get-RepositoryPath).Modules

	. "$ModuleRoot\Git\Functions\Invoke-RepositoryUpdatePromptCheck.ps1"
	. "$ModuleRoot\Git\Functions\Get-RepositoryUpdateDayStart.ps1"
	# Dot-sourced so it exists to Mock even in sessions whose imported modules predate it.
	. "$ModuleRoot\Git\Functions\Invoke-StartupRepositoryUpdate.ps1"
}

AfterAll {
	$global:WinuXRepositoryUpdatePrompt = $script:SavedState
	$global:LASTEXITCODE = $script:SavedExitCode
}

Describe "Invoke-RepositoryUpdatePromptCheck" {
	BeforeEach {
		$global:WinuXRepositoryUpdatePrompt = [pscustomobject]@{
			Original     = { "original> " }
			DayStartHour = 6
			NextCheck    = (Get-Date).AddHours(1)
		}

		Mock Invoke-StartupRepositoryUpdate { }
	}

	It "returns the original prompt's text and does not update before the next day starts" {
		Invoke-RepositoryUpdatePromptCheck | Should -Be "original> "

		Should -Invoke Invoke-StartupRepositoryUpdate -Times 0 -Exactly
	}

	It "updates once the next day has started, then waits for the day after" {
		$global:WinuXRepositoryUpdatePrompt.NextCheck = (Get-Date).AddMinutes(-1)

		Invoke-RepositoryUpdatePromptCheck | Should -Be "original> "
		Invoke-RepositoryUpdatePromptCheck | Out-Null

		Should -Invoke Invoke-StartupRepositoryUpdate -Times 1 -Exactly
		$global:WinuXRepositoryUpdatePrompt.NextCheck | Should -Be (Get-RepositoryUpdateDayStart -DayStartHour 6).AddDays(1)
	}

	It "hands the original prompt the last command's failure" {
		$global:WinuXRepositoryUpdatePrompt.Original = { "status=$?" }

		Get-Item -LiteralPath (Join-Path $TestDrive "missing") -ErrorAction SilentlyContinue
		$text = Invoke-RepositoryUpdatePromptCheck

		$text | Should -Be "status=False"
	}

	It "keeps the exit code of the user's last command" {
		$global:WinuXRepositoryUpdatePrompt.NextCheck = (Get-Date).AddMinutes(-1)
		Mock Invoke-StartupRepositoryUpdate { $global:LASTEXITCODE = 128 }
		$global:LASTEXITCODE = 3

		Invoke-RepositoryUpdatePromptCheck | Out-Null

		Should -Invoke Invoke-StartupRepositoryUpdate -Times 1 -Exactly
		$global:LASTEXITCODE | Should -Be 3
	}

	It "still returns the prompt and moves to the next day when the update throws" {
		$global:WinuXRepositoryUpdatePrompt.NextCheck = (Get-Date).AddMinutes(-1)
		Mock Invoke-StartupRepositoryUpdate { throw "network down" }

		Invoke-RepositoryUpdatePromptCheck | Should -Be "original> "
		$global:WinuXRepositoryUpdatePrompt.NextCheck | Should -BeGreaterThan (Get-Date)
	}

	It "falls back to the default prompt without a recorded original" {
		$global:WinuXRepositoryUpdatePrompt = $null

		Invoke-RepositoryUpdatePromptCheck | Should -BeLike "PS *> "
		Should -Invoke Invoke-StartupRepositoryUpdate -Times 0 -Exactly
	}
}
