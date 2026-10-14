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
		Repair-TerminalIconsThemeCache probes the module's theme cache - a file torn by two shells
		importing at the same instant makes every import fail until it is moved aside - and the
		import runs again, up to three attempts in all. The import is retried whether or not this
		shell moved anything: when several shells start together, another one may have moved the
		torn file aside first, or may still be rewriting the cache this shell just read. A success
		line reports a repair this shell made; an import that succeeded only on a later attempt
		without one is a Debug line. When every attempt fails, the error is logged with
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
		[bool] - $true when Terminal-Icons is loaded, $false when it is not installed or every
		import attempt failed.

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

	# One import and two repair-and-retry rounds: the second round covers a shell whose first retry
	# met another shell's rewrite of the cache mid-write.
	$maxAttempts = 3
	$imported = $false
	$lastError = $null
	$quarantined = [System.Collections.Generic.List[System.IO.FileInfo]]::new()

	for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
		try {
			Import-Module -Name Terminal-Icons -Global -ErrorAction Stop
			$imported = $true
			Write-LogDebug "Terminal-Icons imported on attempt [$attempt]"
			break
		}
		catch {
			$lastError = $_
			Write-LogDebug "Terminal-Icons import attempt [$attempt] failed => $($lastError.Exception.Message)"
		}

		if ($attempt -lt $maxAttempts) {
			foreach ($moved in @(Repair-TerminalIconsThemeCache)) {
				$quarantined.Add($moved)
			}
		}
	}

	if ($imported -and $quarantined.Count -gt 0) {
		Write-LogSuccess "Terminal-Icons imported after moving [$($quarantined.Count)] unreadable theme cache file(s) aside"
	}
	elseif (-not $imported -and $quarantined.Count -eq 0) {
		Write-LogError "Terminal-Icons failed to import [$maxAttempts] times, and its theme cache parses => $($lastError.Exception.Message)" -Exception $lastError
	}
	elseif (-not $imported) {
		Write-LogError "Terminal-Icons still fails to import after its theme cache was repaired => $($lastError.Exception.Message)" -Exception $lastError
	}

	# A quiet late success (another shell made the repair) printed nothing but Debug lines.
	if ($RedrawPrompt -and ($quarantined.Count -gt 0 -or -not $imported)) {
		$null = Restore-ShellPrompt
	}

	return $imported
}
