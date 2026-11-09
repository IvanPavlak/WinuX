function Invoke-StartupTasks {
	<#
	.SYNOPSIS
		Runs the configured startup tasks of one trigger: sign-in, unlock, wake or a newly opened terminal.

	.DESCRIPTION
		The runner Windows and the profile call. It reads `Startup.Tasks`
		(Get-StartupTaskDefinitions), takes the tasks that have -Trigger, in the order they are
		written, and hands each to Invoke-StartupTask with the entry's own options. The list is
		read at every run, so an edited configuration takes effect at the next trigger with
		nothing to register again.

		- SignIn, Unlock, Wake: started by the scheduled tasks Set-StartupTasks registers, in a
		  shell with no window. Each task runs in its own tab or hidden shell. The runner waits
		  for a task before it starts the next (up to the task's Timeout), except one marked
		  `Parallel`, which is started and collected at the end. One task failing never stops
		  the next.
		- TerminalOpen: started by the profile once the first prompt is drawn. Every task runs
		  inline, in that shell, whatever its Window says, and prints under the prompt;
		  -RedrawPrompt draws the prompt again below the output when anything ran. A condition
		  is tested once, never waited for: a task whose condition is not met is skipped
		  silently and, having written no stamp, is due again in the next shell. Nothing runs
		  in a shell that itself belongs to a startup task.

		A task with `Elevation = "Silent"` is not run from here on SignIn, Unlock or Wake: its
		own elevated scheduled task does (see Set-StartupTasks). It is listed as Delegated, or as
		Failed when that scheduled task is missing.

		A task that is not valid is reported at every run and never started. After a SignIn,
		Unlock or Wake run in which a task failed, was skipped for a condition or timed out, one
		terminal tab opens with the list - unless `Startup.FailureReport` is "None". Every line
		is also in the session log (Get-LogPath).

		-WhatIf runs nothing and returns, per task, what would happen now: WouldRun (with the
		conditions it would wait for), NotDue, OutOfScope or Disabled. It is the way to rehearse
		a trigger without signing out.

	.PARAMETER Trigger
		SignIn, Unlock, Wake or TerminalOpen.

	.PARAMETER Name
		Run only the tasks with these names.

	.PARAMETER RedrawPrompt
		After a TerminalOpen run that printed something, draw the prompt again below it.

	.PARAMETER PassThru
		Return one result object per task. -WhatIf returns them without it.

	.OUTPUTS
		None, or with -PassThru / -WhatIf one [pscustomobject] per task: Name, Status, Reason,
		Trigger, Window, Duration, ResultFile.

	.EXAMPLE
		Invoke-StartupTasks -Trigger SignIn -WhatIf
		Lists what the next sign-in would run on this machine, and why the rest would not.

	.EXAMPLE
		Invoke-StartupTasks -Trigger SignIn
		Runs the sign-in tasks now, exactly as the scheduled task does.

	.EXAMPLE
		Invoke-StartupTasks -Trigger TerminalOpen -Name RepositoryUpdate -PassThru
		Runs only RepositoryUpdate, if it is due, and returns its result.
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	[OutputType([pscustomobject])]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[ValidateSet('SignIn', 'Unlock', 'Wake', 'TerminalOpen')]
		[string]$Trigger,

		[Parameter()]
		[string[]]$Name,

		[Parameter()]
		[switch]$RedrawPrompt,

		[Parameter()]
		[switch]$PassThru
	)

	$inline = $Trigger -eq 'TerminalOpen'

	# A shell a startup task runs in is not a newly opened terminal.
	if ($inline -and $global:WinuXStartupTaskShell) { return }

	$definitions = @(Get-StartupTaskDefinitions)
	if ($definitions.Count -eq 0) { return }

	$rehearsal = [bool]$WhatIfPreference
	$conditions = Get-ConfigSetting -Path 'Startup.Conditions' -Default @{}
	$isElevated = [bool](Test-AdminPrivileges -CheckOnly)
	$logsDirectory = Get-LogPath -Directory

	$results = [System.Collections.Generic.List[object]]::new()
	$waiting = [System.Collections.Generic.List[object]]::new()
	$printed = $false

	foreach ($definition in $definitions) {
		if ($Name -and $Name -notcontains $definition.Name) { continue }

		if (-not $definition.Valid) {
			$problem = $definition.Errors -join '; '
			if ($inline) {
				Write-LogError "Startup task [$($definition.Name)] is not valid and never runs - $problem"
				$printed = $true
			}
			$results.Add([pscustomobject]@{ Name = $definition.Name; Status = 'Failed'; Reason = "Not valid: $problem"; Trigger = $Trigger; Window = $null; Duration = [timespan]::Zero; ResultFile = $null })
			continue
		}

		if ($definition.Trigger -notcontains $Trigger) { continue }

		$arguments = @{}
		foreach ($key in @($definition.Parameters.Keys)) { $arguments[$key] = $definition.Parameters[$key] }
		$arguments.Trigger = $Trigger
		$arguments.ConditionDefinitions = $conditions

		if ($inline) {
			$arguments.Window = 'Current'
			$arguments.NoConditionWait = $true
			$arguments.Remove('Parallel')
			$arguments.Remove('KeepOpen')
		}
		elseif ($arguments.Elevation -eq 'Silent' -and -not $isElevated -and -not $rehearsal -and $definition.InScope -and $arguments.Enabled) {
			# Its own elevated scheduled task runs it (Set-StartupTasks); starting it here too
			# would run it twice, and with a consent dialog.
			$registered = Get-ScheduledTask -TaskPath '\WinuX\' -TaskName "StartupTask-Silent-$($definition.Name)-$Trigger" -ErrorAction SilentlyContinue
			if ($registered) {
				$results.Add([pscustomobject]@{ Name = $definition.Name; Status = 'Delegated'; Reason = 'Runs from its own elevated scheduled task'; Trigger = $Trigger; Window = $arguments.Window; Duration = [timespan]::Zero; ResultFile = $null })
			}
			else {
				$results.Add([pscustomobject]@{ Name = $definition.Name; Status = 'Failed'; Reason = 'Its elevated scheduled task is missing - run Set-StartupTasks'; Trigger = $Trigger; Window = $arguments.Window; Duration = [timespan]::Zero; ResultFile = $null })
			}
			continue
		}

		$result = Invoke-StartupTask @arguments -WhatIf:$rehearsal

		if ($result.Status -eq 'Started') {
			$waiting.Add([pscustomobject]@{ Index = $results.Count; Timeout = $arguments.Timeout; Since = (Get-Date) - $result.Duration })
		}
		$results.Add($result)
	}

	# The tasks that were started and left running: collect them now, each up to its own Timeout.
	foreach ($entry in $waiting) {
		$started = $results[$entry.Index]
		# What is left of its Timeout, counted from when it started (0 stays "no limit").
		$remaining = [double]$entry.Timeout
		if ($remaining -gt 0) {
			$remaining = [math]::Max(1, [math]::Ceiling($remaining - ((Get-Date) - $entry.Since).TotalSeconds))
		}
		$waited = Wait-StartupTaskResult -Name $started.Name -ResultFile $started.ResultFile -Timeout $remaining -StampFile (Join-Path $logsDirectory ".startup-task-$($started.Name).stamp")
		$started.Status = $waited.Status
		$started.Reason = $waited.Reason
		$started.Duration = (Get-Date) - $entry.Since
	}

	if ($rehearsal) {
		return $results.ToArray()
	}

	# Inline runs print as they go (the command's own output, a failure, a skip). Runs in other
	# shells are only visible here, so each gets its line - in this shell's session log, since
	# the runner has no window.
	$problems = [System.Collections.Generic.List[string]]::new()
	foreach ($result in $results) {
		if ($inline) {
			# A skip is silent here (the condition was only tested), so it moves no prompt.
			if ($result.Status -in 'Succeeded', 'Failed', 'HandedOff', 'Ended') { $printed = $true }
			continue
		}

		if ($result.Status -in 'Failed', 'Skipped', 'TimedOut') {
			$problems.Add("[$($result.Name)] $($result.Status) - $($result.Reason)")
		}

		switch ($result.Status) {
			{ $_ -in 'Succeeded', 'Ended' } { Write-LogSuccess "Startup task [$($result.Name)] finished ($Trigger)" }
			{ $_ -in 'Failed', 'TimedOut' } { Write-LogError "Startup task [$($result.Name)] $($result.Status.ToLowerInvariant()) ($Trigger) - $($result.Reason)" }
			'Skipped' { Write-LogWarning "Startup task [$($result.Name)] skipped ($Trigger) - $($result.Reason)" }
			{ $_ -in 'HandedOff', 'Delegated' } { Write-LogStep "Startup task [$($result.Name)] $($result.Status.ToLowerInvariant()) ($Trigger) - $($result.Reason)" }
			default { Write-LogDebug " [Invoke-StartupTasks] [$($result.Name)] $($result.Status) ($Trigger) - $($result.Reason)" }
		}
	}

	if (-not $inline -and $problems.Count -gt 0 -and "$(Get-ConfigSetting -Path 'Startup.FailureReport' -Default 'Tab')" -ne 'None') {
		try {
			$reportFile = Join-Path $logsDirectory ".startup-report-$Trigger.txt"
			$report = @("Startup tasks ($Trigger, $(Get-Date -Format 'yyyy-MM-dd HH:mm')) - $($problems.Count) did not finish:", '') + @($problems | ForEach-Object { "  $_" }) + @('', "Session log: $(Get-LogPath)")
			Set-Content -LiteralPath $reportFile -Value $report -Encoding UTF8 -Force -ErrorAction Stop
			Open-Terminal -Command "Get-Content -LiteralPath '$($reportFile.Replace("'", "''"))'" -WindowId 'WinuXStartup'
		}
		catch {
			Write-LogError "Could not show the startup task report => $($_.Exception.Message)" -Exception $_
		}
	}

	if ($RedrawPrompt -and $printed) {
		$null = Restore-ShellPrompt
	}

	if ($PassThru) {
		return $results.ToArray()
	}
}
