function Wait-BrowserWindowReady {
	<#
	.SYNOPSIS
		Waits until a browser has at least one visible window.

	.DESCRIPTION
		Polls the window list until at least one window of the given process
		(optionally narrowed by a title regex) is present, or the timeout
		expires. Returns `$true` when a window appeared, `$false` on timeout.

		Used by `Open-Browser`'s `-Instances` mode as a cold-start gate: when
		the browser is not running yet, launches fired while the first instance
		is still bootstrapping are silently dropped (Chromium's process
		singleton is not accepting hand-offs yet). Waiting for the first window
		before bursting the remaining launches makes the requested instance
		count reliable.

	.PARAMETER ProcessName
		Process name (without .exe) whose windows to wait for, e.g. "msedge".

	.PARAMETER TitlePattern
		Optional title regex a window must also match - used to tell apart
		browsers that share a process name (Firefox vs. Tor Browser).

	.PARAMETER TimeoutSeconds
		Maximum time to wait. Defaults to 30 seconds; fast browsers exit the
		poll in well under a second per 250ms tick.

	.EXAMPLE
		Wait-BrowserWindowReady -ProcessName "brave"
		Waits until a Brave window exists (or 30s pass).

	.EXAMPLE
		Wait-BrowserWindowReady -ProcessName "msedge" -TitlePattern "Microsoft.{0,2}Edge" -TimeoutSeconds 10
		Waits up to 10s for an Edge window.
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param(
		[Parameter(Mandatory = $true)]
		[string]$ProcessName,

		[Parameter()]
		[string]$TitlePattern,

		[Parameter()]
		[int]$TimeoutSeconds = 30
	)

	$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)

	do {
		$browserWindows = @(Get-WindowHandle -ProcessName $ProcessName -ErrorAction SilentlyContinue)
		if ($TitlePattern) {
			$browserWindows = @($browserWindows | Where-Object { $_.Title -match $TitlePattern })
		}

		if ($browserWindows.Count -gt 0) {
			return $true
		}

		Start-Sleep -Milliseconds 250
	} while ([DateTime]::UtcNow -lt $deadline)

	Write-LogDebug " [Wait-BrowserWindowReady] No [$ProcessName] window appeared within [$TimeoutSeconds]s - continuing anyway" -Style Warning
	return $false
}
