function Test-StartupStage {
	<#
	.SYNOPSIS
		Tells the profile whether a startup stage should run, and starts its clock when it should.

	.DESCRIPTION
		The profile wraps every startup stage in a guard pair so each one can be measured on its
		own and switched off for one shell start without editing the profile:

		  if (Test-StartupStage -Name "Terminal-Icons") {
		      Import-Module Terminal-Icons
		      Complete-StartupStage
		  }

		The stage is skipped - the function returns $false and starts nothing - when its name, or
		the word All, is listed in the WINUX_STARTUP_SKIP environment variable (comma or semicolon
		separated, case-insensitive). Otherwise a Stopwatch is started for the stage and $true is
		returned; Complete-StartupStage stops that clock and records the elapsed time.

		This is a guard pair rather than a scriptblock wrapper on purpose: Import-Module, the
		prompt function oh-my-posh defines and New-Alias all bind into the scope that executes them,
		and a wrapper function would swallow them with its own scope. The guard keeps every stage
		in the profile's scope.

		-Required marks a stage that must run whatever the skip list says - the profile's Core
		stage, which loads the configuration everything else reads. The clock still runs for it,
		so its cost is measured like any other stage.

		With WINUX_STARTUP_SKIP unset the function costs one Stopwatch allocation per stage.
		Measure-ShellStartup (System module) sets the variable per child shell to build the
		strip-everything-then-add-one-stage-at-a-time table.

	.PARAMETER Name
		The stage name, as listed in WINUX_STARTUP_SKIP to skip it.

	.PARAMETER Required
		Run the stage even when it - or All - is in the skip list.

	.PARAMETER Skip
		The skip list to consult. Defaults to $env:WINUX_STARTUP_SKIP; a parameter so tests need
		not touch the environment.

	.OUTPUTS
		[bool] - $true when the stage should run (its clock is running), $false when it is skipped.

	.EXAMPLE
		if (Test-StartupStage -Name "OhMyPosh") { . Initialize-OhMyPosh; Complete-StartupStage }
		Times the oh-my-posh stage, or skips it when WINUX_STARTUP_SKIP names it.

	.EXAMPLE
		$env:WINUX_STARTUP_SKIP = "Terminal-Icons,PowerPlan"; pwsh
		Starts a shell without those two stages, everything else as usual.
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[ValidateNotNullOrEmpty()]
		[string]$Name,

		[Parameter()]
		[switch]$Required,

		[Parameter()]
		[AllowNull()]
		[AllowEmptyString()]
		[string]$Skip = $env:WINUX_STARTUP_SKIP
	)

	if (-not $Required -and -not [string]::IsNullOrWhiteSpace($Skip)) {
		$skipped = @($Skip -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
		if ($skipped -contains 'All' -or $skipped -contains $Name) {
			$global:WinuXStartupStage = $null
			return $false
		}
	}

	$global:WinuXStartupStage = [pscustomobject]@{
		Name  = $Name
		Clock = [System.Diagnostics.Stopwatch]::StartNew()
	}

	return $true
}
