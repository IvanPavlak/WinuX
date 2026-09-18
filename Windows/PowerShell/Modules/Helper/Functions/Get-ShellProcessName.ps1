function Get-ShellProcessName {
	<#
	.SYNOPSIS
		Names the processes that are the Windows shell itself, or that host other applications' windows.

	.DESCRIPTION
		The one list of processes no cleanup, teardown or ownership claim may reach for: explorer is
		the shell; ApplicationFrameHost owns the frames of every packaged app (the apps themselves are
		enumerated through their own CoreWindow); the rest are the Start menu, Search, text input,
		lock-screen and notification surfaces (ShellExperienceHost) that Windows restarts on its own,
		and dwm and sihost, which never own a user window at all.

		Get-VisibleWindowProcess never reports them, and a plain Open-Workspace never adopts their
		windows, so a notification popup that happened to be on screen is not a workspace's to close.
		Both read the list from here rather than each carrying a copy.

	.OUTPUTS
		[string[]] Process names, without extension.

	.EXAMPLE
		$shell = [System.Collections.Generic.HashSet[string]]::new([string[]](Get-ShellProcessName), [System.StringComparer]::OrdinalIgnoreCase)
		if ($shell.Contains($window.ProcessName)) { continue }
	#>
	[CmdletBinding()]
	[OutputType([string[]])]
	param()

	return @(
		'explorer',
		'ApplicationFrameHost',
		'TextInputHost',
		'ShellExperienceHost',
		'StartMenuExperienceHost',
		'SearchHost',
		'SearchApp',
		'LockApp',
		'sihost',
		'dwm'
	)
}
