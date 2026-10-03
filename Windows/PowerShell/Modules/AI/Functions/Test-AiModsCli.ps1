function Test-AiModsCli {
	<#
	.SYNOPSIS
		Checks that the Claude Code CLI is installed and that it accepts each deployed mod.

	.DESCRIPTION
		Mods only run in a Claude Code build that has the hooks-module API, and the changelog
		does not name the first such build, so the practical gate is the CLI's own validator:
		`claude plugin validate <path>` reads a mod's manifest and module source the way the
		engine will and exits non-zero on anything the engine would refuse. An older CLI that
		does not know a mod's API fails the same way.

		Returns:

		  Installed  $true when the command resolves on PATH.
		  Invalid    The mod paths whose validation failed (exit code other than 0, or the call
		             threw). Empty when the command is missing - nothing could be checked.

		Deploy-AiMods only warns on the result; links and settings are deployed regardless, so
		installing or updating the CLI later is enough.

	.PARAMETER ModPath
		The mod folders to validate, typically the links Deploy-AiMods just created.

	.PARAMETER Command
		The CLI to call. Defaults to `claude`; tests pass a stub script.

	.EXAMPLE
		(Test-AiModsCli -ModPath "$HOME\.claude\mods\my-mod").Invalid
		Returns the mods the installed CLI refuses.
	#>
	[CmdletBinding()]
	[OutputType([hashtable])]
	param(
		[Parameter()]
		[AllowEmptyCollection()]
		[string[]]$ModPath = @(),

		[Parameter()]
		[string]$Command = 'claude'
	)

	$result = @{
		Installed = $false
		Invalid   = @()
	}

	if (-not (Get-Command -Name $Command -ErrorAction SilentlyContinue)) {
		return $result
	}
	$result.Installed = $true

	foreach ($path in @($ModPath)) {
		if ([string]::IsNullOrWhiteSpace($path)) {
			continue
		}
		try {
			$global:LASTEXITCODE = 0
			& $Command plugin validate $path *> $null
			if ($LASTEXITCODE -ne 0) {
				$result.Invalid += $path
			}
		}
		catch {
			Write-LogDebug "claude plugin validate threw for [$path] => $($_.Exception.Message)"
			$result.Invalid += $path
		}
	}

	return $result
}
