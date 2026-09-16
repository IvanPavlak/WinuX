#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. "$ModuleRoot\System\Functions\Send-TerminalFontKey.ps1"

	if (-not (Get-Command Write-LogDebug -ErrorAction SilentlyContinue)) { function Write-LogDebug { param($Message) } }
	if (-not (Get-Command Add-WindowsFormsType -ErrorAction SilentlyContinue)) { function Add-WindowsFormsType { param([switch]$Quiet) } }
}

Describe "Send-TerminalFontKey" {
	BeforeEach {
		Mock Write-LogDebug { }
		Mock Add-WindowsFormsType { }
	}

	# Every case runs with -WhatIf: the keystroke itself is a static .NET call Pester cannot
	# intercept, and a real Ctrl+0 / Ctrl+Minus would land in whatever window has focus while
	# the suite runs. -WhatIf stops before the send, after the mapping has been logged.

	It "rejects an action outside Reset / Decrease" {
		{ Send-TerminalFontKey -Action Grow -WhatIf } | Should -Throw
		Should -Invoke Write-LogDebug -Times 0 -Exactly
	}

	It "requires an action" {
		{ Send-TerminalFontKey -WhatIf } | Should -Throw
	}

	It "maps <Action> to <Keys>" -ForEach @(
		@{ Action = "Reset"; Keys = "^0" }
		@{ Action = "Decrease"; Keys = "^-" }
	) {
		Send-TerminalFontKey -Action $Action -WhatIf

		Should -Invoke Write-LogDebug -Times 1 -Exactly -ParameterFilter { $Message -eq "[Send-TerminalFontKey] $Action => SendKeys [$Keys]" }
	}

	It "sends nothing and loads nothing under -WhatIf" {
		Send-TerminalFontKey -Action Reset -WhatIf

		Should -Invoke Add-WindowsFormsType -Times 0 -Exactly
	}

	It "supports ShouldProcess so callers can dry-run it" {
		(Get-Command Send-TerminalFontKey).Parameters.ContainsKey("WhatIf") | Should -BeTrue
	}
}
