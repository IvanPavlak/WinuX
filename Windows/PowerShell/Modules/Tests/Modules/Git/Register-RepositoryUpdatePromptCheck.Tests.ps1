#Requires -Modules Pester

BeforeAll {
	# Put back the prompt, the configuration, the prompt-check state and the deprecation flags this
	# file found.
	$script:SavedConfiguration = $global:Configuration
	$script:SavedPrompt = ${function:global:prompt}
	$script:SavedState = $global:WinuXRepositoryUpdatePrompt
	$script:SavedDeprecationWarned = $global:WinuXDeprecationWarned

	$ModuleRoot = (Get-RepositoryPath).Modules

	. "$ModuleRoot\Git\Functions\Register-RepositoryUpdatePromptCheck.ps1"
	. "$ModuleRoot\Git\Functions\Get-RepositoryUpdateStartupSettings.ps1"
	. "$ModuleRoot\Git\Functions\Get-RepositoryUpdateDayStart.ps1"
}

AfterAll {
	$global:Configuration = $script:SavedConfiguration
	Set-Item -LiteralPath function:global:prompt -Value $script:SavedPrompt
	$global:WinuXRepositoryUpdatePrompt = $script:SavedState
	$global:WinuXDeprecationWarned = $script:SavedDeprecationWarned
}

Describe "Register-RepositoryUpdatePromptCheck" {
	BeforeEach {
		$global:Configuration = @{ RepositoryUpdate = @{ Startup = @{ Enabled = $true } } }
		$global:WinuXRepositoryUpdatePrompt = $null
		# A fresh session as far as the once-per-session deprecation warning goes.
		$global:WinuXDeprecationWarned = $null
		$script:OriginalPrompt = { "original> " }
		Set-Item -LiteralPath function:global:prompt -Value $script:OriginalPrompt

		Mock Write-LogWarning { }
	}

	It "does nothing while the startup update is disabled" {
		$global:Configuration.RepositoryUpdate.Startup.Enabled = $false

		Register-RepositoryUpdatePromptCheck

		${function:global:prompt}.ToString() | Should -Be $script:OriginalPrompt.ToString()
		$global:WinuXRepositoryUpdatePrompt | Should -BeNullOrEmpty
	}

	It "does nothing on the Interval schedule" {
		$global:Configuration.RepositoryUpdate.Startup.Schedule = "Interval"

		Register-RepositoryUpdatePromptCheck

		${function:global:prompt}.ToString() | Should -Be $script:OriginalPrompt.ToString()
		$global:WinuXRepositoryUpdatePrompt | Should -BeNullOrEmpty
	}

	It "wraps the prompt and keeps the original" {
		Register-RepositoryUpdatePromptCheck

		${function:global:prompt}.ToString().Trim() | Should -Be "Invoke-RepositoryUpdatePromptCheck"
		$global:WinuXRepositoryUpdatePrompt.Original.ToString() | Should -Be $script:OriginalPrompt.ToString()
	}

	It "looks again when the next day starts" {
		$global:Configuration.RepositoryUpdate.Startup.DayStartHour = 9

		Register-RepositoryUpdatePromptCheck

		$global:WinuXRepositoryUpdatePrompt.DayStartHour | Should -Be 9
		$global:WinuXRepositoryUpdatePrompt.NextCheck | Should -Be (Get-RepositoryUpdateDayStart -DayStartHour 9).AddDays(1)
	}

	It "never wraps the prompt twice" {
		Register-RepositoryUpdatePromptCheck
		Register-RepositoryUpdatePromptCheck

		$global:WinuXRepositoryUpdatePrompt.Original.ToString() | Should -Be $script:OriginalPrompt.ToString()
	}

	It "wraps a prompt the profile defined again" {
		Register-RepositoryUpdatePromptCheck
		$reloadedPrompt = { "reloaded> " }
		Set-Item -LiteralPath function:global:prompt -Value $reloadedPrompt

		Register-RepositoryUpdatePromptCheck

		${function:global:prompt}.ToString().Trim() | Should -Be "Invoke-RepositoryUpdatePromptCheck"
		$global:WinuXRepositoryUpdatePrompt.Original.ToString() | Should -Be $reloadedPrompt.ToString()
	}

	Context "deprecation warning" {
		It "warns once per session, however often it is called" {
			Register-RepositoryUpdatePromptCheck
			Register-RepositoryUpdatePromptCheck
			Register-RepositoryUpdatePromptCheck

			Should -Invoke Write-LogWarning -Times 1 -Exactly
		}

		It "warns even while the startup update is disabled" {
			$global:Configuration.RepositoryUpdate.Startup.Enabled = $false

			Register-RepositoryUpdatePromptCheck

			Should -Invoke Write-LogWarning -Times 1 -Exactly
		}

		It "stays quiet in a session that was already warned, and still wraps the prompt" {
			$global:WinuXDeprecationWarned = @{ 'Register-RepositoryUpdatePromptCheck' = $true }

			Register-RepositoryUpdatePromptCheck

			Should -Invoke Write-LogWarning -Times 0 -Exactly
			${function:global:prompt}.ToString().Trim() | Should -Be "Invoke-RepositoryUpdatePromptCheck"
		}

		It "keeps the flags other deprecated functions set" {
			$global:WinuXDeprecationWarned = @{ 'Invoke-StartupRepositoryUpdate' = $true }

			Register-RepositoryUpdatePromptCheck

			Should -Invoke Write-LogWarning -Times 1 -Exactly
			$global:WinuXDeprecationWarned['Invoke-StartupRepositoryUpdate'] | Should -BeTrue
			$global:WinuXDeprecationWarned['Register-RepositoryUpdatePromptCheck'] | Should -BeTrue
		}
	}
}
