function Close-WindowsTerminalTab {
	<#
	.SYNOPSIS
		Closes one Windows Terminal tab by title via its UIA close button - no focus, no keystrokes.

	.DESCRIPTION
		Finds the TabItem whose name exactly matches the given title in the given Windows
		Terminal window and invokes its close button through UI Automation. Replaces the
		focus-then-Ctrl+W pattern, whose synthesized keystrokes land in whatever window
		actually has focus (closing the user's browser tab if they clicked mid-flow).

		Returns $false when the tab or its close button cannot be found or invoked, so the
		caller can fall back to the legacy SendKeys path.

	.PARAMETER WindowHandle
		Handle of the Windows Terminal top-level window that owns the tab.

	.PARAMETER TabTitle
		Exact title of the tab to close (as reported by Get-WindowsTerminalTabTitles).

	.OUTPUTS
		Boolean. $true when the close button was found and invoked.

	.EXAMPLE
		Close-WindowsTerminalTab -WindowHandle $wtWindow.Handle -TabTitle "ExampleProject.Api"
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[IntPtr]$WindowHandle,

		[Parameter(Mandatory = $true)]
		[string]$TabTitle
	)

	if ($WindowHandle -eq [IntPtr]::Zero) {
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
		foreach ($tabItem in $tabItems) {
			if ([string]$tabItem.Current.Name -eq $TabTitle) {
				$targetTab = $tabItem
				break
			}
		}

		if (-not $targetTab) {
			return $false
		}

		# The close control is a Button child of the TabItem exposing InvokePattern.
		$buttonCondition = New-Object System.Windows.Automation.PropertyCondition(
			[System.Windows.Automation.AutomationElement]::ControlTypeProperty,
			[System.Windows.Automation.ControlType]::Button
		)

		$buttons = $targetTab.FindAll([System.Windows.Automation.TreeScope]::Descendants, $buttonCondition)
		if (-not $buttons -or $buttons.Count -eq 0) {
			return $false
		}

		foreach ($button in $buttons) {
			$invokePattern = $null
			try {
				$invokePattern = $button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
			}
			catch {
				continue
			}

			if ($invokePattern) {
				$invokePattern.Invoke()
				return $true
			}
		}

		return $false
	}
	catch {
		return $false
	}
}
