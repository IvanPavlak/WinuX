function Focus-TerminalTab {
	<#
    .SYNOPSIS
        Focuses Windows Terminal and optionally navigates to a specific tab by title.

    .DESCRIPTION
        Activates the Windows Terminal window. If a TargetTitle is provided, cycles through
        tabs using Ctrl+Tab until the tab with the matching title is found and focused.

    .PARAMETER TargetTitle
        The title of the tab to focus. If not specified, only activates the Windows Terminal window.

    .PARAMETER WindowHandle
        Activate exactly this Windows Terminal window. Without it the first WindowsTerminal PROCESS
        is activated, and since one process hosts every one of its windows, what comes forward is
        that process's main window - not necessarily the wanted one. Callers that have already
        resolved which terminal window they mean (Focus-VirtualDesktop, which must not let focus
        wander onto a window living on another virtual desktop) pass the handle.

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

    .EXAMPLE
        Focus-TerminalTab -WindowHandle $terminalOnTarget.Handle -Quiet
        Activates that one terminal window, leaving the section output to the calling action.
    #>
	[CmdletBinding()]
	param(
		[Parameter()]
		[string]$TargetTitle,

		[Parameter()]
		[IntPtr]$WindowHandle = [IntPtr]::Zero,

		[Parameter()]
		[switch]$Quiet
	)

	if (-not $Quiet) { Write-LogTitle "Focusing Terminal Tab" }

	# A caller that already knows WHICH terminal window it wants passes the handle, and that exact
	# window is what comes forward. The process path below cannot promise that: AppActivate takes a
	# PROCESS id and one Windows Terminal process hosts every one of its windows, so it activates
	# that process's main window. For Focus-VirtualDesktop - whose entire contract is to leave the
	# user on one virtual desktop - activating a sibling terminal window that lives on a different
	# desktop drags the view straight off the desktop it just switched to.
	if ($WindowHandle -ne [IntPtr]::Zero) {
		# Confirm-WindowForeground (Window module) forces the foreground change AND verifies it took,
		# retrying while the asynchronous focus handoff settles - the same helper Snap-AllWindows
		# relies on before injecting keystrokes.
		$focusAcquired = $false
		if (Get-Command Confirm-WindowForeground -ErrorAction SilentlyContinue) {
			$focusAcquired = Confirm-WindowForeground -WindowHandle $WindowHandle
		}

		if (-not $focusAcquired) {
			[void][WindowModule.Native]::SetForegroundWindow($WindowHandle)
		}
	}
	else {
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
	}

	if (-not $TargetTitle) {
		if (-not $Quiet) { Write-LogSuccess "Focused Windows Terminal!" }
		return
	}

	Write-LogDebug " Refocusing on starting tab => [$TargetTitle]..."

	Add-Type -AssemblyName System.Windows.Forms

	# Judge the cycling by the window that was actually activated. Reading back whichever terminal
	# window is enumerated first would cycle tabs in one window and check the title of another.
	$readTerminalTitle = {
		$candidates = @(Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue)
		if ($WindowHandle -ne [IntPtr]::Zero) {
			$candidates = @($candidates | Where-Object { $_.Handle -eq $WindowHandle })
		}

		$currentWindow = $candidates | Select-Object -First 1
		if ($currentWindow) { $currentWindow.Title } else { $null }
	}

	$maxAttempts = 20
	for ($i = 0; $i -lt $maxAttempts; $i++) {
		$currentTitle = & $readTerminalTitle

		if ($currentTitle -eq $TargetTitle) {
			if (-not $Quiet) { Write-LogSuccess "Focused Windows Terminal tab => [$TargetTitle]!" }
			break
		}

		# Move to next tab
		[System.Windows.Forms.SendKeys]::SendWait("^{TAB}")
		Start-Sleep -Milliseconds 10
	}
}
