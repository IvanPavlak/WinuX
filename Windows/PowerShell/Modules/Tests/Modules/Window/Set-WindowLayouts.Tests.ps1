#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Set-WindowLayouts.ps1"
}

Describe "Set-WindowLayouts" {
	BeforeEach {
		Mock Initialize-PositionedWindowTracking { }
		Mock Test-Path { $false }
		Mock Write-Error { }
		Mock Resolve-LayoutTokens { param([hashtable]$LayoutEntry) $LayoutEntry }
	}

	It "returns when ConfigPath does not exist" {
		Set-WindowLayouts -ConfigPath "C:\\Missing\\layout.psd1"

		Should -Invoke Initialize-PositionedWindowTracking -Times 1
		Should -Invoke Test-Path -Times 1
		Should -Invoke Write-Error -Times 1
	}
}
