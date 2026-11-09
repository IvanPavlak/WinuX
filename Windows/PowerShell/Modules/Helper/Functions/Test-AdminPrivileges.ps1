function Test-AdminPrivileges {
	<#
	.SYNOPSIS
		Verify or request Administrator privileges.

	.DESCRIPTION
		Checks if script is running as Administrator. With -CheckOnly, returns boolean.
		Without -CheckOnly, prompts user to elevate if not admin and offers to rerun in elevated shell.
		With -AutoElevate (or AutoElevate = $true in Configuration.local.psd1), the prompt is skipped
		and the command is rerun in the Administrator PowerShell straight away. The Windows UAC
		consent dialog still appears either way - only the confirmation question is removed.

		Inside a startup task nobody is there to answer. While Invoke-StartupTask runs a task's
		command it sets $global:WinuXStartupTask (Name, Elevation, RelaunchCommand), and this
		function then never asks: unless the task has Elevation = "Relaunch" it reports that the
		task needs Administrator privileges, names the option and stops; with Relaunch it reruns
		without the confirmation question, and what it reruns is the task itself
		(RelaunchCommand), not a line of the call stack.

	.PARAMETER CheckOnly
		If specified, only return boolean without prompting or elevating.

	.PARAMETER AutoElevate
		Relaunch the triggering command in the Administrator PowerShell without asking first.
		When not passed, the value of the AutoElevate configuration key is used (default $false).
		An explicit -AutoElevate:$false restores the prompt even when the key is $true.

	.EXAMPLE
		if (Test-AdminPrivileges -CheckOnly) { Write-Host "Running as admin" }
		Test-AdminPrivileges  # Prompts to elevate if not admin

	.EXAMPLE
		Test-AdminPrivileges -AutoElevate  # Reruns elevated without the confirmation question
	#>
	[CmdletBinding()]
	param (
		[Parameter()]
		[switch]$CheckOnly,

		[Parameter()]
		[switch]$AutoElevate
	)

	$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
	$principal = New-Object Security.Principal.WindowsPrincipal($identity)

	if ($CheckOnly) {
		return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
	}

	if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
		# An explicitly bound -AutoElevate (including -AutoElevate:$false) wins over the
		# configuration key. Only the confirmation question is skipped: the UAC consent dialog
		# is raised by Windows for the elevated relaunch and cannot be suppressed from here.
		if (-not $PSBoundParameters.ContainsKey('AutoElevate')) {
			$AutoElevate = [bool](Get-ConfigSetting -Path 'AutoElevate' -Default $false)
		}

		# A startup task's command (see Invoke-StartupTask): no question can be answered, so it
		# either stops here, naming the option that allows the relaunch, or relaunches unasked.
		$startupTask = $global:WinuXStartupTask
		if ($startupTask -and "$($startupTask.Elevation)" -ne 'Relaunch') {
			Write-LogError "Startup task [$($startupTask.Name)] needs Administrator privileges - set Elevation = `"Relaunch`", `"Prompt`" or `"Silent`" on the task"
			throw [System.Management.Automation.PipelineStoppedException]::new()
		}
		if ($startupTask) { $AutoElevate = $true }

		$currentDirectory = (Get-Location).Path
		# Replay the command the user actually typed. Each frame's InvocationInfo.Line is the
		# source line that invoked that frame, so the OUTERMOST frame that recorded a line holds
		# the original typed command (the interactive prompt's own frame records none). Inner
		# frames carry engine source lines (e.g. "& $stepName" dispatching a personal step) that
		# are meaningless in a fresh elevated shell, where those variables do not exist and the
		# rerun dies with "The expression after '&' ... was not valid".
		$callStack = Get-PSCallStack
		$triggeringCommand = ""
		for ($frameIndex = $callStack.Count - 1; $frameIndex -ge 1; $frameIndex--) {
			$triggeringCommand = "$($callStack[$frameIndex].InvocationInfo.Line)".Trim()
			if ($triggeringCommand) { break }
		}
		# The task's own self-contained command: the call stack's line names variables that
		# exist only in the shell the task was started from.
		if ($startupTask -and $startupTask.RelaunchCommand) {
			$triggeringCommand = [string]$startupTask.RelaunchCommand
		}

		Write-LogError "This must be run with Administrator privileges!"

		$relaunch = [bool]$AutoElevate
		if (-not $relaunch) {
			$openConfirmation = Resolve-Selection `
				-MenuTitle "[Open Administrator PowerShell]" `
				-PromptMessage "Do you want to open the Administrator PowerShell and rerun the command? (Enter for default => Yes)" `
				-AllowEmptyPromptResponse:$true

			$relaunch = ($openConfirmation -eq "Yes" -or $null -eq $openConfirmation)
		}

		if ($relaunch) {
			$triggeringCommandFromCurrentDirectory = "Set-Location -Path '$currentDirectory'; $triggeringCommand"
			Open-Terminal -Administrator -Command $triggeringCommandFromCurrentDirectory
			Write-LogSuccess "Rerunning [$triggeringCommand] in the Administrator PowerShell!"
		}

		throw [System.Management.Automation.PipelineStoppedException]::new()
	}
}
