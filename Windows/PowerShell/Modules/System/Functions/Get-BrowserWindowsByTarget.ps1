function Get-BrowserWindowsByTarget {
	<#
	.SYNOPSIS
		Finds visible browser windows for the specified process IDs.

	.DESCRIPTION
		Enumerates top-level windows via the `Win32BrowserHelper` type and returns
		only windows owned by the specified process IDs whose titles match the
		provided regular expression.

	.PARAMETER TargetPids
		Process IDs whose top-level windows should be collected.

	.PARAMETER TitlePattern
		Regular expression used to identify the browser's main windows.

	.EXAMPLE
		Get-BrowserWindowsByTarget -TargetPids @(1234) -TitlePattern 'Google Chrome'
		Returns visible Chrome windows owned by process 1234.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[int[]]$TargetPids,

		[Parameter(Mandatory = $true)]
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

				if ($title -match $TitlePattern) {
					[void]$browserWindows.Add([PSCustomObject]@{
							Handle = $hwnd
							Title  = $title
						})
				}
			}
		}

		return $true
	}

	[Win32BrowserHelper]::EnumWindows($collectCallback, [IntPtr]::Zero) | Out-Null
	return @($browserWindows)
}
