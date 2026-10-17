function Start-VSCodeDetached {
	<#
	.SYNOPSIS
		Launches VS Code without tying it to this shell's console.

	.DESCRIPTION
		Resolves Code.exe (Get-VSCodeExecutablePath) and creates it through Start-ProcessDetached
		(WMI, Win32_Process.Create), so the new VS Code owns no console. Falls back to `code`
		through Start-Process -NoNewWindow when the executable cannot be located or WMI refuses;
		that path hands the shell's console down code.cmd, cmd.exe and the VS Code CLI to the
		VS Code main process, which then holds it for as long as VS Code runs.

		Why it matters: Windows Terminal closes a tab only when every process attached to the
		tab's console has disconnected. A workspace whose last action is
		Terminate-WindowsTerminalTabs -OnlyCurrent exits its shell, but a VS Code cold-started
		from that shell with a plain Start-Process -NoNewWindow kept the console, and the tab
		stayed open with no "[process exited with code ...]" line. A VS Code that is already
		running is not affected: `code -n` then hands the folder to the running instance and
		exits.

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

	$exe = Get-VSCodeExecutablePath
	if ($exe) {
		$processId = Start-ProcessDetached -FilePath $exe -ArgumentList $ArgumentList
		if ($processId) {
			return
		}
		Write-LogDebug " [Start-VSCodeDetached] Detached launch failed - falling back to code on PATH (VS Code will share this shell's console)" -Style Warning
	}
	else {
		Write-LogDebug " [Start-VSCodeDetached] Code.exe not found - launching code on PATH (VS Code will share this shell's console)" -Style Warning
	}

	$startParams = @{
		FilePath    = "code"
		NoNewWindow = $true
		ErrorAction = 'Stop'
	}
	if ($ArgumentList) {
		$startParams['ArgumentList'] = $ArgumentList
	}
	Start-Process @startParams
}
