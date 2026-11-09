#Requires -Modules Pester

BeforeAll {
	# Put back the configuration, the exit code and the task context this file found.
	$script:SavedConfiguration = $global:Configuration
	$script:SavedExitCode = $global:LASTEXITCODE
	$script:SavedTaskContext = $global:WinuXStartupTask

	$ModuleRoot = (Get-RepositoryPath).Modules

	. "$ModuleRoot\Workflow\Functions\Invoke-StartupTask.ps1"
	# Run for real: the frequency check and the text of a relaunch.
	. "$ModuleRoot\Workflow\Functions\Test-StartupTaskDue.ps1"
	. "$ModuleRoot\Workflow\Functions\New-StartupTaskShellCommand.ps1"
	# Dot-sourced so they exist to Mock whatever the session's imported modules hold.
	. "$ModuleRoot\Workflow\Functions\Get-StartupTaskDefinitions.ps1"
	. "$ModuleRoot\Workflow\Functions\Start-StartupTaskShell.ps1"
	. "$ModuleRoot\Workflow\Functions\Wait-StartupTaskResult.ps1"
	. "$ModuleRoot\Workflow\Functions\Test-StartupCondition.ps1"

	# The command every task in this file runs: a stand-in the tests mock, so "did the command
	# run" is a plain Should -Invoke.
	function Invoke-TestStartupCommand { }

	# The parameters a relaunch text hands to Invoke-StartupTask: only its ConvertFrom-Json
	# expression is evaluated, the text itself never runs.
	function Get-TestShellArguments {
		param([Parameter(Mandatory)][string]$Text)

		$tokens = $null
		$errors = $null
		$ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$errors)
		@($errors).Count | Should -Be 0 -Because "the relaunch text must be valid PowerShell"

		$assignment = @($ast.EndBlock.Statements) | Where-Object {
			$_ -is [System.Management.Automation.Language.AssignmentStatementAst] -and $_.Left.Extent.Text -eq '$winuxStartupTaskArguments'
		} | Select-Object -First 1
		$assignment | Should -Not -BeNullOrEmpty

		& ([scriptblock]::Create($assignment.Right.Extent.Text))
	}
}

AfterAll {
	$global:Configuration = $script:SavedConfiguration
	$global:LASTEXITCODE = $script:SavedExitCode
	if ($null -eq $script:SavedTaskContext) { Remove-Variable -Name WinuXStartupTask -Scope Global -ErrorAction SilentlyContinue }
	else { $global:WinuXStartupTask = $script:SavedTaskContext }
}

Describe "Invoke-StartupTask" {
	BeforeEach {
		$script:LogsDir = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
		New-Item -ItemType Directory -Path $script:LogsDir -Force | Out-Null
		$script:StampFile = Join-Path $script:LogsDir ".startup-task-MyTask.stamp"
		$script:LockFile = Join-Path $script:LogsDir ".startup-task-MyTask.lock"
		$script:ResultFile = Join-Path $script:LogsDir ".startup-task-MyTask.result"

		$script:IsElevated = $false
		$script:MachineInScope = $true
		$script:Launch = $null
		$script:Waited = $null
		$script:WaitStatus = 'Succeeded'
		$script:WaitReason = ''

		$global:Configuration = @{
			Startup = @{ Conditions = @{ Network = @{ Test = '$true' }; MyVpn = @{ Test = '$true'; Timeout = 120 } } }
		}
		Remove-Variable -Name WinuXStartupTask -Scope Global -ErrorAction SilentlyContinue

		Mock Get-LogPath { $script:LogsDir }
		Mock Test-AdminPrivileges { $script:IsElevated }
		Mock Test-MachineTypeScope { $script:MachineInScope }
		Mock Test-StartupCondition { $true }
		Mock Get-StartupTaskDefinitions { }
		Mock Start-StartupTaskShell {
			$script:Launch = @{
				Name          = $Name
				Arguments     = $Arguments
				Window        = $Window
				KeepOpen      = $KeepOpen
				Administrator = [bool]$Administrator
			}
		}
		Mock Wait-StartupTaskResult {
			$script:Waited = @{ Name = $Name; ResultFile = $ResultFile; Timeout = $Timeout; StampFile = $StampFile }
			[pscustomobject]@{ Name = $Name; Status = $script:WaitStatus; Reason = $script:WaitReason; ResultFile = $ResultFile }
		}
		Mock Invoke-TestStartupCommand { }
		Mock Write-LogError { }
		Mock Write-LogWarning { }
		Mock Write-LogStep { }
		Mock Write-LogDebug { }
	}

	Context "gates" {
		It "is Disabled with -Enabled:`$false, and runs nothing" {
			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Enabled:$false

			$result.Status | Should -Be 'Disabled'
			Should -Invoke Invoke-TestStartupCommand -Times 0 -Exactly
			$script:StampFile | Should -Not -Exist
			$script:LockFile | Should -Not -Exist
		}

		It "is OutOfScope when -Machine does not cover this machine type" {
			$script:MachineInScope = $false

			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Machine 'PC/Laptop'

			$result.Status | Should -Be 'OutOfScope'
			Should -Invoke Test-MachineTypeScope -Times 1 -Exactly -ParameterFilter { $Scope -eq 'PC/Laptop' }
			Should -Invoke Invoke-TestStartupCommand -Times 0 -Exactly
			$script:StampFile | Should -Not -Exist
		}

		It "runs when -Machine covers this machine type" {
			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Machine 'PC/Laptop'

			$result.Status | Should -Be 'Succeeded'
			Should -Invoke Invoke-TestStartupCommand -Times 1 -Exactly
		}

		It "is OutOfScope when -Hostname names only other computers" {
			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Hostname 'Other-PC', 'Not-This-Computer'

			$result.Status | Should -Be 'OutOfScope'
			Should -Invoke Invoke-TestStartupCommand -Times 0 -Exactly
		}

		It "runs when -Hostname names this computer, among others and in any casing" {
			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Hostname 'Other-PC', $env:COMPUTERNAME.ToLowerInvariant()

			$result.Status | Should -Be 'Succeeded'
		}

		It "has no hostname gate for an empty -Hostname" {
			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Hostname @('', $null)

			$result.Status | Should -Be 'Succeeded'
		}

		It "is NotDue when the frequency says it already ran" {
			Set-Content -Path $script:StampFile -Value "stamp"

			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Frequency Interval -IntervalHours 24

			$result.Status | Should -Be 'NotDue'
			Should -Invoke Invoke-TestStartupCommand -Times 0 -Exactly
			$script:LockFile | Should -Not -Exist
		}

		It "passes -DayStartHour and -IntervalHours to the frequency check" {
			Mock Test-StartupTaskDue { $true }

			Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Frequency OncePerDay -DayStartHour 4 -IntervalHours 8 | Out-Null

			# Once as a gate, once more under the lock.
			Should -Invoke Test-StartupTaskDue -Times 2 -Exactly
			Should -Invoke Test-StartupTaskDue -Times 2 -Exactly -ParameterFilter {
				$Frequency -eq 'OncePerDay' -and $DayStartHour -eq 4 -and $IntervalHours -eq 8 -and $StampFile -like '*.startup-task-MyTask.stamp'
			}
		}

		It "checks Enabled before the scope" {
			$script:MachineInScope = $false

			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Enabled:$false -Machine 'PC'

			$result.Status | Should -Be 'Disabled'
			Should -Invoke Test-MachineTypeScope -Times 0 -Exactly
		}

		It "checks the machine type before the hostname, and the scope before the frequency" {
			$script:MachineInScope = $false
			Mock Test-StartupTaskDue { $false }

			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Machine 'PC' -Hostname 'Not-This-Computer' -Frequency OncePerDay

			$result.Status | Should -Be 'OutOfScope'
			# The machine type's reason, not the hostname's.
			$result.Reason | Should -BeLike 'Machine*'
			Should -Invoke Test-StartupTaskDue -Times 0 -Exactly
		}

		It "checks the hostname before the frequency" {
			Mock Test-StartupTaskDue { $false }

			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Hostname 'Not-This-Computer' -Frequency OncePerDay

			$result.Status | Should -Be 'OutOfScope'
			Should -Invoke Test-StartupTaskDue -Times 0 -Exactly
		}

		It "reports a gate to the result file too, so the waiting shell never waits for nothing" {
			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Enabled:$false -ResultFile $script:ResultFile

			$result.Status | Should -Be 'Disabled'
			(Get-Content -LiteralPath $script:ResultFile -Raw | ConvertFrom-Json).Status | Should -Be 'Disabled'
		}

		It "starts no shell for a task that a gate stops" {
			Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Window Tab -Enabled:$false | Out-Null

			Should -Invoke Start-StartupTaskShell -Times 0 -Exactly
			Should -Invoke Wait-StartupTaskResult -Times 0 -Exactly
		}

		It "refuses a name that could not name a file" {
			{ Invoke-StartupTask -Name 'My Task' -Command 'Invoke-TestStartupCommand' } | Should -Throw
			{ Invoke-StartupTask -Name '..\MyTask' -Command 'Invoke-TestStartupCommand' } | Should -Throw

			Should -Invoke Invoke-TestStartupCommand -Times 0 -Exactly
		}
	}

	Context "-Force" {
		It "runs a task that is not enabled" {
			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Enabled:$false -Force

			$result.Status | Should -Be 'Succeeded'
			Should -Invoke Invoke-TestStartupCommand -Times 1 -Exactly
		}

		It "runs a task that is not due" {
			Set-Content -Path $script:StampFile -Value "stamp"

			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Frequency Interval -IntervalHours 24 -Force

			$result.Status | Should -Be 'Succeeded'
			Should -Invoke Invoke-TestStartupCommand -Times 1 -Exactly
		}

		It "never passes the machine scope" {
			$script:MachineInScope = $false

			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Machine 'PC' -Force

			$result.Status | Should -Be 'OutOfScope'
			Should -Invoke Invoke-TestStartupCommand -Times 0 -Exactly
		}

		It "never passes the hostname scope" {
			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Hostname 'Not-This-Computer' -Force

			$result.Status | Should -Be 'OutOfScope'
			Should -Invoke Invoke-TestStartupCommand -Times 0 -Exactly
		}
	}

	Context "an inline run" {
		It "runs the command, writes the stamp and releases the lock" {
			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand'

			$result.Status | Should -Be 'Succeeded'
			Should -Invoke Invoke-TestStartupCommand -Times 1 -Exactly
			$script:StampFile | Should -Exist
			$script:LockFile | Should -Not -Exist
			Should -Invoke Start-StartupTaskShell -Times 0 -Exactly
		}

		It "returns one result that says what ran, why and where" {
			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Trigger TerminalOpen

			@($result).Count | Should -Be 1
			$result.Name | Should -Be 'MyTask'
			$result.Trigger | Should -Be 'TerminalOpen'
			$result.Window | Should -Be 'Current'
			$result.Duration | Should -BeOfType [timespan]
			$result.ResultFile | Should -BeNullOrEmpty
		}

		It "reports the Manual trigger when none is given" {
			(Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand').Trigger | Should -Be 'Manual'
		}

		It "runs the command as typed at a prompt, arguments and all" {
			Invoke-StartupTask -Name MyTask -Command "Set-Content -LiteralPath '$script:ResultFile.ran' -Value 'done'; Invoke-TestStartupCommand" | Out-Null

			"$script:ResultFile.ran" | Should -Exist
			Should -Invoke Invoke-TestStartupCommand -Times 1 -Exactly
		}

		It "holds the lock while the command runs, and writes the stamp only afterwards" {
			Mock Invoke-TestStartupCommand {
				$script:LockSeenDuringRun = Test-Path -LiteralPath $script:LockFile
				$script:StampSeenDuringRun = Test-Path -LiteralPath $script:StampFile
			}

			Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' | Out-Null

			$script:LockSeenDuringRun | Should -BeTrue
			$script:StampSeenDuringRun | Should -BeFalse
			$script:StampFile | Should -Exist
		}

		It "runs once for two calls within the frequency" {
			Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Frequency Interval -IntervalHours 24 | Out-Null
			$second = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Frequency Interval -IntervalHours 24

			$second.Status | Should -Be 'NotDue'
			Should -Invoke Invoke-TestStartupCommand -Times 1 -Exactly
		}

		It "creates the logs folder when it does not exist yet" {
			$script:LogsDir = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())

			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand'

			$result.Status | Should -Be 'Succeeded'
			Join-Path $script:LogsDir ".startup-task-MyTask.stamp" | Should -Exist
		}

		It "succeeds with a command that is <Label>: it only passes its gates and conditions" -ForEach @(
			@{ Label = 'empty'; Text = '' }
			@{ Label = 'blank'; Text = '   ' }
		) {
			$result = Invoke-StartupTask -Name MyTask -Command $Text -Requires Network

			$result.Status | Should -Be 'Succeeded'
			$script:StampFile | Should -Exist
			$script:LockFile | Should -Not -Exist
			Should -Invoke Test-StartupCondition -Times 1 -Exactly
			Should -Invoke Get-StartupTaskDefinitions -Times 0 -Exactly
		}
	}

	Context "a command that fails" {
		It "is Failed when the command throws, with the error as the reason, and writes no stamp" {
			Mock Invoke-TestStartupCommand { throw "the repository is gone" }
			$script:Result = $null

			{ $script:Result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' } | Should -Not -Throw

			$script:Result.Status | Should -Be 'Failed'
			$script:Result.Reason | Should -Be "the repository is gone"
			$script:StampFile | Should -Not -Exist
			$script:LockFile | Should -Not -Exist
			Should -Invoke Write-LogError -Times 1 -Exactly
		}

		It "is Failed when the command does not parse" {
			$result = Invoke-StartupTask -Name MyTask -Command 'if ('

			$result.Status | Should -Be 'Failed'
			$script:StampFile | Should -Not -Exist
			$script:LockFile | Should -Not -Exist
		}

		It "is Failed when the command names something that does not exist" {
			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-NoSuchStartupTaskCommand'

			$result.Status | Should -Be 'Failed'
			$script:StampFile | Should -Not -Exist
		}

		It "is due again after a failure, and stamps the run that succeeds" {
			$script:CommandCalls = 0
			Mock Invoke-TestStartupCommand {
				$script:CommandCalls++
				if ($script:CommandCalls -eq 1) { throw "network down" }
			}

			$first = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Frequency Interval -IntervalHours 24
			$second = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Frequency Interval -IntervalHours 24

			$first.Status | Should -Be 'Failed'
			$second.Status | Should -Be 'Succeeded'
			$script:CommandCalls | Should -Be 2
			$script:StampFile | Should -Exist
		}
	}

	Context "what the command sees and leaves behind" {
		It "puts the caller's exit code back after a command that changed it" {
			Mock Invoke-TestStartupCommand { $global:LASTEXITCODE = 99 }
			$global:LASTEXITCODE = 3

			Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' | Out-Null

			Should -Invoke Invoke-TestStartupCommand -Times 1 -Exactly
			$global:LASTEXITCODE | Should -Be 3
		}

		It "puts the caller's exit code back after a command that threw" {
			Mock Invoke-TestStartupCommand { $global:LASTEXITCODE = 99; throw "broken" }
			$global:LASTEXITCODE = 3

			Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' | Out-Null

			$global:LASTEXITCODE | Should -Be 3
		}

		It "tells Test-AdminPrivileges which task runs, and that it may not relaunch" {
			Mock Invoke-TestStartupCommand { $script:ContextDuringRun = $global:WinuXStartupTask }

			Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' | Out-Null

			$script:ContextDuringRun.Name | Should -Be 'MyTask'
			$script:ContextDuringRun.Elevation | Should -Be 'None'
			$script:ContextDuringRun.ContainsKey('RelaunchCommand') | Should -BeFalse
		}

		It "hands over the text to start again elevated only with -Elevation Relaunch" {
			Mock Invoke-TestStartupCommand { $script:ContextDuringRun = $global:WinuXStartupTask }

			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Trigger SignIn -Elevation Relaunch -Frequency OncePerDay

			# Relaunch runs inline until the command itself asks for Administrator privileges.
			$result.Status | Should -Be 'Succeeded'
			Should -Invoke Start-StartupTaskShell -Times 0 -Exactly
			$script:ContextDuringRun.Name | Should -Be 'MyTask'
			$script:ContextDuringRun.Elevation | Should -Be 'Relaunch'

			# Self-contained and forced: the gates are behind the task when it starts again.
			$relaunch = Get-TestShellArguments -Text $script:ContextDuringRun.RelaunchCommand
			(@($relaunch.Keys) | Sort-Object) -join ',' | Should -Be 'Command,Force,Name,Trigger,Window'
			$relaunch['Name'] | Should -Be 'MyTask'
			$relaunch['Command'] | Should -BeExactly 'Invoke-TestStartupCommand'
			$relaunch['Trigger'] | Should -Be 'SignIn'
			$relaunch['Window'] | Should -Be 'Current'
			$relaunch['Force'] | Should -BeTrue
		}

		It "removes the task context after the run" {
			Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' | Out-Null

			Should -Invoke Invoke-TestStartupCommand -Times 1 -Exactly
			Get-Variable -Name WinuXStartupTask -Scope Global -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
		}

		It "removes the task context after a run that threw" {
			Mock Invoke-TestStartupCommand { throw "broken" }

			Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Elevation Relaunch | Out-Null

			Get-Variable -Name WinuXStartupTask -Scope Global -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
		}

		It "sets no task context for a task without a command" {
			Invoke-StartupTask -Name MyTask -Command '' | Out-Null

			Get-Variable -Name WinuXStartupTask -Scope Global -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
		}

		It "only asks whether the shell is elevated, never for elevation" {
			Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' | Out-Null

			Should -Invoke Test-AdminPrivileges -Times 1 -Exactly -ParameterFilter { $CheckOnly }
			Should -Invoke Test-AdminPrivileges -Times 0 -Exactly -ParameterFilter { -not $CheckOnly }
		}
	}

	Context "one run at a time" {
		It "is AlreadyRunning while another shell holds the lock<Case>" -ForEach @(
			@{ Case = ''; Forced = $false }
			@{ Case = ', even with -Force'; Forced = $true }
		) {
			# An open handle with no sharing is exactly what a running shell holds.
			$held = [System.IO.File]::Open($script:LockFile, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
			try {
				$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Force:$Forced
			}
			finally {
				$held.Dispose()
			}

			$result.Status | Should -Be 'AlreadyRunning'
			Should -Invoke Invoke-TestStartupCommand -Times 0 -Exactly
			$script:StampFile | Should -Not -Exist
			# The loser leaves the winner's lock alone.
			$script:LockFile | Should -Exist
		}

		It "tells the waiting shell that the task is already running" {
			$held = [System.IO.File]::Open($script:LockFile, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
			try {
				Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -ResultFile $script:ResultFile | Out-Null
			}
			finally {
				$held.Dispose()
			}

			(Get-Content -LiteralPath $script:ResultFile -Raw | ConvertFrom-Json).Status | Should -Be 'AlreadyRunning'
		}

		It "clears a lock left by a shell that died mid-run, and runs" {
			Set-Content -Path $script:LockFile -Value ""

			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand'

			$result.Status | Should -Be 'Succeeded'
			Should -Invoke Invoke-TestStartupCommand -Times 1 -Exactly
			$script:LockFile | Should -Not -Exist
		}

		It "releases the lock when the command throws" {
			Mock Invoke-TestStartupCommand { throw "broken" }

			Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' | Out-Null

			$script:LockFile | Should -Not -Exist
		}

		It "checks the frequency again under the lock, for a run another shell finished in between" {
			$script:DueCalls = 0
			Mock Test-StartupTaskDue {
				$script:DueCalls++
				$script:DueCalls -eq 1
			}

			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Frequency OncePerDay

			$result.Status | Should -Be 'NotDue'
			$script:DueCalls | Should -Be 2
			Should -Invoke Invoke-TestStartupCommand -Times 0 -Exactly
			$script:LockFile | Should -Not -Exist
			$script:StampFile | Should -Not -Exist
		}

		It "does not check the frequency under the lock with -Force" {
			Mock Test-StartupTaskDue { $false }

			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Frequency OncePerDay -Force

			$result.Status | Should -Be 'Succeeded'
			Should -Invoke Test-StartupTaskDue -Times 0 -Exactly
		}
	}

	Context "conditions" {
		It "runs the command once every required condition is met" {
			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Requires Network, MyVpn

			$result.Status | Should -Be 'Succeeded'
			Should -Invoke Test-StartupCondition -Times 2 -Exactly
			Should -Invoke Test-StartupCondition -Times 1 -Exactly -ParameterFilter { $Name -eq 'Network' }
			Should -Invoke Test-StartupCondition -Times 1 -Exactly -ParameterFilter { $Name -eq 'MyVpn' }
		}

		It "is Skipped, with no stamp, when a condition is not met" {
			Mock Test-StartupCondition { $false }

			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Requires Network

			$result.Status | Should -Be 'Skipped'
			$result.Reason | Should -Match 'Network'
			Should -Invoke Invoke-TestStartupCommand -Times 0 -Exactly
			$script:StampFile | Should -Not -Exist
			$script:LockFile | Should -Not -Exist
		}

		It "stops at the first condition that is not met" {
			Mock Test-StartupCondition { $false } -ParameterFilter { $Name -eq 'Network' }

			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Requires Network, MyVpn

			$result.Status | Should -Be 'Skipped'
			Should -Invoke Test-StartupCondition -Times 1 -Exactly
		}

		It "names the condition that was not met, not the ones before it" {
			Mock Test-StartupCondition { $false } -ParameterFilter { $Name -eq 'MyVpn' }

			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Requires Network, MyVpn

			$result.Status | Should -Be 'Skipped'
			$result.Reason | Should -Match 'MyVpn'
			$result.Reason | Should -Not -Match 'Network'
		}

		It "waits for a condition without -NoConditionWait, and says so when it gives up" {
			Mock Test-StartupCondition { $false }

			Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Requires Network | Out-Null

			Should -Invoke Test-StartupCondition -Times 1 -Exactly -ParameterFilter { -not $NoWait }
			Should -Invoke Write-LogWarning -Times 1 -Exactly
		}

		It "tests a condition once with -NoConditionWait, and skips without a word" {
			Mock Test-StartupCondition { $false }

			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Requires Network -NoConditionWait

			$result.Status | Should -Be 'Skipped'
			Should -Invoke Test-StartupCondition -Times 1 -Exactly -ParameterFilter { $NoWait }
			Should -Invoke Write-LogWarning -Times 0 -Exactly
			Should -Invoke Write-LogError -Times 0 -Exactly
			$script:StampFile | Should -Not -Exist
		}

		It "looks the conditions up in Startup.Conditions by default" {
			Mock Test-StartupCondition { $script:DefinitionsSeen = $Definitions; $true }

			Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Requires Network | Out-Null

			$script:DefinitionsSeen.Contains('Network') | Should -BeTrue
			$script:DefinitionsSeen.Contains('MyVpn') | Should -BeTrue
		}

		It "looks the conditions up in -ConditionDefinitions when it is given" {
			Mock Test-StartupCondition { $script:DefinitionsSeen = $Definitions; $true }

			Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Requires Custom -ConditionDefinitions @{ Custom = @{ Test = '$true' } } | Out-Null

			$script:DefinitionsSeen.Contains('Custom') | Should -BeTrue
			$script:DefinitionsSeen.Contains('Network') | Should -BeFalse
		}

		It "tests no condition for a task that requires none, or only empty names" {
			Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Requires @('', $null) | Out-Null

			Should -Invoke Test-StartupCondition -Times 0 -Exactly
			Should -Invoke Invoke-TestStartupCommand -Times 1 -Exactly
		}

		It "takes the lock before it waits, so a second shell does not wait too" {
			Mock Test-StartupCondition { $script:LockSeenWhileWaiting = Test-Path -LiteralPath $script:LockFile; $true }

			Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Requires Network | Out-Null

			$script:LockSeenWhileWaiting | Should -BeTrue
		}
	}

	Context "-ResultFile" {
		It "holds a Running record with this shell's process while the command runs, then the final record" {
			Mock Invoke-TestStartupCommand { $script:RecordDuringRun = Get-Content -LiteralPath $script:ResultFile -Raw | ConvertFrom-Json }

			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -ResultFile $script:ResultFile

			$script:RecordDuringRun.Name | Should -Be 'MyTask'
			$script:RecordDuringRun.Status | Should -Be 'Running'
			$script:RecordDuringRun.ProcessId | Should -Be $PID
			$script:RecordDuringRun.ProcessStartedTicks | Should -Be (Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks

			$final = Get-Content -LiteralPath $script:ResultFile -Raw | ConvertFrom-Json
			$final.Name | Should -Be 'MyTask'
			$final.Status | Should -Be 'Succeeded'
			$result.Status | Should -Be 'Succeeded'
			$result.ResultFile | Should -Be $script:ResultFile
		}

		It "is already Running while the task waits for its conditions" {
			Mock Test-StartupCondition { $script:RecordWhileWaiting = Get-Content -LiteralPath $script:ResultFile -Raw | ConvertFrom-Json; $true }

			Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Requires Network -ResultFile $script:ResultFile | Out-Null

			$script:RecordWhileWaiting.Status | Should -Be 'Running'
		}

		It "ends with the failure and its reason" {
			Mock Invoke-TestStartupCommand { throw "the repository is gone" }

			Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -ResultFile $script:ResultFile | Out-Null

			$final = Get-Content -LiteralPath $script:ResultFile -Raw | ConvertFrom-Json
			$final.Status | Should -Be 'Failed'
			$final.Reason | Should -Be "the repository is gone"
		}

		It "ends with Skipped when a condition is not met" {
			Mock Test-StartupCondition { $false }

			Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Requires Network -ResultFile $script:ResultFile | Out-Null

			(Get-Content -LiteralPath $script:ResultFile -Raw | ConvertFrom-Json).Status | Should -Be 'Skipped'
		}

		It "writes no result file for an inline run that nobody waits on" {
			Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' | Out-Null

			$script:ResultFile | Should -Not -Exist
			@(Get-ChildItem -LiteralPath $script:LogsDir -Force).Name | Should -Be '.startup-task-MyTask.stamp'
		}
	}

	Context "-Window Tab and Hidden" {
		It "starts a <Window> shell for the task and runs nothing in this one" -ForEach @(
			@{ Window = 'Tab' }
			@{ Window = 'Hidden' }
		) {
			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Window $Window

			Should -Invoke Start-StartupTaskShell -Times 1 -Exactly
			$script:Launch.Name | Should -Be 'MyTask'
			$script:Launch.Window | Should -Be $Window
			$result.Window | Should -Be $Window
			Should -Invoke Invoke-TestStartupCommand -Times 0 -Exactly
			Should -Invoke Test-StartupCondition -Times 0 -Exactly
			$script:LockFile | Should -Not -Exist
			$script:StampFile | Should -Not -Exist
		}

		It "hands the new shell an inline run of the same task" {
			Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Trigger SignIn -Window Tab -Frequency Interval -IntervalHours 4 -DayStartHour 5 | Out-Null

			$child = $script:Launch.Arguments
			$child.Name | Should -Be 'MyTask'
			$child.Command | Should -BeExactly 'Invoke-TestStartupCommand'
			$child.Trigger | Should -Be 'SignIn'
			$child.Window | Should -Be 'Current'
			$child.Frequency | Should -Be 'Interval'
			$child.IntervalHours | Should -Be 4
			$child.DayStartHour | Should -Be 5
			$child.Elevation | Should -Be 'None'
			$child.Force | Should -BeFalse
		}

		It "tells the new shell to report to the task's result file" {
			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Window Tab

			$script:Launch.Arguments.ResultFile | Should -Be $script:ResultFile
			$result.ResultFile | Should -Be $script:ResultFile
		}

		It "keeps a -ResultFile it was given" {
			$custom = Join-Path $script:LogsDir "custom.result"

			Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Window Tab -ResultFile $custom | Out-Null

			$script:Launch.Arguments.ResultFile | Should -Be $custom
			$script:Waited.ResultFile | Should -Be $custom
		}

		It "removes an old result before the shell starts, so it is not taken for the new one" {
			Set-Content -LiteralPath $script:ResultFile -Value '{"Name":"MyTask","Status":"Succeeded","Reason":""}'
			Mock Start-StartupTaskShell { $script:ResultSeenAtLaunch = Test-Path -LiteralPath $Arguments.ResultFile }

			Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Window Tab | Out-Null

			$script:ResultSeenAtLaunch | Should -BeFalse
		}

		It "hands over only the conditions the task requires" {
			$conditions = @{
				Network = @{ Test = 'Test-Connection example.org -Count 1 -Quiet' }
				MyVpn   = @{ Test = '$true'; Timeout = 120 }
				Unused  = @{ Test = '$false' }
			}

			Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Window Tab -Requires Network, MyVpn -ConditionDefinitions $conditions | Out-Null

			$child = $script:Launch.Arguments
			($child.Requires -join ',') | Should -Be 'Network,MyVpn'
			(@($child.ConditionDefinitions.Keys) | Sort-Object) -join ',' | Should -Be 'MyVpn,Network'
			$child.ConditionDefinitions['MyVpn'].Timeout | Should -Be 120
			$child.ConditionDefinitions['Network'].Test | Should -Be 'Test-Connection example.org -Count 1 -Quiet'
		}

		It "takes the conditions from Startup.Conditions when none are given" {
			Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Window Hidden -Requires MyVpn | Out-Null

			$child = $script:Launch.Arguments
			(@($child.ConditionDefinitions.Keys) -join ',') | Should -Be 'MyVpn'
			$child.ConditionDefinitions['MyVpn'].Timeout | Should -Be 120
		}

		It "hands over no conditions for a task that requires none" {
			Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Window Tab | Out-Null

			@($script:Launch.Arguments.Requires).Count | Should -Be 0
			$script:Launch.Arguments.ConditionDefinitions.Count | Should -Be 0
		}

		It "passes -KeepOpen on to the shell: <KeepOpen>" -ForEach @(
			@{ KeepOpen = 'OnFailure' }
			@{ KeepOpen = 'Always' }
			@{ KeepOpen = 'Never' }
		) {
			Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Window Tab -KeepOpen $KeepOpen | Out-Null

			$script:Launch.KeepOpen | Should -Be $KeepOpen
		}

		It "keeps the tab open only on failure by default" {
			Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Window Tab | Out-Null

			$script:Launch.KeepOpen | Should -Be 'OnFailure'
		}

		It "passes -Force on to the new shell, whose gates would stop the task again otherwise" {
			Set-Content -Path $script:StampFile -Value "stamp"

			Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Window Tab -Frequency Interval -IntervalHours 24 -Force | Out-Null

			$script:Launch.Arguments.Force | Should -BeTrue
		}

		It "waits for the shell up to -Timeout and returns how the task ended there" {
			$script:WaitStatus = 'TimedOut'
			$script:WaitReason = 'No result yet'

			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Window Tab -Timeout 45

			Should -Invoke Wait-StartupTaskResult -Times 1 -Exactly
			$script:Waited.Name | Should -Be 'MyTask'
			$script:Waited.ResultFile | Should -Be $script:ResultFile
			$script:Waited.Timeout | Should -Be 45
			# The stamp of a task that closed its own shell is written by the waiting side.
			$script:Waited.StampFile | Should -Be $script:StampFile
			$result.Status | Should -Be 'TimedOut'
			$result.Reason | Should -Be 'No result yet'
			$result.Window | Should -Be 'Tab'
		}

		It "waits 600 seconds by default" {
			Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Window Tab | Out-Null

			$script:Waited.Timeout | Should -Be 600
		}

		It "returns Started at once with -Parallel, without waiting" {
			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Window Tab -Parallel

			$result.Status | Should -Be 'Started'
			$result.ResultFile | Should -Be $script:ResultFile
			Should -Invoke Start-StartupTaskShell -Times 1 -Exactly
			Should -Invoke Wait-StartupTaskResult -Times 0 -Exactly
		}

		It "is Failed, without waiting or throwing, when the shell cannot be started" {
			Mock Start-StartupTaskShell { throw "The operation was canceled by the user." }
			$script:Result = $null

			{ $script:Result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Window Tab } | Should -Not -Throw

			$script:Result.Status | Should -Be 'Failed'
			Should -Invoke Wait-StartupTaskResult -Times 0 -Exactly
			Should -Invoke Write-LogError -Times 1 -Exactly
		}

		It "is Failed when the shell cannot be started, also with -Parallel" {
			Mock Start-StartupTaskShell { throw "The operation was canceled by the user." }

			(Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Window Hidden -Parallel).Status | Should -Be 'Failed'
		}
	}

	Context "elevation" {
		It "starts the shell <Mode> for -Elevation <Elevation> in a shell that is elevated: <Elevated>" -ForEach @(
			@{ Elevation = 'None'; Elevated = $false; Administrator = $false; Child = 'None'; Mode = 'unelevated' }
			@{ Elevation = 'Relaunch'; Elevated = $false; Administrator = $false; Child = 'Relaunch'; Mode = 'unelevated' }
			@{ Elevation = 'Prompt'; Elevated = $false; Administrator = $true; Child = 'None'; Mode = 'elevated' }
			@{ Elevation = 'Silent'; Elevated = $false; Administrator = $true; Child = 'None'; Mode = 'elevated' }
			@{ Elevation = 'Prompt'; Elevated = $true; Administrator = $false; Child = 'None'; Mode = 'as it is' }
			@{ Elevation = 'Silent'; Elevated = $true; Administrator = $false; Child = 'None'; Mode = 'as it is' }
			@{ Elevation = 'Relaunch'; Elevated = $true; Administrator = $false; Child = 'Relaunch'; Mode = 'as it is' }
		) {
			$script:IsElevated = $Elevated

			Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Window Tab -Elevation $Elevation | Out-Null

			$script:Launch.Administrator | Should -Be $Administrator
			# A shell that starts elevated has nothing left to ask for; only Relaunch travels on.
			$script:Launch.Arguments.Elevation | Should -Be $Child
		}

		It "starts a hidden shell elevated too for -Elevation <Elevation>" -ForEach @(
			@{ Elevation = 'Prompt' }
			@{ Elevation = 'Silent' }
		) {
			Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Window Hidden -Elevation $Elevation | Out-Null

			$script:Launch.Window | Should -Be 'Hidden'
			$script:Launch.Administrator | Should -BeTrue
		}

		It "moves an inline <Elevation> task to an Administrator tab while this shell is not elevated" -ForEach @(
			@{ Elevation = 'Prompt' }
			@{ Elevation = 'Silent' }
		) {
			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Elevation $Elevation

			Should -Invoke Invoke-TestStartupCommand -Times 0 -Exactly
			Should -Invoke Start-StartupTaskShell -Times 1 -Exactly
			$script:Launch.Window | Should -Be 'Tab'
			$script:Launch.Administrator | Should -BeTrue
			$script:Launch.Arguments.Window | Should -Be 'Current'
			$result.Window | Should -Be 'Tab'
			Should -Invoke Wait-StartupTaskResult -Times 1 -Exactly
		}

		It "runs an inline <Elevation> task here when this shell is elevated already" -ForEach @(
			@{ Elevation = 'Prompt' }
			@{ Elevation = 'Silent' }
		) {
			$script:IsElevated = $true

			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Elevation $Elevation

			$result.Status | Should -Be 'Succeeded'
			$result.Window | Should -Be 'Current'
			Should -Invoke Invoke-TestStartupCommand -Times 1 -Exactly
			Should -Invoke Start-StartupTaskShell -Times 0 -Exactly
		}

		It "runs an inline Relaunch task here, elevated or not" {
			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Elevation Relaunch

			$result.Window | Should -Be 'Current'
			Should -Invoke Invoke-TestStartupCommand -Times 1 -Exactly
			Should -Invoke Start-StartupTaskShell -Times 0 -Exactly
		}
	}

	Context "by name alone" {
		BeforeEach {
			# Everything the caller keeps for itself is set to something else here: the window,
			# the tab behavior and the parallel run belong to a SignIn run of this task.
			$script:Definition = [pscustomobject]@{
				Name       = 'MyTask'
				Trigger    = @('SignIn')
				InScope    = $true
				Valid      = $true
				Errors     = @()
				Legacy     = $false
				Parameters = @{
					Name          = 'MyTask'
					Command       = 'Invoke-TestStartupCommand'
					Requires      = @('Network')
					Window        = 'Hidden'
					KeepOpen      = 'Never'
					Parallel      = $true
					Frequency     = 'Interval'
					DayStartHour  = 4
					IntervalHours = 8.0
					Elevation     = 'None'
					Timeout       = 45.0
					Enabled       = $true
					Machine       = 'PC/Laptop'
				}
			}

			Mock Get-StartupTaskDefinitions { $script:Definition }
		}

		It "runs the configured task of that name" {
			$result = Invoke-StartupTask MyTask

			$result.Status | Should -Be 'Succeeded'
			Should -Invoke Get-StartupTaskDefinitions -Times 1 -Exactly -ParameterFilter { ($Name -join ',') -eq 'MyTask' }
			Should -Invoke Invoke-TestStartupCommand -Times 1 -Exactly
			Should -Invoke Test-StartupCondition -Times 1 -Exactly -ParameterFilter { $Name -eq 'Network' }
			Should -Invoke Test-MachineTypeScope -Times 1 -Exactly -ParameterFilter { $Scope -eq 'PC/Laptop' }
		}

		It "runs it in this shell, whatever window the entry names" {
			$result = Invoke-StartupTask MyTask

			$result.Window | Should -Be 'Current'
			Should -Invoke Start-StartupTaskShell -Times 0 -Exactly
			Should -Invoke Wait-StartupTaskResult -Times 0 -Exactly
		}

		It "takes the window from the command line, and neither KeepOpen nor Parallel from the entry" {
			$result = Invoke-StartupTask MyTask -Window Tab

			$script:Launch.Window | Should -Be 'Tab'
			$script:Launch.KeepOpen | Should -Be 'OnFailure'
			# Not Started: the entry's Parallel does not apply to a run typed at a prompt.
			Should -Invoke Wait-StartupTaskResult -Times 1 -Exactly
			$result.Status | Should -Be 'Succeeded'
			$script:Waited.Timeout | Should -Be 45
		}

		It "applies the entry's frequency" {
			Set-Content -Path $script:StampFile -Value "stamp"

			(Invoke-StartupTask MyTask).Status | Should -Be 'NotDue'
			Should -Invoke Invoke-TestStartupCommand -Times 0 -Exactly
		}

		It "applies the entry's interval" {
			Set-Content -Path $script:StampFile -Value "stamp"
			(Get-Item -Path $script:StampFile -Force).LastWriteTime = (Get-Date).AddHours(-9)

			(Invoke-StartupTask MyTask).Status | Should -Be 'Succeeded'
		}

		It "applies the entry's machine scope" {
			$script:MachineInScope = $false

			(Invoke-StartupTask MyTask).Status | Should -Be 'OutOfScope'
		}

		It "applies the entry's Enabled, which -Force passes" {
			$script:Definition.Parameters.Enabled = $false

			(Invoke-StartupTask MyTask).Status | Should -Be 'Disabled'
			(Invoke-StartupTask MyTask -Force).Status | Should -Be 'Succeeded'
		}

		It "lets a parameter on the command line win over the entry's" {
			Set-Content -Path $script:StampFile -Value "stamp"

			$result = Invoke-StartupTask MyTask -Frequency EveryTime -Requires MyVpn

			$result.Status | Should -Be 'Succeeded'
			Should -Invoke Test-StartupCondition -Times 1 -Exactly
			Should -Invoke Test-StartupCondition -Times 1 -Exactly -ParameterFilter { $Name -eq 'MyVpn' }
		}

		It "leaves the definition it was given untouched" {
			Invoke-StartupTask MyTask -Force | Out-Null

			$script:Definition.Parameters.Window | Should -Be 'Hidden'
			$script:Definition.Parameters.KeepOpen | Should -Be 'Never'
			$script:Definition.Parameters.Parallel | Should -BeTrue
			$script:Definition.Parameters.ContainsKey('Force') | Should -BeFalse
		}

		It "is Failed, and runs nothing, when the configured task is not valid" {
			$script:Definition.Valid = $false
			$script:Definition.Errors = @('Unknown key [Colour]')
			$script:Result = $null

			{ $script:Result = Invoke-StartupTask MyTask -Force } | Should -Not -Throw

			$script:Result.Status | Should -Be 'Failed'
			$script:Result.Name | Should -Be 'MyTask'
			Should -Invoke Invoke-TestStartupCommand -Times 0 -Exactly
			Should -Invoke Start-StartupTaskShell -Times 0 -Exactly
			Should -Invoke Write-LogError -Times 1 -Exactly
			$script:StampFile | Should -Not -Exist
		}

		It "is Failed, and runs nothing, when no task of that name is configured" {
			Mock Get-StartupTaskDefinitions { }
			$script:Result = $null

			{ $script:Result = Invoke-StartupTask MyTask } | Should -Not -Throw

			$script:Result.Status | Should -Be 'Failed'
			Should -Invoke Invoke-TestStartupCommand -Times 0 -Exactly
			Should -Invoke Write-LogError -Times 1 -Exactly
		}

		It "never reads the configured tasks when -Command is given" {
			Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' | Out-Null

			Should -Invoke Get-StartupTaskDefinitions -Times 0 -Exactly
			# Nothing of the entry applies: no condition, no machine scope.
			Should -Invoke Test-StartupCondition -Times 0 -Exactly
			Should -Invoke Test-MachineTypeScope -Times 0 -Exactly
		}

		It "asks for the deprecated RepositoryUpdate task, disabled or not, only with -Force" {
			Mock Get-StartupTaskDefinitions { }

			Invoke-StartupTask RepositoryUpdate -Force | Out-Null
			Should -Invoke Get-StartupTaskDefinitions -Times 1 -Exactly -ParameterFilter { $IncludeLegacyDisabled -and ($Name -join ',') -eq 'RepositoryUpdate' }

			Invoke-StartupTask RepositoryUpdate | Out-Null
			Should -Invoke Get-StartupTaskDefinitions -Times 1 -Exactly -ParameterFilter { -not $IncludeLegacyDisabled -and ($Name -join ',') -eq 'RepositoryUpdate' }
		}

		It "does not ask for the deprecated task under any other name" {
			Invoke-StartupTask MyTask -Force | Out-Null

			Should -Invoke Get-StartupTaskDefinitions -Times 1 -Exactly -ParameterFilter { -not $IncludeLegacyDisabled }
		}
	}

	Context "-WhatIf" {
		It "returns WouldRun and runs nothing" {
			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -WhatIf

			$result.Status | Should -Be 'WouldRun'
			$result.Name | Should -Be 'MyTask'
			Should -Invoke Invoke-TestStartupCommand -Times 0 -Exactly
			$script:StampFile | Should -Not -Exist
			$script:LockFile | Should -Not -Exist
		}

		It "starts no shell for a <Window> task" -ForEach @(
			@{ Window = 'Tab' }
			@{ Window = 'Hidden' }
		) {
			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Window $Window -Elevation Prompt -WhatIf

			$result.Status | Should -Be 'WouldRun'
			Should -Invoke Start-StartupTaskShell -Times 0 -Exactly
			Should -Invoke Wait-StartupTaskResult -Times 0 -Exactly
		}

		It "tests each condition once and names the ones the task would wait for" {
			Mock Test-StartupCondition { $false } -ParameterFilter { $Name -eq 'MyVpn' }

			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Requires Network, MyVpn -WhatIf

			$result.Status | Should -Be 'WouldRun'
			$result.Reason | Should -Match 'MyVpn'
			$result.Reason | Should -Not -Match 'Network'
			Should -Invoke Test-StartupCondition -Times 2 -Exactly -ParameterFilter { $NoWait }
			Should -Invoke Test-StartupCondition -Times 0 -Exactly -ParameterFilter { -not $NoWait }
		}

		It "names no condition when all are met" {
			$result = Invoke-StartupTask -Name MyTask -Command 'Invoke-TestStartupCommand' -Requires Network -WhatIf

			$result.Status | Should -Be 'WouldRun'
			$result.Reason | Should -BeNullOrEmpty
		}

		It "still says <Status> for a task a gate stops" -ForEach @(
			@{ Status = 'Disabled' }
			@{ Status = 'OutOfScope' }
			@{ Status = 'NotDue' }
		) {
			Set-Content -Path $script:StampFile -Value "stamp"
			$arguments = @{ Name = 'MyTask'; Command = 'Invoke-TestStartupCommand' }
			switch ($Status) {
				'Disabled' { $arguments.Enabled = $false }
				'OutOfScope' { $arguments.Hostname = 'Not-This-Computer' }
				'NotDue' { $arguments.Frequency = 'Interval'; $arguments.IntervalHours = 24 }
			}

			(Invoke-StartupTask @arguments -WhatIf).Status | Should -Be $Status
		}
	}
}
