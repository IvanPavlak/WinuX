#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules

	. "$ModuleRoot\Workflow\Functions\Test-StartupTaskDue.ps1"

	# Writes the stamp and dates it. Every test passes -Now or -BootTime next to it, so nothing
	# here depends on the clock.
	function Set-TestStamp {
		param(
			[Parameter(Mandatory)][string]$Path,
			[Parameter(Mandatory)][datetime]$Written
		)

		Set-Content -Path $Path -Value "stamp"
		(Get-Item -Path $Path -Force).LastWriteTime = $Written
	}
}

Describe "Test-StartupTaskDue" {
	BeforeEach {
		$script:Stamp = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
		# A Tuesday at noon, far from any daylight-saving change.
		$script:Noon = [datetime]::new(2026, 3, 10, 12, 0, 0)
	}

	Context "EveryTime" {
		It "is due however fresh the stamp is" {
			Set-TestStamp -Path $script:Stamp -Written $script:Noon

			Test-StartupTaskDue -StampFile $script:Stamp -Frequency EveryTime -Now $script:Noon | Should -BeTrue
		}

		It "is the default frequency" {
			Set-TestStamp -Path $script:Stamp -Written $script:Noon

			Test-StartupTaskDue -StampFile $script:Stamp -Now $script:Noon | Should -BeTrue
		}

		It "never looks at the stamp" {
			Set-TestStamp -Path $script:Stamp -Written $script:Noon
			Mock Test-Path { $true }
			Mock Get-Item { }

			Test-StartupTaskDue -StampFile $script:Stamp -Frequency EveryTime -Now $script:Noon | Should -BeTrue

			Should -Invoke Test-Path -Times 0 -Exactly
			Should -Invoke Get-Item -Times 0 -Exactly
		}
	}

	Context "no stamp yet" {
		It "is due with <Frequency>" -ForEach @(
			@{ Frequency = 'EveryTime' }
			@{ Frequency = 'OncePerBoot' }
			@{ Frequency = 'OncePerDay' }
			@{ Frequency = 'Interval' }
		) {
			Test-StartupTaskDue -StampFile $script:Stamp -Frequency $Frequency -Now $script:Noon -BootTime $script:Noon.AddHours(-1) | Should -BeTrue
		}
	}

	Context "OncePerDay" {
		It "is not due when the last run was after today's day start" {
			Set-TestStamp -Path $script:Stamp -Written $script:Noon.Date.AddHours(6).AddMinutes(1)

			Test-StartupTaskDue -StampFile $script:Stamp -Frequency OncePerDay -DayStartHour 6 -Now $script:Noon | Should -BeFalse
		}

		It "is due when the last run was before today's day start, however recently" {
			Set-TestStamp -Path $script:Stamp -Written $script:Noon.Date.AddHours(6).AddMinutes(-1)

			Test-StartupTaskDue -StampFile $script:Stamp -Frequency OncePerDay -DayStartHour 6 -Now $script:Noon | Should -BeTrue
		}

		It "is not due for a run at the very moment the day started" {
			Set-TestStamp -Path $script:Stamp -Written $script:Noon.Date.AddHours(6)

			Test-StartupTaskDue -StampFile $script:Stamp -Frequency OncePerDay -DayStartHour 6 -Now $script:Noon | Should -BeFalse
		}

		It "is due when the last run was days ago" {
			Set-TestStamp -Path $script:Stamp -Written $script:Noon.AddDays(-5)

			Test-StartupTaskDue -StampFile $script:Stamp -Frequency OncePerDay -DayStartHour 6 -Now $script:Noon | Should -BeTrue
		}

		It "starts the day at 06:00 by default" {
			Set-TestStamp -Path $script:Stamp -Written $script:Noon.Date.AddHours(5).AddMinutes(59)
			Test-StartupTaskDue -StampFile $script:Stamp -Frequency OncePerDay -Now $script:Noon | Should -BeTrue

			Set-TestStamp -Path $script:Stamp -Written $script:Noon.Date.AddHours(6).AddMinutes(1)
			Test-StartupTaskDue -StampFile $script:Stamp -Frequency OncePerDay -Now $script:Noon | Should -BeFalse
		}

		It "follows -DayStartHour" {
			Set-TestStamp -Path $script:Stamp -Written $script:Noon.Date.AddHours(9)

			# 09:00 is after a day that started at 06:00, but before one that starts at 11:00.
			Test-StartupTaskDue -StampFile $script:Stamp -Frequency OncePerDay -DayStartHour 6 -Now $script:Noon | Should -BeFalse
			Test-StartupTaskDue -StampFile $script:Stamp -Frequency OncePerDay -DayStartHour 11 -Now $script:Noon | Should -BeTrue
		}

		Context "before the day start hour, the day is still yesterday's" {
			BeforeEach {
				# 03:00, with the day starting at 06:00: the current day began yesterday at 06:00.
				$script:Night = $script:Noon.Date.AddHours(3)
			}

			It "is not due after a run yesterday evening" {
				Set-TestStamp -Path $script:Stamp -Written $script:Night.AddHours(-4)

				Test-StartupTaskDue -StampFile $script:Stamp -Frequency OncePerDay -DayStartHour 6 -Now $script:Night | Should -BeFalse
			}

			It "is not due after a run past midnight" {
				Set-TestStamp -Path $script:Stamp -Written $script:Night.AddHours(-2)

				Test-StartupTaskDue -StampFile $script:Stamp -Frequency OncePerDay -DayStartHour 6 -Now $script:Night | Should -BeFalse
			}

			It "is due after a run before yesterday's day start" {
				Set-TestStamp -Path $script:Stamp -Written $script:Night.Date.AddDays(-1).AddHours(5).AddMinutes(59)

				Test-StartupTaskDue -StampFile $script:Stamp -Frequency OncePerDay -DayStartHour 6 -Now $script:Night | Should -BeTrue
			}

			It "is not due after a run right after yesterday's day start" {
				Set-TestStamp -Path $script:Stamp -Written $script:Night.Date.AddDays(-1).AddHours(6).AddMinutes(1)

				Test-StartupTaskDue -StampFile $script:Stamp -Frequency OncePerDay -DayStartHour 6 -Now $script:Night | Should -BeFalse
			}
		}

		It "starts the day at midnight with -DayStartHour 0" {
			$justPastMidnight = $script:Noon.Date.AddMinutes(30)

			Set-TestStamp -Path $script:Stamp -Written $justPastMidnight.AddHours(-1)
			Test-StartupTaskDue -StampFile $script:Stamp -Frequency OncePerDay -DayStartHour 0 -Now $justPastMidnight | Should -BeTrue

			Set-TestStamp -Path $script:Stamp -Written $justPastMidnight.AddMinutes(-10)
			Test-StartupTaskDue -StampFile $script:Stamp -Frequency OncePerDay -DayStartHour 0 -Now $justPastMidnight | Should -BeFalse
		}

		It "ignores -IntervalHours and -BootTime" {
			Set-TestStamp -Path $script:Stamp -Written $script:Noon.AddMinutes(-1)

			Test-StartupTaskDue -StampFile $script:Stamp -Frequency OncePerDay -IntervalHours 0 -BootTime $script:Noon -Now $script:Noon | Should -BeFalse
		}
	}

	Context "Interval" {
		It "is due once the last run is exactly the interval old" {
			Set-TestStamp -Path $script:Stamp -Written $script:Noon.AddHours(-4)

			Test-StartupTaskDue -StampFile $script:Stamp -Frequency Interval -IntervalHours 4 -Now $script:Noon | Should -BeTrue
		}

		It "is not due while the last run is younger than the interval" {
			Set-TestStamp -Path $script:Stamp -Written $script:Noon.AddHours(-4).AddMinutes(1)

			Test-StartupTaskDue -StampFile $script:Stamp -Frequency Interval -IntervalHours 4 -Now $script:Noon | Should -BeFalse
		}

		It "is due when the last run is older than the interval" {
			Set-TestStamp -Path $script:Stamp -Written $script:Noon.AddHours(-5)

			Test-StartupTaskDue -StampFile $script:Stamp -Frequency Interval -IntervalHours 4 -Now $script:Noon | Should -BeTrue
		}

		It "takes a fraction of an hour" {
			Set-TestStamp -Path $script:Stamp -Written $script:Noon.AddMinutes(-29)
			Test-StartupTaskDue -StampFile $script:Stamp -Frequency Interval -IntervalHours 0.5 -Now $script:Noon | Should -BeFalse

			Set-TestStamp -Path $script:Stamp -Written $script:Noon.AddMinutes(-31)
			Test-StartupTaskDue -StampFile $script:Stamp -Frequency Interval -IntervalHours 0.5 -Now $script:Noon | Should -BeTrue
		}

		It "defaults to 24 hours" {
			Set-TestStamp -Path $script:Stamp -Written $script:Noon.AddHours(-23)
			Test-StartupTaskDue -StampFile $script:Stamp -Frequency Interval -Now $script:Noon | Should -BeFalse

			Set-TestStamp -Path $script:Stamp -Written $script:Noon.AddHours(-25)
			Test-StartupTaskDue -StampFile $script:Stamp -Frequency Interval -Now $script:Noon | Should -BeTrue
		}

		It "is always due with an interval of <Hours>" -ForEach @(
			@{ Hours = 0 }
			@{ Hours = -1 }
		) {
			Set-TestStamp -Path $script:Stamp -Written $script:Noon

			Test-StartupTaskDue -StampFile $script:Stamp -Frequency Interval -IntervalHours $Hours -Now $script:Noon | Should -BeTrue
		}

		It "ignores the day boundary" {
			# Written before today's day start, but within the interval.
			Set-TestStamp -Path $script:Stamp -Written $script:Noon.Date.AddHours(5)

			Test-StartupTaskDue -StampFile $script:Stamp -Frequency Interval -IntervalHours 24 -DayStartHour 6 -Now $script:Noon | Should -BeFalse
		}
	}

	Context "OncePerBoot" {
		It "is due when the last run was before the machine started" {
			Set-TestStamp -Path $script:Stamp -Written $script:Noon.AddHours(-3)

			Test-StartupTaskDue -StampFile $script:Stamp -Frequency OncePerBoot -BootTime $script:Noon.AddHours(-2) -Now $script:Noon | Should -BeTrue
		}

		It "is not due when the last run was after the machine started" {
			Set-TestStamp -Path $script:Stamp -Written $script:Noon.AddHours(-1)

			Test-StartupTaskDue -StampFile $script:Stamp -Frequency OncePerBoot -BootTime $script:Noon.AddHours(-2) -Now $script:Noon | Should -BeFalse
		}

		It "is not due for a run at the very moment the machine started" {
			Set-TestStamp -Path $script:Stamp -Written $script:Noon.AddHours(-2)

			Test-StartupTaskDue -StampFile $script:Stamp -Frequency OncePerBoot -BootTime $script:Noon.AddHours(-2) -Now $script:Noon | Should -BeFalse
		}

		It "is not due days after the run, as long as the machine has not restarted" {
			Set-TestStamp -Path $script:Stamp -Written $script:Noon.AddDays(-9)

			Test-StartupTaskDue -StampFile $script:Stamp -Frequency OncePerBoot -BootTime $script:Noon.AddDays(-10) -Now $script:Noon | Should -BeFalse
		}

		It "ignores the day boundary and the interval" {
			Set-TestStamp -Path $script:Stamp -Written $script:Noon.AddDays(-3)

			Test-StartupTaskDue -StampFile $script:Stamp -Frequency OncePerBoot -BootTime $script:Noon.AddDays(-4) -DayStartHour 6 -IntervalHours 1 -Now $script:Noon | Should -BeFalse
		}
	}

	Context "without -Now and -BootTime" {
		# The margins are years wide, so the real clock decides nothing here.
		It "measures an interval from the current time" {
			Set-TestStamp -Path $script:Stamp -Written ([datetime]::new(2020, 1, 1, 12, 0, 0))
			Test-StartupTaskDue -StampFile $script:Stamp -Frequency Interval -IntervalHours 24 | Should -BeTrue

			Set-TestStamp -Path $script:Stamp -Written (Get-Date).AddMinutes(-1)
			Test-StartupTaskDue -StampFile $script:Stamp -Frequency Interval -IntervalHours 87600 | Should -BeFalse
		}

		It "takes the machine's own start for OncePerBoot" {
			Set-TestStamp -Path $script:Stamp -Written ([datetime]::new(2020, 1, 1, 12, 0, 0))
			Test-StartupTaskDue -StampFile $script:Stamp -Frequency OncePerBoot | Should -BeTrue

			# A stamp written now is younger than any boot this session can have had.
			Set-Content -Path $script:Stamp -Value "stamp"
			Test-StartupTaskDue -StampFile $script:Stamp -Frequency OncePerBoot | Should -BeFalse
		}
	}
}
