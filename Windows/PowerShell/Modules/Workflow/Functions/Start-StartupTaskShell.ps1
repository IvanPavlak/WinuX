function Start-StartupTaskShell {
	<#
	.SYNOPSIS
		Starts the shell a startup task runs in: a terminal tab, or a hidden shell.

	.DESCRIPTION
		Invoke-StartupTask calls this for a task whose Window is Tab or Hidden. The new shell
		runs Invoke-StartupTask again with -Arguments, this time inline, and reports through the
		task's result file (see Wait-StartupTaskResult). This function only starts the shell; it
		never waits for it.

		- Tab: Open-Terminal opens a tab in the Windows Terminal window named by -WindowId, so
		  the tabs of one startup share a window. The tab's shell loads the profile as any
		  terminal does. When the task is over the tab closes itself according to -KeepOpen:
		  OnFailure (default) closes it unless the task failed, was skipped or was handed off;
		  Never always closes it; Always leaves it. A task without a Command is a plain terminal:
		  its shell is not marked as a task shell, so the tasks of a newly opened terminal run in
		  it as in any other.
		- Hidden: pwsh starts with no window and -NonInteractive, loads the profile without its
		  interactive stages (New-StartupTaskShellCommand -LoadProfile) and exits when the task
		  is over. Nothing in it can ask a question.

		-Administrator starts the shell elevated - `Open-Terminal -Administrator` for a tab,
		`Start-Process -Verb RunAs` for a hidden shell - which raises the Windows consent dialog
		unless the caller is elevated already. A declined dialog throws; Invoke-StartupTask
		reports it as the task's failure.

	.PARAMETER Name
		The task's name, for messages.

	.PARAMETER Arguments
		The parameters the new shell passes to Invoke-StartupTask. Must hold -Window Current and
		the -ResultFile the caller waits on.

	.PARAMETER Window
		Tab (default) or Hidden.

	.PARAMETER KeepOpen
		OnFailure (default), Always or Never. Only a tab can stay open.

	.PARAMETER Administrator
		Start the shell elevated.

	.PARAMETER WindowId
		The Windows Terminal window the tab opens in. Default "WinuXStartup".

	.EXAMPLE
		Start-StartupTaskShell -Name MyTask -Arguments @{ Name = "MyTask"; Command = "Open-Workspace MyWorkspace"; Window = "Current"; ResultFile = $resultFile }
		Opens a tab that runs MyTask and closes when it succeeded.

	.EXAMPLE
		Start-StartupTaskShell -Name MyTask -Arguments $arguments -Window Hidden
		Runs MyTask in a shell with no window.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[string]$Name,

		[Parameter(Mandatory = $true)]
		[System.Collections.IDictionary]$Arguments,

		[Parameter()]
		[ValidateSet('Tab', 'Hidden')]
		[string]$Window = 'Tab',

		[Parameter()]
		[ValidateSet('OnFailure', 'Always', 'Never')]
		[string]$KeepOpen = 'OnFailure',

		[Parameter()]
		[switch]$Administrator,

		[Parameter()]
		[string]$WindowId = 'WinuXStartup'
	)

	$hasCommand = -not [string]::IsNullOrWhiteSpace([string]$Arguments['Command'])

	if ($Window -eq 'Hidden') {
		$encoded = New-StartupTaskShellCommand -Arguments $Arguments -LoadProfile -TaskShell -ExitAlways -Encoded
		$process = @{
			FilePath     = Join-Path -Path $PSHOME -ChildPath 'pwsh.exe'
			ArgumentList = @('-NoLogo', '-NoProfile', '-NonInteractive', '-EncodedCommand', $encoded)
			WindowStyle  = 'Hidden'
		}
		if ($Administrator) { $process.Verb = 'RunAs' }

		Write-LogDebug " [Start-StartupTaskShell] Starting hidden shell for [$Name] (administrator: $([bool]$Administrator))"
		Start-Process @process
		return
	}

	# Every status that is not a problem closes an OnFailure tab; a problem leaves it open so
	# its output can be read.
	$command = @{ Arguments = $Arguments; TaskShell = $hasCommand }
	if ($KeepOpen -eq 'Never') {
		$command.ExitAlways = $true
	}
	elseif ($KeepOpen -eq 'OnFailure') {
		$command.ExitOn = @('Succeeded', 'NotDue', 'Disabled', 'OutOfScope', 'AlreadyRunning')
	}
	$text = New-StartupTaskShellCommand @command

	Write-LogDebug " [Start-StartupTaskShell] Opening tab for [$Name] in window [$WindowId] (administrator: $([bool]$Administrator), keep open: $KeepOpen)"
	Open-Terminal -Command $text -WindowId $WindowId -Administrator:$Administrator
}
