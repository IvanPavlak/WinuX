#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Get-WindowsTerminalTabTitles.ps1"
}

Describe "Get-WindowsTerminalTabTitles" {
	It "returns `$null for a zero handle" {
		Get-WindowsTerminalTabTitles -WindowHandle ([IntPtr]::Zero) | Should -BeNullOrEmpty
	}

	It "returns `$null when the handle is not a live automation element" {
		# UIA FromHandle throws for a bogus handle - the helper must swallow it and
		# report `$null so callers fall back to the legacy SendKeys path.
		Get-WindowsTerminalTabTitles -WindowHandle ([IntPtr]0x7FFFFFFF) | Should -BeNullOrEmpty
	}

	It "returns `$null (never an empty array) for a live window that exposes no TabItems" {
		# Any non-WT window works: a live WT window always has >=1 tab, so zero results
		# must be indistinguishable from "UIA could not see the tabs" for the caller.
		$nonTerminalWindow = [WindowModule.Native]::GetAllWindows() |
			Where-Object { $_.ProcessName -notin @('WindowsTerminal') } |
			Select-Object -First 1

		if (-not $nonTerminalWindow) {
			Set-ItResult -Skipped -Because "no non-terminal window available in this session"
			return
		}

		$titles = Get-WindowsTerminalTabTitles -WindowHandle $nonTerminalWindow.Handle
		# Either $null (no TabItems / UIA unavailable) or a non-empty list - never @().
		if ($null -ne $titles) {
			@($titles).Count | Should -BeGreaterThan 0
		}
		else {
			$titles | Should -BeNullOrEmpty
		}
	}

	It "reads tab titles from a live Windows Terminal window when one exists" {
		$wtWindow = [WindowModule.Native]::GetAllWindows() |
			Where-Object { $_.ProcessName -eq 'WindowsTerminal' } |
			Select-Object -First 1

		if (-not $wtWindow) {
			Set-ItResult -Skipped -Because "no Windows Terminal window available in this session"
			return
		}

		$titles = Get-WindowsTerminalTabTitles -WindowHandle $wtWindow.Handle

		if ($null -eq $titles) {
			Set-ItResult -Skipped -Because "UIA could not read the tab strip in this session"
			return
		}

		@($titles).Count | Should -BeGreaterThan 0
		foreach ($title in $titles) {
			$title | Should -BeOfType [string]
		}
	}
}
