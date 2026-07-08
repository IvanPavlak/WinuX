function Invoke-TerminateWindowsTerminalTabsIncludeCurrentCleanup {
	<#
	.SYNOPSIS
		Finalizes `-IncludeCurrent` cleanup for terminal tab closure.

	.DESCRIPTION
		Prints the final closed-tab summary, restores the original host window title,
		spawns a safety-net PowerShell process to force-close the hosting Windows
		Terminal process if it lingers, and then invokes the exit seam.

	.PARAMETER ClosedTabs
		Titles of terminal tabs that were closed before the current tab cleanup step.

	.PARAMETER StartingTitle
		Original title of the current terminal tab.

	.PARAMETER OriginalHostTitle
		Original PowerShell host title to restore before exiting.

	.PARAMETER CloseWaitSeconds
		Waits before closing the current tab so the caller can read the final status
		output before the shell exits.

	.EXAMPLE
		Invoke-TerminateWindowsTerminalTabsIncludeCurrentCleanup -ClosedTabs @('TabA') -StartingTitle 'CurrentTab' -OriginalHostTitle 'OriginalTitle'
		Finalizes cleanup and exits the current terminal tab.
	#>
	[CmdletBinding()]
	param(
		[Parameter()]
		[string[]]$ClosedTabs,

		[Parameter()]
		[string]$StartingTitle,

		[Parameter()]
		[string]$OriginalHostTitle,

		[Parameter()]
		[ValidateRange(0, 300)]
		[int]$CloseWaitSeconds = 0
	)

	$closedTabsToReport = @($ClosedTabs)
	if ($StartingTitle) {
		$closedTabsToReport += $StartingTitle
	}

	Write-LogDebug "  Closing current tab via clean process exit" -Style Warning

	Write-LogSuccess "Closed [$($closedTabsToReport.Count)] terminal tab(s)"

	try { $Host.UI.RawUI.WindowTitle = $OriginalHostTitle } catch {}

	if ($CloseWaitSeconds -gt 0) {
		Write-LogDebug " Waiting $CloseWaitSeconds second(s) before exiting the current tab" -Style Step

		Start-Sleep -Seconds $CloseWaitSeconds
	}

	$currentWtPid = (Get-Process -Name "WindowsTerminal" -ErrorAction SilentlyContinue | Select-Object -First 1).Id
	if ($currentWtPid) {
		$cleanupCommand = "Start-Sleep -Seconds 2; if (Get-Process -Id $currentWtPid -ErrorAction SilentlyContinue) { Stop-Process -Id $currentWtPid -Force -ErrorAction SilentlyContinue }"
		Start-Process powershell.exe -ArgumentList "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-Command", $cleanupCommand -WindowStyle Hidden
	}

	Invoke-TerminateWindowsTerminalTabsExit
}
