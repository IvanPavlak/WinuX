function Invoke-ObsidianWorkspaceLoad {
	<#
	.SYNOPSIS
		Loads a saved Obsidian workspace through the CLI and reports a refusal truthfully.

	.DESCRIPTION
		The one checked `workspace:load` call. The CLI answers some requests instead of doing the
		work, and each of these is a refusal - never a success line:
		- "Command line interface is not enabled" - the per-machine toggle is off.
		- "unable to find Obsidian" - Obsidian gone or not yet up.
		- "Error: Workspace "<Name>" not found." - the name is not saved in the vault (the CLI
		  exits 0 with it, so only the text tells).
		- "CLI call failed" / "CLI call timed out" - the lines Invoke-ObsidianCli synthesises for a
		  launch failure and for a call that did not exit within -TimeoutSeconds.
		- no answer at all.
		A refusal is reported together with its fix, unless -Silent, and the result says which line
		refused so a caller can tell a transient "not yet up" from a permanent one.

		A timed-out call is not taken at its word: Obsidian may have applied the load while the
		CLI's reply was lost, so the vault's workspace list is read once (`workspaces`, which marks
		the active one) and a "<Name> (active)" entry counts as loaded.

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

	.PARAMETER TimeoutSeconds
		Longest wait for the load call (Invoke-ObsidianCli -TimeoutSeconds). Default 5.

	.OUTPUTS
		PSCustomObject with:
		- Loaded  : $true when the CLI accepted the load (or, after a timeout, the workspace is active)
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
		[switch]$Silent,

		[Parameter()]
		[ValidateRange(0.1, 600)]
		[double]$TimeoutSeconds = 5
	)

	# Lines the CLI answers instead of doing the work, and the two Invoke-ObsidianCli synthesises.
	$cliRefusal = 'not enabled|unable to find Obsidian|^Error:|^CLI call failed|^CLI call timed out'

	$answer = @(Invoke-ObsidianCli -CliPath $CliPath -Arguments @("vault=$Vault", 'workspace:load', "name=$Name") -TimeoutSeconds $TimeoutSeconds)
	$refusal = @($answer | Where-Object { $_ -match $cliRefusal }) | Select-Object -First 1
	if (-not $refusal -and $answer.Count -eq 0) { $refusal = 'The CLI gave no answer' }

	if ($refusal -match '^CLI call timed out') {
		# The reply may be what got lost, not the load: ask which workspace is active.
		$active = @(Invoke-ObsidianCli -CliPath $CliPath -Arguments @("vault=$Vault", 'workspaces') -TimeoutSeconds 2)
		if ($active -contains "$Name (active)") {
			Write-LogDebug " [Open-Obsidian] Load call timed out, but [$Name] is the active workspace" -Style Success
			return [PSCustomObject]@{ Loaded = $true; Refusal = $null; Message = $null }
		}
	}

	if ($refusal) {
		$fix = switch -Regex ($refusal) {
			'^Error:' { "Check the name against the vault's saved workspaces (Get-ObsidianWorkspaceNames)." }
			'unable to find Obsidian|^CLI call timed out|no answer' { "Obsidian did not answer - run [Open-Obsidian -Workspace $Name] again once it responds." }
			default { "Run [Enable-ObsidianCli] with Obsidian closed, or enable it under Settings > General > Advanced > Command line interface." }
		}
		$message = "Obsidian workspace [$Name] not loaded => $refusal $fix"
		if (-not $Silent) { Write-LogWarning $message }
		return [PSCustomObject]@{ Loaded = $false; Refusal = [string]$refusal; Message = $message }
	}

	return [PSCustomObject]@{ Loaded = $true; Refusal = $null; Message = $null }
}
