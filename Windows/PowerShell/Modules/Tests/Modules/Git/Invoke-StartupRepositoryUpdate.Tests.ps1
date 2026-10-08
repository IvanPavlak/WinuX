#Requires -Modules Pester

BeforeAll {
	# Put back exactly the configuration and logging state this file found, so the rest of the
	# worker never logs into this file's temporary folder.
	$script:SavedConfiguration = $global:Configuration
	$script:SavedLoggingState = $global:LoggingState
	$script:SavedMachineType = $global:MachineType

	$ModuleRoot = (Get-RepositoryPath).Modules

	. "$ModuleRoot\Git\Functions\Invoke-StartupRepositoryUpdate.ps1"
	. "$ModuleRoot\Git\Functions\Test-RepositoryUpdateStampFresh.ps1"
	. "$ModuleRoot\Git\Functions\Get-RepositoryUpdateStartupSettings.ps1"
	. "$ModuleRoot\Git\Functions\Get-RepositoryUpdateDayStart.ps1"
	# Dot-sourced so they exist to Mock even in sessions whose imported modules predate them.
	. "$ModuleRoot\Git\Functions\Update-Repositories.ps1"
	. "$ModuleRoot\Bootstrap\Functions\Resolve-RepositoryUpdateScope.ps1"
}

AfterAll {
	$global:Configuration = $script:SavedConfiguration
	$global:LoggingState = $script:SavedLoggingState
	$global:MachineType = $script:SavedMachineType
}

Describe "Invoke-StartupRepositoryUpdate" {
	BeforeEach {
		$script:LogsDir = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
		New-Item -ItemType Directory -Path $script:LogsDir -Force | Out-Null
		$script:StampFile = Join-Path $script:LogsDir ".last-repository-update"

		$global:LoggingState = @{ LogsDir = $script:LogsDir }
		$global:MachineType = "Test"
		$global:Configuration = @{
			BootstrapConfig  = @{}
			RepositoryUpdate = @{ Startup = @{ Enabled = $true } }
		}

		Mock Update-Repositories { }
		Mock Write-LogError { }
	}

	Context "enabled and throttled" {
		It "does nothing when Startup.Enabled is off" {
			$global:Configuration.RepositoryUpdate.Startup.Enabled = $false

			Invoke-StartupRepositoryUpdate

			Should -Invoke Update-Repositories -Times 0 -Exactly
			$script:StampFile | Should -Not -Exist
		}

		It "does nothing when the RepositoryUpdate section is absent" {
			$global:Configuration = @{ BootstrapConfig = @{} }

			Invoke-StartupRepositoryUpdate

			Should -Invoke Update-Repositories -Times 0 -Exactly
		}

		It "runs and writes the stamp when there is no stamp yet" {
			Invoke-StartupRepositoryUpdate

			Should -Invoke Update-Repositories -Times 1 -Exactly
			$script:StampFile | Should -Exist
		}

		It "skips when it already ran today" {
			Set-Content -Path $script:StampFile -Value "stamp"

			Invoke-StartupRepositoryUpdate

			Should -Invoke Update-Repositories -Times 0 -Exactly
		}

		It "runs once the stamp is from an earlier day, however long ago that was" {
			Set-Content -Path $script:StampFile -Value "stamp"
			(Get-Item -Path $script:StampFile -Force).LastWriteTime = (Get-Date).AddDays(-5)

			Invoke-StartupRepositoryUpdate

			Should -Invoke Update-Repositories -Times 1 -Exactly
		}

		It "runs when the last run was before today's day start, even less than 24 hours ago" {
			Set-Content -Path $script:StampFile -Value "stamp"
			(Get-Item -Path $script:StampFile -Force).LastWriteTime = (Get-RepositoryUpdateDayStart -DayStartHour 6).AddMinutes(-1)

			Invoke-StartupRepositoryUpdate

			Should -Invoke Update-Repositories -Times 1 -Exactly
		}

		It "skips when the last run was after today's day start" {
			Set-Content -Path $script:StampFile -Value "stamp"
			(Get-Item -Path $script:StampFile -Force).LastWriteTime = (Get-RepositoryUpdateDayStart -DayStartHour 6).AddMinutes(1)

			Invoke-StartupRepositoryUpdate

			Should -Invoke Update-Repositories -Times 0 -Exactly
		}

		It "honours a custom DayStartHour" {
			$global:Configuration.RepositoryUpdate.Startup.DayStartHour = 14
			Set-Content -Path $script:StampFile -Value "stamp"
			(Get-Item -Path $script:StampFile -Force).LastWriteTime = (Get-RepositoryUpdateDayStart -DayStartHour 14).AddMinutes(-1)

			Invoke-StartupRepositoryUpdate

			Should -Invoke Update-Repositories -Times 1 -Exactly
		}

		It "honours a custom IntervalHours on the Interval schedule" {
			$global:Configuration.RepositoryUpdate.Startup.Schedule = "Interval"
			$global:Configuration.RepositoryUpdate.Startup.IntervalHours = 1
			Set-Content -Path $script:StampFile -Value "stamp"
			(Get-Item -Path $script:StampFile -Force).LastWriteTime = (Get-Date).AddHours(-2)

			Invoke-StartupRepositoryUpdate

			Should -Invoke Update-Repositories -Times 1 -Exactly
		}

		It "defaults to 24 hours on the Interval schedule when IntervalHours is absent" {
			$global:Configuration.RepositoryUpdate.Startup = @{ Enabled = $true; Schedule = "Interval" }
			Set-Content -Path $script:StampFile -Value "stamp"
			(Get-Item -Path $script:StampFile -Force).LastWriteTime = (Get-Date).AddHours(-23)

			Invoke-StartupRepositoryUpdate

			Should -Invoke Update-Repositories -Times 0 -Exactly
		}

		It "refreshes the stamp before the update runs, so a second shell does not run it again" {
			Mock Update-Repositories { $script:StampSeenDuringRun = Test-Path $script:StampFile }

			Invoke-StartupRepositoryUpdate
			Invoke-StartupRepositoryUpdate

			$script:StampSeenDuringRun | Should -BeTrue
			Should -Invoke Update-Repositories -Times 1 -Exactly
		}
	}

	Context "one shell at a time" {
		BeforeEach { $script:LockFile = Join-Path $script:LogsDir ".repository-update.lock" }

		It "does nothing while another shell holds the lock" {
			# An open handle with no sharing is exactly what a running shell holds.
			$held = [System.IO.File]::Open($script:LockFile, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
			try {
				Invoke-StartupRepositoryUpdate
			}
			finally {
				$held.Dispose()
			}

			Should -Invoke Update-Repositories -Times 0 -Exactly
			$script:StampFile | Should -Not -Exist
		}

		It "does nothing while another shell holds the lock, even with -Force" {
			$held = [System.IO.File]::Open($script:LockFile, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
			try {
				Invoke-StartupRepositoryUpdate -Force
			}
			finally {
				$held.Dispose()
			}

			Should -Invoke Update-Repositories -Times 0 -Exactly
		}

		It "clears a lock left by a shell that died mid-run and runs" {
			Set-Content -Path $script:LockFile -Value ""

			Invoke-StartupRepositoryUpdate

			Should -Invoke Update-Repositories -Times 1 -Exactly
		}

		It "holds the lock during the run and releases it afterwards" {
			Mock Update-Repositories { $script:LockSeenDuringRun = Test-Path $script:LockFile }

			Invoke-StartupRepositoryUpdate

			$script:LockSeenDuringRun | Should -BeTrue
			$script:LockFile | Should -Not -Exist
		}

		It "releases the lock when the update throws" {
			Mock Update-Repositories { throw "network down" }

			Invoke-StartupRepositoryUpdate

			$script:LockFile | Should -Not -Exist
		}

		It "does not take the lock when the stamp is fresh" {
			Set-Content -Path $script:StampFile -Value "stamp"

			Invoke-StartupRepositoryUpdate

			$script:LockFile | Should -Not -Exist
			Should -Invoke Update-Repositories -Times 0 -Exactly
		}
	}

	Context "-Force" {
		It "runs while the stamp is fresh" {
			Set-Content -Path $script:StampFile -Value "stamp"

			Invoke-StartupRepositoryUpdate -Force

			Should -Invoke Update-Repositories -Times 1 -Exactly
		}

		It "runs while Startup.Enabled is off" {
			$global:Configuration.RepositoryUpdate.Startup.Enabled = $false

			Invoke-StartupRepositoryUpdate -Force

			Should -Invoke Update-Repositories -Times 1 -Exactly
		}
	}

	Context "how it updates" {
		It "never clones and prints the compact summary" {
			Invoke-StartupRepositoryUpdate

			Should -Invoke Update-Repositories -Times 1 -Exactly -ParameterFilter { $NoClone -and $Quiet }
		}

		It "updates every group when no scope is configured anywhere" {
			Invoke-StartupRepositoryUpdate

			Should -Invoke Update-Repositories -Times 1 -Exactly -ParameterFilter { $All }
		}

		It "uses its own Startup.Scope when it is set" {
			$global:Configuration.BootstrapConfig.RepositoryUpdateScope = @{ Default = "Work" }
			$global:Configuration.RepositoryUpdate.Startup.Scope = @{ Test = "Private" }

			Invoke-StartupRepositoryUpdate

			Should -Invoke Update-Repositories -Times 1 -Exactly -ParameterFilter { ($Group -join ",") -eq "Private" }
		}

		It "falls back to the Bootstrap scope when Startup.Scope is absent" {
			$global:Configuration.BootstrapConfig.RepositoryUpdateScope = @{ Default = "Work, OpenSource" }

			Invoke-StartupRepositoryUpdate

			Should -Invoke Update-Repositories -Times 1 -Exactly -ParameterFilter { ($Group -join ",") -eq "Work,OpenSource" }
		}

		It "does not decide the default branch itself" {
			Invoke-StartupRepositoryUpdate

			Should -Invoke Update-Repositories -Times 1 -Exactly -ParameterFilter { -not $PSBoundParameters.ContainsKey('IncludeDefaultBranch') }
		}
	}

	Context "never breaks the shell" {
		It "logs an error instead of throwing when the update throws" {
			Mock Update-Repositories { throw "network down" }

			{ Invoke-StartupRepositoryUpdate } | Should -Not -Throw
			Should -Invoke Write-LogError -Times 1 -Exactly
		}

		It "accepts -RedrawPrompt without a console line editor to redraw" {
			# The test host is not inside PSReadLine's ReadLine, so the redraw has nothing to do;
			# what matters is that the switch can never break the update or the shell.
			{ Invoke-StartupRepositoryUpdate -RedrawPrompt } | Should -Not -Throw
			Should -Invoke Update-Repositories -Times 1 -Exactly
		}

		It "creates the logs folder when it does not exist yet" {
			$global:LoggingState = @{ LogsDir = (Join-Path $TestDrive "fresh-logs") }

			Invoke-StartupRepositoryUpdate

			Join-Path $TestDrive "fresh-logs\.last-repository-update" | Should -Exist
			Should -Invoke Update-Repositories -Times 1 -Exactly
		}
	}
}
