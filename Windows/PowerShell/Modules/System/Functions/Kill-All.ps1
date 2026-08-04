function Kill-All {
	<#
	.SYNOPSIS
		Terminates all user processes and cleans up the environment.

	.DESCRIPTION
		Runs a configurable sequence of cleanup steps:
		- VirtualDesktops : removes all virtual desktops except the first one
		- Docker          : stops Docker containers and Docker Desktop (DockerWizard -Stop)
		- Browsers        : terminates configured browser processes (gracefully via WM_CLOSE)
		- VisibleWindows  : terminates processes with visible windows (except browsers and
		                    the Universal.VisibleWindowExclusions list)
		- NamedProcesses  : terminates named processes (the Universal.TerminateProcessNames list)
		- TerminalTabs    : closes extra Windows Terminal tabs
		- CenterTerminal  : centers the surviving terminal on the primary monitor
		- FocusTerminal   : refocuses the surviving terminal tab
		- ReloadProfile   : reloads the PowerShell profile (off by default)

		Every step can be enabled or disabled persistently via the KillAll.Steps section
		of Configuration.psd1 / Configuration.local.psd1. Each entry is either a plain
		boolean or a per-machine-type hashtable with a Default fallback, e.g.:
		  KillAll = @{ Steps = @{ Docker = @{ Default = $true; Laptop = $false } } }
		Steps missing from config use their built-in defaults (everything on except
		ReloadProfile), so an absent section reproduces the classic full run.

		Per invocation, -Skip forces steps off and -Include forces them on, overriding
		config in both directions. -Skip wins when a step appears in both.

		Unless -IncludeCurrent is specified, the surviving Windows Terminal is
		centered on the primary monitor (pulled back from a secondary monitor if
		needed) and refocused, so the run always ends on the terminal. -IncludeCurrent
		suppresses the CenterTerminal and FocusTerminal steps regardless of config.

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

	.PARAMETER Skip
		Step names to skip for this invocation, overriding config. Valid names:
		VirtualDesktops, Docker, Browsers, VisibleWindows, NamedProcesses,
		TerminalTabs, CenterTerminal, FocusTerminal, ReloadProfile.
		Wins over -Include when a step appears in both.

	.PARAMETER Include
		Step names to run for this invocation even if config disables them.
		Same valid names as -Skip.

	.PARAMETER IncludeCurrent
		If specified, also closes the current Windows Terminal tab. When omitted,
		the surviving terminal is instead centered on the primary monitor and refocused.

	.PARAMETER ReloadPowerShellProfile
		If specified, reloads the PowerShell profile after terminating processes.
		Equivalent to -Include ReloadProfile.

	.EXAMPLE
		Kill-All

	.EXAMPLE
		Kill-All -Skip Docker

	.EXAMPLE
		Kill-All -Skip Docker, Browsers -Exclude "*YouTube*"

	.EXAMPLE
		Kill-All -Include ReloadProfile

	.EXAMPLE
		Kill-All -IncludeCurrent
	#>
	[CmdletBinding()]
	param(
		[Parameter()]
		[string[]]$Exclude,

		[Parameter()]
		[ValidateSet("VirtualDesktops", "Docker", "Browsers", "VisibleWindows", "NamedProcesses", "TerminalTabs", "CenterTerminal", "FocusTerminal", "ReloadProfile")]
		[string[]]$Skip,

		[Parameter()]
		[ValidateSet("VirtualDesktops", "Docker", "Browsers", "VisibleWindows", "NamedProcesses", "TerminalTabs", "CenterTerminal", "FocusTerminal", "ReloadProfile")]
		[string[]]$Include,

		[Parameter()]
		[switch]$IncludeCurrent,

		[Parameter()]
		[switch]$ReloadPowerShellProfile
	)

	Write-LogTitle "Kill All"

	# Kept separate from $Include: assigning back to a parameter re-runs its
	# ValidateSet, which rejects the $null element @($Include) yields when the
	# parameter was omitted.
	$includeSteps = @($Include | Where-Object { $_ })
	if ($ReloadPowerShellProfile) {
		$includeSteps += "ReloadProfile"
	}

	$stepStates = [ordered]@{
		VirtualDesktops = Resolve-KillAllStep -Name "VirtualDesktops" -Default $true -Skip $Skip -Include $includeSteps
		Docker          = Resolve-KillAllStep -Name "Docker" -Default $true -Skip $Skip -Include $includeSteps
		Browsers        = Resolve-KillAllStep -Name "Browsers" -Default $true -Skip $Skip -Include $includeSteps
		VisibleWindows  = Resolve-KillAllStep -Name "VisibleWindows" -Default $true -Skip $Skip -Include $includeSteps
		NamedProcesses  = Resolve-KillAllStep -Name "NamedProcesses" -Default $true -Skip $Skip -Include $includeSteps
		TerminalTabs    = Resolve-KillAllStep -Name "TerminalTabs" -Default $true -Skip $Skip -Include $includeSteps
		CenterTerminal  = Resolve-KillAllStep -Name "CenterTerminal" -Default $true -Skip $Skip -Include $includeSteps
		FocusTerminal   = Resolve-KillAllStep -Name "FocusTerminal" -Default $true -Skip $Skip -Include $includeSteps
		ReloadProfile   = Resolve-KillAllStep -Name "ReloadProfile" -Default $false -Skip $Skip -Include $includeSteps
	}

	if (Test-LogVerbose) {
		if ($Exclude) {
			Write-LogDebug "Excluding windows matching patterns => [$($Exclude -join ', ')]" -Style Step
		}

		$disabledSteps = @($stepStates.Keys | Where-Object { -not $stepStates[$_] })
		if ($disabledSteps) {
			Write-LogDebug "Skipping steps => [$($disabledSteps -join ', ')]" -Style Step
		}
	}

	if ($stepStates.VirtualDesktops) {
		[void](Remove-VirtualDesktops)
	}

	if ($stepStates.Docker) {
		DockerWizard -Stop
	}

	if ($stepStates.Browsers) {
		Terminate-AllBrowserProcesses -Exclude $Exclude
	}

	if ($stepStates.VisibleWindows) {
		Terminate-AllProcessesWithVisibleWindows -Exclude $Exclude
	}

	if ($stepStates.NamedProcesses) {
		Terminate-AllProcessesByName -Exclude $Exclude
	}

	# Allow everything else to close
	Start-Sleep -Milliseconds 500

	if ($stepStates.TerminalTabs) {
		Terminate-WindowsTerminalTabs -IncludeCurrent:$IncludeCurrent
	}

	if ($stepStates.ReloadProfile) {
		Reload-PowerShellProfile
	}

	if (-not $IncludeCurrent) {
		if ($stepStates.CenterTerminal) {
			Center-Terminal
		}

		if ($stepStates.FocusTerminal) {
			Focus-TerminalTab -Quiet
		}
	}

	Write-LogSuccess "Kill All finished successfully!"
}
