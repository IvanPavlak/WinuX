#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Workflow\Functions"

	. "$FunctionsPath\Focus-TerminalTab.ps1"
}

Describe "Focus-TerminalTab" {
	BeforeEach {
		Mock Get-Process { @() }
		Mock Write-Host { }
		Mock Write-LogDebug { }
		Mock Write-LogSuccess { }
	}

	It "returns when Windows Terminal is not running" {
		{ Focus-TerminalTab } | Should -Not -Throw
		Should -Invoke Write-Host -Times 0
	}

	It "writes debug message when terminal is not running and debug is enabled" {
		Focus-TerminalTab

		Should -Invoke Write-LogDebug -Times 1
	}
}
