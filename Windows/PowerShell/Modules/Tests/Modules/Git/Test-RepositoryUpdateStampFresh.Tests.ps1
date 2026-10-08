#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules

	. "$ModuleRoot\Git\Functions\Test-RepositoryUpdateStampFresh.ps1"
	. "$ModuleRoot\Git\Functions\Get-RepositoryUpdateDayStart.ps1"
}

Describe "Test-RepositoryUpdateStampFresh" {
	BeforeEach {
		$script:Stamp = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
	}

	It "is not fresh when there is no stamp" {
		Test-RepositoryUpdateStampFresh -StampFile $script:Stamp | Should -BeFalse
		Test-RepositoryUpdateStampFresh -StampFile $script:Stamp -Schedule Interval -IntervalHours 24 | Should -BeFalse
	}

	Context "Daily schedule" {
		It "is fresh when the stamp was written since the day started" {
			Set-Content -Path $script:Stamp -Value "stamp"
			(Get-Item -Path $script:Stamp -Force).LastWriteTime = (Get-RepositoryUpdateDayStart -DayStartHour 6).AddMinutes(1)

			Test-RepositoryUpdateStampFresh -StampFile $script:Stamp -DayStartHour 6 | Should -BeTrue
		}

		It "is not fresh when the stamp was written before the day started, however recently" {
			Set-Content -Path $script:Stamp -Value "stamp"
			(Get-Item -Path $script:Stamp -Force).LastWriteTime = (Get-RepositoryUpdateDayStart -DayStartHour 6).AddMinutes(-1)

			Test-RepositoryUpdateStampFresh -StampFile $script:Stamp -DayStartHour 6 | Should -BeFalse
		}

		It "follows -DayStartHour" {
			$dayStart = Get-RepositoryUpdateDayStart -DayStartHour 14
			Set-Content -Path $script:Stamp -Value "stamp"
			(Get-Item -Path $script:Stamp -Force).LastWriteTime = $dayStart.AddMinutes(-1)

			Test-RepositoryUpdateStampFresh -StampFile $script:Stamp -DayStartHour 14 | Should -BeFalse

			(Get-Item -Path $script:Stamp -Force).LastWriteTime = $dayStart.AddMinutes(1)

			Test-RepositoryUpdateStampFresh -StampFile $script:Stamp -DayStartHour 14 | Should -BeTrue
		}

		It "is the default schedule, with the day starting at 06:00" {
			Set-Content -Path $script:Stamp -Value "stamp"
			(Get-Item -Path $script:Stamp -Force).LastWriteTime = (Get-RepositoryUpdateDayStart -DayStartHour 6).AddMinutes(-1)

			Test-RepositoryUpdateStampFresh -StampFile $script:Stamp | Should -BeFalse
		}
	}

	Context "Interval schedule" {
		It "is fresh when the stamp is younger than the interval" {
			Set-Content -Path $script:Stamp -Value "stamp"

			Test-RepositoryUpdateStampFresh -StampFile $script:Stamp -Schedule Interval -IntervalHours 24 | Should -BeTrue
		}

		It "is not fresh when the stamp is older than the interval" {
			Set-Content -Path $script:Stamp -Value "stamp"
			(Get-Item -Path $script:Stamp -Force).LastWriteTime = (Get-Date).AddHours(-25)

			Test-RepositoryUpdateStampFresh -StampFile $script:Stamp -Schedule Interval -IntervalHours 24 | Should -BeFalse
		}

		It "ignores the day boundary" {
			# Written before today's boundary but within the interval: still fresh.
			Set-Content -Path $script:Stamp -Value "stamp"
			(Get-Item -Path $script:Stamp -Force).LastWriteTime = (Get-RepositoryUpdateDayStart -DayStartHour 6).AddMinutes(-1)

			Test-RepositoryUpdateStampFresh -StampFile $script:Stamp -Schedule Interval -IntervalHours 48 | Should -BeTrue
		}

		It "is never fresh with an interval of 0, so every shell runs it" {
			Set-Content -Path $script:Stamp -Value "stamp"

			Test-RepositoryUpdateStampFresh -StampFile $script:Stamp -Schedule Interval -IntervalHours 0 | Should -BeFalse
		}
	}
}
