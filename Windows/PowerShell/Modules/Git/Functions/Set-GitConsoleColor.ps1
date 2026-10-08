function Set-GitConsoleColor {
	<#
	.SYNOPSIS
		Makes git color its output while it is shown through Out-Host, then turns that off again.

	.DESCRIPTION
		Update-Repository sends git's output to the console with `| Out-Host`, so it never ends up
		in the function's result. Git then writes into a pipe instead of a terminal and drops its
		colors - the green and red + and - of a pull's diffstat among them. This function forces
		them back for the commands that follow, through git's environment configuration
		(GIT_CONFIG_COUNT, GIT_CONFIG_KEY_0 = color.ui, GIT_CONFIG_VALUE_0 = always), which every
		git call of this process then reads without its arguments changing.

		Only when the console output is not redirected (a log file or a pipe would get escape
		codes) and GIT_CONFIG_COUNT is not set already (a caller further up turned it on, or the
		user configured git that way) - in both cases it changes nothing and returns $false.
		Returns $true when it set the variables; only then should the caller turn it off again
		with -Off, so a nested call never undoes its caller's setting.

		Colors only affect what git draws for people: porcelain and format output (status
		--porcelain, rev-parse, rev-list, stash list --format) is never colored.

	.PARAMETER Off
		Remove the three variables again.

	.OUTPUTS
		[bool] - $true when the colors were turned on by this call. Nothing with -Off.

	.EXAMPLE
		$colored = Set-GitConsoleColor
		try { git merge --ff-only origin/master | Out-Host }
		finally { if ($colored) { Set-GitConsoleColor -Off } }
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false)]
		[switch]$Off
	)

	if ($Off) {
		Remove-Item -Path Env:GIT_CONFIG_COUNT, Env:GIT_CONFIG_KEY_0, Env:GIT_CONFIG_VALUE_0 -ErrorAction SilentlyContinue
		return
	}

	if ([Console]::IsOutputRedirected -or $env:GIT_CONFIG_COUNT) { return $false }

	$env:GIT_CONFIG_COUNT = "1"
	$env:GIT_CONFIG_KEY_0 = "color.ui"
	$env:GIT_CONFIG_VALUE_0 = "always"
	return $true
}
