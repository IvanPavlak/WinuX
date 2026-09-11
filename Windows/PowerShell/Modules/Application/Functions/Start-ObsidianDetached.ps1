function Start-ObsidianDetached {
	<#
	.SYNOPSIS
		Launches Obsidian for a vault without tying it to this shell's console.

	.DESCRIPTION
		Creates the process through WMI (Win32_Process.Create), whose parent is the WMI provider
		host - no console to inherit, so closing the terminal that ran Open-Obsidian leaves
		Obsidian standing. Falls back to the obsidian:// URI through Start-Process when the
		executable cannot be located or WMI refuses; that path inherits the console.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Vault
	)

	$uri = "obsidian://open?vault=$([uri]::EscapeDataString($Vault))"
	$exe = Get-ObsidianExecutablePath

	if ($exe) {
		try {
			$result = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = "`"$exe`" `"$uri`"" } -ErrorAction Stop
			if ($result.ReturnValue -eq 0) {
				Write-LogDebug " [Open-Obsidian] Launched detached => [$exe] pid $($result.ProcessId)" -Style Success
				return
			}
			Write-LogDebug " [Open-Obsidian] Win32_Process.Create returned $($result.ReturnValue) - falling back to the URI" -Style Warning
		}
		catch {
			Write-LogDebug " [Open-Obsidian] Detached launch failed => $($_.Exception.Message) - falling back to the URI" -Style Warning
		}
	}
	else {
		Write-LogDebug " [Open-Obsidian] Obsidian.exe not found - launching through the URI handler (Obsidian will share this shell's console)" -Style Warning
	}

	Start-Process $uri
}
