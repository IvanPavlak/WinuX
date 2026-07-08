function Close-ProjectTerminals {
	<#
    .SYNOPSIS
        Closes all Windows Terminal tabs matching a specific project name pattern.

    .DESCRIPTION
        Cycles through all Windows Terminal tabs using keyboard shortcuts (Ctrl+Tab) and closes
        tabs that match the pattern "ProjectName.*" (e.g., "AnotherProject.Api", "AnotherProject.Ui") using Ctrl+W.
        This is used to prevent duplicate tabs when reopening projects.

    .PARAMETER ProjectName
        The project name to match against tab titles (e.g., "AnotherProject", "ExampleProject")

    .OUTPUTS
        Returns the count of closed tabs

    .EXAMPLE
        Close-ProjectTerminals -ProjectName "AnotherProject"
        Closes all terminal tabs starting with "AnotherProject." (e.g., "AnotherProject.Api", "AnotherProject.Ui")

    .EXAMPLE
        Close-ProjectTerminals -ProjectName "ExampleProject"
        Closes all terminal tabs for ExampleProject project with debug output
    #>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[string]$ProjectName,

		[Parameter()]
		[System.IntPtr]$TerminalWindowHandle = [System.IntPtr]::Zero,

		[Parameter()]
		[string]$StartingTabTitle
	)

	try {
		$wtProcess = Get-Process | Where-Object { $_.ProcessName -eq "WindowsTerminal" } | Select-Object -First 1

		if (-not $wtProcess) {
			Write-LogDebug " Windows Terminal is not running" -Style Warning
			return 0
		}

		Write-LogDebug " Looking for terminal tabs with project [$ProjectName]..."

		Add-Type -AssemblyName System.Windows.Forms

		[void][System.Reflection.Assembly]::LoadWithPartialName("Microsoft.VisualBasic")
		$initialWindow = Get-TargetTerminalWindow -TerminalWindowHandle $TerminalWindowHandle

		if ($initialWindow -and $initialWindow.Handle -ne [System.IntPtr]::Zero) {
			[void][WindowModule.Native]::SetForegroundWindow($initialWindow.Handle)
		}
		else {
			[Microsoft.VisualBasic.Interaction]::AppActivate($wtProcess.Id)
		}
		Start-Sleep -Milliseconds 25

		$initialWindow = Get-TargetTerminalWindow -TerminalWindowHandle $TerminalWindowHandle
		$startingTitle = if ($StartingTabTitle) { $StartingTabTitle } elseif ($initialWindow) { $initialWindow.Title } else { $null }

		if (-not $startingTitle) {
			Write-LogDebug " Could not get Windows Terminal window title" -Style Warning
			return 0
		}

		# Since Open-Terminal uses --suppressApplicationTitle, tab names are preserved
		# even when child processes (npm, node, dotnet) are running.
		# We can directly close matching tabs without needing to Ctrl+C all tabs first.

		$maxTabs = 20  # Safety limit

		Write-LogDebug " Closing tabs matching project [$ProjectName]..."

		$checkedTitles = @()
		$closedTabs = @()

		for ($i = 0; $i -lt $maxTabs; $i++) {
			$currentWindow = Get-TargetTerminalWindow -TerminalWindowHandle $TerminalWindowHandle
			$currentTitle = if ($currentWindow) { $currentWindow.Title } else { $null }

			if (-not $currentTitle) {
				break
			}

			# Check if this tab belongs to the project (e.g., "AnotherProject.Api", "AnotherProject.Ui")
			if ($currentTitle -match "^$([regex]::Escape($ProjectName))\.") {
				# Skip the tab we're running from to avoid killing the current session
				if ($currentTitle -eq $startingTitle) {
					Write-LogDebug "  Skipping current tab => [$currentTitle]" -Style Step
					$checkedTitles += $currentTitle
					[System.Windows.Forms.SendKeys]::SendWait("^{TAB}")
					Start-Sleep -Milliseconds 25
					continue
				}

				Write-LogDebug "  Closing terminal tab => [$currentTitle]" -Style Step

				# Close this tab with Ctrl+W
				[System.Windows.Forms.SendKeys]::SendWait("^w")
				$closedTabs += $currentTitle
				Start-Sleep -Milliseconds 25

				# After closing, we're automatically moved to another tab
				# Continue checking from the current position
				continue
			}

			# If we've already checked this title, we've cycled through all tabs
			if ($checkedTitles -contains $currentTitle) {
				break
			}

			$checkedTitles += $currentTitle

			# Move to next tab
			[System.Windows.Forms.SendKeys]::SendWait("^{TAB}")
			Start-Sleep -Milliseconds 25
		}

		if ($startingTitle) {
			$targetWindow = Get-TargetTerminalWindow -TerminalWindowHandle $TerminalWindowHandle

			if ($targetWindow -and $targetWindow.Handle -ne [System.IntPtr]::Zero) {
				[void][WindowModule.Native]::SetForegroundWindow($targetWindow.Handle)
				Start-Sleep -Milliseconds 25

				for ($i = 0; $i -lt $maxTabs; $i++) {
					$currentWindow = Get-TargetTerminalWindow -TerminalWindowHandle $TerminalWindowHandle
					$currentTitle = if ($currentWindow) { $currentWindow.Title } else { $null }

					if ($currentTitle -eq $startingTitle) {
						break
					}

					[System.Windows.Forms.SendKeys]::SendWait("^{TAB}")
					Start-Sleep -Milliseconds 25
				}
			}
			else {
				Focus-TerminalTab -TargetTitle $startingTitle
			}
		}

		if ($closedTabs.Count -gt 0 -and -not (Test-LogVerbose)) {
			Write-LogSuccess "Closed [$($closedTabs.Count)] existing terminal tab(s) for project [$ProjectName]"
		}
		elseif ($closedTabs.Count -gt 0 -and (Test-LogVerbose)) {
			Write-LogSuccess "Closed [$($closedTabs.Count)] terminal tab(s) for [$ProjectName]"
		}
		elseif (Test-LogVerbose) {
			Write-LogWarning "  No terminal tabs found for [$ProjectName]"
		}

		return $closedTabs.Count
	}
	catch {
		Write-LogDebug " Error closing terminal tabs => $_" -Style Error
		return 0
	}
}
