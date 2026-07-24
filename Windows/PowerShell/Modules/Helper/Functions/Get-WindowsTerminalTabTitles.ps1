function Get-WindowsTerminalTabTitles {
	<#
	.SYNOPSIS
		Reads the tab titles of a Windows Terminal window via UI Automation - no focus, no keystrokes.

	.DESCRIPTION
		Enumerates the TabItem elements of the given Windows Terminal window through UI Automation
		and returns their names in tab order. Replaces the SendKeys Ctrl+Tab cycling probes, which
		had to foreground each window and type into it (stealing focus, racing user input, and
		costing ~50-100ms per tab). Windows Terminal's UIA tree is small, so a Descendants scan is
		fast (tens of milliseconds per window).

		Returns $null - never an empty array - when the tabs cannot be read (UIA unavailable,
		element gone, or no TabItem exposed), so callers can distinguish "UIA failed, use the
		legacy fallback" from a real answer: a live WT window always has at least one tab.

	.PARAMETER WindowHandle
		Handle of the Windows Terminal top-level window to inspect.

	.OUTPUTS
		[string[]] tab titles in tab-strip order, or $null when they cannot be read.

	.EXAMPLE
		$titles = Get-WindowsTerminalTabTitles -WindowHandle $wtWindow.Handle
		if ($null -eq $titles) { Write-Verbose "fall back to Ctrl+Tab cycling" }
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[IntPtr]$WindowHandle
	)

	if ($WindowHandle -eq [IntPtr]::Zero) {
		return $null
	}

	try {
		Add-Type -AssemblyName UIAutomationClient -ErrorAction Stop
		Add-Type -AssemblyName UIAutomationTypes -ErrorAction Stop

		$root = [System.Windows.Automation.AutomationElement]::FromHandle($WindowHandle)
		if (-not $root) {
			return $null
		}

		$tabCondition = New-Object System.Windows.Automation.PropertyCondition(
			[System.Windows.Automation.AutomationElement]::ControlTypeProperty,
			[System.Windows.Automation.ControlType]::TabItem
		)

		$tabItems = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $tabCondition)
		if (-not $tabItems -or $tabItems.Count -eq 0) {
			# A live WT window always has >=1 tab - zero results means UIA could not see them.
			return $null
		}

		$titles = @(
			foreach ($tabItem in $tabItems) {
				[string]$tabItem.Current.Name
			}
		)

		return $titles
	}
	catch {
		return $null
	}
}
