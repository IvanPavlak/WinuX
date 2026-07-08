#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Wait-ForWorkspaceWindows.ps1"
}

Describe "Wait-ForWorkspaceWindows" {
	BeforeEach {
		Mock Resolve-LayoutTokens { param([hashtable]$LayoutEntry) $LayoutEntry }
		Mock Clear-WindowCache { }
	}

	It "rejects empty layout input" {
		{ Wait-ForWorkspaceWindows -LayoutConfig @() } | Should -Throw
		Should -Invoke Clear-WindowCache -Times 0
	}
}
