#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules

	. "$ModuleRoot\Git\Functions\Get-RepositoryUpdateDayStart.ps1"
}

Describe "Get-RepositoryUpdateDayStart" {
	It "returns today at the start hour once that hour has passed" {
		Get-RepositoryUpdateDayStart -DayStartHour 6 -At ([datetime]'2026-10-08 10:15') | Should -Be ([datetime]'2026-10-08 06:00')
	}

	It "returns yesterday at the start hour before that hour, so late-night work stays on the same day" {
		Get-RepositoryUpdateDayStart -DayStartHour 6 -At ([datetime]'2026-10-08 05:59') | Should -Be ([datetime]'2026-10-07 06:00')
	}

	It "treats the start hour itself as the new day" {
		Get-RepositoryUpdateDayStart -DayStartHour 6 -At ([datetime]'2026-10-08 06:00') | Should -Be ([datetime]'2026-10-08 06:00')
	}

	It "is plain midnight with a start hour of 0" {
		Get-RepositoryUpdateDayStart -DayStartHour 0 -At ([datetime]'2026-10-08 00:30') | Should -Be ([datetime]'2026-10-08 00:00')
	}

	It "crosses a month boundary" {
		Get-RepositoryUpdateDayStart -DayStartHour 6 -At ([datetime]'2026-11-01 03:00') | Should -Be ([datetime]'2026-10-31 06:00')
	}

	It "defaults -At to now" {
		$before = Get-Date
		$result = Get-RepositoryUpdateDayStart -DayStartHour 6

		$result | Should -BeLessOrEqual $before
		$before - $result | Should -BeLessThan ([timespan]::FromDays(1))
	}

	It "rejects an hour outside 0-23" {
		{ Get-RepositoryUpdateDayStart -DayStartHour 24 } | Should -Throw
	}
}
