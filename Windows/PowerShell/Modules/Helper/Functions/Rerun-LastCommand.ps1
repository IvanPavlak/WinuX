function ReRun-LastCommand {
	<#
	.SYNOPSIS
		Reruns a recent command in a fresh PowerShell shell.

	.DESCRIPTION
		When an operation fails (e.g., RPC errors, layout verification failures), this function
		allows you to select from recent command history and rerun it in a fresh non-admin shell.
		This resolves issues that require a clean shell environment.

	.PARAMETER NumberOfLastTriggeringCommands
		Number of recent commands to display for selection. Default is 5.

	.PARAMETER ErrorMessage
		Optional custom error message to display before showing command selection.

	.PARAMETER AutoAccept
		If specified, automatically selects the most recent command without prompting the user.

	.EXAMPLE
		ReRun-LastCommand
		# Shows last 5 commands with default RPC error message

	.EXAMPLE
		ReRun-LastCommand -AutoAccept
		# Automatically runs the last command found in history
	#>
	[CmdletBinding()]
	param(
		[Parameter()]
		[int]$NumberOfLastTriggeringCommands = 5,

		[Parameter()]
		[string]$ErrorMessage = "An error that typically requires a fresh shell to resolve occured!",

		[Parameter()]
		[switch]$AutoAccept
	)

	Write-LogWarning "$ErrorMessage"

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
			$cmd -notmatch '^\s*ReRun-LastCommand' -and
			$commands -notcontains $cmd) {
			$commands += $cmd
		}
	}

	if ($commands.Count -eq 0) {
		Write-LogError "No commands available. Please rerun your command manually."
		return
	}

	$selectedCommand = $null

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

	$currentDirectory = (Get-Location).Path

	Write-LogSuccess "Opening new shell with command..."

	# Heal any modifier left logically stuck by the failed run BEFORE driving the
	# terminal with more synthesized input below (tab cycling via Ctrl+Tab/Ctrl+W,
	# window close via Ctrl+Shift+W) - a held Shift/Win would corrupt those combos -
	# and so the fresh shell takes over a session with clean keyboard state.
	if (Get-Command Reset-KeyboardModifiers -ErrorAction SilentlyContinue) {
		$null = Reset-KeyboardModifiers -IncludeMouseButton
	}

	# Add Win32 API for window focusing
	if (-not ([System.Management.Automation.PSTypeName]'RerunWindowHelper').Type) {
		Add-Type @"
			using System;
			using System.Runtime.InteropServices;

			public class RerunWindowHelper {
				[DllImport("user32.dll")]
				public static extern bool SetForegroundWindow(IntPtr hWnd);
			}
"@
	}

	Add-Type -AssemblyName System.Windows.Forms

	$wtProcess = Get-Process -Name "WindowsTerminal" -ErrorAction SilentlyContinue
	if ($wtProcess) {
		[Microsoft.VisualBasic.Interaction]::AppActivate($wtProcess.Id)
	}

	# Capture the original window handle BEFORE opening new terminal
	$originalWindow = Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue | Select-Object -First 1
	$originalWindowHandle = if ($originalWindow) { $originalWindow.Handle } else { $null }

	Terminate-WindowsTerminalTabs

	$commandToRun = "Set-Location -Path '$currentDirectory'; $selectedCommand"

	Open-Terminal -Command $commandToRun -TabTitles "PowerShell"

	# This timing is important
	Start-Sleep -Milliseconds 500

	# Focus back on the original window and close it
	if ($originalWindowHandle) {
		[RerunWindowHelper]::SetForegroundWindow($originalWindowHandle) | Out-Null
		Start-Sleep -Milliseconds 250
		[System.Windows.Forms.SendKeys]::SendWait("^+w")
	}

	[Environment]::Exit(0)
}
