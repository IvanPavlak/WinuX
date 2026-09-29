function Complete-StartupStage {
	<#
	.SYNOPSIS
		Stops the clock Test-StartupStage started and records the stage's time.

	.DESCRIPTION
		The second half of the profile's stage guard (see Test-StartupStage). Stops the running
		stage clock and appends a record - the stage name and its elapsed milliseconds, rounded to
		one decimal - to $global:WinuXStartupTimings, which is how a running shell answers "what
		did my startup spend its time on":

		  $WinuXStartupTimings | Format-Table

		When the WINUX_STARTUP_TRACE environment variable names a file, the same record is appended
		to it as one tab-separated line (Name, milliseconds). Measure-ShellStartup (System module)
		reads that file after each child shell it launches, which is how the per-stage times of a
		shell that has already exited reach the table.

		Does nothing when no stage clock is running, so a stray call is harmless. A trace file that
		cannot be written is ignored: measurement must never break a shell start.

	.PARAMETER TracePath
		The trace file to append to. Defaults to $env:WINUX_STARTUP_TRACE; empty means no file.

	.EXAMPLE
		if (Test-StartupStage -Name "Aliases") { New-Alias -Name c -Value Show-TerminalGreeting; Complete-StartupStage }
		Records how long the alias stage took.

	.EXAMPLE
		$WinuXStartupTimings | Sort-Object Milliseconds -Descending | Format-Table
		In a running shell: the stages of this start, slowest first.
	#>
	[CmdletBinding()]
	param(
		[Parameter()]
		[AllowNull()]
		[AllowEmptyString()]
		[string]$TracePath = $env:WINUX_STARTUP_TRACE
	)

	$stage = $global:WinuXStartupStage
	if (-not $stage) { return }

	$stage.Clock.Stop()
	$milliseconds = [math]::Round($stage.Clock.Elapsed.TotalMilliseconds, 1)

	if ($null -eq $global:WinuXStartupTimings) {
		$global:WinuXStartupTimings = [System.Collections.Generic.List[object]]::new()
	}
	$global:WinuXStartupTimings.Add([pscustomobject]@{
			Stage        = $stage.Name
			Milliseconds = $milliseconds
		})

	if (-not [string]::IsNullOrWhiteSpace($TracePath)) {
		try {
			$line = "{0}`t{1}`n" -f $stage.Name, $milliseconds.ToString([cultureinfo]::InvariantCulture)
			[System.IO.File]::AppendAllText($TracePath, $line)
		}
		catch { }
	}

	$global:WinuXStartupStage = $null
}
