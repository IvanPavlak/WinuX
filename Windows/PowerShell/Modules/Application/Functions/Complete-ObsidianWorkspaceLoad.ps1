function Complete-ObsidianWorkspaceLoad {
	<#
	.SYNOPSIS
		Finishes an Obsidian workspace load that Open-Obsidian -Deferred handed back to the flow.

	.DESCRIPTION
		The tail Open-Obsidian registers through Register-DeferredAction when it runs inside a
		workspace open: wait for the CLI if Obsidian was only just launched, then the checked load
		(Invoke-ObsidianWorkspaceLoad), then the success line Open-Obsidian itself would have
		printed. Complete-DeferredActions runs it once the remaining openers have run.

		Deferring pays because on a cold start the CLI cannot answer until Obsidian has finished
		its own startup - measured at 2.7 s for the readiness probe plus 1.0 s for the load - and
		Open-Obsidian used to stand still for all of it while every opener behind it waited its
		turn. Run after them, Obsidian has booted in the meantime and only the load is left.

		It must run BEFORE the layout's window wait, not during it: Wait-ForWorkspaceWindows holds a
		window stable only while its TITLE and dimensions stop changing, and loading a workspace
		retitles Obsidian's window. Open-Workspace drains the deferred actions immediately before
		the Set-WorkspaceWindowLayout action, which is what makes the deferral safe.

	.PARAMETER CliPath
		Full path to Obsidian.com (Get-ObsidianCliPath).

	.PARAMETER Vault
		Vault name the CLI addresses.

	.PARAMETER Name
		Saved Obsidian workspace to load.

	.PARAMETER ColdStart
		Obsidian was launched by the deferring call and may still be starting: poll the CLI
		(Wait-ObsidianCli) before the load. Omit for a load against an already-running Obsidian,
		which answered before the open began and needs no poll.

	.PARAMETER TimeoutSeconds
		Budget for the readiness poll on a cold start. Default 10.

	.OUTPUTS
		[bool] $true when the CLI accepted the load, $false when it never answered or refused.

	.EXAMPLE
		Complete-ObsidianWorkspaceLoad -CliPath (Get-ObsidianCliPath) -Vault Obsidian -Name Server -ColdStart
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param (
		[Parameter(Mandatory = $true)]
		[string]$CliPath,

		[Parameter(Mandatory = $true)]
		[string]$Vault,

		[Parameter(Mandatory = $true)]
		[string]$Name,

		[Parameter()]
		[switch]$ColdStart,

		[Parameter()]
		[ValidateRange(0, 120)]
		[int]$TimeoutSeconds = 10
	)

	if ($ColdStart) {
		if (-not (Wait-ObsidianCli -CliPath $CliPath -Vault $Vault -TimeoutSeconds $TimeoutSeconds)) {
			Write-LogWarning "Obsidian CLI did not answer within $TimeoutSeconds seconds - workspace [$Name] may not be loaded. Run [Open-Obsidian -Workspace $Name] again once it is up."
			return $false
		}
	}

	if (Invoke-ObsidianWorkspaceLoad -CliPath $CliPath -Vault $Vault -Name $Name) {
		Write-LogSuccess "Obsidian opened in workspace [$Name]!"
		return $true
	}

	return $false
}
