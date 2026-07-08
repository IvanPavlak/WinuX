function Focus-TerminalTab {
	<#
    .SYNOPSIS
        Focuses Windows Terminal and optionally navigates to a specific tab by title.

    .DESCRIPTION
        Activates the Windows Terminal window. If a TargetTitle is provided, cycles through
        tabs using Ctrl+Tab until the tab with the matching title is found and focused.

    .PARAMETER TargetTitle
        The title of the tab to focus. If not specified, only activates the Windows Terminal window.

    .PARAMETER Quiet
        Suppress the "[Focusing Terminal Tab]" section title and the "Focused Windows Terminal!"
        success message. Used when this function is invoked as an internal sub-step of another
        action (e.g. Focus-VirtualDesktop), so the parent owns the visible section output instead
        of this nested call printing a competing title.

    .EXAMPLE
        Focus-TerminalTab
        Activates the Windows Terminal window without switching tabs.

    .EXAMPLE
        Focus-TerminalTab -TargetTitle "PowerShell"
        Activates the Windows Terminal window and cycles to the tab titled "PowerShell".
    #>
	[CmdletBinding()]
	param(
		[Parameter()]
		[string]$TargetTitle,

		[Parameter()]
		[switch]$Quiet
	)

	if (-not $Quiet) { Write-LogTitle "Focusing Terminal Tab" }

	$wtProcess = Get-Process | Where-Object { $_.ProcessName -eq "WindowsTerminal" } | Select-Object -First 1

	if (-not $wtProcess) {
		Write-LogDebug " Windows Terminal is not running" -Style Warning
		return
	}

	[void][System.Reflection.Assembly]::LoadWithPartialName("Microsoft.VisualBasic")
	try {
		[Microsoft.VisualBasic.Interaction]::AppActivate($wtProcess.Id)
	}
	catch {
		# Process may have exited or lacks a visible window - fall back to window handle
		$wtWindow = Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue | Select-Object -First 1
		if ($wtWindow) {
			[void][WindowModule.Native]::SetForegroundWindow($wtWindow.Handle)
		}
		else {
			Write-LogDebug " Could not activate Windows Terminal window" -Style Warning
			return
		}
	}

	if (-not $TargetTitle) {
		if (-not $Quiet) { Write-LogSuccess "Focused Windows Terminal!" }
		return
	}

	Write-LogDebug " Refocusing on starting tab => [$TargetTitle]..."

	Add-Type -AssemblyName System.Windows.Forms

	$maxAttempts = 20
	for ($i = 0; $i -lt $maxAttempts; $i++) {
		$currentWindow = Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue | Select-Object -First 1
		$currentTitle = if ($currentWindow) { $currentWindow.Title } else { $null }

		if ($currentTitle -eq $TargetTitle) {
			if (-not $Quiet) { Write-LogSuccess "Focused Windows Terminal tab => [$TargetTitle]!" }
			break
		}

		# Move to next tab
		[System.Windows.Forms.SendKeys]::SendWait("^{TAB}")
		Start-Sleep -Milliseconds 10
	}
}
