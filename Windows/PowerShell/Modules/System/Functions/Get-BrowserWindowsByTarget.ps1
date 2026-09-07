function Get-BrowserWindowsByTarget {
	<#
	.SYNOPSIS
		Finds visible browser windows for the specified process IDs.

	.DESCRIPTION
		Enumerates top-level windows via the `Win32BrowserHelper` type and returns every
		visible, titled window owned by the specified process IDs.

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

	$collectCallback = {
		param($hwnd, $lParam)

		$processId = 0
		[Win32BrowserHelper]::GetWindowThreadProcessId($hwnd, [ref]$processId) | Out-Null

		if ($TargetPids -contains $processId -and [Win32BrowserHelper]::IsWindowVisible($hwnd)) {
			$length = [Win32BrowserHelper]::GetWindowTextLength($hwnd)
			if ($length -gt 0) {
				$sb = New-Object System.Text.StringBuilder($length + 1)
				[void][Win32BrowserHelper]::GetWindowText($hwnd, $sb, $sb.Capacity)
				$title = $sb.ToString()

				[void]$browserWindows.Add([PSCustomObject]@{
						Handle         = $hwnd
						Title          = $title
						ProcessId      = [int]$processId
						MatchesPattern = [bool]($TitlePattern -and $title -match $TitlePattern)
					})
			}
		}

		return $true
	}

	[Win32BrowserHelper]::EnumWindows($collectCallback, [IntPtr]::Zero) | Out-Null
	return @($browserWindows)
}
