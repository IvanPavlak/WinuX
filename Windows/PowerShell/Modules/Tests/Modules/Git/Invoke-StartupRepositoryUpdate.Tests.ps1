#Requires -Modules Pester

BeforeAll {
	# Put back exactly the configuration, logging state and deprecation flags this file found, so
	# the rest of the worker never logs into this file's temporary folder.
	$script:SavedConfiguration = $global:Configuration
	$script:SavedLoggingState = $global:LoggingState
	$script:SavedMachineType = $global:MachineType
	$script:SavedDeprecationWarned = $global:WinuXDeprecationWarned

	$ModuleRoot = (Get-RepositoryPath).Modules

	. "$ModuleRoot\Git\Functions\Invoke-StartupRepositoryUpdate.ps1"
	# The startup task the wrapper forwards to. Dot-sourced so they exist to Mock even in sessions
	# whose imported modules predate them, and so the last Context can run them for real.
	. "$ModuleRoot\Workflow\Functions\Get-StartupTaskDefinitions.ps1"
	. "$ModuleRoot\Workflow\Functions\Invoke-StartupTask.ps1"
	. "$ModuleRoot\Workflow\Functions\Test-StartupTaskDue.ps1"
	. "$ModuleRoot\Workflow\Functions\Test-StartupCondition.ps1"
	. "$ModuleRoot\Git\Functions\Update-Repositories.ps1"
	. "$ModuleRoot\Bootstrap\Functions\Resolve-RepositoryUpdateScope.ps1"
	. "$ModuleRoot\Helper\Functions\Restore-ShellPrompt.ps1"
}

AfterAll {
	$global:Configuration = $script:SavedConfiguration
	$global:LoggingState = $script:SavedLoggingState
	$global:MachineType = $script:SavedMachineType
	$global:WinuXDeprecationWarned = $script:SavedDeprecationWarned
}

Describe "Invoke-StartupRepositoryUpdate" {
	BeforeEach {
		# A fresh session as far as the once-per-session deprecation warning goes.
		$global:WinuXDeprecationWarned = $null

		Mock Write-LogWarning { }
		Mock Write-LogError { }
		Mock Restore-ShellPrompt { $false }
	}

	Context "forwarding to the RepositoryUpdate startup task" {
		BeforeEach {
			# Everything the wrapper must change is set to something else here: the task's own
			# window, tab behavior and parallel run belong to a SignIn run, not to this shell.
			$script:Definition = [pscustomobject]@{
				Name       = 'RepositoryUpdate'
				Trigger    = @('SignIn', 'TerminalOpen')
				InScope    = $true
				Valid      = $true
				Errors     = @()
				Legacy     = $false
				Parameters = @{
					Name          = 'RepositoryUpdate'
					Command       = 'Update-Repositories -All -NoClone -Quiet'
					Requires      = @('Network')
					Window        = 'Hidden'
					KeepOpen      = 'Never'
					Parallel      = $true
					Frequency     = 'Interval'
					DayStartHour  = 4
					IntervalHours = 8.0
					Elevation     = 'None'
					Timeout       = 600.0
					Enabled       = $true
					Machine       = 'PC/Laptop'
				}
			}
			$script:ResultStatus = 'Succeeded'

			Mock Get-StartupTaskDefinitions { $script:Definition }
			Mock Invoke-StartupTask { [pscustomobject]@{ Name = 'RepositoryUpdate'; Status = $script:ResultStatus; Reason = '' } }
		}

		It "asks for the task named RepositoryUpdate, without the disabled deprecated one" {
			Invoke-StartupRepositoryUpdate

			Should -Invoke Get-StartupTaskDefinitions -Times 1 -Exactly -ParameterFilter { ($Name -join ',') -eq 'RepositoryUpdate' -and -not $IncludeLegacyDisabled }
		}

		It "asks for the deprecated task even while it is disabled with -Force" {
			Invoke-StartupRepositoryUpdate -Force

			Should -Invoke Get-StartupTaskDefinitions -Times 1 -Exactly -ParameterFilter { ($Name -join ',') -eq 'RepositoryUpdate' -and $IncludeLegacyDisabled }
		}

		It "runs the task in this shell as a TerminalOpen run that never waits for a condition" {
			Invoke-StartupRepositoryUpdate

			Should -Invoke Invoke-StartupTask -Times 1 -Exactly -ParameterFilter {
				$Name -eq 'RepositoryUpdate' -and $Window -eq 'Current' -and $Trigger -eq 'TerminalOpen' -and $NoConditionWait -and -not $Force
			}
		}

		It "hands the task's own settings on" {
			Invoke-StartupRepositoryUpdate

			Should -Invoke Invoke-StartupTask -Times 1 -Exactly -ParameterFilter {
				$Command -eq 'Update-Repositories -All -NoClone -Quiet' -and
				($Requires -join ',') -eq 'Network' -and
				$Frequency -eq 'Interval' -and $DayStartHour -eq 4 -and $IntervalHours -eq 8 -and
				$Machine -eq 'PC/Laptop' -and $Enabled
			}
		}

		It "never hands on Parallel or KeepOpen" {
			Invoke-StartupRepositoryUpdate

			Should -Invoke Invoke-StartupTask -Times 1 -Exactly -ParameterFilter {
				-not $PesterBoundParameters.ContainsKey('Parallel') -and -not $PesterBoundParameters.ContainsKey('KeepOpen')
			}
		}

		It "leaves the definition it was given untouched" {
			Invoke-StartupRepositoryUpdate -Force

			$script:Definition.Parameters.Window | Should -Be 'Hidden'
			$script:Definition.Parameters.KeepOpen | Should -Be 'Never'
			$script:Definition.Parameters.Parallel | Should -BeTrue
			$script:Definition.Parameters.ContainsKey('Force') | Should -BeFalse
			$script:Definition.Parameters.ContainsKey('Trigger') | Should -BeFalse
		}

		It "forces the run with -Force" {
			Invoke-StartupRepositoryUpdate -Force

			Should -Invoke Invoke-StartupTask -Times 1 -Exactly -ParameterFilter { $Force -and $Window -eq 'Current' -and $Trigger -eq 'TerminalOpen' }
		}

		It "does nothing when no task of that name exists" {
			Mock Get-StartupTaskDefinitions { }

			{ Invoke-StartupRepositoryUpdate -RedrawPrompt } | Should -Not -Throw

			Should -Invoke Invoke-StartupTask -Times 0 -Exactly
			Should -Invoke Restore-ShellPrompt -Times 0 -Exactly
			Should -Invoke Write-LogError -Times 0 -Exactly
		}

		It "does nothing when the task is not valid" {
			$script:Definition.Valid = $false
			$script:Definition.Errors = @('Trigger is missing')

			{ Invoke-StartupRepositoryUpdate -Force -RedrawPrompt } | Should -Not -Throw

			Should -Invoke Invoke-StartupTask -Times 0 -Exactly
			Should -Invoke Restore-ShellPrompt -Times 0 -Exactly
		}

		It "returns nothing" {
			Invoke-StartupRepositoryUpdate | Should -BeNullOrEmpty
		}

		It "draws the prompt again with -RedrawPrompt after a run that ended as <Status>" -ForEach @(
			@{ Status = 'Succeeded' }
			@{ Status = 'Failed' }
		) {
			$script:ResultStatus = $Status

			Invoke-StartupRepositoryUpdate -RedrawPrompt

			Should -Invoke Restore-ShellPrompt -Times 1 -Exactly
		}

		It "does not draw the prompt again when the task ended as <Status>" -ForEach @(
			@{ Status = 'NotDue' }
			@{ Status = 'Disabled' }
			@{ Status = 'OutOfScope' }
			@{ Status = 'AlreadyRunning' }
			@{ Status = 'Skipped' }
		) {
			$script:ResultStatus = $Status

			Invoke-StartupRepositoryUpdate -RedrawPrompt

			Should -Invoke Invoke-StartupTask -Times 1 -Exactly
			Should -Invoke Restore-ShellPrompt -Times 0 -Exactly
		}

		It "never draws the prompt again without the switch" {
			Invoke-StartupRepositoryUpdate

			Should -Invoke Invoke-StartupTask -Times 1 -Exactly
			Should -Invoke Restore-ShellPrompt -Times 0 -Exactly
		}

		It "logs an error instead of throwing when the task cannot be run" {
			Mock Invoke-StartupTask { throw "no such shell" }

			{ Invoke-StartupRepositoryUpdate -RedrawPrompt } | Should -Not -Throw

			Should -Invoke Write-LogError -Times 1 -Exactly
			Should -Invoke Restore-ShellPrompt -Times 0 -Exactly
		}

		It "logs an error instead of throwing when the configuration cannot be read" {
			Mock Get-StartupTaskDefinitions { throw "broken configuration" }

			{ Invoke-StartupRepositoryUpdate } | Should -Not -Throw

			Should -Invoke Write-LogError -Times 1 -Exactly
			Should -Invoke Invoke-StartupTask -Times 0 -Exactly
		}
	}

	Context "deprecation warning" {
		BeforeEach {
			Mock Get-StartupTaskDefinitions { }
			Mock Invoke-StartupTask { }
		}

		It "warns once per session, however often it is called" {
			Invoke-StartupRepositoryUpdate
			Invoke-StartupRepositoryUpdate -Force
			Invoke-StartupRepositoryUpdate

			Should -Invoke Write-LogWarning -Times 1 -Exactly
		}

		It "warns even when there is nothing to run" {
			Invoke-StartupRepositoryUpdate

			Should -Invoke Invoke-StartupTask -Times 0 -Exactly
			Should -Invoke Write-LogWarning -Times 1 -Exactly
		}

		It "stays quiet in a session that was already warned" {
			$global:WinuXDeprecationWarned = @{ 'Invoke-StartupRepositoryUpdate' = $true }

			Invoke-StartupRepositoryUpdate

			Should -Invoke Write-LogWarning -Times 0 -Exactly
		}

		It "keeps the flags other deprecated functions set" {
			$global:WinuXDeprecationWarned = @{ 'Register-RepositoryUpdatePromptCheck' = $true }

			Invoke-StartupRepositoryUpdate

			Should -Invoke Write-LogWarning -Times 1 -Exactly
			$global:WinuXDeprecationWarned['Register-RepositoryUpdatePromptCheck'] | Should -BeTrue
			$global:WinuXDeprecationWarned['Invoke-StartupRepositoryUpdate'] | Should -BeTrue
		}

		It "starts its flag table over when the global holds something else" {
			$global:WinuXDeprecationWarned = "not a table"

			{ Invoke-StartupRepositoryUpdate } | Should -Not -Throw

			Should -Invoke Write-LogWarning -Times 1 -Exactly
			$global:WinuXDeprecationWarned['Invoke-StartupRepositoryUpdate'] | Should -BeTrue
		}
	}

	# Nothing below is mocked between the wrapper and Update-Repositories: the real
	# Get-StartupTaskDefinitions builds the task from the configuration and the real
	# Invoke-StartupTask runs it, so this is what an existing caller of the deprecated function
	# still gets.
	Context "what a caller still gets (real startup task)" {
		BeforeEach {
			$script:LogsDir = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
			New-Item -ItemType Directory -Path $script:LogsDir -Force | Out-Null
			$script:StampFile = Join-Path $script:LogsDir ".startup-task-RepositoryUpdate.stamp"
			$script:LockFile = Join-Path $script:LogsDir ".startup-task-RepositoryUpdate.lock"

			$global:LoggingState = @{ LogsDir = $script:LogsDir }
			$global:MachineType = "Test"
			$global:Configuration = @{
				BootstrapConfig  = @{}
				RepositoryUpdate = @{ Startup = @{ Enabled = $true } }
			}

			Mock Update-Repositories { }
			Mock Write-LogDebug { }
		}

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

		It "updates every group, never clones and prints the compact summary" {
			Invoke-StartupRepositoryUpdate

			Should -Invoke Update-Repositories -Times 1 -Exactly -ParameterFilter { $All -and $NoClone -and $Quiet }
		}

		It "uses Startup.Scope when it is set" {
			$global:Configuration.BootstrapConfig.RepositoryUpdateScope = @{ Default = "Work" }
			$global:Configuration.RepositoryUpdate.Startup.Scope = @{ Test = "Private" }

			Invoke-StartupRepositoryUpdate

			Should -Invoke Update-Repositories -Times 1 -Exactly -ParameterFilter { ($Group -join ",") -eq "Private" -and $NoClone -and $Quiet }
		}

		It "falls back to the Bootstrap scope when Startup.Scope is absent" {
			$global:Configuration.BootstrapConfig.RepositoryUpdateScope = @{ Default = "Work, OpenSource" }

			Invoke-StartupRepositoryUpdate

			Should -Invoke Update-Repositories -Times 1 -Exactly -ParameterFilter { ($Group -join ",") -eq "Work,OpenSource" }
		}

		It "does not decide the default branch itself" {
			Invoke-StartupRepositoryUpdate

			Should -Invoke Update-Repositories -Times 1 -Exactly -ParameterFilter { -not $PesterBoundParameters.ContainsKey('IncludeDefaultBranch') }
		}

		It "prefers a startup task named RepositoryUpdate over the deprecated keys" {
			$global:Configuration.Startup = @{
				Tasks = @(
					@{ Name = "RepositoryUpdate"; Command = "Update-Repositories -Group 'Mine' -NoClone -Quiet"; Trigger = "TerminalOpen" }
				)
			}

			Invoke-StartupRepositoryUpdate

			Should -Invoke Update-Repositories -Times 1 -Exactly
			Should -Invoke Update-Repositories -Times 1 -Exactly -ParameterFilter { ($Group -join ",") -eq "Mine" }
		}

		It "runs once per day and stamps the run under the startup task's name" {
			Invoke-StartupRepositoryUpdate
			Invoke-StartupRepositoryUpdate

			Should -Invoke Update-Repositories -Times 1 -Exactly
			$script:StampFile | Should -Exist
		}

		It "runs again once the stamp is from an earlier day" {
			Set-Content -Path $script:StampFile -Value "stamp"
			(Get-Item -Path $script:StampFile -Force).LastWriteTime = (Get-Date).AddDays(-5)

			Invoke-StartupRepositoryUpdate

			Should -Invoke Update-Repositories -Times 1 -Exactly
		}

		It "tries again after a run that threw, and logs the failure instead of throwing" {
			$script:UpdateCalls = 0
			Mock Update-Repositories {
				$script:UpdateCalls++
				if ($script:UpdateCalls -eq 1) { throw "network down" }
			}

			{ Invoke-StartupRepositoryUpdate } | Should -Not -Throw
			$script:StampFile | Should -Not -Exist
			Invoke-StartupRepositoryUpdate

			$script:UpdateCalls | Should -Be 2
			Should -Invoke Write-LogError -Times 1 -Exactly
			$script:StampFile | Should -Exist
		}

		It "runs with -Force while the stamp is fresh" {
			Set-Content -Path $script:StampFile -Value "stamp"

			Invoke-StartupRepositoryUpdate
			Should -Invoke Update-Repositories -Times 0 -Exactly

			Invoke-StartupRepositoryUpdate -Force
			Should -Invoke Update-Repositories -Times 1 -Exactly
		}

		It "runs with -Force while Startup.Enabled is off" {
			$global:Configuration.RepositoryUpdate.Startup.Enabled = $false

			Invoke-StartupRepositoryUpdate -Force

			Should -Invoke Update-Repositories -Times 1 -Exactly
		}

		It "does nothing while another shell runs the task, even with -Force" {
			# An open handle with no sharing is exactly what a running shell holds.
			$held = [System.IO.File]::Open($script:LockFile, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
			try {
				Invoke-StartupRepositoryUpdate -Force -RedrawPrompt
			}
			finally {
				$held.Dispose()
			}

			Should -Invoke Update-Repositories -Times 0 -Exactly
			Should -Invoke Restore-ShellPrompt -Times 0 -Exactly
		}

		It "releases the task's lock after a run, also one that threw" {
			Invoke-StartupRepositoryUpdate -Force
			$script:LockFile | Should -Not -Exist

			Mock Update-Repositories { throw "network down" }
			Invoke-StartupRepositoryUpdate -Force
			$script:LockFile | Should -Not -Exist
		}

		It "draws the prompt again only after a run" {
			Invoke-StartupRepositoryUpdate -RedrawPrompt
			Invoke-StartupRepositoryUpdate -RedrawPrompt

			Should -Invoke Update-Repositories -Times 1 -Exactly
			Should -Invoke Restore-ShellPrompt -Times 1 -Exactly
		}
	}
}
