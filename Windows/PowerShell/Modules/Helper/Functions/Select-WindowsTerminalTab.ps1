function Select-WindowsTerminalTab {
	<#
	.SYNOPSIS
		Makes one Windows Terminal tab the active tab via UI Automation - no focus, no keystrokes.

	.DESCRIPTION
		Finds the tab in the given Windows Terminal window and selects it through its
		SelectionItemPattern. Replaces the Ctrl+Tab cycling that read the window title after every
		keystroke: the title lags the tab switch, so the cycle could stop one tab late, and the
		keystrokes land in whatever window actually has focus. Selecting a tab does not bring the
		window to the foreground, so it never pulls the view onto another virtual desktop.

		-TabIndex is preferred when the tab at that position carries -TabTitle (or no title was
		given), which tells apart several tabs with the same title. Otherwise the first tab whose
		title matches -TabTitle exactly is selected.

		Returns $false when the tab cannot be found or selected, so the caller can fall back to its
		legacy path.

	.PARAMETER WindowHandle
		Handle of the Windows Terminal top-level window that owns the tab.

	.PARAMETER TabTitle
		Exact title of the tab to select (as reported by Get-WindowsTerminalTabTitles).

	.PARAMETER TabIndex
		0-based position of the tab in the tab strip. -1 (default) selects by title only.

	.OUTPUTS
		Boolean. $true when the tab was found and selected.

	.EXAMPLE
		Select-WindowsTerminalTab -WindowHandle $wtWindow.Handle -TabTitle "ExampleProject.Api"

	.EXAMPLE
		Select-WindowsTerminalTab -WindowHandle $wtWindow.Handle -TabIndex 0
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param(
		[Parameter(Mandatory = $true)]
		[IntPtr]$WindowHandle,

		[Parameter()]
		[string]$TabTitle,

		[Parameter()]
		[int]$TabIndex = -1
	)

	if ($WindowHandle -eq [IntPtr]::Zero) {
		return $false
	}

	if ([string]::IsNullOrEmpty($TabTitle) -and $TabIndex -lt 0) {
		return $false
	}

	try {
		Add-Type -AssemblyName UIAutomationClient -ErrorAction Stop
		Add-Type -AssemblyName UIAutomationTypes -ErrorAction Stop

		$root = [System.Windows.Automation.AutomationElement]::FromHandle($WindowHandle)
		if (-not $root) {
			return $false
		}

		$tabCondition = New-Object System.Windows.Automation.PropertyCondition(
			[System.Windows.Automation.AutomationElement]::ControlTypeProperty,
			[System.Windows.Automation.ControlType]::TabItem
		)

		$tabItems = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $tabCondition)
		if (-not $tabItems -or $tabItems.Count -eq 0) {
			return $false
		}

		$targetTab = $null

		if ($TabIndex -ge 0 -and $TabIndex -lt $tabItems.Count) {
			$indexedTab = $tabItems[$TabIndex]
			if ([string]::IsNullOrEmpty($TabTitle) -or [string]$indexedTab.Current.Name -eq $TabTitle) {
				$targetTab = $indexedTab
			}
		}

		if (-not $targetTab -and -not [string]::IsNullOrEmpty($TabTitle)) {
			foreach ($tabItem in $tabItems) {
				if ([string]$tabItem.Current.Name -eq $TabTitle) {
					$targetTab = $tabItem
					break
				}
			}
		}

		if (-not $targetTab) {
			return $false
		}

		$selectionPattern = $null
		if (-not $targetTab.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$selectionPattern)) {
			return $false
		}

		$selectionPattern.Select()
		return $true
	}
	catch {
		return $false
	}
}
