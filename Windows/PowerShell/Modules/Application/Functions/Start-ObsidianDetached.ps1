function Start-ObsidianDetached {
	<#
	.SYNOPSIS
		Launches Obsidian for a vault without tying it to this shell's console.

	.DESCRIPTION
		Starts Obsidian.exe (Get-ObsidianExecutablePath) with the obsidian:// URI through
		Start-ProcessDetached, so the new Obsidian owns no console and closing the terminal that
		ran Open-Obsidian leaves it standing. The fallback, when the executable cannot be located
		or WMI refuses, is the URI through Start-Process; that path shares this shell's console.

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

	$null = Start-ProcessDetached -FilePath (Get-ObsidianExecutablePath) -ArgumentList "`"$uri`"" -Fallback @{ FilePath = $uri }
}
