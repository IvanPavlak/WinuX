function Start-VSCodeDetached {
	<#
	.SYNOPSIS
		Launches VS Code without tying it to this shell's console.

	.DESCRIPTION
		Starts Code.exe (Get-VSCodeExecutablePath) through Start-ProcessDetached, so the new
		VS Code owns no console. The fallback, when the executable cannot be located or WMI
		refuses, is `code` through Start-Process -NoNewWindow - the previous launch shape, which
		hands this shell's console down to VS Code. Open-VSCode and Open-VSCodeWorkspace launch
		through this function.

		A VS Code that is already running is unaffected either way: `code -n` then hands the
		folder to the running instance and exits. The detached launch matters for a cold start
		from a shell that exits afterwards, such as a workspace ending in
		Terminate-WindowsTerminalTabs -OnlyCurrent (see "The Workspace Tab Stays Open After
		[Closing current terminal tab]" in docs/winux/reference/troubleshooting.md).

	.PARAMETER ArgumentList
		Arguments for VS Code, as given to Start-Process -ArgumentList, e.g. "-n", "`"<folder>`"".
		Quote a path that may contain spaces yourself. Omit to open an empty window.

	.EXAMPLE
		Start-VSCodeDetached -ArgumentList "-n", "`"C:\Projects\MyProject`""
		Opens the folder in a new VS Code window that outlives this terminal tab.

	.EXAMPLE
		Start-VSCodeDetached
		Opens VS Code without a folder.
	#>
	[CmdletBinding()]
	param (
		[Parameter()]
		[string[]]$ArgumentList
	)

	$fallback = @{
		FilePath    = "code"
		NoNewWindow = $true
		ErrorAction = 'Stop'
	}
	if ($ArgumentList) {
		$fallback['ArgumentList'] = $ArgumentList
	}

	$null = Start-ProcessDetached -FilePath (Get-VSCodeExecutablePath) -ArgumentList $ArgumentList -Fallback $fallback
}
