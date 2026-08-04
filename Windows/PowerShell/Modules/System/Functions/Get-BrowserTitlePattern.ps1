function Get-BrowserTitlePattern {
	<#
	.SYNOPSIS
		Returns the window title regex that identifies a browser's main windows.

	.DESCRIPTION
		Maps a browser name (a key of `Configuration.Universal.Browsers`) to the
		regular expression that identifies that browser's visible top-level
		windows by title. Returns `$null` for unknown browser names.

		This is the single source of truth for browser window identification,
		shared by `Terminate-AllBrowserProcesses` (to find the windows to close)
		and `Open-Browser`'s `-Instances` mode (to count only the target
		browser's existing windows - Firefox and Tor Browser share the
		firefox.exe process name, so a process-level count cannot tell them
		apart).

		The Edge pattern allows up to two arbitrary characters between
		"Microsoft" and "Edge" because Edge's real window title embeds a
		zero-width space (U+200B) before the regular space: "Microsoft​ Edge".
		U+200B is a format character, not whitespace, so neither a literal space
		nor `\s` matches it.

	.PARAMETER BrowserName
		Browser name as configured in `Configuration.Universal.Browsers`
		(e.g. "Firefox", "Tor", "Chrome", "Edge", "Brave").

	.EXAMPLE
		Get-BrowserTitlePattern -BrowserName "Edge"
		Returns the regex matching Microsoft Edge window titles.

	.EXAMPLE
		Get-BrowserTitlePattern -BrowserName "Tor"
		Returns "Tor Browser", distinguishing Tor windows from Firefox ones.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param(
		[Parameter(Mandatory = $true)]
		[string]$BrowserName
	)

	$browserTitlePatterns = @{
		Firefox = "Mozilla Firefox|Firefox Developer Edition|Firefox Nightly"
		Tor     = "Tor Browser"
		Chrome  = "Google Chrome"
		Edge    = "Microsoft.{0,2}Edge"
		Brave   = "Brave"
	}

	return $browserTitlePatterns[$BrowserName]
}
