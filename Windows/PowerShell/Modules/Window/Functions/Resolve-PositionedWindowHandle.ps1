function Resolve-PositionedWindowHandle {
	<#
	.SYNOPSIS
		Re-resolves a possibly stale tracked window handle to a live window.

	.DESCRIPTION
		Given a tracked window state (with WindowTitle and optional process fingerprint),
		searches the current windows to find the matching live window. It enumerates the
		window list once via Get-CachedWindows and filters in memory: by tracked title
		(literal substring match), then by process name, then by the captured process ID
		when a fingerprint was recorded. This lets Snap-AllWindows recover when a window
		was recreated or its handle was reassigned during a long-running session - the
		primary reason snaps fail only in reused shells but succeed from a fresh shell.
		Returns the first matching live window, or $null.

	.PARAMETER WindowState
		The tracked window state object. Expected members: WindowTitle, ProcessName, ProcessId.

	.OUTPUTS
		The first matching live window object from the cached window list, or $null when no match is found.

	.EXAMPLE
		$fresh = Resolve-PositionedWindowHandle -WindowState $tracked
		if ($fresh) { $handle = $fresh.Handle }
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[object]$WindowState
	)

	# Enumerate the window list a single time instead of issuing multiple Get-WindowHandle
	# calls (each of which would re-run EnumWindows) during snap recovery loops.
	$candidates = @(Get-CachedWindows)

	if ($WindowState.WindowTitle) {
		# Escape the captured title so dynamic captions are matched literally (substring), not as regex.
		$titlePattern = [regex]::Escape($WindowState.WindowTitle)
		$candidates = @($candidates | Where-Object { -not [string]::IsNullOrEmpty($_.Title) -and $_.Title -match $titlePattern })
	}

	if ($WindowState.ProcessName) {
		# Process name is a literal captured name - match exactly to avoid grabbing a
		# same-titled window owned by a different process.
		$candidates = @($candidates | Where-Object { $_.ProcessName -eq $WindowState.ProcessName })
	}

	if ($WindowState.ProcessId -and $WindowState.ProcessId -gt 0) {
		# Strongest signal: only accept a window owned by the originally tracked process.
		$candidates = @($candidates | Where-Object { [uint32]$_.ProcessId -eq [uint32]$WindowState.ProcessId })
	}

	return $candidates | Select-Object -First 1
}
