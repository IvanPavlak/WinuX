function Close-BrowserWindows {
	<#
	.SYNOPSIS
		Posts `WM_CLOSE` to each supplied browser window handle.

	.DESCRIPTION
		Gracefully closes browser windows by posting `WM_CLOSE` through Close-Window to each
		handle collected by `Get-BrowserWindowsByTarget`.

	.PARAMETER WindowsToClose
		Browser window objects containing a `Handle` property.

	.EXAMPLE
		Close-BrowserWindows -WindowsToClose $windows
		Posts `WM_CLOSE` to every handle in `$windows`.
	#>
	[CmdletBinding()]
	param(
		[Parameter()]
		[object[]]$WindowsToClose
	)

	foreach ($window in $WindowsToClose) {
		[void](Close-Window -Handle ([IntPtr]$window.Handle))
	}
}
