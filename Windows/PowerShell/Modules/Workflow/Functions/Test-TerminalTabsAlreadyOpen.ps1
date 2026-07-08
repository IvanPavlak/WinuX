function Test-TerminalTabsAlreadyOpen {
	<#
    .SYNOPSIS
        Checks if expected terminal tabs are already open by cycling through Windows Terminal tabs.

    .DESCRIPTION
        Cycles through all Windows Terminal tabs using keyboard shortcuts (Ctrl+Tab) and checks
        which expected tab names exist. Returns an object with AllOpen (bool) and FoundTabs (array)
        so callers can decide whether to skip entirely or open only missing tabs.

    .PARAMETER ExpectedTabNames
        Array of tab names to check for (e.g., @("WinuX.Root", "ExampleProject.Api", "ExampleProject.Ui"))

    .PARAMETER ProjectName
        The project name for display in the warning message

    .EXAMPLE
        $result = Test-TerminalTabsAlreadyOpen -ExpectedTabNames @("WinuX.Root", "WinuX.DOCS") -ProjectName "WinuX"
        $result.AllOpen    # $true if all tabs exist
        $result.FoundTabs  # @("WinuX.Root") - tabs that were found
    #>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[string[]]$ExpectedTabNames,

		[Parameter(Mandatory)]
		[string]$ProjectName
	)

	try {
		$wtProcess = Get-Process | Where-Object { $_.ProcessName -eq "WindowsTerminal" } | Select-Object -First 1

		if (-not $wtProcess) {
			return [PSCustomObject]@{
				AllOpen   = $false
				FoundTabs = @()
			}
		}

		Add-Type -AssemblyName System.Windows.Forms
		[void][System.Reflection.Assembly]::LoadWithPartialName("Microsoft.VisualBasic")

		# Get ALL Windows Terminal windows - tabs in other WT windows would be missed
		# if we only checked the first one (Ctrl+Tab only cycles within one window)
		$allWtWindows = @(Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue)

		if (-not $allWtWindows -or $allWtWindows.Count -eq 0) {
			return [PSCustomObject]@{
				AllOpen   = $false
				FoundTabs = @()
			}
		}

		$foundTabs = @()
		$maxTabs = 20  # Safety limit per window

		foreach ($wtWindow in $allWtWindows) {
			# Activate this specific WT window (SetForegroundWindow targets a handle,
			# unlike AppActivate which targets any window of the process)
			[void][WindowModule.Native]::SetForegroundWindow($wtWindow.Handle)
			Start-Sleep -Milliseconds 50

			# Re-read title after activation (may have changed)
			$startWindow = Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue |
				Where-Object { $_.Handle -eq $wtWindow.Handle }
			$startingTitle = if ($startWindow) { $startWindow.Title } else { $null }

			if (-not $startingTitle) { continue }

			$checkedTitles = @($startingTitle)

			# Check starting (active) tab against expected names
			foreach ($expectedTab in $ExpectedTabNames) {
				if ($startingTitle -match [regex]::Escape($expectedTab)) {
					if ($foundTabs -notcontains $expectedTab) {
						$foundTabs += $expectedTab
					}
				}
			}

			# Cycle through remaining tabs in this window
			for ($i = 0; $i -lt $maxTabs; $i++) {
				[System.Windows.Forms.SendKeys]::SendWait("^{TAB}")
				Start-Sleep -Milliseconds 10

				$currentWindow = Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue |
					Where-Object { $_.Handle -eq $wtWindow.Handle }
				$currentTitle = if ($currentWindow) { $currentWindow.Title } else { $null }

				if (-not $currentTitle -or $checkedTitles -contains $currentTitle) {
					break
				}

				$checkedTitles += $currentTitle

				foreach ($expectedTab in $ExpectedTabNames) {
					if ($currentTitle -match [regex]::Escape($expectedTab)) {
						if ($foundTabs -notcontains $expectedTab) {
							$foundTabs += $expectedTab
						}
					}
				}
			}

			# Early exit if all tabs have been found
			if ($foundTabs.Count -eq $ExpectedTabNames.Count) { break }
		}

		$allTabsExist = ($foundTabs.Count -eq $ExpectedTabNames.Count)

		if ($allTabsExist) {
			Write-LogWarning "Project [$ProjectName] terminals are already open!"
		}
		elseif ($foundTabs.Count -gt 0) {
			$missingTabs = $ExpectedTabNames | Where-Object { $foundTabs -notcontains $_ }
			Write-LogWarning "Some [$ProjectName] terminals already open. Missing: [$($missingTabs -join ', ')]"
		}

		return [PSCustomObject]@{
			AllOpen   = $allTabsExist
			FoundTabs = $foundTabs
		}
	}
	catch {
		return [PSCustomObject]@{
			AllOpen   = $false
			FoundTabs = @()
		}
	}
}
