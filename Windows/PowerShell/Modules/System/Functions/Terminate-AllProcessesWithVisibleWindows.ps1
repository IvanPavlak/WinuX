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

	# Candidates come from the WINDOW side (Get-VisibleWindowProcess: every visible, titled
	# top-level window grouped by owning process), not from Get-Process' MainWindowTitle. The
	# .NET main window is the first visible unowned window in z-order, titled or not, so a
	# process whose untitled helper window happened to sit on top reported an empty title and
	# was skipped - which window is first depends on focus history, so the same app survived
	# one run and died the next. Packaged apps were skipped the same way (their frames belong
	# to ApplicationFrameHost). Enumerating windows sees every such process.
	$allProcesses = @(Get-VisibleWindowProcess | Where-Object {
			-not $defaultExcludedProcessNames.Contains($_.ProcessName)
		})

	# Separate processes into those to terminate and those to exclude. A force-kill is per
	# process, so ONE excluded window spares the whole process - the other windows cannot be
	# taken down without also taking the kept one.
	$processesToTerminate = @()
	$excludedProcesses = @()

	foreach ($process in $allProcesses) {
		$isExcluded = $false
		if ($Exclude) {
			foreach ($title in @($process.WindowTitles)) {
				if (Test-WindowTitleMatch -ProcessName $process.ProcessName -WindowTitle $title -Patterns $Exclude) {
					$isExcluded = $true
					break
				}
			}
		}

		if ($isExcluded) {
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

	$survivors = @()
	if ($processesToTerminate) {
		foreach ($process in $processesToTerminate) {
			Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
		}

		# Stop-Process -Force returns once the terminate request is issued, not once the process
		# is gone. Wait for the exits (bounded) and then look again: a process that is still
		# alive - access denied on an elevated app, a hung teardown - is reported instead of
		# being counted as terminated.
		$targetIds = @($processesToTerminate | ForEach-Object { [int]$_.Id })
		Wait-Process -Id $targetIds -Timeout $script:VisibleWindowTerminationWaitSeconds -ErrorAction SilentlyContinue

		foreach ($process in $processesToTerminate) {
			if (Get-Process -Id $process.Id -ErrorAction SilentlyContinue) {
				$survivors += $process
			}
		}
	}

	if ($survivors.Count -gt 0) {
		Write-LogWarning "$($survivors.Count) process(es) with visible windows could not be terminated:"
		Write-LogList -Items @($survivors | ForEach-Object { "$($_.ProcessName) [PID => $($_.Id) | Window => $($_.MainWindowTitle)]" })
	}
	else {
		Write-LogSuccess "Terminated all processes with Visible Windows successfully!"
	}
}

# How long Terminate-AllProcessesWithVisibleWindows waits for force-killed processes to exit
# before it looks for survivors. Script-scoped so tests can shorten it.
$script:VisibleWindowTerminationWaitSeconds = 5
