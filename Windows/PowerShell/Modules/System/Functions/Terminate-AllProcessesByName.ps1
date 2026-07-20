function Terminate-AllProcessesByName {
	<#
	.SYNOPSIS
		Terminates specific processes by their names.

	.DESCRIPTION
		Forcefully terminates every process named in the
		Configuration.Universal.TerminateProcessNames list. Missing processes are
		silently ignored; when the list is absent or empty the function warns and
		terminates nothing. Docker is intentionally not part of this cleanup - it is
		handled separately by DockerWizard before this function runs.
		Processes with windows matching exclusion patterns will be skipped.

	.PARAMETER Exclude
		Array of window title patterns to exclude from termination.
		Supports both wildcard and regex patterns (same format as layout .psd1 files):
		  Wildcard: "*YouTube*", "*Important Chat*"
		  Regex: ".*YouTube.*", "(.*Gmail.*|.*Inbox.*)"
		Processes with windows matching any of these patterns will not be closed.

	.EXAMPLE
		Terminate-AllProcessesByName

	.EXAMPLE
		Terminate-AllProcessesByName -Exclude "*Important Project*"
	#>
	[CmdletBinding()]
	param (
		[Parameter()]
		[string[]]$Exclude
	)

	Write-LogTitle "Terminating All Named Processes"

	$processNames = @()
	if ($Configuration -and $Configuration.Universal -and $Configuration.Universal.TerminateProcessNames) {
		$processNames = @($Configuration.Universal.TerminateProcessNames)
	}

	if (-not $processNames) {
		Write-LogWarning "No process names configured (Universal.TerminateProcessNames) - nothing to terminate!"
		return
	}

	Write-LogDebug " Target processes => [$($processNames -join ', ')]" -Style Step

	$processNames | ForEach-Object {
		$processName = $_
		$processes = Get-Process -Name $processName -ErrorAction SilentlyContinue

		if ($processes) {
			# Separate processes into those to terminate and those to exclude
			$processesToTerminate = @()
			$excludedProcesses = @()

			foreach ($process in $processes) {
				# Check if this process matches exclusion patterns (by process name or window title)
				if ($Exclude -and (Test-WindowTitleMatch -ProcessName $process.ProcessName -WindowTitle $process.MainWindowTitle -Patterns $Exclude)) {
					$excludedProcesses += $process
				}
				else {
					$processesToTerminate += $process
				}
			}

			if ((Test-LogVerbose) -and $excludedProcesses) {
				Write-LogDebug " Excluding [$(@($excludedProcesses).Count)] [$processName] process(es) =>" -Style Warning
				$excludedProcesses | ForEach-Object {
					Write-LogDebug "   • $($_.ProcessName) [PID => $($_.Id) | Window => $($_.MainWindowTitle)]" -Style Warning
				}
			}

			if ($processesToTerminate) {
				Write-LogDebug " Found [$(@($processesToTerminate).Count)] [$processName] process(es) - terminating..." -Style Step
				$processesToTerminate | Stop-Process -Force
			}
			elseif ((Test-LogVerbose) -and -not $excludedProcesses) {
				Write-LogDebug " No [$processName] processes found!" -Style Warning
			}
		}
		else {
			Write-LogDebug " No [$processName] processes found!" -Style Warning
		}
	}

	Write-LogSuccess "Terminated all Named processes successfully!"
}
