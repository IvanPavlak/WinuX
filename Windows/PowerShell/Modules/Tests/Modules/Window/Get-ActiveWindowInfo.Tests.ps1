#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Write-WindowInfoBlock.ps1"
	. "$FunctionsPath\Get-ActiveWindowInfo.ps1"
}

Describe "Get-ActiveWindowInfo" {
	BeforeEach {
		Mock Create-CenteredBorder { "-----" }
		Mock Get-CachedWindows { @() }
		Mock Write-Host { }
		Mock Write-LogTitle { }
		Mock Write-LogError { }
	}

	It "handles no windows found in one-shot mode" {
		{ Get-ActiveWindowInfo } | Should -Not -Throw
		Should -Invoke Get-CachedWindows -Times 1
		Should -Invoke Write-LogTitle -Times 1
		Should -Invoke Write-LogError -Times 1
	}
}
