#Requires -Modules Pester

BeforeAll {
	# Put back the configuration and the task-shell marker this file found.
	$script:SavedConfiguration = $global:Configuration
	$script:SavedTaskShell = $global:WinuXStartupTaskShell

	$ModuleRoot = (Get-RepositoryPath).Modules

	. "$ModuleRoot\Workflow\Functions\Invoke-StartupTasks.ps1"
	# Dot-sourced so they exist to Mock whatever the session's imported modules hold.
	. "$ModuleRoot\Workflow\Functions\Get-StartupTaskDefinitions.ps1"
	. "$ModuleRoot\Workflow\Functions\Invoke-StartupTask.ps1"
	. "$ModuleRoot\Workflow\Functions\Wait-StartupTaskResult.ps1"

	# A stand-in for the mock to attach to, so the real Task Scheduler is never asked.
	function Get-ScheduledTask {
		[CmdletBinding()]
		param($TaskPath, $TaskName)
	}

	# One definition as Get-StartupTaskDefinitions returns it, every default filled in.
	function New-TestStartupDefinition {
		param(
			[Parameter(Mandatory)][string]$Name,
			[string[]]$Trigger = @('SignIn'),
			[hashtable]$Options = @{},
			[bool]$Valid = $true,
			[bool]$InScope = $true
		)

		$parameters = @{
			Name          = $Name
			Command       = "Start-$Name"
			Requires      = @()
			Window        = 'Tab'
			KeepOpen      = 'OnFailure'
			Parallel      = $false
			Frequency     = 'EveryTime'
			DayStartHour  = 6
			IntervalHours = 24.0
			Elevation     = 'None'
			Timeout       = 600.0
			Enabled       = $true
		}
		foreach ($key in $Options.Keys) { $parameters[$key] = $Options[$key] }

		$errors = @()
		if (-not $Valid) { $errors = @('Unknown key [Colour]') }

		[pscustomobject]@{
			Name       = $Name
			Trigger    = $Trigger
			InScope    = $InScope
			Valid      = $Valid
			Errors     = $errors
			Legacy     = $false
			Parameters = $parameters
		}
	}
}

AfterAll {
	$global:Configuration = $script:SavedConfiguration
	if ($null -eq $script:SavedTaskShell) { Remove-Variable -Name WinuXStartupTaskShell -Scope Global -ErrorAction SilentlyContinue }
	else { $global:WinuXStartupTaskShell = $script:SavedTaskShell }
}

Describe "Invoke-StartupTasks" {
	BeforeEach {
		$script:LogsDir = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
		New-Item -ItemType Directory -Path $script:LogsDir -Force | Out-Null

		$script:Definitions = @()
		# What the mocked Invoke-StartupTask answers per task name (Succeeded when absent), and
		# what the mocked wait ends with.
		$script:Statuses = @{}
		$script:WaitStatuses = @{}
		$script:Calls = [System.Collections.Generic.List[object]]::new()
		$script:WaitCalls = [System.Collections.Generic.List[object]]::new()
		$script:Events = [System.Collections.Generic.List[string]]::new()
		$script:IsElevated = $false
		$script:ScheduledTask = $null
		$script:ReportCommand = $null
		$script:ScheduledTaskQuery = $null

		$global:Configuration = @{ Startup = @{ Conditions = @{ Network = @{ Test = '$true' } } } }
		Remove-Variable -Name WinuXStartupTaskShell -Scope Global -ErrorAction SilentlyContinue

		Mock Get-StartupTaskDefinitions { $script:Definitions }
		Mock Invoke-StartupTask {
			$bound = @{}
			foreach ($key in $PesterBoundParameters.Keys) { $bound[$key] = $PesterBoundParameters[$key] }
			$script:Calls.Add($bound)
			$script:Events.Add("run:$Name")

			$status = 'Succeeded'
			if ($bound.WhatIf) { $status = 'WouldRun' }
			elseif ($script:Statuses.ContainsKey($Name)) { $status = $script:Statuses[$Name] }

			[pscustomobject]@{
				Name       = $Name
				Status     = $status
				Reason     = "reason of $Name"
				Trigger    = $Trigger
				Window     = $Window
				Duration   = [timespan]::Zero
				ResultFile = (Join-Path $script:LogsDir ".startup-task-$Name.result")
			}
		}
		Mock Wait-StartupTaskResult {
			$script:WaitCalls.Add(@{ Name = $Name; ResultFile = $ResultFile; Timeout = $Timeout; StampFile = $StampFile })
			$script:Events.Add("wait:$Name")

			$status = 'Succeeded'
			if ($script:WaitStatuses.ContainsKey($Name)) { $status = $script:WaitStatuses[$Name] }

			[pscustomobject]@{ Name = $Name; Status = $status; Reason = "waited for $Name"; ResultFile = $ResultFile }
		}
		Mock Get-ScheduledTask {
			$script:ScheduledTaskQuery = @{ TaskPath = $TaskPath; TaskName = $TaskName }
			$script:ScheduledTask
		}
		Mock Open-Terminal { $script:ReportCommand = ($Command -join "`n") }
		Mock Restore-ShellPrompt { $true }
		Mock Test-AdminPrivileges { $script:IsElevated }
		Mock Get-LogPath { if ($Directory) { $script:LogsDir } else { Join-Path $script:LogsDir "Session.log" } }
		Mock Write-LogSuccess { }
		Mock Write-LogError { }
		Mock Write-LogWarning { }
		Mock Write-LogStep { }
		Mock Write-LogDebug { }
	}

	Context "which tasks run" {
		It "runs only the tasks that have the trigger, in configuration order" {
			$script:Definitions = @(
				New-TestStartupDefinition -Name C -Trigger SignIn
				New-TestStartupDefinition -Name A -Trigger Wake
				New-TestStartupDefinition -Name B -Trigger Wake, SignIn
				New-TestStartupDefinition -Name D -Trigger TerminalOpen
			)

			Invoke-StartupTasks -Trigger SignIn

			($script:Events -join ',') | Should -Be 'run:C,run:B'
		}

		It "reads the tasks at every run" {
			$script:Definitions = @(New-TestStartupDefinition -Name A -Trigger SignIn)
			Invoke-StartupTasks -Trigger SignIn

			$script:Definitions = @(New-TestStartupDefinition -Name B -Trigger SignIn)
			Invoke-StartupTasks -Trigger SignIn

			($script:Events -join ',') | Should -Be 'run:A,run:B'
			Should -Invoke Get-StartupTaskDefinitions -Times 2 -Exactly
		}

		It "hands each task its own options, the trigger and the configured conditions" {
			$script:Definitions = @(
				New-TestStartupDefinition -Name A -Trigger Wake -Options @{
					Command   = 'Open-Workspace MyWorkspace'
					Requires  = @('Network')
					Window    = 'Hidden'
					KeepOpen  = 'Never'
					Frequency = 'OncePerDay'
					Timeout   = 30.0
					Machine   = 'PC/Laptop'
				}
			)

			Invoke-StartupTasks -Trigger Wake

			$script:Calls.Count | Should -Be 1
			$call = $script:Calls[0]
			$call.Name | Should -Be 'A'
			$call.Command | Should -Be 'Open-Workspace MyWorkspace'
			($call.Requires -join ',') | Should -Be 'Network'
			$call.Window | Should -Be 'Hidden'
			$call.KeepOpen | Should -Be 'Never'
			[bool]$call.Parallel | Should -BeFalse
			$call.Frequency | Should -Be 'OncePerDay'
			$call.Timeout | Should -Be 30
			$call.Machine | Should -Be 'PC/Laptop'
			$call.Enabled | Should -BeTrue
			$call.Trigger | Should -Be 'Wake'
			$call.ConditionDefinitions.Contains('Network') | Should -BeTrue
			$call.ContainsKey('NoConditionWait') | Should -BeFalse
			$call.ContainsKey('Force') | Should -BeFalse
		}

		It "leaves the gates to Invoke-StartupTask: a disabled or out-of-scope task is handed on as it is" {
			$script:Definitions = @(
				New-TestStartupDefinition -Name Parked -Options @{ Enabled = $false }
				New-TestStartupDefinition -Name Elsewhere -InScope $false -Options @{ Hostname = @('Other-PC') }
			)

			Invoke-StartupTasks -Trigger SignIn

			$script:Calls.Count | Should -Be 2
			$script:Calls[0].Enabled | Should -BeFalse
			($script:Calls[1].Hostname -join ',') | Should -Be 'Other-PC'
		}

		It "runs only the tasks named by -Name" {
			$script:Definitions = @(
				New-TestStartupDefinition -Name A
				New-TestStartupDefinition -Name B
				New-TestStartupDefinition -Name C
			)

			Invoke-StartupTasks -Trigger SignIn -Name C, A

			($script:Events -join ',') | Should -Be 'run:A,run:C'
		}

		It "does not run a named task that lacks the trigger" {
			$script:Definitions = @(New-TestStartupDefinition -Name A -Trigger Wake)

			Invoke-StartupTasks -Trigger SignIn -Name A

			$script:Calls.Count | Should -Be 0
		}

		It "goes on with the next task after one that failed" {
			$script:Definitions = @(
				New-TestStartupDefinition -Name A
				New-TestStartupDefinition -Name B
			)
			$script:Statuses.A = 'Failed'

			Invoke-StartupTasks -Trigger SignIn

			($script:Events -join ',') | Should -Be 'run:A,run:B'
		}

		It "does nothing at all when no startup task is configured" {
			$script:Definitions = @()

			Invoke-StartupTasks -Trigger SignIn -PassThru -RedrawPrompt | Should -BeNullOrEmpty

			Should -Invoke Invoke-StartupTask -Times 0 -Exactly
			Should -Invoke Test-AdminPrivileges -Times 0 -Exactly
			Should -Invoke Open-Terminal -Times 0 -Exactly
			Should -Invoke Restore-ShellPrompt -Times 0 -Exactly
		}

		It "leaves the definitions it was given untouched" {
			$script:Definitions = @(New-TestStartupDefinition -Name A -Trigger TerminalOpen -Options @{ Parallel = $true; KeepOpen = 'Never' })

			Invoke-StartupTasks -Trigger TerminalOpen

			$parameters = $script:Definitions[0].Parameters
			$parameters.Window | Should -Be 'Tab'
			$parameters.KeepOpen | Should -Be 'Never'
			$parameters.Parallel | Should -BeTrue
			$parameters.ContainsKey('Trigger') | Should -BeFalse
			$parameters.ContainsKey('NoConditionWait') | Should -BeFalse
			$parameters.ContainsKey('ConditionDefinitions') | Should -BeFalse
		}

		It "only asks whether the shell is elevated, never for elevation" {
			$script:Definitions = @(New-TestStartupDefinition -Name A)

			Invoke-StartupTasks -Trigger SignIn

			Should -Invoke Test-AdminPrivileges -Times 0 -Exactly -ParameterFilter { -not $CheckOnly }
		}
	}

	Context "the TerminalOpen trigger" {
		It "runs every task in this shell, whatever its Window says, and never waits for a condition" {
			$script:Definitions = @(New-TestStartupDefinition -Name A -Trigger TerminalOpen -Options @{ Window = 'Hidden'; Requires = @('Network') })

			Invoke-StartupTasks -Trigger TerminalOpen

			$call = $script:Calls[0]
			$call.Window | Should -Be 'Current'
			[bool]$call.NoConditionWait | Should -BeTrue
			$call.Trigger | Should -Be 'TerminalOpen'
			($call.Requires -join ',') | Should -Be 'Network'
		}

		It "never hands on Parallel or KeepOpen" {
			$script:Definitions = @(New-TestStartupDefinition -Name A -Trigger TerminalOpen -Options @{ Parallel = $true; KeepOpen = 'Never' })

			Invoke-StartupTasks -Trigger TerminalOpen

			$script:Calls[0].ContainsKey('Parallel') | Should -BeFalse
			$script:Calls[0].ContainsKey('KeepOpen') | Should -BeFalse
		}

		It "hands Parallel and KeepOpen on for the <Trigger> trigger, and keeps the task's Window" -ForEach @(
			@{ Trigger = 'SignIn' }
			@{ Trigger = 'Unlock' }
			@{ Trigger = 'Wake' }
		) {
			$script:Definitions = @(New-TestStartupDefinition -Name A -Trigger $Trigger -Options @{ Parallel = $true; KeepOpen = 'Never'; Window = 'Hidden' })

			Invoke-StartupTasks -Trigger $Trigger

			$call = $script:Calls[0]
			[bool]$call.Parallel | Should -BeTrue
			$call.KeepOpen | Should -Be 'Never'
			$call.Window | Should -Be 'Hidden'
			$call.ContainsKey('NoConditionWait') | Should -BeFalse
		}

		It "returns at once in a shell that belongs to a startup task" {
			$global:WinuXStartupTaskShell = $true
			$script:Definitions = @(New-TestStartupDefinition -Name A -Trigger TerminalOpen)

			Invoke-StartupTasks -Trigger TerminalOpen -PassThru -RedrawPrompt | Should -BeNullOrEmpty

			Should -Invoke Get-StartupTaskDefinitions -Times 0 -Exactly
			Should -Invoke Invoke-StartupTask -Times 0 -Exactly
			Should -Invoke Restore-ShellPrompt -Times 0 -Exactly
		}

		It "still runs the <Trigger> tasks in a shell that belongs to a startup task" -ForEach @(
			@{ Trigger = 'SignIn' }
			@{ Trigger = 'Unlock' }
			@{ Trigger = 'Wake' }
		) {
			$global:WinuXStartupTaskShell = $true
			$script:Definitions = @(New-TestStartupDefinition -Name A -Trigger $Trigger)

			Invoke-StartupTasks -Trigger $Trigger

			Should -Invoke Invoke-StartupTask -Times 1 -Exactly
		}

		It "opens no report tab, even for a task that failed" {
			$script:Definitions = @(New-TestStartupDefinition -Name A -Trigger TerminalOpen)
			$script:Statuses.A = 'Failed'

			Invoke-StartupTasks -Trigger TerminalOpen

			Should -Invoke Open-Terminal -Times 0 -Exactly
			@(Get-ChildItem -LiteralPath $script:LogsDir -Force).Count | Should -Be 0
		}
	}

	Context "a task that is not valid" {
		It "is never run, and is reported as Failed" {
			$script:Definitions = @(
				New-TestStartupDefinition -Name Broken -Valid $false
				New-TestStartupDefinition -Name A
			)

			$results = @(Invoke-StartupTasks -Trigger SignIn -PassThru)

			($script:Events -join ',') | Should -Be 'run:A'
			$results.Count | Should -Be 2
			$results[0].Name | Should -Be 'Broken'
			$results[0].Status | Should -Be 'Failed'
			$results[0].Trigger | Should -Be 'SignIn'
			$results[1].Status | Should -Be 'Succeeded'
		}

		It "is reported at every trigger, since its own trigger cannot be trusted: <Trigger>" -ForEach @(
			@{ Trigger = 'SignIn' }
			@{ Trigger = 'Wake' }
			@{ Trigger = 'TerminalOpen' }
		) {
			$script:Definitions = @(New-TestStartupDefinition -Name Broken -Trigger @() -Valid $false)

			$results = @(Invoke-StartupTasks -Trigger $Trigger -PassThru)

			$results.Count | Should -Be 1
			$results[0].Status | Should -Be 'Failed'
			Should -Invoke Invoke-StartupTask -Times 0 -Exactly
		}

		It "is not reported when -Name names other tasks" {
			$script:Definitions = @(
				New-TestStartupDefinition -Name Broken -Valid $false
				New-TestStartupDefinition -Name A
			)

			$results = @(Invoke-StartupTasks -Trigger SignIn -Name A -PassThru)

			($results.Name -join ',') | Should -Be 'A'
			Should -Invoke Open-Terminal -Times 0 -Exactly
		}

		It "is shown in the shell that just opened, and the prompt is drawn again below it" {
			$script:Definitions = @(New-TestStartupDefinition -Name Broken -Trigger TerminalOpen -Valid $false)

			Invoke-StartupTasks -Trigger TerminalOpen -RedrawPrompt

			Should -Invoke Write-LogError -Times 1 -Exactly
			Should -Invoke Restore-ShellPrompt -Times 1 -Exactly
		}

		It "is listed in the report tab after a sign-in" {
			$script:Definitions = @(New-TestStartupDefinition -Name Broken -Valid $false)

			Invoke-StartupTasks -Trigger SignIn

			Should -Invoke Open-Terminal -Times 1 -Exactly
			Get-Content -LiteralPath (Join-Path $script:LogsDir ".startup-report-SignIn.txt") -Raw | Should -Match '\[Broken\]'
		}
	}

	Context "tasks that were started and left running" {
		It "collects a Started task after every task was started, and reports how it ended" {
			$script:Definitions = @(
				New-TestStartupDefinition -Name A -Options @{ Parallel = $true; Timeout = 30.0 }
				New-TestStartupDefinition -Name B
				New-TestStartupDefinition -Name C -Options @{ Parallel = $true; Timeout = 0.0 }
			)
			$script:Statuses.A = 'Started'
			$script:Statuses.C = 'Started'
			$script:WaitStatuses.C = 'Ended'

			$results = @(Invoke-StartupTasks -Trigger SignIn -PassThru)

			($script:Events -join ',') | Should -Be 'run:A,run:B,run:C,wait:A,wait:C'
			($results.Name -join ',') | Should -Be 'A,B,C'
			$results[0].Status | Should -Be 'Succeeded'
			$results[0].Reason | Should -Be 'waited for A'
			$results[1].Status | Should -Be 'Succeeded'
			$results[2].Status | Should -Be 'Ended'
			$results[0].Duration | Should -BeOfType [timespan]
		}

		It "waits on the task's own result file, up to its own Timeout, and names its stamp" {
			$script:Definitions = @(New-TestStartupDefinition -Name A -Options @{ Parallel = $true; Timeout = 30.0 })
			$script:Statuses.A = 'Started'

			Invoke-StartupTasks -Trigger SignIn

			$script:WaitCalls.Count | Should -Be 1
			$script:WaitCalls[0].Name | Should -Be 'A'
			$script:WaitCalls[0].ResultFile | Should -Be (Join-Path $script:LogsDir ".startup-task-A.result")
			$script:WaitCalls[0].Timeout | Should -Be 30
			$script:WaitCalls[0].StampFile | Should -Be (Join-Path $script:LogsDir ".startup-task-A.stamp")
		}

		It "waits for nothing when no task was left running" {
			$script:Definitions = @(New-TestStartupDefinition -Name A)

			Invoke-StartupTasks -Trigger SignIn

			Should -Invoke Wait-StartupTaskResult -Times 0 -Exactly
		}

		It "reports a started task that never answered as TimedOut, in the report tab too" {
			$script:Definitions = @(New-TestStartupDefinition -Name A -Options @{ Parallel = $true })
			$script:Statuses.A = 'Started'
			$script:WaitStatuses.A = 'TimedOut'

			$results = @(Invoke-StartupTasks -Trigger SignIn -PassThru)

			$results[0].Status | Should -Be 'TimedOut'
			Should -Invoke Open-Terminal -Times 1 -Exactly
		}
	}

	Context "a task with Elevation Silent" {
		BeforeEach {
			$script:Definitions = @(New-TestStartupDefinition -Name S -Options @{ Elevation = 'Silent' })
		}

		It "is Delegated, not run from here, when its own scheduled task exists" {
			$script:ScheduledTask = [pscustomobject]@{ TaskName = 'StartupTask-Silent-S-SignIn' }

			$results = @(Invoke-StartupTasks -Trigger SignIn -PassThru)

			$results.Count | Should -Be 1
			$results[0].Name | Should -Be 'S'
			$results[0].Status | Should -Be 'Delegated'
			Should -Invoke Invoke-StartupTask -Times 0 -Exactly
			Should -Invoke Open-Terminal -Times 0 -Exactly
		}

		It "looks for the scheduled task of this task and the <Trigger> trigger" -ForEach @(
			@{ Trigger = 'SignIn' }
			@{ Trigger = 'Unlock' }
			@{ Trigger = 'Wake' }
		) {
			$script:Definitions = @(New-TestStartupDefinition -Name S -Trigger $Trigger -Options @{ Elevation = 'Silent' })

			Invoke-StartupTasks -Trigger $Trigger

			Should -Invoke Get-ScheduledTask -Times 1 -Exactly
			$script:ScheduledTaskQuery.TaskPath | Should -Be '\WinuX\'
			$script:ScheduledTaskQuery.TaskName | Should -Be "StartupTask-Silent-S-$Trigger"
		}

		It "is Failed, and listed in the report tab, when its scheduled task is missing" {
			$script:ScheduledTask = $null

			$results = @(Invoke-StartupTasks -Trigger SignIn -PassThru)

			$results[0].Status | Should -Be 'Failed'
			Should -Invoke Invoke-StartupTask -Times 0 -Exactly
			Should -Invoke Open-Terminal -Times 1 -Exactly
			Get-Content -LiteralPath (Join-Path $script:LogsDir ".startup-report-SignIn.txt") -Raw | Should -Match '\[S\]'
		}

		It "runs like any other task when this shell is elevated: that is its scheduled task running it" {
			$script:IsElevated = $true

			$results = @(Invoke-StartupTasks -Trigger SignIn -PassThru)

			$results[0].Status | Should -Be 'Succeeded'
			$script:Calls.Count | Should -Be 1
			$script:Calls[0].Elevation | Should -Be 'Silent'
			Should -Invoke Get-ScheduledTask -Times 0 -Exactly
		}

		It "is handed to Invoke-StartupTask, which reports its gate, when it is <Case>" -ForEach @(
			@{ Case = 'not enabled'; InScope = $true; Enabled = $false }
			@{ Case = 'out of scope'; InScope = $false; Enabled = $true }
		) {
			$script:Definitions = @(New-TestStartupDefinition -Name S -InScope $InScope -Options @{ Elevation = 'Silent'; Enabled = $Enabled })

			Invoke-StartupTasks -Trigger SignIn

			$script:Calls.Count | Should -Be 1
			Should -Invoke Get-ScheduledTask -Times 0 -Exactly
		}

		It "is rehearsed like any other task with -WhatIf" {
			$results = @(Invoke-StartupTasks -Trigger SignIn -WhatIf)

			$results[0].Status | Should -Be 'WouldRun'
			Should -Invoke Get-ScheduledTask -Times 0 -Exactly
		}

		It "does not hold up the other tasks" {
			$script:Definitions = @(
				New-TestStartupDefinition -Name S -Options @{ Elevation = 'Silent' }
				New-TestStartupDefinition -Name A
			)
			$script:ScheduledTask = [pscustomobject]@{ TaskName = 'StartupTask-Silent-S-SignIn' }

			$results = @(Invoke-StartupTasks -Trigger SignIn -PassThru)

			($results.Status -join ',') | Should -Be 'Delegated,Succeeded'
			($script:Events -join ',') | Should -Be 'run:A'
		}
	}

	Context "the failure report" {
		It "opens one tab in the startup window after a task that ended as <Status>" -ForEach @(
			@{ Status = 'Failed' }
			@{ Status = 'Skipped' }
			@{ Status = 'TimedOut' }
		) {
			$script:Definitions = @(
				New-TestStartupDefinition -Name Fine
				New-TestStartupDefinition -Name Trouble
			)
			$script:Statuses.Trouble = $Status

			Invoke-StartupTasks -Trigger SignIn

			Should -Invoke Open-Terminal -Times 1 -Exactly
			Should -Invoke Open-Terminal -Times 1 -Exactly -ParameterFilter { $WindowId -eq 'WinuXStartup' }

			# The tab shows the report file, which lists the task that did not finish and no other.
			$reportFile = Join-Path $script:LogsDir ".startup-report-SignIn.txt"
			$reportFile | Should -Exist
			$script:ReportCommand.Contains($reportFile) | Should -BeTrue
			$report = Get-Content -LiteralPath $reportFile -Raw
			$report | Should -Match '\[Trouble\]'
			$report | Should -Not -Match '\[Fine\]'
		}

		It "opens one tab however many tasks did not finish" {
			$script:Definitions = @(
				New-TestStartupDefinition -Name A
				New-TestStartupDefinition -Name B
			)
			$script:Statuses.A = 'Failed'
			$script:Statuses.B = 'Skipped'

			Invoke-StartupTasks -Trigger SignIn

			Should -Invoke Open-Terminal -Times 1 -Exactly
			$report = Get-Content -LiteralPath (Join-Path $script:LogsDir ".startup-report-SignIn.txt") -Raw
			$report | Should -Match '\[A\]'
			$report | Should -Match '\[B\]'
		}

		It "names the report after the trigger: <Trigger>" -ForEach @(
			@{ Trigger = 'Unlock' }
			@{ Trigger = 'Wake' }
		) {
			$script:Definitions = @(New-TestStartupDefinition -Name A -Trigger $Trigger)
			$script:Statuses.A = 'Failed'

			Invoke-StartupTasks -Trigger $Trigger

			Join-Path $script:LogsDir ".startup-report-$Trigger.txt" | Should -Exist
		}

		It "opens no tab after a task that ended as <Status>" -ForEach @(
			@{ Status = 'Succeeded' }
			@{ Status = 'Ended' }
			@{ Status = 'NotDue' }
			@{ Status = 'Disabled' }
			@{ Status = 'OutOfScope' }
			@{ Status = 'AlreadyRunning' }
			@{ Status = 'HandedOff' }
		) {
			$script:Definitions = @(New-TestStartupDefinition -Name A)
			$script:Statuses.A = $Status

			Invoke-StartupTasks -Trigger SignIn

			Should -Invoke Open-Terminal -Times 0 -Exactly
			@(Get-ChildItem -LiteralPath $script:LogsDir -Force).Count | Should -Be 0
		}

		It "opens no tab when Startup.FailureReport is None, in any casing: <Value>" -ForEach @(
			@{ Value = 'None' }
			@{ Value = 'none' }
		) {
			$global:Configuration.Startup.FailureReport = $Value
			$script:Definitions = @(New-TestStartupDefinition -Name A)
			$script:Statuses.A = 'Failed'

			Invoke-StartupTasks -Trigger SignIn

			Should -Invoke Open-Terminal -Times 0 -Exactly
			@(Get-ChildItem -LiteralPath $script:LogsDir -Force).Count | Should -Be 0
		}

		It "opens the tab when Startup.FailureReport is Tab" {
			$global:Configuration.Startup.FailureReport = 'Tab'
			$script:Definitions = @(New-TestStartupDefinition -Name A)
			$script:Statuses.A = 'Failed'

			Invoke-StartupTasks -Trigger SignIn

			Should -Invoke Open-Terminal -Times 1 -Exactly
		}

		It "does not throw, and still returns the results, when the tab cannot be opened" {
			Mock Open-Terminal { throw "Windows Terminal is not installed" }
			$script:Definitions = @(New-TestStartupDefinition -Name A)
			$script:Statuses.A = 'Failed'
			$script:Returned = $null

			{ $script:Returned = @(Invoke-StartupTasks -Trigger SignIn -PassThru) } | Should -Not -Throw

			$script:Returned.Count | Should -Be 1
			$script:Returned[0].Status | Should -Be 'Failed'
		}
	}

	Context "-RedrawPrompt" {
		It "draws the prompt again after an inline task that ended as <Status>" -ForEach @(
			@{ Status = 'Succeeded' }
			@{ Status = 'Failed' }
			@{ Status = 'HandedOff' }
			@{ Status = 'Ended' }
		) {
			$script:Definitions = @(New-TestStartupDefinition -Name A -Trigger TerminalOpen)
			$script:Statuses.A = $Status

			Invoke-StartupTasks -Trigger TerminalOpen -RedrawPrompt

			Should -Invoke Restore-ShellPrompt -Times 1 -Exactly
		}

		It "does not draw the prompt again after an inline task that ended as <Status>: nothing was printed" -ForEach @(
			@{ Status = 'NotDue' }
			@{ Status = 'Skipped' }
			@{ Status = 'Disabled' }
			@{ Status = 'OutOfScope' }
			@{ Status = 'AlreadyRunning' }
		) {
			$script:Definitions = @(New-TestStartupDefinition -Name A -Trigger TerminalOpen)
			$script:Statuses.A = $Status

			Invoke-StartupTasks -Trigger TerminalOpen -RedrawPrompt

			Should -Invoke Invoke-StartupTask -Times 1 -Exactly
			Should -Invoke Restore-ShellPrompt -Times 0 -Exactly
		}

		It "draws the prompt once when one task of several ran" {
			$script:Definitions = @(
				New-TestStartupDefinition -Name A -Trigger TerminalOpen
				New-TestStartupDefinition -Name B -Trigger TerminalOpen
				New-TestStartupDefinition -Name C -Trigger TerminalOpen
			)
			$script:Statuses.A = 'NotDue'
			$script:Statuses.C = 'Skipped'

			Invoke-StartupTasks -Trigger TerminalOpen -RedrawPrompt

			Should -Invoke Restore-ShellPrompt -Times 1 -Exactly
		}

		It "never draws the prompt again without the switch" {
			$script:Definitions = @(New-TestStartupDefinition -Name A -Trigger TerminalOpen)

			Invoke-StartupTasks -Trigger TerminalOpen

			Should -Invoke Invoke-StartupTask -Times 1 -Exactly
			Should -Invoke Restore-ShellPrompt -Times 0 -Exactly
		}

		It "never draws the prompt again when no task has the trigger" {
			$script:Definitions = @(New-TestStartupDefinition -Name A -Trigger SignIn)

			Invoke-StartupTasks -Trigger TerminalOpen -RedrawPrompt

			Should -Invoke Restore-ShellPrompt -Times 0 -Exactly
		}

		It "never draws a prompt for the <Trigger> trigger, whose runner has no window" -ForEach @(
			@{ Trigger = 'SignIn' }
			@{ Trigger = 'Wake' }
		) {
			$script:Definitions = @(New-TestStartupDefinition -Name A -Trigger $Trigger)

			Invoke-StartupTasks -Trigger $Trigger -RedrawPrompt

			Should -Invoke Invoke-StartupTask -Times 1 -Exactly
			Should -Invoke Restore-ShellPrompt -Times 0 -Exactly
		}
	}

	Context "-PassThru" {
		It "returns nothing without it" {
			$script:Definitions = @(New-TestStartupDefinition -Name A)
			$script:Statuses.A = 'Failed'

			Invoke-StartupTasks -Trigger SignIn | Should -BeNullOrEmpty
		}

		It "returns one result per task, in the order they ran" {
			$script:Definitions = @(
				New-TestStartupDefinition -Name B
				New-TestStartupDefinition -Name A
				New-TestStartupDefinition -Name Other -Trigger Wake
			)
			$script:Statuses.A = 'NotDue'

			$results = @(Invoke-StartupTasks -Trigger SignIn -PassThru)

			($results.Name -join ',') | Should -Be 'B,A'
			($results.Status -join ',') | Should -Be 'Succeeded,NotDue'
			$results[0].Trigger | Should -Be 'SignIn'
		}
	}

	Context "-WhatIf" {
		It "rehearses every task and returns what would happen, without -PassThru" {
			$script:Definitions = @(
				New-TestStartupDefinition -Name A
				New-TestStartupDefinition -Name B
			)

			$results = @(Invoke-StartupTasks -Trigger SignIn -WhatIf)

			($results.Name -join ',') | Should -Be 'A,B'
			($results.Status -join ',') | Should -Be 'WouldRun,WouldRun'
			$script:Calls.Count | Should -Be 2
			[bool]$script:Calls[0].WhatIf | Should -BeTrue
			[bool]$script:Calls[1].WhatIf | Should -BeTrue
		}

		It "does not rehearse a real run" {
			$script:Definitions = @(New-TestStartupDefinition -Name A)

			Invoke-StartupTasks -Trigger SignIn

			[bool]$script:Calls[0].WhatIf | Should -BeFalse
		}

		It "rehearses the TerminalOpen trigger the same way, and draws no prompt" {
			$script:Definitions = @(New-TestStartupDefinition -Name A -Trigger TerminalOpen)

			$results = @(Invoke-StartupTasks -Trigger TerminalOpen -RedrawPrompt -WhatIf)

			$results[0].Status | Should -Be 'WouldRun'
			$script:Calls[0].Window | Should -Be 'Current'
			Should -Invoke Restore-ShellPrompt -Times 0 -Exactly
		}

		It "opens no report tab and writes no report, even for a task that is not valid" {
			$script:Definitions = @(
				New-TestStartupDefinition -Name Broken -Valid $false
				New-TestStartupDefinition -Name A
			)

			$results = @(Invoke-StartupTasks -Trigger SignIn -WhatIf)

			($results.Status -join ',') | Should -Be 'Failed,WouldRun'
			Should -Invoke Open-Terminal -Times 0 -Exactly
			Should -Invoke Wait-StartupTaskResult -Times 0 -Exactly
			@(Get-ChildItem -LiteralPath $script:LogsDir -Force).Count | Should -Be 0
		}
	}
}
