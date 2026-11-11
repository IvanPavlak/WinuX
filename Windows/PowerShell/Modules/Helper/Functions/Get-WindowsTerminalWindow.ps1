function Get-WindowsTerminalWindow {
	<#
	.SYNOPSIS
		Lists the Windows Terminal windows that hold tabs, leaving out Windows Terminal's own helper windows.

	.DESCRIPTION
		The one lookup every function uses to find Windows Terminal windows. It returns the
		windows of the WindowsTerminal process (Get-WindowHandle -ProcessName WindowsTerminal) in
		the same order, minus the helper windows Windows Terminal opens for itself.

		Such a helper window is visible and has a title, so the window enumeration lists it next
		to the real terminal windows, and it can come first. It has no tab strip: a caller that
		took it for "the" terminal window could not read its tabs, and one that walked the tabs
		by keystrokes could mistake its own tab for someone else's and close it. The helper
		windows are recognised by their exact title: "PopupHost".

	.OUTPUTS
		The window records of Get-WindowHandle (Handle, Title, ProcessName, ProcessId, ...), one per
		Windows Terminal window, or nothing when none is open.

	.EXAMPLE
		$terminalWindow = Get-WindowsTerminalWindow | Select-Object -First 1
		Gets the first real Windows Terminal window.

	.EXAMPLE
		@(Get-WindowsTerminalWindow | Where-Object { $_.Handle -ne $currentHandle })
		Lists every other Windows Terminal window.
	#>
	[CmdletBinding()]
	[OutputType([object])]
	param()

	# Exact, case-sensitive titles of the windows Windows Terminal opens for itself.
	$helperWindowTitles = @('PopupHost')

	foreach ($window in @(Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue)) {
		if (-not $window) { continue }
		if ($helperWindowTitles -ccontains [string]$window.Title) { continue }
		$window
	}
}
