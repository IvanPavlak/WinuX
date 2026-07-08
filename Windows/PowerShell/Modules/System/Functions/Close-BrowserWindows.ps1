function Close-BrowserWindows {
	<#
	.SYNOPSIS
		Posts `WM_CLOSE` to each supplied browser window handle.

	.DESCRIPTION
		Gracefully closes browser windows by posting `WM_CLOSE` directly to each
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
		[Win32BrowserHelper]::PostMessage($window.Handle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
	}
}
