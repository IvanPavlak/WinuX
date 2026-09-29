function Invoke-ShellStartupSample {
	<#
	.SYNOPSIS
		Starts one child shell to its first prompt and returns how long it took - one sample for
		Measure-ShellStartup.

	.DESCRIPTION
		Launches PowerShell in the CURRENT console (a plain call, not Start-Process) with the given
		skip list in WINUX_STARTUP_SKIP and a fresh trace file in WINUX_STARTUP_TRACE, runs its
		profile to completion and exits. The wall time from launch to exit is the sample; the
		trace file the profile's stage guards wrote is read back into per-stage milliseconds.

		Sharing the console matters: it is what makes the sample honest. The child inherits
		WT_SESSION, an interactive console and the terminal that answers the cell-size query, so the
		image logo, the sixel path and everything else the greeting does for real is what gets
		measured. The price is that the child clears the screen and draws its panel - the caller
		prints its table afterwards.

		-Bare launches with -NoProfile instead: the floor a shell costs before any profile runs,
		which is the first row of every measurement.

		The two environment variables are restored to what they were, whatever happens, and the
		trace file is deleted after it is read.

	.PARAMETER Skip
		The WINUX_STARTUP_SKIP value for the child: a comma-separated list of stage names, or
		empty for a full start.

	.PARAMETER Bare
		Launch with -NoProfile - no stages at all.

	.PARAMETER Executable
		The PowerShell executable to launch. Defaults to the one running this function, so the
		child is the same build as the shell being measured.

	.OUTPUTS
		[pscustomobject] with Milliseconds (wall time, one decimal) and Stages (hashtable of stage
		name => milliseconds from the trace file; empty for -Bare).

	.EXAMPLE
		Invoke-ShellStartupSample
		One full shell start; Milliseconds is the wall time, Stages the per-stage breakdown.

	.EXAMPLE
		Invoke-ShellStartupSample -Skip "Greeting,Terminal-Icons"
		One start without those two stages.

	.EXAMPLE
		Invoke-ShellStartupSample -Bare
		One start with -NoProfile.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param(
		[Parameter(Position = 0)]
		[AllowNull()]
		[AllowEmptyString()]
		[string]$Skip = "",

		[Parameter()]
		[switch]$Bare,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[string]$Executable = (Get-Process -Id $PID).Path
	)

	$previousSkip = $env:WINUX_STARTUP_SKIP
	$previousTrace = $env:WINUX_STARTUP_TRACE
	$tracePath = Join-Path ([System.IO.Path]::GetTempPath()) ("winux-startup-{0}.trace" -f [guid]::NewGuid().ToString("N"))

	try {
		$env:WINUX_STARTUP_SKIP = $Skip
		$env:WINUX_STARTUP_TRACE = $tracePath

		$arguments = if ($Bare) { @("-NoLogo", "-NoProfile", "-Command", "exit") } else { @("-NoLogo", "-NoProfileLoadTime", "-Command", "exit") }

		$clock = [System.Diagnostics.Stopwatch]::StartNew()
		& $Executable @arguments
		$clock.Stop()

		$stages = if ($Bare) { @{} } else { Read-ShellStartupTrace -Path $tracePath }

		return [pscustomobject]@{
			Milliseconds = [math]::Round($clock.Elapsed.TotalMilliseconds, 1)
			Stages       = $stages
		}
	}
	finally {
		$env:WINUX_STARTUP_SKIP = $previousSkip
		$env:WINUX_STARTUP_TRACE = $previousTrace
		Remove-Item -LiteralPath $tracePath -Force -ErrorAction SilentlyContinue
	}
}
