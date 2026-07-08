function Get-TargetTerminalWindow {
	<#
	.SYNOPSIS
		Locate a specific Windows Terminal window or get the first available.

	.DESCRIPTION
		Searches for Windows Terminal process windows. If a specific window handle is provided,
		return that window; otherwise return the first Terminal window found.

	.PARAMETER TerminalWindowHandle
		Optional IntPtr handle to look for (default: all windows).

	.EXAMPLE
		$termWin = Get-TargetTerminalWindow
		Write-Host "Terminal handle: $($termWin.Handle)"
	#>
	[CmdletBinding()]
	param(
		[Parameter()]
		[System.IntPtr]$TerminalWindowHandle = [System.IntPtr]::Zero
	)

	$wtWindows = @(Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue)

	if ($TerminalWindowHandle -ne [System.IntPtr]::Zero) {
		$matchedWindow = $wtWindows | Where-Object { $_.Handle -eq $TerminalWindowHandle } | Select-Object -First 1
		if ($matchedWindow) {
			return $matchedWindow
		}
	}

	return $wtWindows | Select-Object -First 1
}
