function New-StartupTaskShellCommand {
	<#
	.SYNOPSIS
		Builds the command line a new shell runs for a startup task, or for the startup runner.

	.DESCRIPTION
		Startup tasks cross process borders: the scheduled task starts the runner, the runner
		starts a shell per task, and an elevation starts an Administrator one. Every one of those
		shells gets its work as one self-contained piece of PowerShell text, built here so the
		three callers (Start-StartupTaskShell, Invoke-StartupTask and Set-StartupTasks) agree on
		it.

		The text is, in order:

		1. With -LoadProfile, a prelude for a shell started with `pwsh -NoProfile`: it sets
		   WINUX_STARTUP_SKIP to -SkipStage, dot-sources the profiles PowerShell itself would
		   have loaded, and removes the variable again so shells started later are not affected.
		   That gives the shell the configuration, the modules and the aliases without the
		   greeting, the prompt theme and the other interactive stages.
		2. With -TaskShell, a marker ($global:WinuXStartupTaskShell) that tells
		   `Invoke-StartupTasks -Trigger TerminalOpen` this shell belongs to a startup task, so
		   the tasks of a newly opened terminal do not run in it.
		3. The work: -Command verbatim, or with -Arguments a call of Invoke-StartupTask with
		   exactly those parameters. The parameters travel as JSON inside the text, so nothing
		   depends on a variable or a configuration value of the calling shell.
		4. With -ExitOn, `exit` when the task's status is one of those named - how a task's tab
		   closes itself. -ExitAlways exits whatever the status.

		-Encoded returns the text as the Base64 string `pwsh -EncodedCommand` takes.

	.PARAMETER Arguments
		Parameters for Invoke-StartupTask. Values must survive JSON: strings, numbers, booleans,
		arrays and hashtables of those.

	.PARAMETER Command
		PowerShell text to run instead of an Invoke-StartupTask call.

	.PARAMETER LoadProfile
		Add the prelude for a shell started with -NoProfile.

	.PARAMETER SkipStage
		The profile stages the prelude skips. Defaults to every interactive stage.

	.PARAMETER TaskShell
		Mark the shell as belonging to a startup task.

	.PARAMETER ExitOn
		Statuses after which the shell exits. Only with -Arguments.

	.PARAMETER ExitAlways
		Exit after the work whatever happened.

	.PARAMETER Encoded
		Return the Base64 form for `pwsh -EncodedCommand`.

	.OUTPUTS
		[string] - the PowerShell text, or its Base64 form.

	.EXAMPLE
		New-StartupTaskShellCommand -Arguments @{ Name = "MyTask"; Command = "Open-Workspace MyWorkspace" } -TaskShell -ExitOn Succeeded
		The text of a tab that runs MyTask and closes itself when it succeeded.

	.EXAMPLE
		New-StartupTaskShellCommand -Command "Invoke-StartupTasks -Trigger SignIn" -LoadProfile -ExitAlways -Encoded
		What the sign-in scheduled task hands to pwsh.
	#>
	[CmdletBinding(DefaultParameterSetName = 'Arguments')]
	[OutputType([string])]
	param(
		[Parameter(Mandatory = $true, ParameterSetName = 'Arguments')]
		[System.Collections.IDictionary]$Arguments,

		[Parameter(Mandatory = $true, ParameterSetName = 'Command')]
		[ValidateNotNullOrEmpty()]
		[string]$Command,

		[Parameter()]
		[switch]$LoadProfile,

		[Parameter()]
		[string[]]$SkipStage = @('Schema', 'Greeting', 'PSReadLine', 'Terminal-Icons', 'PSReadLineOptions', 'OhMyPosh', 'PowerPlan', 'LogMaintenance', 'StartupTasks'),

		[Parameter()]
		[switch]$TaskShell,

		[Parameter(ParameterSetName = 'Arguments')]
		[string[]]$ExitOn,

		[Parameter()]
		[switch]$ExitAlways,

		[Parameter()]
		[switch]$Encoded
	)

	$lines = [System.Collections.Generic.List[string]]::new()

	if ($LoadProfile) {
		$skipList = (@($SkipStage | Where-Object { $_ }) -join ',').Replace("'", "''")
		$lines.Add("`$env:WINUX_STARTUP_SKIP = '$skipList'")
		$lines.Add('foreach ($winuxProfile in $PROFILE.AllUsersAllHosts, $PROFILE.AllUsersCurrentHost, $PROFILE.CurrentUserAllHosts, $PROFILE.CurrentUserCurrentHost) { if ($winuxProfile -and (Test-Path -LiteralPath $winuxProfile)) { . $winuxProfile } }')
		$lines.Add('Remove-Item -Path Env:WINUX_STARTUP_SKIP -ErrorAction SilentlyContinue')
	}

	if ($TaskShell) {
		$lines.Add('$global:WinuXStartupTaskShell = $true')
	}

	if ($PSCmdlet.ParameterSetName -eq 'Command') {
		$lines.Add($Command)
	}
	else {
		$json = (ConvertTo-Json -InputObject $Arguments -Depth 8 -Compress).Replace("'", "''")
		$lines.Add("`$winuxStartupTaskArguments = ConvertFrom-Json -InputObject '$json' -AsHashtable")
		$lines.Add('$winuxStartupTaskResult = Invoke-StartupTask @winuxStartupTaskArguments')

		$statuses = @($ExitOn | Where-Object { $_ })
		if ($statuses.Count -gt 0 -and -not $ExitAlways) {
			$statusList = @($statuses | ForEach-Object { "'" + $_.Replace("'", "''") + "'" }) -join ', '
			$lines.Add("if (`$winuxStartupTaskResult -and `$winuxStartupTaskResult.Status -in $statusList) { exit }")
		}
	}

	if ($ExitAlways) {
		$lines.Add('exit')
	}

	$text = $lines -join "`n"

	if ($Encoded) {
		return [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($text))
	}

	return $text
}
