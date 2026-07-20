function Terminate-AllProcessesWithVisibleWindows {
	<#
	.SYNOPSIS
		Terminates all processes with visible windows except excluded ones.

	.DESCRIPTION
		Forcefully terminates all processes that have visible windows, excluding
		every process named in Configuration.Universal.VisibleWindowExclusions and
		every browser declared in Configuration.Universal.Browsers (which are handled
		gracefully by Terminate-AllBrowserProcesses instead). When the exclusion list
		is absent or empty the function warns and terminates nothing, since running
		without it would force-kill WindowsTerminal - the shell running the cleanup.
		Additional windows can be excluded using the -Exclude parameter.

	.PARAMETER Exclude
		Array of window title patterns to exclude from termination.
		Supports both wildcard and regex patterns (same format as layout .psd1 files):
		  Wildcard: "*YouTube*", "*Obsidian*"
		  Regex: ".*YouTube.*", "(.*Gmail.*|.*Inbox.*)"
		Windows matching any of these patterns will not be closed.

	.EXAMPLE
		Terminate-AllProcessesWithVisibleWindows

	.EXAMPLE
		Terminate-AllProcessesWithVisibleWindows -Exclude "*YouTube*"

	.EXAMPLE
		Terminate-AllProcessesWithVisibleWindows -Exclude "*YouTube*", "*Obsidian*"
	#>
	[CmdletBinding()]
	param (
		[Parameter()]
		[string[]]$Exclude
	)

	Write-LogTitle "Terminating All Processes with Visible Windows"

	# Static exclusions come from Configuration.Universal.VisibleWindowExclusions (see the
	# key's comment there - the PowerToys entries in particular are load-bearing). Refuse
	# to run without them: with no exclusions this would force-kill WindowsTerminal,
	# taking down the very shell (and Kill-All run) executing this function.
	$configuredExclusions = @()
	if ($Configuration -and $Configuration.Universal -and $Configuration.Universal.VisibleWindowExclusions) {
		$configuredExclusions = @($Configuration.Universal.VisibleWindowExclusions)
	}

	if (-not $configuredExclusions) {
		Write-LogWarning "No exclusions configured (Universal.VisibleWindowExclusions) - terminating nothing!"
		return
	}

	# Build the default-exclusion process-name list dynamically. Browser process names
	# are pulled from Configuration.Universal.Browsers so this stays in sync with
	# Terminate-AllBrowserProcesses (which has already gracefully closed those windows
	# via WM_CLOSE - we must not race it by force-killing the underlying processes here,
	# which would also kill excluded browser windows like a kept YouTube tab).
	$defaultExcludedProcessNames = [System.Collections.Generic.HashSet[string]]::new(
		[System.StringComparer]::OrdinalIgnoreCase)
	foreach ($exclusion in $configuredExclusions) {
		$null = $defaultExcludedProcessNames.Add($exclusion)
	}

	if ($Configuration -and $Configuration.Universal -and $Configuration.Universal.Browsers) {
		foreach ($browserDef in $Configuration.Universal.Browsers.Values) {
			if ($browserDef.Exe) {
				$null = $defaultExcludedProcessNames.Add(
					[System.IO.Path]::GetFileNameWithoutExtension($browserDef.Exe))
			}
		}
	}

	$allProcesses = Get-Process | Where-Object {
		$_.MainWindowTitle -ne "" -and
		-not $defaultExcludedProcessNames.Contains($_.ProcessName)
	}

	# Separate processes into those to terminate and those to exclude
	$processesToTerminate = @()
	$excludedProcesses = @()

	foreach ($process in $allProcesses) {
		if ($Exclude -and (Test-WindowTitleMatch -ProcessName $process.ProcessName -WindowTitle $process.MainWindowTitle -Patterns $Exclude)) {
			$excludedProcesses += $process
		}
		else {
			$processesToTerminate += $process
		}
	}

	if (Test-LogVerbose) {
		if ($excludedProcesses) {
			Write-LogDebug "Excluding [$(@($excludedProcesses).Count)] process(es)" -Style Warning
			$excludedProcesses | ForEach-Object {
				Write-LogDebug "$($_.ProcessName) [PID => $($_.Id) | Window => $($_.MainWindowTitle)]" -Style Warning
			}
		}

		if ($processesToTerminate) {
			Write-LogDebug "Found [$(@($processesToTerminate).Count)] process(es) to terminate" -Style Step
			$processesToTerminate | ForEach-Object {
				Write-LogDebug "$($_.ProcessName) [PID => $($_.Id) | Window => $($_.MainWindowTitle)]" -Style Step
			}
		}
		else {
			Write-LogDebug "No processes with visible windows found!" -Style Warning
		}
	}

	if ($processesToTerminate) {
		$processesToTerminate | Stop-Process -Force
	}

	Write-LogSuccess "Terminated all processes with Visible Windows successfully!"
}
