function Get-WindowDisplayName {
	<#
	.SYNOPSIS
		Resolves a friendly display label for a window from its process name, falling back to its title.

	.DESCRIPTION
		Returns a stable, human-friendly label for a window so output lists read cleanly regardless of
		the window's live title. Known processes are mapped to a product name (for example WindowsTerminal
		=> "Windows Terminal", whose live title follows the active tab/profile); any other process falls
		back to the supplied window title. Used by the window-listing functions (Center-Windows,
		Move-Windows) to label the windows they acted on.

	.PARAMETER ProcessName
		The window's owning process name (without .exe), as returned by Get-CachedWindows / Get-WindowHandle.

	.PARAMETER Title
		The window title, used as the label for processes without a friendly-name mapping.

	.EXAMPLE
		Get-WindowDisplayName -ProcessName "WindowsTerminal" -Title "PowerShell"
		Returns "Windows Terminal".

	.EXAMPLE
		Get-WindowDisplayName -ProcessName "chrome" -Title "GitHub - Google Chrome"
		Returns "GitHub - Google Chrome" (no friendly mapping, falls back to the title).
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[string]$ProcessName,

		[Parameter(Mandatory = $false)]
		[AllowEmptyString()]
		[string]$Title
	)

	# Friendly display names for known processes; anything else falls back to the window title.
	$friendlyProcessNames = @{
		WindowsTerminal = 'Windows Terminal'
	}

	if ($friendlyProcessNames.ContainsKey($ProcessName)) {
		return $friendlyProcessNames[$ProcessName]
	}

	return $Title
}
