function Set-StartupTasks {
	<#
	.SYNOPSIS
		Registers the Windows scheduled tasks that run the configured startup tasks, and removes the ones no longer needed.

	.DESCRIPTION
		Startup tasks (`Startup.Tasks`) are run by Invoke-StartupTasks; this function is what
		makes Windows call it. It keeps ONE scheduled task per trigger in use, not one per
		startup task, under the Task Scheduler folder \WinuX\:

		- StartupTasks-SignIn: at this user's sign-in.
		- StartupTasks-Unlock: when this user unlocks the workstation.
		- StartupTasks-Wake: when the machine resumes from sleep (the System log's
		  Power-Troubleshooter event 1).

		Each runs `Invoke-StartupTasks -Trigger <Trigger>` in a shell with no window, as the
		signed-in user, unelevated, on battery too. The list of startup tasks is read when the
		trigger fires, so editing `Startup.Tasks` needs no second run of this function - only
		starting or stopping to use a whole trigger does. The TerminalOpen trigger needs no
		scheduled task: the profile runs it.

		A startup task with `Elevation = "Silent"` gets a scheduled task of its own per trigger
		(StartupTask-Silent-<Name>-<Trigger>) that runs with the highest privileges, so Windows
		shows no consent dialog. Its command, its options and the conditions it requires are
		copied into that scheduled task NOW: a later edit of the configuration changes nothing
		for it until this function runs again. That keeps a configuration edit from becoming
		Administrator rights without consent. The command still loads this repository's modules
		when it runs, so a Silent task is a standing way to run that command elevated - use it
		only for a command you would run elevated without looking.

		Only valid, enabled tasks in this machine's scope count (Get-StartupTaskDefinitions).
		Scheduled tasks of the two name patterns above that nothing needs any more are removed,
		so a machine whose last startup task was deleted ends up with none. Running it again
		changes nothing but the registration time.

		Registering and removing need Administrator privileges (Test-AdminPrivileges); -List and
		a run that finds nothing to do do not. Bootstrap calls this as the step StartupTasks.

	.PARAMETER List
		Show what would be registered and what is, and change nothing: one object per scheduled
		task with TaskName, Trigger, RunLevel and State (Registered, Missing or Stale).

	.PARAMETER Remove
		Remove every startup scheduled task, whatever the configuration says.

	.OUTPUTS
		None; with -List, one [pscustomobject] per scheduled task.

	.EXAMPLE
		Set-StartupTasks
		Registers the scheduled tasks the configured startup tasks need on this machine.

	.EXAMPLE
		Set-StartupTasks -List
		Shows which scheduled tasks exist, which are missing and which are left over.

	.EXAMPLE
		Set-StartupTasks -Remove
		Removes every startup scheduled task from this machine.
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	[OutputType([pscustomobject])]
	param(
		[Parameter()]
		[switch]$List,

		[Parameter()]
		[switch]$Remove
	)

	$taskPath = '\WinuX\'
	$osTriggers = @('SignIn', 'Unlock', 'Wake')
	$pwshPath = Join-Path -Path $PSHOME -ChildPath 'pwsh.exe'

	# What this machine needs: one runner per trigger in use, one elevated task per Silent task
	# and trigger.
	$desired = [ordered]@{}
	if (-not $Remove) {
		$definitions = @(Get-StartupTaskDefinitions | Where-Object { $_.Valid -and $_.InScope -and $_.Parameters.Enabled })
		$conditions = Get-ConfigSetting -Path 'Startup.Conditions' -Default @{}

		foreach ($trigger in $osTriggers) {
			$runnerTasks = @($definitions | Where-Object { $_.Trigger -contains $trigger -and $_.Parameters.Elevation -ne 'Silent' })
			if ($runnerTasks.Count -gt 0) {
				$desired["StartupTasks-$trigger"] = @{
					Trigger     = $trigger
					RunLevel    = 'Limited'
					Encoded     = New-StartupTaskShellCommand -Command "Invoke-StartupTasks -Trigger $trigger" -LoadProfile -ExitAlways -Encoded
					Description = "WinuX: runs the startup tasks of the $trigger trigger (Invoke-StartupTasks)."
				}
			}

			foreach ($definition in @($definitions | Where-Object { $_.Trigger -contains $trigger -and $_.Parameters.Elevation -eq 'Silent' })) {
				# Frozen: the options and the conditions travel inside the scheduled task.
				$frozen = @{}
				foreach ($key in @($definition.Parameters.Keys)) { $frozen[$key] = $definition.Parameters[$key] }
				$frozen.Trigger = $trigger
				$frozen.Parallel = $false
				$frozenConditions = @{}
				foreach ($required in @($definition.Parameters.Requires)) {
					foreach ($key in @($conditions.Keys)) {
						if ([string]$key -eq $required) { $frozenConditions[$required] = $conditions[$key] }
					}
				}
				$frozen.ConditionDefinitions = $frozenConditions

				$desired["StartupTask-Silent-$($definition.Name)-$trigger"] = @{
					Trigger     = $trigger
					RunLevel    = 'Highest'
					Encoded     = New-StartupTaskShellCommand -Arguments $frozen -LoadProfile -ExitAlways -Encoded
					Description = "WinuX: runs the startup task [$($definition.Name)] elevated on $trigger (Invoke-StartupTask). Its command was copied in when Set-StartupTasks ran."
				}
			}
		}
	}

	$existing = @(Get-ScheduledTask -TaskPath $taskPath -ErrorAction SilentlyContinue |
			Where-Object { $_.TaskName -like 'StartupTasks-*' -or $_.TaskName -like 'StartupTask-Silent-*' })
	$existingNames = @($existing | ForEach-Object { $_.TaskName })
	$stale = @($existingNames | Where-Object { -not $desired.Contains($_) })

	if ($List) {
		foreach ($taskName in $desired.Keys) {
			[pscustomobject]@{
				TaskName = $taskName
				Trigger  = $desired[$taskName].Trigger
				RunLevel = $desired[$taskName].RunLevel
				State    = if ($existingNames -contains $taskName) { 'Registered' } else { 'Missing' }
			}
		}
		foreach ($taskName in $stale) {
			[pscustomobject]@{ TaskName = $taskName; Trigger = $null; RunLevel = $null; State = 'Stale' }
		}
		return
	}

	if ($desired.Count -eq 0 -and $stale.Count -eq 0) {
		Write-LogStep "No startup tasks need a scheduled task on this machine"
		return
	}

	if (-not $WhatIfPreference) { Test-AdminPrivileges }

	Write-LogTitle "[Startup Tasks]"

	$user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
	$failed = 0

	foreach ($taskName in $desired.Keys) {
		$entry = $desired[$taskName]
		if (-not $PSCmdlet.ShouldProcess("$taskPath$taskName", "Register scheduled task ($($entry.Trigger), $($entry.RunLevel))")) { continue }

		try {
			# conhost --headless gives the shell a console without a window, so nothing flashes
			# on screen when the trigger fires.
			$action = New-ScheduledTaskAction -Execute (Join-Path $env:SystemRoot 'System32\conhost.exe') -Argument "--headless `"$pwshPath`" -NoLogo -NoProfile -NonInteractive -EncodedCommand $($entry.Encoded)"

			$trigger = switch ($entry.Trigger) {
				'SignIn' { New-ScheduledTaskTrigger -AtLogOn -User $user }
				'Unlock' {
					# StateChange 8 is TASK_SESSION_UNLOCK. New-ScheduledTaskTrigger has no switch
					# for it, so the trigger is built from its CIM class.
					$class = Get-CimClass -Namespace 'Root/Microsoft/Windows/TaskScheduler' -ClassName 'MSFT_TaskSessionStateChangeTrigger' -ErrorAction Stop
					New-CimInstance -CimClass $class -Property @{ StateChange = 8; UserId = $user; Enabled = $true } -ClientOnly -ErrorAction Stop
				}
				'Wake' {
					$class = Get-CimClass -Namespace 'Root/Microsoft/Windows/TaskScheduler' -ClassName 'MSFT_TaskEventTrigger' -ErrorAction Stop
					$subscription = "<QueryList><Query Id=`"0`" Path=`"System`"><Select Path=`"System`">*[System[Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and EventID=1]]</Select></Query></QueryList>"
					New-CimInstance -CimClass $class -Property @{ Subscription = $subscription; Enabled = $true } -ClientOnly -ErrorAction Stop
				}
			}

			$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel $entry.RunLevel
			$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([timespan]::Zero)

			Register-ScheduledTask -TaskPath $taskPath -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description $entry.Description -Force -ErrorAction Stop | Out-Null
			Write-LogSuccess "Registered [$taskName]" -NoLeadingNewline
		}
		catch {
			$failed++
			Write-LogError "Could not register [$taskName] => $($_.Exception.Message)" -Exception $_
		}
	}

	foreach ($taskName in $stale) {
		if (-not $PSCmdlet.ShouldProcess("$taskPath$taskName", "Remove scheduled task")) { continue }

		try {
			Unregister-ScheduledTask -TaskPath $taskPath -TaskName $taskName -Confirm:$false -ErrorAction Stop
			Write-LogSuccess "Removed [$taskName] (no startup task needs it any more)" -NoLeadingNewline
		}
		catch {
			$failed++
			Write-LogError "Could not remove [$taskName] => $($_.Exception.Message)" -Exception $_
		}
	}

	if ($failed -gt 0) {
		Write-LogWarning "Startup tasks: $failed scheduled task(s) could not be changed"
	}
}
