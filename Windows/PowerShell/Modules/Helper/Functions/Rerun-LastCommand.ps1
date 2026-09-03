function ReRun-LastCommand {
	<#
	.SYNOPSIS
		Reruns a recent command in a fresh PowerShell shell.

	.DESCRIPTION
		When an operation fails (e.g., RPC errors, layout verification failures), this function
		allows you to select from recent command history and rerun it in a fresh non-admin shell.
		This resolves issues that require a clean shell environment.

		Once the fresh shell is up, the original window is closed by posting `WM_CLOSE` to its
		handle: that needs no focus and synthesizes no input. The previous Ctrl+Shift+W hotkey
		closed the window hosting this very process, so the process was torn down mid-injection,
		before the Ctrl/Shift key-ups were sent - both modifiers then stayed logically held for
		the rest of the desktop session (uppercase typing, Enter read as Shift+Enter).

	.PARAMETER NumberOfLastTriggeringCommands
		Number of recent commands to display for selection. Default is 5.

	.PARAMETER ErrorMessage
		Optional custom error message to display before showing command selection.

	.PARAMETER AutoAccept
		If specified, automatically selects the most recent command without prompting the user.

	.PARAMETER Command
		Exact command to rerun in the fresh shell. When provided, PSReadLine history is not
		consulted at all - the shared history file is written incrementally by every open
		pwsh session, so its most recent line can be a command typed in another window.
		Open-Workspace records its resolved invocation through Set-WorkspaceRerunCommand
		(Window module state, never the environment) and Set-WorkspaceWindowLayout passes it
		through here on escalation.

	.EXAMPLE
		ReRun-LastCommand
		# Shows last 5 commands with default RPC error message

	.EXAMPLE
		ReRun-LastCommand -AutoAccept
		# Automatically runs the last command found in history

	.EXAMPLE
		ReRun-LastCommand -AutoAccept -Command "Open-Workspace -Workspace 'WinuX'"
		# Reruns exactly this command; history is never read
	#>
	[CmdletBinding()]
	param(
		[Parameter()]
		[int]$NumberOfLastTriggeringCommands = 5,

		[Parameter()]
		[string]$ErrorMessage = "An error that typically requires a fresh shell to resolve occured!",

		[Parameter()]
		[switch]$AutoAccept,

		# Exact command to rerun. When provided, PSReadLine history is not consulted at all -
		# the shared history file is written incrementally by EVERY open pwsh session, so
		# "most recent line" can be a command the user typed in another window meanwhile.
		[Parameter()]
		[string]$Command
	)

	Write-LogWarning "$ErrorMessage"

	$selectedCommand = $null

	if (-not [string]::IsNullOrWhiteSpace($Command)) {
		$selectedCommand = $Command
		Write-LogSuccess "Re-running caller-supplied command => [$selectedCommand]"
	}
	else {
		# Get PSReadLine history file path (contains actual typed commands)
		try {
			$historyPath = (Get-PSReadLineOption).HistorySavePath
		}
		catch {
			Write-LogError "Error: Could not access PSReadLine history. $($_.Exception.Message)"
			return
		}

		if (-not (Test-Path $historyPath)) {
			Write-LogError "No command history file found. Please rerun your command manually."
			return
		}

		# Read history file and get recent commands
		$allCommands = Get-Content $historyPath -ErrorAction SilentlyContinue

		if (-not $allCommands -or $allCommands.Count -eq 0) {
			Write-LogError "No command history available. Please rerun your command manually."
			return
		}

		# Get last N commands (in reverse order - most recent first), filtering out ReRun-LastCommand
		$commands = @()
		for ($i = $allCommands.Count - 1; $i -ge 0 -and $commands.Count -lt $NumberOfLastTriggeringCommands; $i--) {
			$cmd = $allCommands[$i].Trim()

			# Skip empty lines, ReRun-LastCommand invocations, and duplicates
			if ($cmd -and
				$cmd -notmatch '^\s*ReRun-LastCommand' -and
				$commands -notcontains $cmd) {
				$commands += $cmd
			}
		}

		if ($commands.Count -eq 0) {
			Write-LogError "No commands available. Please rerun your command manually."
			return
		}

		if ($AutoAccept) {
			$selectedCommand = $commands[0]
			Write-LogSuccess "Auto-accepting most recent command => [$selectedCommand]"
		}
		else {
			$selectedCommand = Resolve-Selection `
				-OptionList $commands `
				-MenuTitle "[Select a command to re-run in a new shell]" `
				-PromptMessage "Select a command number or press Enter to select [1]" `
				-AllowEmptyPromptResponse:$true

			# Default to first command (most recent) if no selection made
			if ([string]::IsNullOrEmpty($selectedCommand)) {
				$selectedCommand = $commands[0]
				Write-LogSuccess "Defaulting to most recent command => [$selectedCommand]"
			}
		}
	}

	$currentDirectory = (Get-Location).Path

	Write-LogSuccess "Opening new shell with command..."

	# Heal any modifier left logically stuck by the failed run BEFORE driving the
	# terminal with more synthesized input below (Terminate-WindowsTerminalTabs' legacy
	# pass cycles tabs with Ctrl+Tab and closes them with Ctrl+C/Ctrl+W) - a held
	# Shift/Win would corrupt those combos - and so the fresh shell takes over a session
	# with clean keyboard state.
	if (Get-Command Reset-KeyboardModifiers -ErrorAction SilentlyContinue) {
		$null = Reset-KeyboardModifiers -IncludeMouseButton
	}

	# Add Win32 API for closing the original window. Deliberately exposes no focus API:
	# WM_CLOSE is posted straight to the window handle, so nothing here needs the window
	# to be foreground and nothing synthesizes input (see the close call below).
	if (-not ([System.Management.Automation.PSTypeName]'RerunWindowHelper').Type) {
		Add-Type @"
			using System;
			using System.Runtime.InteropServices;

			public class RerunWindowHelper {
				[DllImport("user32.dll")]
				public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

				public const uint WM_CLOSE = 0x0010;
			}
"@
	}

	$wtProcess = Get-Process -Name "WindowsTerminal" -ErrorAction SilentlyContinue
	if ($wtProcess) {
		# AppActivate lives in Microsoft.VisualBasic, which is NOT loaded by default - an
		# unhandled type-resolution error here used to abort the rerun AFTER the retry
		# markers were persisted, leaving the next open in stale window-only retry mode.
		try {
			Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop
			[Microsoft.VisualBasic.Interaction]::AppActivate($wtProcess.Id)
		}
		catch {
			Write-LogDebug " Could not activate Windows Terminal before respawn: $($_.Exception.Message)" -Style Warning
		}
	}

	# Capture the original window handle BEFORE opening new terminal
	$originalWindow = Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue | Select-Object -First 1
	$originalWindowHandle = if ($originalWindow) { $originalWindow.Handle } else { $null }

	Terminate-WindowsTerminalTabs

	$commandToRun = "Set-Location -Path '$currentDirectory'; $selectedCommand"

	Open-Terminal -Command $commandToRun -TabTitles "PowerShell"

	# This timing is important
	Start-Sleep -Milliseconds 500

	# Close the original window deterministically: WM_CLOSE needs no focus and synthesizes no
	# input. The old path focused this window and injected Ctrl+Shift+W - which closes the very
	# window hosting THIS process, so Windows Terminal tore the process down inside SendWait,
	# before the Ctrl/Shift key-ups were injected. Both modifiers then stayed logically held for
	# the rest of the desktop session: the fresh shell typed uppercase and PSReadLine read Enter
	# as Shift+Enter, so commands stopped submitting. Nothing could self-heal it either, because
	# there is no "after" - the process was already gone.
	if ($originalWindowHandle) {
		Write-LogDebug " Closing the original terminal window via WM_CLOSE => [$originalWindowHandle]" -Style Step
		[RerunWindowHelper]::PostMessage($originalWindowHandle, [RerunWindowHelper]::WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
	}

	# [Environment]::Exit skips every finally block, so this is the last chance to release
	# anything the tab-close passes above may have stranded (the legacy pass sends Ctrl+Tab /
	# Ctrl+C / Ctrl+W). Same seam as Invoke-TerminateWindowsTerminalTabsExit.
	if (Get-Command Reset-KeyboardModifiers -ErrorAction SilentlyContinue) {
		$null = Reset-KeyboardModifiers
	}

	Invoke-RerunLastCommandExit
}
