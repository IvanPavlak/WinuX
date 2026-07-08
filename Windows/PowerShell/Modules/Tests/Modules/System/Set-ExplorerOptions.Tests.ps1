#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Set-ExplorerOptions.ps1"
}

Describe "Set-ExplorerOptions" {
	BeforeEach {
		$script:Configuration = [PSCustomObject]@{
			ExplorerOptions = $null
		}
		Mock Write-Host { }
		Mock Write-LogTitle { }
		Mock Write-LogError { }
		Mock Restart-Explorer { }
	}

	It "returns when ExplorerOptions are missing from configuration" {
		{ Set-ExplorerOptions } | Should -Not -Throw
		Should -Invoke Restart-Explorer -Times 0
		Should -Invoke Write-LogTitle -Times 1
		Should -Invoke Write-LogError -Times 1
	}
}
