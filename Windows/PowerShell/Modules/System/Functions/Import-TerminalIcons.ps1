function Import-TerminalIcons {
	<#
	.SYNOPSIS
		Imports Terminal-Icons into the session, repairing its theme cache first when a torn cache
		file is what stops the import.

	.DESCRIPTION
		Terminal-Icons draws the file and folder glyphs in directory listings. The profile queues
		this function as the startup stage Terminal-Icons, run after the first prompt from the
		one PowerShell.OnIdle event, because the import was measured at 165-400 ms and the icons
		are only needed once something is listed. -Global, because the queue runs in a scope of
		its own.

		Import-Module Terminal-Icons -Global is the whole happy path. When it throws,
		Repair-TerminalIconsThemeCache probes the module's theme cache: a file torn by two shells
		importing at the same instant makes every import fail until it is moved aside. If the
		repair moved something, the import runs once more and a success line says so. If it found
		nothing to move, or the second import fails as well, the error is logged with
		Write-LogError (console, session log and error log) - a shell without icons always leaves
		a trace. A module that is not installed is a Debug line and $false;
		Install-PowerShellModules installs it.

	.PARAMETER RedrawPrompt
		After something was printed - a quarantine warning, the success line, an error - draw the
		prompt again through Restore-ShellPrompt. The profile passes it: from the idle-time queue
		the prompt is already on screen, so the output pushes it away and PSReadLine keeps
		waiting on a blank line. Nothing is redrawn when the import went quietly, or outside
		PSReadLine.

	.OUTPUTS
		[bool] - $true when Terminal-Icons is loaded, $false when it is not installed or the
		import failed.

	.EXAMPLE
		Import-TerminalIcons
		Loads the module, or reports why it cannot be loaded.

	.EXAMPLE
		Import-TerminalIcons -RedrawPrompt
		What the profile runs after the first prompt.
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param(
		[Parameter()]
		[switch]$RedrawPrompt
	)

	if (-not (Get-Module -ListAvailable -Name Terminal-Icons)) {
		Write-LogDebug "Terminal-Icons is not installed - nothing to import"
		return $false
	}

	$imported = $false
	$printed = $false
	try {
		Import-Module -Name Terminal-Icons -Global -ErrorAction Stop
		$imported = $true
		Write-LogDebug "Terminal-Icons imported"
	}
	catch {
		$firstError = $_
		$printed = $true
		Write-LogDebug "Terminal-Icons failed to import => $($firstError.Exception.Message) - probing its theme cache"
		$quarantined = @(Repair-TerminalIconsThemeCache)

		if ($quarantined.Count -eq 0) {
			Write-LogError "Terminal-Icons failed to import, and its theme cache parses => $($firstError.Exception.Message)" -Exception $firstError
		}
		else {
			try {
				Import-Module -Name Terminal-Icons -Global -ErrorAction Stop
				$imported = $true
				Write-LogSuccess "Terminal-Icons imported after moving [$($quarantined.Count)] unreadable theme cache file(s) aside"
			}
			catch {
				Write-LogError "Terminal-Icons still fails to import after its theme cache was repaired => $($_.Exception.Message)" -Exception $_
			}
		}
	}

	if ($printed -and $RedrawPrompt) {
		$null = Restore-ShellPrompt
	}

	return $imported
}
