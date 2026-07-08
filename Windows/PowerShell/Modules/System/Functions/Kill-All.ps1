function Kill-All {
	<#
	.SYNOPSIS
		Terminates all user processes and cleans up the environment.

	.DESCRIPTION
		Removes all virtual desktops except the first one, then terminates:
		- All configured browser processes (gracefully via WM_CLOSE)
		- All processes with visible windows (except browsers, Rainmeter, WindowsTerminal)
		- Named processes (Code, WhatsApp, Outlook, riseup-vpn)
		- Extra Windows Terminal tabs
		Optionally reloads the PowerShell profile.

		Unless -IncludeCurrent is specified, the surviving Windows Terminal is
		centered on the primary monitor (pulled back from a secondary monitor if
		needed) and refocused, so the run always ends on the terminal.

		If virtual desktop cleanup cannot recover from a VirtualDesktop/RPC failure,
		Remove-VirtualDesktops owns the failure output. Kill-All suppresses the
		nested return value so process cleanup can continue without emitting a raw
		$false value.

	.PARAMETER Exclude
		Array of window title patterns to exclude from termination.
		Supports both wildcard and regex patterns (same format as layout .psd1 files):
		  Wildcard: "*YouTube*", "*Obsidian*", "Chrome - *"
		  Regex: "^Chrome", ".*Firefox.*", "(.*Gmail.*|.*Inbox.*)"
		Windows matching any of these patterns will not be closed.

	.PARAMETER IncludeCurrent
		If specified, also closes the current Windows Terminal tab. When omitted,
		the surviving terminal is instead centered on the primary monitor and refocused.

	.PARAMETER ReloadPowerShellProfile
		If specified, reloads the PowerShell profile after terminating processes.

	.EXAMPLE
		Kill-All

	.EXAMPLE
		Kill-All -Exclude "*YouTube*"

	.EXAMPLE
		Kill-All -Exclude "*YouTube*", "*Gmail*", "(.*Obsidian.*|.*Notion.*)"

	.EXAMPLE
		Kill-All -IncludeCurrent

	.EXAMPLE
		Kill-All -ReloadPowerShellProfile
	#>
	[CmdletBinding()]
	param(
		[Parameter()]
		[string[]]$Exclude,

		[Parameter()]
		[switch]$IncludeCurrent,

		[Parameter()]
		[switch]$ReloadPowerShellProfile
	)

	Write-LogTitle "Kill All"

	if ($Exclude -and (Test-LogVerbose)) {
		Write-LogDebug "Excluding windows matching patterns => [$($Exclude -join ', ')]" -Style Step
	}

	[void](Remove-VirtualDesktops)

	DockerWizard -Stop

	Terminate-AllBrowserProcesses -Exclude $Exclude
	Terminate-AllProcessesWithVisibleWindows -Exclude $Exclude
	Terminate-AllProcessesByName -Exclude $Exclude

	# Allow everything else to close
	Start-Sleep -Milliseconds 500

	Terminate-WindowsTerminalTabs -IncludeCurrent:$IncludeCurrent

	if ($ReloadPowerShellProfile) {
		Reload-PowerShellProfile
	}

	if (-not $IncludeCurrent) {
		Center-Terminal
		Focus-TerminalTab -Quiet
	}

	Write-LogSuccess "Kill All finished successfully!"
}
