#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Refresh-BrowserTabs.ps1"
}

Describe "Refresh-BrowserTabs" {
	BeforeEach {
		Mock Add-Type { }
		Mock Get-WindowHandle { $null }
		Mock Write-Host { }
		Mock Write-LogTitle { }
		Mock Write-LogWarning { }
	}

	It "reports no browser tabs when no browser windows are found" {
		{ Refresh-BrowserTabs } | Should -Not -Throw
		Should -Invoke Get-WindowHandle -Times 4
		Should -Invoke Write-LogTitle -Times 1
		Should -Invoke Write-LogWarning -Times 1
	}
}
