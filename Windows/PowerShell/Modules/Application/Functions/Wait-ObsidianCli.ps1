function Wait-ObsidianCli {
	<#
	.SYNOPSIS
		Polls the Obsidian CLI until it reaches the running vault, or the timeout elapses.

	.DESCRIPTION
		Runs `obsidian vault=<Vault> workspaces` repeatedly. While Obsidian is still starting the
		CLI answers "The CLI is unable to find Obsidian" (exit code 1); the first answer without it
		means commands will be executed.
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param (
		[Parameter(Mandatory = $true)]
		[string]$CliPath,

		[Parameter(Mandatory = $true)]
		[string]$Vault,

		[Parameter()]
		[int]$TimeoutSeconds = 10,

		[Parameter()]
		[int]$PollMilliseconds = 200
	)

	$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
	do {
		$answer = @(Invoke-ObsidianCli -CliPath $CliPath -Arguments @("vault=$Vault", 'workspaces')) -join "`n"
		if ($answer -notmatch 'unable to find Obsidian') { return $true }
		Start-Sleep -Milliseconds $PollMilliseconds
	} while ([DateTime]::UtcNow -lt $deadline)

	return $false
}
