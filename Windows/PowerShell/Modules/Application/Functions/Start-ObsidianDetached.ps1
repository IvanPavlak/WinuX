function Start-ObsidianDetached {
	<#
	.SYNOPSIS
		Launches Obsidian for a vault without tying it to this shell's console.

	.DESCRIPTION
		Creates the process through Start-ProcessDetached (WMI, Win32_Process.Create), whose parent
		is the WMI provider host - no console to inherit, so closing the terminal that ran
		Open-Obsidian leaves Obsidian standing. Falls back to the obsidian:// URI through
		Start-Process when the executable cannot be located or WMI refuses; that path inherits the
		console.

	.PARAMETER Vault
		The vault name, URI-encoded into obsidian://open?vault=<Vault>.

	.EXAMPLE
		Start-ObsidianDetached -Vault Obsidian
		Starts Obsidian on the vault named Obsidian, detached from this shell.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Vault
	)

	$uri = "obsidian://open?vault=$([uri]::EscapeDataString($Vault))"
	$exe = Get-ObsidianExecutablePath

	if ($exe) {
		$processId = Start-ProcessDetached -FilePath $exe -ArgumentList "`"$uri`""
		if ($processId) {
			Write-LogDebug " [Open-Obsidian] Launched detached => [$exe] pid $processId" -Style Success
			return
		}
		Write-LogDebug " [Open-Obsidian] Detached launch failed - falling back to the URI" -Style Warning
	}
	else {
		Write-LogDebug " [Open-Obsidian] Obsidian.exe not found - launching through the URI handler (Obsidian will share this shell's console)" -Style Warning
	}

	Start-Process $uri
}
