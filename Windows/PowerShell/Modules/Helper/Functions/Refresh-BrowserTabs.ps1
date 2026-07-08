
function Refresh-BrowserTabs {
	<#
	.SYNOPSIS
		Hard-refreshes every tab of every open browser window exactly once.

	.DESCRIPTION
		Enumerates Firefox, Chrome, Edge, and Brave windows and hard-refreshes (Ctrl+Shift+R)
		every tab in each window. Used after Set-SystemTheme to apply theme changes instantly
		without manual refresh.

		There is no cross-browser shortcut that reloads all tabs simultaneously, so tabs are
		visited one at a time. To guarantee each tab is hit exactly once - and never twice - the
		real browser tab strip is read through UI Automation and each tab is activated directly
		via its SelectionItemPattern before the refresh keystroke is sent. This avoids two flaws
		of the previous Ctrl+Tab cycle:
		  - Web pages expose their own role="tab" widgets (mapped to ControlType.TabItem), which
		    inflated the tab count and caused the cycle to wrap around and re-refresh tabs.
		  - Dropped Ctrl+Tab keystrokes desynchronised the cycle.
		If a window's tabs cannot be activated through UI Automation, the function falls back to a
		deterministic Ctrl+Tab cycle driven by the accurate tab count, and finally to refreshing
		just the active tab.

		Refreshing moves the active tab around, so each window's originally-active tab is restored
		afterwards. When the original tab cannot be determined or re-selected, the window is left on
		its first tab.

	.EXAMPLE
		Refresh-BrowserTabs
	#>
	param()

	Write-LogTitle "Refreshing Browser Tabs"

	# SendKeys is used to deliver the hard-refresh keystroke to the focused browser window.
	Add-Type -AssemblyName System.Windows.Forms

	# Reads the real browser tab strip via UI Automation, returning the chrome tab elements in
	# left-to-right order. TabItems that live inside the page document (web content's own
	# role="tab" widgets) are excluded so only the browser's actual tabs remain.
	$resolveBrowserTabs = {
		param(
			[Parameter(Mandatory)]
			[System.IntPtr]$WindowHandle
		)

		if ($WindowHandle -eq [IntPtr]::Zero) {
			return @()
		}

		try {
			Add-Type -AssemblyName UIAutomationClient -ErrorAction Stop
			Add-Type -AssemblyName UIAutomationTypes -ErrorAction Stop

			$root = [System.Windows.Automation.AutomationElement]::FromHandle($WindowHandle)
			if (-not $root) {
				return @()
			}

			$tabItemCondition = New-Object System.Windows.Automation.PropertyCondition(
				[System.Windows.Automation.AutomationElement]::ControlTypeProperty,
				[System.Windows.Automation.ControlType]::TabItem
			)
			$documentCondition = New-Object System.Windows.Automation.PropertyCondition(
				[System.Windows.Automation.AutomationElement]::ControlTypeProperty,
				[System.Windows.Automation.ControlType]::Document
			)

			$allTabs = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $tabItemCondition)
			if (-not $allTabs -or $allTabs.Count -eq 0) {
				return @()
			}

			# Collect the RuntimeIds of every TabItem that lives inside a page Document. These are
			# the web page's own tab widgets, not browser tabs, and must not be refreshed.
			$pageTabIds = New-Object 'System.Collections.Generic.HashSet[string]'
			$documents = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $documentCondition)
			foreach ($document in $documents) {
				$documentTabs = $document.FindAll([System.Windows.Automation.TreeScope]::Descendants, $tabItemCondition)
				foreach ($documentTab in $documentTabs) {
					[void]$pageTabIds.Add(($documentTab.GetRuntimeId() -join '.'))
				}
			}

			$browserTabs = @()
			foreach ($tab in $allTabs) {
				if (-not $pageTabIds.Contains(($tab.GetRuntimeId() -join '.'))) {
					$browserTabs += $tab
				}
			}

			return $browserTabs
		}
		catch {
			return @()
		}
	}

	# Activates a tab through its SelectionItemPattern. Returns $true only when the tab was
	# actually selected, so the caller never sends a refresh that lands on the wrong tab.
	$selectTab = {
		param($TabElement)

		try {
			$pattern = $null
			if ($TabElement.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$pattern)) {
				$pattern.Select()
				return $true
			}
		}
		catch {
		}

		return $false
	}

	# Reports whether a tab is the currently-active (selected) one, used to remember which tab to
	# restore after refreshing. Returns $false when selection state cannot be read.
	$isTabSelected = {
		param($TabElement)

		try {
			$pattern = $null
			if ($TabElement.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$pattern)) {
				return [bool]$pattern.Current.IsSelected
			}
		}
		catch {
		}

		return $false
	}

	# Supported browsers - process names that match the Configuration.Universal.Browsers
	$browserProcesses = @("firefox", "chrome", "msedge", "brave")
	$refreshedBrowsers = @()

	foreach ($browserName in $browserProcesses) {
		$browserWindows = Get-WindowHandle -ProcessName $browserName -ErrorAction SilentlyContinue

		if (-not $browserWindows) {
			continue
		}

		Write-LogStep " Refreshing [$browserName] tabs..."
		Write-LogDebug "  Found [$($browserWindows.Count) $browserName] window(s)!" -Style Step

		foreach ($window in $browserWindows) {
			try {
				# Reliably acquire and verify focus. Without confirmed focus the refresh keystroke
				# would land on whatever window happens to be foreground, so skip instead.
				if (-not (Confirm-WindowForeground -WindowHandle $window.Handle)) {
					Write-LogDebug "  Could not focus window [$($window.Title)] - skipping to avoid sending keys to the wrong window" -Style Warning
					continue
				}

				$browserTabs = @(& $resolveBrowserTabs $window.Handle)

				if ($browserTabs.Count -gt 0) {
					Write-LogDebug "  Detected [$($browserTabs.Count)] tab(s) in [$browserName] window [$($window.Title)]" -Style Step

					# Remember which tab was active so it can be restored once refreshing moves the
					# selection around. 0 means the active tab could not be determined.
					$originalTabIndex = 0
					for ($i = 0; $i -lt $browserTabs.Count; $i++) {
						if (& $isTabSelected $browserTabs[$i]) {
							$originalTabIndex = $i + 1
							break
						}
					}

					# Primary path: activate each real tab directly, then hard-refresh it. Because we
					# iterate the actual tab elements (not a keystroke cycle), every tab is hit once.
					$refreshedCount = 0
					foreach ($tab in $browserTabs) {
						if (& $selectTab $tab) {
							Start-Sleep -Milliseconds 50
							[System.Windows.Forms.SendKeys]::SendWait("^+r")
							Start-Sleep -Milliseconds 40
							$refreshedCount++
						}
					}

					if ($refreshedCount -gt 0) {
						# Restore the originally-active tab; fall back to the first tab when it is
						# unknown or can no longer be selected.
						$restoreTab = if ($originalTabIndex -gt 0) { $browserTabs[$originalTabIndex - 1] } else { $browserTabs[0] }
						if (-not (& $selectTab $restoreTab)) {
							[void](& $selectTab $browserTabs[0])
						}
					}
					else {
						# Fallback: tab strip exposed no selectable tabs. Use a deterministic Ctrl+Tab
						# cycle bounded by the accurate tab count so each tab is still refreshed once.
						Write-LogDebug "  Tab selection unavailable - using Ctrl+Tab cycle for [$($window.Title)]" -Style Warning

						[System.Windows.Forms.SendKeys]::SendWait("^1")
						Start-Sleep -Milliseconds 40
						[System.Windows.Forms.SendKeys]::SendWait("^+r")
						Start-Sleep -Milliseconds 40

						for ($tabIndex = 2; $tabIndex -le $browserTabs.Count; $tabIndex++) {
							[System.Windows.Forms.SendKeys]::SendWait("^{TAB}")
							Start-Sleep -Milliseconds 40
							[System.Windows.Forms.SendKeys]::SendWait("^+r")
							Start-Sleep -Milliseconds 40
						}

						# Restore the originally-active tab. Ctrl+1..Ctrl+8 jump to a specific tab in
						# every supported browser; for an unknown tab or one beyond the eighth, land on
						# the first tab.
						if ($originalTabIndex -ge 1 -and $originalTabIndex -le 8) {
							[System.Windows.Forms.SendKeys]::SendWait("^$originalTabIndex")
						}
						else {
							[System.Windows.Forms.SendKeys]::SendWait("^1")
						}
						Start-Sleep -Milliseconds 40
					}
				}
				else {
					# Last resort: UI Automation gave us nothing, so refresh only the active tab.
					Write-LogDebug "  UI Automation tab list unavailable for [$($window.Title)] - refreshing active tab only" -Style Warning
					[System.Windows.Forms.SendKeys]::SendWait("^+r")
					Start-Sleep -Milliseconds 40
				}

				Write-LogDebug "  Refreshed tabs in window: $($window.Title)" -Style Success
			}
			catch {
				Write-LogDebug "  Error refreshing window [$($window.Title)]: $_" -Style Error
			}
		}

		$refreshedBrowsers += $browserName
	}

	if ($refreshedBrowsers.Count -gt 0) {
		Write-LogSuccess "Refreshed [$($refreshedBrowsers -join ', ')] tabs!"
	}
	else {
		Write-LogWarning "No browser tabs to refresh!"
	}
}
