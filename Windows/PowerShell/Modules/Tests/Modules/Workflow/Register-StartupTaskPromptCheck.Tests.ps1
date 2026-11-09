#Requires -Modules Pester

BeforeAll {
	# Put back the prompt, the configuration, the prompt-check state and the task-shell marker
	# this file found.
	$script:SavedConfiguration = $global:Configuration
	$script:SavedPrompt = ${function:global:prompt}
	$script:SavedState = $global:WinuXStartupTaskPrompt
	$script:SavedTaskShell = $global:WinuXStartupTaskShell

	$ModuleRoot = (Get-RepositoryPath).Modules

	. "$ModuleRoot\Workflow\Functions\Register-StartupTaskPromptCheck.ps1"
	# The real reader: which tasks count (valid, in scope, enabled, once per day, TerminalOpen)
	# is decided on what it returns for a configuration, so the tests hand over configurations.
	. "$ModuleRoot\Workflow\Functions\Get-StartupTaskDefinitions.ps1"
	. "$ModuleRoot\Bootstrap\Functions\Resolve-RepositoryUpdateScope.ps1"
}

AfterAll {
	$global:Configuration = $script:SavedConfiguration
	Set-Item -LiteralPath function:global:prompt -Value $script:SavedPrompt
	$global:WinuXStartupTaskPrompt = $script:SavedState
	if ($null -eq $script:SavedTaskShell) { Remove-Variable -Name WinuXStartupTaskShell -Scope Global -ErrorAction SilentlyContinue }
	else { $global:WinuXStartupTaskShell = $script:SavedTaskShell }
}

Describe "Register-StartupTaskPromptCheck" {
	BeforeEach {
		$global:Configuration = @{
			Startup = @{ Tasks = @(@{ Name = 'MyDaily'; Command = 'Update-Something'; Trigger = 'TerminalOpen'; Frequency = 'OncePerDay' }) }
		}
		$global:WinuXStartupTaskPrompt = $null
		Remove-Variable -Name WinuXStartupTaskShell -Scope Global -ErrorAction SilentlyContinue
		$script:OriginalPrompt = { "original> " }
		Set-Item -LiteralPath function:global:prompt -Value $script:OriginalPrompt

		# A Tuesday at noon, so every boundary below is a fixed moment.
		$script:Now = [datetime]::new(2026, 3, 10, 12, 0, 0)
		Mock Get-Date { $script:Now }
		Mock Resolve-RepositoryUpdateScope { @{ All = $true; Groups = @() } }
	}

	Context "when there is nothing to look again for" {
		It "does nothing when <Case>" -ForEach @(
			@{ Case = 'no startup task is configured'; Tasks = @() }
			@{ Case = 'the daily task is not enabled'; Tasks = @(@{ Name = 'MyDaily'; Trigger = 'TerminalOpen'; Frequency = 'OncePerDay'; Enabled = $false }) }
			@{ Case = 'the daily task belongs to another computer'; Tasks = @(@{ Name = 'MyDaily'; Trigger = 'TerminalOpen'; Frequency = 'OncePerDay'; Hostname = 'Not-This-Computer' }) }
			@{ Case = 'the daily task is not valid'; Tasks = @(@{ Name = 'MyDaily'; Trigger = 'TerminalOpen'; Frequency = 'OncePerDay'; Colour = 'Blue' }) }
			@{ Case = 'the daily task does not have the TerminalOpen trigger'; Tasks = @(@{ Name = 'MyDaily'; Trigger = 'SignIn'; Frequency = 'OncePerDay' }) }
			@{ Case = 'the TerminalOpen task runs every time'; Tasks = @(@{ Name = 'MyTask'; Trigger = 'TerminalOpen' }) }
			@{ Case = 'the TerminalOpen task runs per interval'; Tasks = @(@{ Name = 'MyTask'; Trigger = 'TerminalOpen'; Frequency = 'Interval'; IntervalHours = 4 }) }
			@{ Case = 'the TerminalOpen task runs once per boot'; Tasks = @(@{ Name = 'MyTask'; Trigger = 'TerminalOpen'; Frequency = 'OncePerBoot' }) }
		) {
			$global:Configuration = @{ Startup = @{ Tasks = $Tasks } }

			Register-StartupTaskPromptCheck

			${function:global:prompt}.ToString() | Should -Be $script:OriginalPrompt.ToString()
			$global:WinuXStartupTaskPrompt | Should -BeNullOrEmpty
		}

		It "does nothing when the configuration has no Startup section" {
			$global:Configuration = @{}

			Register-StartupTaskPromptCheck

			${function:global:prompt}.ToString() | Should -Be $script:OriginalPrompt.ToString()
			$global:WinuXStartupTaskPrompt | Should -BeNullOrEmpty
		}

		It "does nothing in a shell that belongs to a startup task" {
			$global:WinuXStartupTaskShell = $true

			Register-StartupTaskPromptCheck

			${function:global:prompt}.ToString() | Should -Be $script:OriginalPrompt.ToString()
			$global:WinuXStartupTaskPrompt | Should -BeNullOrEmpty
		}
	}

	Context "wrapping the prompt" {
		It "wraps the prompt and keeps the original" {
			Register-StartupTaskPromptCheck

			${function:global:prompt}.ToString().Trim() | Should -Be "Invoke-StartupTaskPromptCheck"
			$global:WinuXStartupTaskPrompt.Original.ToString() | Should -Be $script:OriginalPrompt.ToString()
		}

		It "wraps the prompt for a daily task among tasks that do not count" {
			$global:Configuration.Startup.Tasks = @(
				@{ Name = 'AtSignIn'; Trigger = 'SignIn'; Frequency = 'OncePerDay' }
				@{ Name = 'EveryShell'; Trigger = 'TerminalOpen' }
				@{ Name = 'MyDaily'; Trigger = @('SignIn', 'TerminalOpen'); Frequency = 'OncePerDay' }
			)

			Register-StartupTaskPromptCheck

			${function:global:prompt}.ToString().Trim() | Should -Be "Invoke-StartupTaskPromptCheck"
		}

		It "wraps the prompt for the deprecated daily repository update" {
			$global:Configuration = @{ RepositoryUpdate = @{ Startup = @{ Enabled = $true; DayStartHour = 9 } } }

			Register-StartupTaskPromptCheck

			${function:global:prompt}.ToString().Trim() | Should -Be "Invoke-StartupTaskPromptCheck"
			$global:WinuXStartupTaskPrompt.NextCheck | Should -Be ([datetime]::new(2026, 3, 11, 9, 0, 0))
		}

		It "does nothing for the deprecated repository update on the Interval schedule" {
			$global:Configuration = @{ RepositoryUpdate = @{ Startup = @{ Enabled = $true; Schedule = 'Interval' } } }

			Register-StartupTaskPromptCheck

			${function:global:prompt}.ToString() | Should -Be $script:OriginalPrompt.ToString()
			$global:WinuXStartupTaskPrompt | Should -BeNullOrEmpty
		}

		It "never wraps the prompt twice" {
			Register-StartupTaskPromptCheck
			$state = $global:WinuXStartupTaskPrompt
			Register-StartupTaskPromptCheck

			${function:global:prompt}.ToString().Trim() | Should -Be "Invoke-StartupTaskPromptCheck"
			[object]::ReferenceEquals($global:WinuXStartupTaskPrompt, $state) | Should -BeTrue
			$global:WinuXStartupTaskPrompt.Original.ToString() | Should -Be $script:OriginalPrompt.ToString()
		}

		It "wraps a prompt the profile defined again" {
			Register-StartupTaskPromptCheck
			$reloadedPrompt = { "reloaded> " }
			Set-Item -LiteralPath function:global:prompt -Value $reloadedPrompt

			Register-StartupTaskPromptCheck

			${function:global:prompt}.ToString().Trim() | Should -Be "Invoke-StartupTaskPromptCheck"
			$global:WinuXStartupTaskPrompt.Original.ToString() | Should -Be $reloadedPrompt.ToString()
		}

		It "installs a prompt that resolves Invoke-StartupTaskPromptCheck like any typed command" {
			Register-StartupTaskPromptCheck

			# Unbound: a wrapper tied to a module would not find the function after a reload.
			${function:global:prompt}.Module | Should -BeNullOrEmpty
		}
	}

	Context "the next day boundary" {
		It "is today's day start while that is still ahead" {
			$global:Configuration.Startup.Tasks[0].DayStartHour = 15

			Register-StartupTaskPromptCheck

			$global:WinuXStartupTaskPrompt.NextCheck | Should -Be ([datetime]::new(2026, 3, 10, 15, 0, 0))
		}

		It "is tomorrow's day start once today's has passed" {
			$global:Configuration.Startup.Tasks[0].DayStartHour = 9

			Register-StartupTaskPromptCheck

			$global:WinuXStartupTaskPrompt.NextCheck | Should -Be ([datetime]::new(2026, 3, 11, 9, 0, 0))
		}

		It "is tomorrow's day start at the very moment today's begins" {
			$global:Configuration.Startup.Tasks[0].DayStartHour = 12

			Register-StartupTaskPromptCheck

			$global:WinuXStartupTaskPrompt.NextCheck | Should -Be ([datetime]::new(2026, 3, 11, 12, 0, 0))
		}

		It "is 06:00 for a task that names no DayStartHour" {
			Register-StartupTaskPromptCheck

			$global:WinuXStartupTaskPrompt.NextCheck | Should -Be ([datetime]::new(2026, 3, 11, 6, 0, 0))
		}

		It "is the earliest next day start among the daily tasks: <Case>" -ForEach @(
			@{ Case = 'both still ahead today'; Hours = @(20, 15); Expected = [datetime]::new(2026, 3, 10, 15, 0, 0) }
			@{ Case = 'one passed, one ahead'; Hours = @(9, 15); Expected = [datetime]::new(2026, 3, 10, 15, 0, 0) }
			@{ Case = 'both passed'; Hours = @(9, 4); Expected = [datetime]::new(2026, 3, 11, 4, 0, 0) }
			@{ Case = 'midnight and the afternoon'; Hours = @(0, 18); Expected = [datetime]::new(2026, 3, 10, 18, 0, 0) }
		) {
			$global:Configuration.Startup.Tasks = @(
				@{ Name = 'First'; Trigger = 'TerminalOpen'; Frequency = 'OncePerDay'; DayStartHour = $Hours[0] }
				@{ Name = 'Second'; Trigger = 'TerminalOpen'; Frequency = 'OncePerDay'; DayStartHour = $Hours[1] }
			)

			Register-StartupTaskPromptCheck

			$global:WinuXStartupTaskPrompt.NextCheck | Should -Be $Expected
		}

		It "ignores the day start of tasks that do not count" {
			$global:Configuration.Startup.Tasks = @(
				@{ Name = 'Parked'; Trigger = 'TerminalOpen'; Frequency = 'OncePerDay'; DayStartHour = 13; Enabled = $false }
				@{ Name = 'Elsewhere'; Trigger = 'TerminalOpen'; Frequency = 'OncePerDay'; DayStartHour = 14; Hostname = 'Not-This-Computer' }
				@{ Name = 'AtSignIn'; Trigger = 'SignIn'; Frequency = 'OncePerDay'; DayStartHour = 15 }
				@{ Name = 'PerInterval'; Trigger = 'TerminalOpen'; Frequency = 'Interval'; DayStartHour = 16 }
				@{ Name = 'MyDaily'; Trigger = 'TerminalOpen'; Frequency = 'OncePerDay'; DayStartHour = 20 }
			)

			Register-StartupTaskPromptCheck

			$global:WinuXStartupTaskPrompt.NextCheck | Should -Be ([datetime]::new(2026, 3, 10, 20, 0, 0))
		}

		It "is refreshed, without wrapping again, when it is called again" {
			Register-StartupTaskPromptCheck
			$global:WinuXStartupTaskPrompt.NextCheck | Should -Be ([datetime]::new(2026, 3, 11, 6, 0, 0))

			# The next day, past the boundary: what Invoke-StartupTaskPromptCheck calls it for.
			$script:Now = [datetime]::new(2026, 3, 11, 8, 30, 0)
			Register-StartupTaskPromptCheck

			$global:WinuXStartupTaskPrompt.NextCheck | Should -Be ([datetime]::new(2026, 3, 12, 6, 0, 0))
			$global:WinuXStartupTaskPrompt.Original.ToString() | Should -Be $script:OriginalPrompt.ToString()
		}

		It "follows a DayStartHour that changed in the configuration" {
			Register-StartupTaskPromptCheck

			$global:Configuration.Startup.Tasks[0].DayStartHour = 18
			Register-StartupTaskPromptCheck

			$global:WinuXStartupTaskPrompt.NextCheck | Should -Be ([datetime]::new(2026, 3, 10, 18, 0, 0))
		}
	}
}
