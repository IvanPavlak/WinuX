#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules

	. "$ModuleRoot\Workflow\Functions\Wait-StartupTaskResult.ps1"

	# Writes a result record the way Invoke-StartupTask does: one line of JSON.
	function Set-TestResultRecord {
		param(
			[Parameter(Mandatory)][string]$Path,
			[Parameter(Mandatory)][string]$Status,
			[string]$Reason = '',
			[object]$ProcessId,
			[object]$ProcessStartedTicks
		)

		$record = [ordered]@{ Name = 'MyTask'; Status = $Status; Reason = $Reason }
		if ($null -ne $ProcessId) { $record.ProcessId = $ProcessId }
		if ($null -ne $ProcessStartedTicks) { $record.ProcessStartedTicks = $ProcessStartedTicks }

		Set-Content -LiteralPath $Path -Value (ConvertTo-Json -InputObject $record -Compress) -Encoding UTF8 -Force
	}
}

Describe "Wait-StartupTaskResult" {
	BeforeEach {
		$script:Directory = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
		New-Item -ItemType Directory -Path $script:Directory -Force | Out-Null
		$script:ResultFile = Join-Path $script:Directory ".startup-task-MyTask.result"
		$script:StampFile = Join-Path $script:Directory ".startup-task-MyTask.stamp"

		# This very process stands in for a task's shell that is still alive.
		$script:OwnStartTicks = (Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks

		# A clock only the mocked sleep moves, so a timeout passes without any real wait.
		$script:Clock = [datetime]::new(2026, 3, 10, 12, 0, 0)
		$script:Sleeps = 0
		Mock Get-Date { if ($Format) { $script:Clock.ToString($Format) } else { $script:Clock } }
		Mock Start-Sleep {
			$script:Sleeps++
			$script:Clock = $script:Clock.AddMilliseconds($Milliseconds)
		}
	}

	Context "a final record" {
		It "returns the status and the reason of a task that ended as <Status>" -ForEach @(
			@{ Status = 'Succeeded' }
			@{ Status = 'Failed' }
			@{ Status = 'Skipped' }
			@{ Status = 'NotDue' }
			@{ Status = 'HandedOff' }
			@{ Status = 'AlreadyRunning' }
		) {
			Set-TestResultRecord -Path $script:ResultFile -Status $Status -Reason "what happened"

			$result = Wait-StartupTaskResult -Name MyTask -ResultFile $script:ResultFile -StampFile $script:StampFile

			@($result).Count | Should -Be 1
			$result.Name | Should -Be 'MyTask'
			$result.Status | Should -Be $Status
			$result.Reason | Should -Be "what happened"
			$result.ResultFile | Should -Be $script:ResultFile
			$script:Sleeps | Should -Be 0
		}

		It "writes no stamp: the task wrote its own" {
			Set-TestResultRecord -Path $script:ResultFile -Status Succeeded

			Wait-StartupTaskResult -Name MyTask -ResultFile $script:ResultFile -StampFile $script:StampFile | Out-Null

			$script:StampFile | Should -Not -Exist
		}

		It "takes a final record even though it names a process that is gone" {
			Mock Get-Process { }
			Set-TestResultRecord -Path $script:ResultFile -Status Failed -Reason "it threw" -ProcessId 4242 -ProcessStartedTicks 1

			$result = Wait-StartupTaskResult -Name MyTask -ResultFile $script:ResultFile -StampFile $script:StampFile

			$result.Status | Should -Be 'Failed'
			$script:StampFile | Should -Not -Exist
		}
	}

	Context "a task that is still running" {
		It "keeps waiting while the shell that wrote the Running record is alive, until the timeout" {
			Set-TestResultRecord -Path $script:ResultFile -Status Running -ProcessId $PID -ProcessStartedTicks $script:OwnStartTicks

			$result = Wait-StartupTaskResult -Name MyTask -ResultFile $script:ResultFile -Timeout 1 -StampFile $script:StampFile

			$result.Status | Should -Be 'TimedOut'
			$result.Name | Should -Be 'MyTask'
			$result.ResultFile | Should -Be $script:ResultFile
			# Read at 0, 250, 500, 750 and 1000 ms.
			Should -Invoke Start-Sleep -Times 4 -Exactly
			Should -Invoke Start-Sleep -Times 4 -Exactly -ParameterFilter { $Milliseconds -eq 250 }
		}

		It "writes no stamp for a task it stopped waiting for" {
			Set-TestResultRecord -Path $script:ResultFile -Status Running -ProcessId $PID -ProcessStartedTicks $script:OwnStartTicks

			Wait-StartupTaskResult -Name MyTask -ResultFile $script:ResultFile -Timeout 1 -StampFile $script:StampFile | Out-Null

			$script:StampFile | Should -Not -Exist
		}

		It "reads the file every -PollMilliseconds" {
			Set-TestResultRecord -Path $script:ResultFile -Status Running -ProcessId $PID -ProcessStartedTicks $script:OwnStartTicks

			Wait-StartupTaskResult -Name MyTask -ResultFile $script:ResultFile -Timeout 1 -PollMilliseconds 500 | Out-Null

			Should -Invoke Start-Sleep -Times 2 -Exactly
			Should -Invoke Start-Sleep -Times 2 -Exactly -ParameterFilter { $Milliseconds -eq 500 }
		}

		It "returns the final record as soon as the running task writes it" {
			Set-TestResultRecord -Path $script:ResultFile -Status Running -ProcessId $PID -ProcessStartedTicks $script:OwnStartTicks
			Mock Start-Sleep {
				$script:Sleeps++
				if ($script:Sleeps -eq 3) {
					Set-Content -LiteralPath $script:ResultFile -Value '{"Name":"MyTask","Status":"Skipped","Reason":"Condition [MyVpn] was not met in time"}'
				}
			}

			$result = Wait-StartupTaskResult -Name MyTask -ResultFile $script:ResultFile -Timeout 600 -StampFile $script:StampFile

			$result.Status | Should -Be 'Skipped'
			$result.Reason | Should -Be 'Condition [MyVpn] was not met in time'
			$script:Sleeps | Should -Be 3
		}

		It "keeps waiting when the record's start time is within two seconds of the process's: <Seconds> s" -ForEach @(
			@{ Seconds = 1 }
			@{ Seconds = -1 }
			@{ Seconds = 2 }
			@{ Seconds = -2 }
		) {
			$recorded = $script:OwnStartTicks + [timespan]::FromSeconds($Seconds).Ticks
			Set-TestResultRecord -Path $script:ResultFile -Status Running -ProcessId $PID -ProcessStartedTicks $recorded

			$result = Wait-StartupTaskResult -Name MyTask -ResultFile $script:ResultFile -Timeout 1 -StampFile $script:StampFile

			$result.Status | Should -Be 'TimedOut'
		}

		It "keeps waiting when the record's start time <Case>, so only the process id decides" -ForEach @(
			@{ Case = 'is 0'; Ticks = 0 }
			@{ Case = 'is negative'; Ticks = -5 }
			@{ Case = 'is not a number'; Ticks = 'unknown' }
		) {
			Set-TestResultRecord -Path $script:ResultFile -Status Running -ProcessId $PID -ProcessStartedTicks $Ticks

			$result = Wait-StartupTaskResult -Name MyTask -ResultFile $script:ResultFile -Timeout 1 -StampFile $script:StampFile

			$result.Status | Should -Be 'TimedOut'
			$script:StampFile | Should -Not -Exist
		}

		It "keeps waiting when the record has no start time" {
			Set-TestResultRecord -Path $script:ResultFile -Status Running -ProcessId $PID

			(Wait-StartupTaskResult -Name MyTask -ResultFile $script:ResultFile -Timeout 1).Status | Should -Be 'TimedOut'
		}

		It "keeps waiting for a Running record that names no process" {
			Mock Get-Process { }
			Set-TestResultRecord -Path $script:ResultFile -Status Running

			$result = Wait-StartupTaskResult -Name MyTask -ResultFile $script:ResultFile -Timeout 1 -StampFile $script:StampFile

			$result.Status | Should -Be 'TimedOut'
			Should -Invoke Get-Process -Times 0 -Exactly
			$script:StampFile | Should -Not -Exist
		}
	}

	Context "a task whose shell is gone" {
		It "counts as Ended, at once, when no process has the recorded id" {
			Mock Get-Process { }
			Set-TestResultRecord -Path $script:ResultFile -Status Running -ProcessId 4242 -ProcessStartedTicks $script:OwnStartTicks

			$result = Wait-StartupTaskResult -Name MyTask -ResultFile $script:ResultFile -Timeout 600 -StampFile $script:StampFile

			$result.Status | Should -Be 'Ended'
			$result.Name | Should -Be 'MyTask'
			$script:Sleeps | Should -Be 0
			Should -Invoke Get-Process -Times 1 -Exactly -ParameterFilter { $Id -eq 4242 }
		}

		It "writes the task's stamp, as after a success" {
			Mock Get-Process { }
			Set-TestResultRecord -Path $script:ResultFile -Status Running -ProcessId 4242 -ProcessStartedTicks $script:OwnStartTicks

			Wait-StartupTaskResult -Name MyTask -ResultFile $script:ResultFile -StampFile $script:StampFile | Out-Null

			$script:StampFile | Should -Exist
		}

		It "writes nothing without -StampFile" {
			Mock Get-Process { }
			Set-TestResultRecord -Path $script:ResultFile -Status Running -ProcessId 4242 -ProcessStartedTicks $script:OwnStartTicks

			(Wait-StartupTaskResult -Name MyTask -ResultFile $script:ResultFile).Status | Should -Be 'Ended'

			@(Get-ChildItem -LiteralPath $script:Directory -Force).Count | Should -Be 1
		}

		It "still reports Ended when the stamp cannot be written" {
			Mock Get-Process { }
			Set-TestResultRecord -Path $script:ResultFile -Status Running -ProcessId 4242 -ProcessStartedTicks $script:OwnStartTicks
			$unwritable = Join-Path $script:Directory "no-such-folder\.startup-task-MyTask.stamp"
			$script:Result = $null

			{ $script:Result = Wait-StartupTaskResult -Name MyTask -ResultFile $script:ResultFile -StampFile $unwritable } | Should -Not -Throw

			$script:Result.Status | Should -Be 'Ended'
		}

		It "counts a live process that started <Seconds> s away from the recorded time as another process" -ForEach @(
			@{ Seconds = 3 }
			@{ Seconds = -3 }
			@{ Seconds = 3600 }
		) {
			# The id is this process's, so it is alive: only the start time says it is not the task's shell.
			$recorded = $script:OwnStartTicks + [timespan]::FromSeconds($Seconds).Ticks
			Set-TestResultRecord -Path $script:ResultFile -Status Running -ProcessId $PID -ProcessStartedTicks $recorded

			$result = Wait-StartupTaskResult -Name MyTask -ResultFile $script:ResultFile -Timeout 600 -StampFile $script:StampFile

			$result.Status | Should -Be 'Ended'
			$script:Sleeps | Should -Be 0
			$script:StampFile | Should -Exist
		}

		It "notices that the shell went away while it was waiting" {
			$script:ShellAlive = $true
			Mock Get-Process { if ($script:ShellAlive) { [pscustomobject]@{ Id = 4242; StartTime = [datetime]::new(2026, 3, 10, 11, 0, 0) } } }
			Mock Start-Sleep {
				$script:Sleeps++
				if ($script:Sleeps -eq 2) { $script:ShellAlive = $false }
			}
			Set-TestResultRecord -Path $script:ResultFile -Status Running -ProcessId 4242 -ProcessStartedTicks ([datetime]::new(2026, 3, 10, 11, 0, 0).ToUniversalTime().Ticks)

			$result = Wait-StartupTaskResult -Name MyTask -ResultFile $script:ResultFile -Timeout 600 -StampFile $script:StampFile

			$result.Status | Should -Be 'Ended'
			$script:Sleeps | Should -Be 2
			$script:StampFile | Should -Exist
		}
	}

	Context "a record that is not there yet" {
		It "times out when no result file ever appears" {
			$result = Wait-StartupTaskResult -Name MyTask -ResultFile $script:ResultFile -Timeout 2 -StampFile $script:StampFile

			$result.Status | Should -Be 'TimedOut'
			$result.Reason | Should -Not -BeNullOrEmpty
			Should -Invoke Start-Sleep -Times 8 -Exactly
			$script:StampFile | Should -Not -Exist
		}

		It "waits without limit with a timeout of 0, until the file appears" {
			# Each sleep moves the clock an hour: no timeout, however long, would have survived this.
			Mock Start-Sleep {
				$script:Sleeps++
				$script:Clock = $script:Clock.AddHours(1)
				if ($script:Sleeps -eq 5) {
					Set-Content -LiteralPath $script:ResultFile -Value '{"Name":"MyTask","Status":"Succeeded","Reason":""}'
				}
			}

			$result = Wait-StartupTaskResult -Name MyTask -ResultFile $script:ResultFile -Timeout 0

			$result.Status | Should -Be 'Succeeded'
			$script:Sleeps | Should -Be 5
		}

		It "reads again when the file <Case>" -ForEach @(
			@{ Case = 'is half written'; Content = '{"Name":"MyTask","Sta' }
			@{ Case = 'is empty'; Content = '' }
			@{ Case = 'is not JSON'; Content = 'not a record' }
			@{ Case = 'holds a record without a status'; Content = '{"Name":"MyTask"}' }
		) {
			Set-Content -LiteralPath $script:ResultFile -Value $Content
			Mock Start-Sleep {
				$script:Sleeps++
				Set-Content -LiteralPath $script:ResultFile -Value '{"Name":"MyTask","Status":"Succeeded","Reason":""}'
			}
			$script:Result = $null

			{ $script:Result = Wait-StartupTaskResult -Name MyTask -ResultFile $script:ResultFile -Timeout 600 } | Should -Not -Throw

			$script:Result.Status | Should -Be 'Succeeded'
			$script:Sleeps | Should -Be 1
		}

		It "times out on a file that never becomes readable" {
			Set-Content -LiteralPath $script:ResultFile -Value '{"Name":"MyTask","Sta'

			(Wait-StartupTaskResult -Name MyTask -ResultFile $script:ResultFile -Timeout 1).Status | Should -Be 'TimedOut'
		}
	}
}
