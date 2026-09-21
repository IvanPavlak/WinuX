function Complete-ObsidianWorkspaceLoad {
	<#
	.SYNOPSIS
		Finishes an Obsidian workspace load that Open-Obsidian -Deferred handed back to the flow.

	.DESCRIPTION
		The tail Open-Obsidian registers through Register-DeferredAction when it runs inside a
		workspace open: the checked load (Invoke-ObsidianWorkspaceLoad), then the success line
		Open-Obsidian itself would have printed. Complete-DeferredActions runs it once the
		remaining openers have run.

		Deferring pays because on a cold start the CLI cannot answer until Obsidian has finished
		its own startup, and Open-Obsidian used to stand still for all of it while every opener
		behind it waited its turn. Run after them, Obsidian has normally booted in the meantime,
		so the load is attempted FIRST and the readiness poll (Wait-ObsidianCli, itself a CLI
		process launch) is paid only when that first attempt comes back "unable to find
		Obsidian" on a cold start - the one refusal that means "not yet", not "no". Any other
		refusal is final and is reported as such without a poll or a second attempt.

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
		Obsidian was launched by the deferring call and may still be starting: a "not yet up"
		refusal on the first attempt is followed by the readiness poll and one more attempt.
		Omit for a load against an already-running Obsidian, where that refusal is final.

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

	# Load first. By the time the flow drains, Obsidian has usually been up for seconds, and the
	# readiness poll would be one more process launch to learn what the load itself reports.
	$result = Invoke-ObsidianWorkspaceLoad -CliPath $CliPath -Vault $Vault -Name $Name -Silent:$ColdStart

	if (-not $result.Loaded -and $ColdStart) {
		if ($result.Refusal -match 'unable to find Obsidian') {
			# Not yet up. Now the poll earns its cost: wait for the CLI to reach Obsidian, then
			# one more attempt, reported normally.
			if (-not (Wait-ObsidianCli -CliPath $CliPath -Vault $Vault -TimeoutSeconds $TimeoutSeconds)) {
				Write-LogWarning "Obsidian CLI did not answer within $TimeoutSeconds seconds - workspace [$Name] may not be loaded. Run [Open-Obsidian -Workspace $Name] again once it is up."
				return $false
			}
			$result = Invoke-ObsidianWorkspaceLoad -CliPath $CliPath -Vault $Vault -Name $Name
		}
		else {
			# A final refusal (toggle off, launch failure). The first attempt was silent so a
			# transient "not yet up" would not alarm; this one is real and is reported once.
			Write-LogWarning $result.Message
		}
	}

	if ($result.Loaded) {
		Write-LogSuccess "Obsidian opened in workspace [$Name]!"
		return $true
	}

	return $false
}
