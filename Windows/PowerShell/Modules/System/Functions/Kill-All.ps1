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

		The open-workspace tracker (Save-WorkspaceState / Close-Workspace) is cleared too, but only
		when Browsers, VisibleWindows and NamedProcesses all ran - a full run leaves nothing a
		workspace opened, so a populated tracker would have Close-Workspace offer workspaces that are
		no longer open. Skip any of those steps and the tracker is kept, because the windows that
		survived are still closable.

		Under the same condition the run ends with a survivor audit (Report-KillAllSurvivors):
		every visible, titled application window still standing that is neither a configured
		exclusion nor an -Exclude match is listed as a warning, and the closing line says how
		many survived instead of reporting success. The browser and visible-window steps verify
		their own work as well (windows waited for, processes waited for), so a straggler here is
		something that genuinely refused to go - typically a dialog waiting for an answer.

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

	$stepStates = Resolve-KillAllSteps -Skip $Skip -Include $includeSteps

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

	# The open-workspace tracker must not go on claiming windows this run took down: left populated,
	# Close-Workspace would keep offering workspaces that are long gone and then report every one of
	# their windows as already closed. It is only cleared when the run was actually thorough, though.
	# Staleness is merely noisy - Close-Workspace reports an item it cannot find as already closed -
	# whereas clearing too eagerly is a real capability loss, because the windows that DID survive a
	# partial run become unclosable. So all three window-taking steps have to have run; skip any one
	# of them and the tracker stays, still describing what is left. Guarded with Get-Command because
	# Workflow is a separate module and need not be loaded, and done BEFORE the tab termination,
	# which with -IncludeCurrent ends this process outright.
	$survivors = @()
	if ($stepStates.Browsers -and $stepStates.VisibleWindows -and $stepStates.NamedProcesses) {
		if (Get-Command Save-WorkspaceState -ErrorAction SilentlyContinue) {
			Save-WorkspaceState -Entry @()
		}

		# Closing audit: with all three window-taking steps run, nothing that is not excluded
		# should still own a window. Whatever does is reported window by window, so a run that
		# left something behind never ends on a success line.
		$survivors = @(Report-KillAllSurvivors -Exclude $Exclude)
	}

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

	if ($survivors.Count -gt 0) {
		Write-LogWarning "Kill All finished with $($survivors.Count) window(s) still open."
	}
	else {
		Write-LogSuccess "Kill All finished successfully!"
	}
}
