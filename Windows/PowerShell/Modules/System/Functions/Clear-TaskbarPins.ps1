function Clear-TaskbarPins {
	<#
	.SYNOPSIS
		Clears all pinned taskbar items by deleting the Taskband registry key.

	.DESCRIPTION
		Deletes `HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband` and
		its subkeys to remove all taskbar pins. Restarts Explorer to apply the change
		unless `-SkipExplorerRestart` is specified.
		Requires administrator privileges.

	.PARAMETER SkipExplorerRestart
		Skips the Explorer restart after clearing pins. Use when Explorer will be restarted
		by the calling function (e.g. Unpin-TaskbarApps).

	.EXAMPLE
		Clear-TaskbarPins
		Clears all taskbar pins and restarts Explorer.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false)]
		[switch]$SkipExplorerRestart
	)

	Test-AdminPrivileges

	Write-LogTitle "Clearing All Taskbar Pins via Registry"

	$taskbandPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband"

	try {
		if (-not (Test-Path $taskbandPath)) {
			Write-LogWarning "Taskband registry path does not exist. No pins to clear"
			return
		}

		$properties = Get-ItemProperty -Path $taskbandPath -ErrorAction SilentlyContinue

		if (-not $properties) {
			Write-LogWarning "No taskbar pin data found in registry"
			return
		}

		$propertiesToRemove = @("Favorites", "FavoritesResolve", "FavoritesChanges", "FavoritesVersion", "FavoritesRemovedChanges")
		$removedCount = 0

		foreach ($prop in $propertiesToRemove) {
			try {
				$value = Get-ItemProperty -Path $taskbandPath -Name $prop -ErrorAction SilentlyContinue
				if ($value) {
					Remove-ItemProperty -Path $taskbandPath -Name $prop -Force -ErrorAction Stop
					Write-LogStep "   - Removed registry value => [$prop]" -NoLeadingNewline
					$removedCount++
				}
			}
			catch {
				Write-Host -ForegroundColor Yellow "   - Could not remove $($prop): $($_.Exception.Message)"
			}
		}

		if ($removedCount -eq 0) {
			Write-LogWarning "No taskbar pin properties found to remove"
		}
		else {
			Write-LogSuccess "Cleared [$removedCount] taskbar pin registry values!"
		}

		if (-not $SkipExplorerRestart) {
			Restart-Explorer -Message "Waiting for Explorer to fully restart and clear taskbar pins..."

			Write-LogSuccess "All taskbar pins have been cleared!"
		}
	}
	catch {
		Write-LogError "Failed to clear taskbar pins: $($_.Exception.Message)"
		return
	}
}
