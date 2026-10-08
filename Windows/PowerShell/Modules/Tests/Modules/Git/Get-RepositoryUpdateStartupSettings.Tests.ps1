#Requires -Modules Pester

BeforeAll {
	$script:SavedConfiguration = $global:Configuration

	$ModuleRoot = (Get-RepositoryPath).Modules

	. "$ModuleRoot\Git\Functions\Get-RepositoryUpdateStartupSettings.ps1"
}

AfterAll {
	$global:Configuration = $script:SavedConfiguration
}

Describe "Get-RepositoryUpdateStartupSettings" {
	It "fills in every default when the section is absent" {
		$global:Configuration = @{}

		$settings = Get-RepositoryUpdateStartupSettings

		$settings.Enabled | Should -BeFalse
		$settings.Schedule | Should -Be 'Daily'
		$settings.DayStartHour | Should -Be 6
		$settings.IntervalHours | Should -Be 24
	}

	It "reads every configured key" {
		$global:Configuration = @{
			RepositoryUpdate = @{ Startup = @{ Enabled = $true; Schedule = 'Interval'; DayStartHour = 4; IntervalHours = 8 } }
		}

		$settings = Get-RepositoryUpdateStartupSettings

		$settings.Enabled | Should -BeTrue
		$settings.Schedule | Should -Be 'Interval'
		$settings.DayStartHour | Should -Be 4
		$settings.IntervalHours | Should -Be 8
	}

	It "matches the schedule case-insensitively and returns its canonical spelling" {
		$global:Configuration = @{ RepositoryUpdate = @{ Startup = @{ Schedule = 'interval' } } }

		(Get-RepositoryUpdateStartupSettings).Schedule | Should -BeExactly 'Interval'
	}

	It "falls back to Daily for an unknown schedule" {
		$global:Configuration = @{ RepositoryUpdate = @{ Startup = @{ Schedule = 'Weekly' } } }

		(Get-RepositoryUpdateStartupSettings).Schedule | Should -Be 'Daily'
	}

	It "falls back to 6 for a day start hour outside 0-23 or not a number" -TestCases @(
		@{ Hour = 24 }
		@{ Hour = -1 }
		@{ Hour = 'morning' }
	) {
		param($Hour)
		$global:Configuration = @{ RepositoryUpdate = @{ Startup = @{ DayStartHour = $Hour } } }

		(Get-RepositoryUpdateStartupSettings).DayStartHour | Should -Be 6
	}

	It "accepts midnight as the day start" {
		$global:Configuration = @{ RepositoryUpdate = @{ Startup = @{ DayStartHour = 0 } } }

		(Get-RepositoryUpdateStartupSettings).DayStartHour | Should -Be 0
	}

	It "falls back to 24 for an interval that is not a number" {
		$global:Configuration = @{ RepositoryUpdate = @{ Startup = @{ IntervalHours = 'daily' } } }

		(Get-RepositoryUpdateStartupSettings).IntervalHours | Should -Be 24
	}
}
