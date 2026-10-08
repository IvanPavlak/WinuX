#Requires -Modules Pester

BeforeAll {
	# Put back the prompt, the configuration and the prompt-check state this file found.
	$script:SavedConfiguration = $global:Configuration
	$script:SavedPrompt = ${function:global:prompt}
	$script:SavedState = $global:WinuXRepositoryUpdatePrompt

	$ModuleRoot = (Get-RepositoryPath).Modules

	. "$ModuleRoot\Git\Functions\Register-RepositoryUpdatePromptCheck.ps1"
	. "$ModuleRoot\Git\Functions\Get-RepositoryUpdateStartupSettings.ps1"
	. "$ModuleRoot\Git\Functions\Get-RepositoryUpdateDayStart.ps1"
}

AfterAll {
	$global:Configuration = $script:SavedConfiguration
	Set-Item -LiteralPath function:global:prompt -Value $script:SavedPrompt
	$global:WinuXRepositoryUpdatePrompt = $script:SavedState
}

Describe "Register-RepositoryUpdatePromptCheck" {
	BeforeEach {
		$global:Configuration = @{ RepositoryUpdate = @{ Startup = @{ Enabled = $true } } }
		$global:WinuXRepositoryUpdatePrompt = $null
		$script:OriginalPrompt = { "original> " }
		Set-Item -LiteralPath function:global:prompt -Value $script:OriginalPrompt
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
}
