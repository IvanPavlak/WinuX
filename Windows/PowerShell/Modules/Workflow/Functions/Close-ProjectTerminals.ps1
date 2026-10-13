function Close-ProjectTerminals {
	<#
    .SYNOPSIS
        Closes all Windows Terminal tabs matching a specific project name pattern.

    .DESCRIPTION
        Reads the tab strip of every Windows Terminal window through UI Automation and closes the
        tabs whose title matches "ProjectName.*" (e.g., "AnotherProject.Api", "AnotherProject.Ui")
        through each tab's own close button. No window is focused and no keystroke is sent.

        The tab this shell runs in is never closed: closing it would end the process mid-run and
        leave every other project tab open. It is identified by Resolve-HostingTerminalTab, and by
        -StartingTabTitle when the caller passes one.

        A window whose tabs cannot be read (its virtual desktop is not on screen) has its desktop
        brought up for the read, and the view is put back afterwards. A window that stays
        unreadable is reported and skipped - there is no keystroke fallback, because Ctrl+Tab and
        Ctrl+W go to whatever tab is active, which is how the calling tab used to get closed.

        This is used to prevent duplicate tabs when reopening projects.

    .PARAMETER ProjectName
        The project name to match against tab titles (e.g., "AnotherProject", "ExampleProject")

    .PARAMETER TerminalWindowHandle
        Only close tabs in this Windows Terminal window. Without it every window is searched.

    .PARAMETER StartingTabTitle
        Title of a tab that must never be closed, in addition to the tab this shell runs in.

    .OUTPUTS
        Returns the count of closed tabs

    .EXAMPLE
        Close-ProjectTerminals -ProjectName "AnotherProject"
        Closes all terminal tabs starting with "AnotherProject." (e.g., "AnotherProject.Api", "AnotherProject.Ui")

    .EXAMPLE
        Set-LogLevel Verbose { Close-ProjectTerminals -ProjectName "ExampleProject" }
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

	$closedTabs = @()
	$restoreDesktopIndex = $null

	try {
		$terminalWindows = @(Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue)
		if ($TerminalWindowHandle -ne [System.IntPtr]::Zero) {
			$terminalWindows = @($terminalWindows | Where-Object { $_.Handle -eq $TerminalWindowHandle })
		}

		if ($terminalWindows.Count -eq 0) {
			Write-LogDebug " Windows Terminal is not running" -Style Warning
			return 0
		}

		Write-LogDebug " Looking for terminal tabs with project [$ProjectName]..."

		$hostingTerminal = Resolve-HostingTerminalTab
		$projectTabPattern = "^$([regex]::Escape($ProjectName))\."

		foreach ($terminalWindow in $terminalWindows) {
			$terminalHandle = [IntPtr]$terminalWindow.Handle
			$liveTabTitles = Get-WindowsTerminalTabTitles -WindowHandle $terminalHandle

			if ($null -eq $liveTabTitles) {
				# Windows Terminal composes its tab strip only while its virtual desktop is on
				# screen; a workspace's terminal is usually parked on another one.
				$previousDesktop = Ensure-DesktopVisible -WindowHandle $terminalHandle
				if ($null -ne $previousDesktop -and $null -eq $restoreDesktopIndex) {
					$restoreDesktopIndex = $previousDesktop
				}

				$liveTabTitles = Get-WindowsTerminalTabTitles -WindowHandle $terminalHandle
			}

			if ($null -eq $liveTabTitles) {
				Write-LogWarning "Could not read the tabs of terminal window [$($terminalWindow.Title)] - its [$ProjectName] tabs were left open"
				continue
			}

			foreach ($tabTitle in @($liveTabTitles | Where-Object { $_ -match $projectTabPattern })) {
				$isHostingTab = $hostingTerminal -and
				$hostingTerminal.Handle -eq $terminalHandle -and
				$hostingTerminal.TabTitle -eq $tabTitle

				if ($isHostingTab -or ($StartingTabTitle -and $tabTitle -eq $StartingTabTitle)) {
					Write-LogDebug "  Skipping current tab => [$tabTitle]" -Style Step
					continue
				}

				Write-LogDebug "  Closing terminal tab => [$tabTitle]" -Style Step

				if (Close-WindowsTerminalTab -WindowHandle $terminalHandle -TabTitle $tabTitle) {
					$closedTabs += $tabTitle
					# Let Windows Terminal remove the tab from the strip before the next close.
					Start-Sleep -Milliseconds 25
				}
				else {
					Write-LogDebug "  Could not close terminal tab => [$tabTitle]" -Style Warning
				}
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
		return $closedTabs.Count
	}
	finally {
		if ($null -ne $restoreDesktopIndex) {
			[void](Ensure-DesktopVisible -DesktopIndex $restoreDesktopIndex)
		}
	}
}
