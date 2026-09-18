function Get-BrowserWindowsByTarget {
	<#
	.SYNOPSIS
		Finds visible browser windows for the specified process IDs.

	.DESCRIPTION
		Reads the Window module's enumeration (Get-CachedWindows, which already keeps only
		visible, titled top-level windows) and returns every window owned by the specified
		process IDs.

		The title pattern no longer gates the result. It used to, and that left every
		browser window whose title lacks the brand suffix standing after a cleanup: an
		undocked DevTools window, a Picture-in-Picture player, an installed web app (PWA)
		window, a print or download dialog. Those windows belong to a browser process that
		is being shut down, so they are returned too; `MatchesPattern` records whether the
		title carried the brand marker, for logging and for callers that still want to
		tell two brands sharing one process name apart (Firefox vs. Tor Browser).

	.PARAMETER TargetPids
		Process IDs whose top-level windows should be collected.

	.PARAMETER TitlePattern
		Regular expression identifying the browser's main windows. Optional; sets the
		`MatchesPattern` flag on each returned window rather than filtering.

	.OUTPUTS
		One object per window: Handle, Title, ProcessId, MatchesPattern.

	.EXAMPLE
		Get-BrowserWindowsByTarget -TargetPids @(1234) -TitlePattern 'Google Chrome'
		Returns every visible Chrome window owned by process 1234, main windows flagged.
	#>
	[CmdletBinding()]
	[OutputType([object[]])]
	param(
		[Parameter(Mandatory = $true)]
		[int[]]$TargetPids,

		[Parameter()]
		[string]$TitlePattern
	)

	$browserWindows = New-Object System.Collections.ArrayList

	foreach ($window in @(Get-CachedWindows)) {
		$processId = [int]$window.ProcessId
		if ($TargetPids -notcontains $processId) {
			continue
		}

		[void]$browserWindows.Add([PSCustomObject]@{
				Handle         = [IntPtr]$window.Handle
				Title          = [string]$window.Title
				ProcessId      = $processId
				MatchesPattern = [bool]($TitlePattern -and $window.Title -match $TitlePattern)
			})
	}

	return @($browserWindows)
}
