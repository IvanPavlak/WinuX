function Wait-ObsidianCli {
	<#
	.SYNOPSIS
		Polls the Obsidian CLI until it reaches the running vault, or the timeout elapses.

	.DESCRIPTION
		Runs `obsidian vault=<Vault> workspaces` repeatedly. While Obsidian is still starting the
		CLI answers "The CLI is unable to find Obsidian" (exit code 1); the first answer without it
		means commands will be executed. A probe that timed out or failed to launch counts as
		"not yet", and each probe's own timeout is the time left to the overall deadline (at
		least 1 s). Returns $true as soon as a probe gets through, $false once the deadline has
		passed.

	.PARAMETER CliPath
		Full path to Obsidian.com (Get-ObsidianCliPath).

	.PARAMETER Vault
		The vault to probe.

	.PARAMETER TimeoutSeconds
		Give up after this many seconds. Default 10.

	.PARAMETER PollMilliseconds
		Pause between probes in milliseconds. Default 200.

	.OUTPUTS
		[bool] $true when the CLI reached the running vault, $false on timeout.

	.EXAMPLE
		Wait-ObsidianCli -CliPath (Get-ObsidianCliPath) -Vault Obsidian -TimeoutSeconds 10
		Waits up to 10 seconds for a just-launched Obsidian to answer the CLI.
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
		# One probe never outlives the poll's own deadline; a probe that timed out is "not yet".
		$remaining = [Math]::Max(1, ($deadline - [DateTime]::UtcNow).TotalSeconds)
		$answer = @(Invoke-ObsidianCli -CliPath $CliPath -Arguments @("vault=$Vault", 'workspaces') -TimeoutSeconds $remaining) -join "`n"
		if ($answer -notmatch 'unable to find Obsidian|^CLI call (timed out|failed)') { return $true }
		Start-Sleep -Milliseconds $PollMilliseconds
	} while ([DateTime]::UtcNow -lt $deadline)

	return $false
}
