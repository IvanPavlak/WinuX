function Invoke-StartupTask {
	<#
	.SYNOPSIS
		Runs one startup task: any command, with conditions, a frequency, a window and an elevation.

	.DESCRIPTION
		The generic runner behind startup tasks. Every option of a `Startup.Tasks` entry is a
		parameter here, so an entry is exactly a set of parameters for this function, and the
		same call works by hand:

		  Invoke-StartupTask -Name MyUpdate -Command "Update-Repositories -All -NoClone -Quiet" -Requires Network -Frequency OncePerDay

		Called with a -Name and no -Command, it runs the configured task of that name
		(Get-StartupTaskDefinitions) in the current shell; parameters given on the command line
		win over the entry's.

		What happens, in order:

		1. Gates. A task with -Enabled:$false is Disabled, one whose -Machine or -Hostname does
		   not cover this machine is OutOfScope, one whose -Frequency says it already ran is
		   NotDue (Test-StartupTaskDue). -Force passes the Enabled and frequency gates, never the
		   scope.
		2. Where. -Window Current (default) runs the task in this shell. Tab or Hidden starts a
		   shell for it (Start-StartupTaskShell), which runs this function again inline, and
		   waits for its result up to -Timeout seconds (Wait-StartupTaskResult) - or, with
		   -Parallel, returns at once with the status Started.
		3. The inline run takes the task's lock (Logs\.startup-task-<Name>.lock, held open for
		   the whole run, so the same task never runs twice at once: the loser is
		   AlreadyRunning), checks the frequency again under it, waits for every -Requires
		   condition (Test-StartupCondition; one that is not met in time makes the task Skipped)
		   and runs -Command. With -NoConditionWait each condition is tested once and a task
		   whose condition is not met is skipped without a word - what a newly opened terminal
		   does, so a shell opened offline is never held up.
		4. The command runs as typed at a prompt, so aliases and functions work. It has Failed
		   when it throws; errors it only writes do not count. Its `$LASTEXITCODE` never leaks
		   into the calling shell.
		5. Only a run that Succeeded writes the stamp (Logs\.startup-task-<Name>.stamp) the
		   frequency is measured from, so a failed or skipped task is due again at the next
		   trigger. A task that closes its own shell counts as finished (status Ended) and its
		   stamp is written by the waiting side.

		Elevation. With -Elevation None (default) the task runs unelevated, and a command that
		asks for Administrator privileges through Test-AdminPrivileges fails at once with a
		message naming this parameter, instead of showing a question nobody is there to answer.
		Relaunch lets that request through: the task starts again in an Administrator tab
		(Windows asks for consent) and this run ends as HandedOff. Either way Test-AdminPrivileges
		stops the pipeline it was called from, as it always does: the task's result file, stamp
		and lock are settled first, but an inline run returns nothing and whatever called it
		stops with it. A task in its own tab or hidden shell is unaffected - only that shell
		stops, and the result file tells the waiting side. Prompt starts the task's shell
		elevated from the beginning, one consent dialog, and tracks it like any other. Silent is
		Prompt without the dialog, and only when Set-StartupTasks registered the task's own
		elevated scheduled task; started any other way it asks like Prompt.

	.PARAMETER Name
		The task's name: letters, digits, `-` and `_`. Names its stamp, lock and result files.

	.PARAMETER Command
		The command line to run. Without one the task only passes its gates and conditions - in
		a tab, that is a plain terminal.

	.PARAMETER Trigger
		What caused this run: Manual (default), SignIn, Unlock, Wake or TerminalOpen. Reported in
		the result.

	.PARAMETER Machine
		Machine scope ("PC/Laptop") the task is limited to.

	.PARAMETER Hostname
		Computer names the task is limited to.

	.PARAMETER Requires
		Names of the conditions to wait for before the command runs.

	.PARAMETER ConditionDefinitions
		The conditions -Requires names: name => @{ Test; Timeout; Interval }. Defaults to
		`Startup.Conditions`.

	.PARAMETER NoConditionWait
		Test each -Requires condition once instead of waiting for it, and skip quietly when one
		is not met.

	.PARAMETER Window
		Current (default), Tab or Hidden.

	.PARAMETER KeepOpen
		OnFailure (default), Always or Never: whether a Tab stays open when the task is over.

	.PARAMETER Parallel
		With Tab or Hidden: return as soon as the shell is started.

	.PARAMETER Frequency
		EveryTime (default), OncePerBoot, OncePerDay or Interval.

	.PARAMETER DayStartHour
		The hour (0-23) a new day starts, for OncePerDay. Default 6.

	.PARAMETER IntervalHours
		Minimum hours between two successful runs, for Interval. Default 24.

	.PARAMETER Elevation
		None (default), Relaunch, Prompt or Silent.

	.PARAMETER Timeout
		Seconds to wait for a Tab or Hidden run. Default 600; 0 waits without limit.

	.PARAMETER Enabled
		$false parks the task.

	.PARAMETER Force
		Run even when the task is disabled or not due.

	.PARAMETER ResultFile
		Where an inline run reports to the shell that started it. Set by Start-StartupTaskShell.

	.OUTPUTS
		[pscustomobject] with Name, Status, Reason, Trigger, Window, Duration and ResultFile.
		Status is one of Succeeded, Failed, Skipped, TimedOut, Ended, Started, HandedOff, NotDue,
		OutOfScope, Disabled, AlreadyRunning or, with -WhatIf, WouldRun.

	.EXAMPLE
		Invoke-StartupTask -Name MyWorkspace -Command "Open-Workspace MyWorkspace" -Requires MyVpn -Window Tab
		Opens a tab, waits there for MyVpn, opens the workspace and closes the tab.

	.EXAMPLE
		Invoke-StartupTask RepositoryUpdate -Force
		Runs the configured RepositoryUpdate task here and now, whatever its frequency says.

	.EXAMPLE
		Invoke-StartupTask -Name MyCleanup -Command "Clear-MyCache" -Window Hidden -Frequency Interval -IntervalHours 4 -WhatIf
		Says whether MyCleanup would run now, and runs nothing.
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	[OutputType([pscustomobject])]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]*$')]
		[string]$Name,

		[Parameter(Position = 1)]
		[AllowEmptyString()]
		[AllowNull()]
		[string]$Command,

		[Parameter()]
		[ValidateSet('Manual', 'SignIn', 'Unlock', 'Wake', 'TerminalOpen')]
		[string]$Trigger = 'Manual',

		[Parameter()]
		[string]$Machine,

		[Parameter()]
		[AllowNull()]
		[AllowEmptyCollection()]
		[string[]]$Hostname,

		[Parameter()]
		[AllowNull()]
		[AllowEmptyCollection()]
		[string[]]$Requires,

		[Parameter()]
		[AllowNull()]
		[System.Collections.IDictionary]$ConditionDefinitions,

		[Parameter()]
		[switch]$NoConditionWait,

		[Parameter()]
		[ValidateSet('Current', 'Tab', 'Hidden')]
		[string]$Window = 'Current',

		[Parameter()]
		[ValidateSet('OnFailure', 'Always', 'Never')]
		[string]$KeepOpen = 'OnFailure',

		[Parameter()]
		[switch]$Parallel,

		[Parameter()]
		[ValidateSet('EveryTime', 'OncePerBoot', 'OncePerDay', 'Interval')]
		[string]$Frequency = 'EveryTime',

		[Parameter()]
		[ValidateRange(0, 23)]
		[int]$DayStartHour = 6,

		[Parameter()]
		[double]$IntervalHours = 24,

		[Parameter()]
		[ValidateSet('None', 'Relaunch', 'Prompt', 'Silent')]
		[string]$Elevation = 'None',

		[Parameter()]
		[double]$Timeout = 600,

		[Parameter()]
		[bool]$Enabled = $true,

		[Parameter()]
		[switch]$Force,

		[Parameter()]
		[string]$ResultFile
	)

	$started = Get-Date

	# The record the shell that started this one waits on (Wait-StartupTaskResult). Written by
	# every exit of an inline run, so the waiting side never waits for a task that will not run.
	$writeRecord = {
		param([string]$RecordStatus, [string]$RecordReason)

		if (-not $ResultFile) { return }
		try {
			$record = [ordered]@{
				Name                = $Name
				Status              = $RecordStatus
				Reason              = $RecordReason
				ProcessId           = $PID
				ProcessStartedTicks = (Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks
				Updated             = (Get-Date -Format 'o')
			}
			Set-Content -LiteralPath $ResultFile -Value (ConvertTo-Json -InputObject $record -Compress) -Encoding UTF8 -Force -ErrorAction Stop
		}
		catch {
			Write-LogDebug " [Invoke-StartupTask] Could not write the result of [$Name] => $($_.Exception.Message)" -Style Warning
		}
	}

	$newResult = {
		param([string]$ResultStatus, [string]$ResultReason)

		[pscustomobject]@{
			Name       = $Name
			Status     = $ResultStatus
			Reason     = $ResultReason
			Trigger    = $Trigger
			Window     = $Window
			Duration   = (Get-Date) - $started
			ResultFile = $ResultFile
		}
	}

	# By name alone: the configured task supplies what the command line left out. Where it
	# runs stays the caller's choice - a task typed at a prompt runs in that shell.
	if (-not $PSBoundParameters.ContainsKey('Command')) {
		$includeLegacy = ($Name -eq 'RepositoryUpdate' -and $Force)
		$definition = @(Get-StartupTaskDefinitions -Name $Name -IncludeLegacyDisabled:$includeLegacy) | Select-Object -First 1
		if ($definition) {
			if (-not $definition.Valid) {
				$problem = "The configured task is not valid: $($definition.Errors -join '; ')"
				Write-LogError "Startup task [$Name] did not run - $problem"
				return (& $newResult 'Failed' $problem)
			}
			foreach ($key in @($definition.Parameters.Keys)) {
				if ($key -in 'Window', 'KeepOpen', 'Parallel') { continue }
				if (-not $PSBoundParameters.ContainsKey($key)) {
					Set-Variable -Name $key -Value $definition.Parameters[$key]
				}
			}
		}
		else {
			$problem = "No startup task named [$Name] is configured - pass -Command, or add it to Startup.Tasks"
			Write-LogError "Startup task [$Name] did not run - $problem"
			return (& $newResult 'Failed' $problem)
		}
	}

	$logsDirectory = Get-LogPath -Directory
	if (-not (Test-Path -LiteralPath $logsDirectory)) {
		New-Item -ItemType Directory -Path $logsDirectory -Force | Out-Null
	}
	$stampFile = Join-Path $logsDirectory ".startup-task-$Name.stamp"
	$lockFile = Join-Path $logsDirectory ".startup-task-$Name.lock"
	$dueArguments = @{
		StampFile     = $stampFile
		Frequency     = $Frequency
		DayStartHour  = $DayStartHour
		IntervalHours = $IntervalHours
	}

	# Gates: cheap, and the same in the shell that starts a task and in the shell that runs it.
	$gate = $null
	$hostnames = @($Hostname | Where-Object { $_ })
	if (-not $Enabled -and -not $Force) {
		$gate = 'Disabled', 'The task is not enabled'
	}
	elseif ($Machine -and -not (Test-MachineTypeScope -Scope $Machine -Context "Startup task [$Name]")) {
		$gate = 'OutOfScope', "Machine [$Machine] does not cover this machine type [$global:MachineType]"
	}
	elseif ($hostnames.Count -gt 0 -and $hostnames -notcontains $env:COMPUTERNAME) {
		$gate = 'OutOfScope', "Hostname [$($hostnames -join ', ')] does not name this computer [$env:COMPUTERNAME]"
	}
	elseif (-not $Force -and -not (Test-StartupTaskDue @dueArguments)) {
		$gate = 'NotDue', "Already ran ($Frequency)"
	}

	if ($gate) {
		& $writeRecord $gate[0] $gate[1]
		return (& $newResult $gate[0] $gate[1])
	}

	$conditionSource = $ConditionDefinitions
	if ($null -eq $conditionSource) {
		$conditionSource = Get-ConfigSetting -Path 'Startup.Conditions' -Default @{}
	}
	$required = @($Requires | Where-Object { $_ })

	if (-not $PSCmdlet.ShouldProcess("startup task [$Name]", "Run ($Window)")) {
		$unmet = @($required | Where-Object { -not (Test-StartupCondition -Name $_ -Definitions $conditionSource -NoWait) })
		$note = if ($unmet.Count -gt 0) { "Would wait for: $($unmet -join ', ')" } else { '' }
		return (& $newResult 'WouldRun' $note)
	}

	# An elevated run needs an elevated shell; an inline one cannot become elevated, so it
	# moves to a tab.
	$isElevated = [bool](Test-AdminPrivileges -CheckOnly)
	$needsElevatedShell = ($Elevation -in 'Prompt', 'Silent') -and -not $isElevated
	if ($Window -eq 'Current' -and $needsElevatedShell) { $Window = 'Tab' }

	if ($Window -ne 'Current') {
		if (-not $ResultFile) { $ResultFile = Join-Path $logsDirectory ".startup-task-$Name.result" }

		# The new shell gets the conditions it needs with the task, so it reads nothing but
		# its own parameters.
		$conditions = @{}
		foreach ($requiredName in $required) {
			foreach ($key in @($conditionSource.Keys)) {
				if ([string]$key -eq $requiredName) { $conditions[$requiredName] = $conditionSource[$key] }
			}
		}

		$childElevation = if ($Elevation -eq 'Relaunch') { 'Relaunch' } else { 'None' }
		$childArguments = @{
			Name                 = $Name
			Command              = [string]$Command
			Trigger              = $Trigger
			Requires             = $required
			ConditionDefinitions = $conditions
			Window               = 'Current'
			Frequency            = $Frequency
			DayStartHour         = $DayStartHour
			IntervalHours        = $IntervalHours
			Elevation            = $childElevation
			Force                = [bool]$Force
			ResultFile           = $ResultFile
		}

		try {
			if (Test-Path -LiteralPath $ResultFile) { Remove-Item -LiteralPath $ResultFile -Force -ErrorAction Stop }
			Start-StartupTaskShell -Name $Name -Arguments $childArguments -Window $Window -KeepOpen $KeepOpen -Administrator:$needsElevatedShell
		}
		catch {
			Write-LogError "Startup task [$Name] could not be started => $($_.Exception.Message)" -Exception $_
			return (& $newResult 'Failed' "Could not start its shell: $($_.Exception.Message)")
		}

		if ($Parallel) {
			return (& $newResult 'Started' '')
		}

		$waited = Wait-StartupTaskResult -Name $Name -ResultFile $ResultFile -Timeout $Timeout -StampFile $stampFile
		return (& $newResult $waited.Status $waited.Reason)
	}

	# Inline run.
	$status = 'Failed'
	$reason = ''
	$lock = $null
	try {
		do {
			# One run at a time, whichever trigger or shell asks. The holder keeps the lock file
			# open with no sharing, so Windows refuses to delete it while that shell lives; a
			# lock that CAN be deleted was left by a shell that died mid-run.
			if (Test-Path -LiteralPath $lockFile) {
				try { Remove-Item -LiteralPath $lockFile -Force -ErrorAction Stop }
				catch {
					$status = 'AlreadyRunning'
					$reason = 'Another shell is running this task'
					break
				}
			}
			try {
				$lock = [System.IO.File]::Open($lockFile, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
			}
			catch [System.IO.IOException] {
				$status = 'AlreadyRunning'
				$reason = 'Another shell is running this task'
				break
			}
			catch {
				$status = 'Failed'
				$reason = "Could not take the task's lock: $($_.Exception.Message)"
				break
			}

			# Again under the lock: another shell may have finished a run in between.
			if (-not $Force -and -not (Test-StartupTaskDue @dueArguments)) {
				$status = 'NotDue'
				$reason = "Already ran ($Frequency)"
				break
			}

			& $writeRecord 'Running' ''
			if ($ResultFile) { Write-LogStep "Startup task [$Name]" }

			$unmetCondition = $null
			foreach ($requiredName in $required) {
				if (-not (Test-StartupCondition -Name $requiredName -Definitions $conditionSource -NoWait:$NoConditionWait)) {
					$unmetCondition = $requiredName
					break
				}
			}
			if ($unmetCondition) {
				$status = 'Skipped'
				if ($NoConditionWait) {
					$reason = "Condition [$unmetCondition] is not met"
					Write-LogDebug " [Invoke-StartupTask] [$Name] skipped - $reason"
				}
				else {
					$reason = "Condition [$unmetCondition] was not met in time"
					Write-LogWarning "Startup task [$Name] skipped - $reason"
				}
				break
			}

			if ([string]::IsNullOrWhiteSpace($Command)) {
				$status = 'Succeeded'
				break
			}

			# What Test-AdminPrivileges reads while the command runs: without Relaunch a request
			# for Administrator privileges fails at once; with it, this text is what starts again
			# in the Administrator tab - self-contained, and forced, since the gates are behind us.
			$context = @{ Name = $Name; Elevation = $Elevation }
			if ($Elevation -eq 'Relaunch') {
				# One line (the statements are joined with ";"): Test-AdminPrivileges logs it. The
				# Administrator tab it opens stays open afterwards, like any elevated rerun.
				$context.RelaunchCommand = (New-StartupTaskShellCommand -TaskShell -Arguments @{
						Name    = $Name
						Command = [string]$Command
						Trigger = $Trigger
						Window  = 'Current'
						Force   = $true
					}) -replace "`r?`n", '; '
			}

			$exitCode = $global:LASTEXITCODE
			$completed = $false
			try {
				$scriptBlock = [scriptblock]::Create($Command)
				$global:WinuXStartupTask = $context
				& $scriptBlock | Out-Host
				$completed = $true
				$status = 'Succeeded'
			}
			catch {
				# A stopped pipeline (Test-AdminPrivileges refusing or relaunching, Ctrl+C) never
				# arrives here: PowerShell runs no catch for it. It goes on up and stops the caller
				# too; the finally below records what it meant before that happens.
				$completed = $true
				$status = 'Failed'
				$reason = $_.Exception.Message
				Write-LogError "Startup task [$Name] failed => $($_.Exception.Message)" -Exception $_
			}
			finally {
				$global:LASTEXITCODE = $exitCode
				Remove-Variable -Name WinuXStartupTask -Scope Global -ErrorAction SilentlyContinue
				if (-not $completed) {
					if ($Elevation -eq 'Relaunch') {
						$status = 'HandedOff'
						$reason = 'The command asked for Administrator privileges and was started again in an Administrator tab'
					}
					else {
						$status = 'Failed'
						$reason = 'The command was stopped before it finished (it asked for Administrator privileges, or was interrupted)'
					}
				}
			}
		} while ($false)
	}
	finally {
		if ($status -eq 'Succeeded') {
			try { Set-Content -LiteralPath $stampFile -Value (Get-Date -Format 'o') -Encoding UTF8 -Force -ErrorAction Stop }
			catch { Write-LogDebug " [Invoke-StartupTask] Could not write the stamp of [$Name] => $($_.Exception.Message)" -Style Warning }
		}
		if ($lock) {
			$lock.Dispose()
			Remove-Item -LiteralPath $lockFile -Force -ErrorAction SilentlyContinue
		}
		& $writeRecord $status $reason
	}

	return (& $newResult $status $reason)
}
