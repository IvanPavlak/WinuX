function Invoke-ObsidianWorkspaceLoad {
	<#
	.SYNOPSIS
		Loads a saved Obsidian workspace through the CLI and reports a refusal truthfully.

	.DESCRIPTION
		The one checked `workspace:load` call. The CLI answers some requests instead of doing the
		work - the per-machine toggle being off ("Command line interface is not enabled"), Obsidian
		gone or not yet up ("unable to find Obsidian"), and the "CLI call failed" line
		Invoke-ObsidianCli synthesises for a launch failure - and all three used to be swallowed
		by a success line. A refusal is reported together with its fix, unless -Silent, and the
		result says which line refused so a caller can tell a transient "not yet up" from a
		permanent "not enabled".

		Both load sites go through this: Open-Obsidian's immediate path, and
		Complete-ObsidianWorkspaceLoad when the load was deferred by a workspace open.

	.PARAMETER CliPath
		Full path to Obsidian.com (Get-ObsidianCliPath).

	.PARAMETER Vault
		Vault name the CLI addresses.

	.PARAMETER Name
		Saved Obsidian workspace to load.

	.PARAMETER Silent
		Do not write the refusal warning; the caller reads it from the result's Message and
		decides. For an attempt the caller expects may be premature.

	.OUTPUTS
		PSCustomObject with:
		- Loaded  : $true when the CLI accepted the load
		- Refusal : the CLI line that refused it, else $null
		- Message : the warning text for that refusal (the fix included), else $null

	.EXAMPLE
		if ((Invoke-ObsidianWorkspaceLoad -CliPath (Get-ObsidianCliPath) -Vault Obsidian -Name Server).Loaded) { "loaded" }
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Mandatory = $true)]
		[string]$CliPath,

		[Parameter(Mandatory = $true)]
		[string]$Vault,

		[Parameter(Mandatory = $true)]
		[string]$Name,

		[Parameter()]
		[switch]$Silent
	)

	# Lines the CLI answers instead of doing the work. "not enabled" is the per-machine toggle
	# being off (Obsidian.com exists and runs, so Get-ObsidianCliPath cannot tell); the other two
	# are Obsidian gone or not yet answering, and a launch failure reported by Invoke-ObsidianCli.
	$cliRefusal = 'not enabled|unable to find Obsidian|^CLI call failed'

	$answer = @(Invoke-ObsidianCli -CliPath $CliPath -Arguments @("vault=$Vault", 'workspace:load', "name=$Name"))
	$refusal = @($answer | Where-Object { $_ -match $cliRefusal }) | Select-Object -First 1
	if ($refusal) {
		$message = "Obsidian workspace [$Name] not loaded => $refusal Run [Enable-ObsidianCli] with Obsidian closed, or enable it under Settings > General > Advanced > Command line interface."
		if (-not $Silent) { Write-LogWarning $message }
		return [PSCustomObject]@{ Loaded = $false; Refusal = [string]$refusal; Message = $message }
	}

	return [PSCustomObject]@{ Loaded = $true; Refusal = $null; Message = $null }
}
