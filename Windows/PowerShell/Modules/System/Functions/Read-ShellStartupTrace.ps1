function Read-ShellStartupTrace {
	<#
	.SYNOPSIS
		Reads the per-stage times a shell start wrote to its WINUX_STARTUP_TRACE file.

	.DESCRIPTION
		Complete-StartupStage appends one tab-separated line per stage - the stage name and its
		milliseconds - to the file named by WINUX_STARTUP_TRACE. This function turns that file into
		a hashtable of stage name to milliseconds, so Measure-ShellStartup can show what a stage
		cost inside the shell next to what its presence added to the wall time.

		A missing file, an empty file and a line that does not parse all degrade to "no data":
		the result is an empty hashtable or the line is dropped. A stage that appears twice keeps
		its last value - a profile that is re-run in the same shell (Reload-PowerShellProfile)
		appends a second set of lines, and the later set describes the later run.

	.PARAMETER Path
		The trace file to read.

	.OUTPUTS
		[hashtable] - stage name => milliseconds ([double]).

	.EXAMPLE
		Read-ShellStartupTrace -Path "$env:TEMP\startup.trace"
		Returns @{ Core = 412.3; Greeting = 610.7; ... } for that shell start.
	#>
	[CmdletBinding()]
	[OutputType([hashtable])]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[ValidateNotNullOrEmpty()]
		[string]$Path
	)

	$stages = @{}
	if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $stages }

	foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
		$parts = $line -split "`t"
		if ($parts.Count -lt 2) { continue }

		$value = 0.0
		if ([double]::TryParse($parts[1].Trim(), [System.Globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref]$value)) {
			$stages[$parts[0].Trim()] = $value
		}
	}

	return $stages
}
