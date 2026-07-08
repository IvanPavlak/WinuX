#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\ReRun-LastCommand.ps1"
}

Describe "ReRun-LastCommand" {
	BeforeEach {
		Mock Write-Host { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }
	}

	It "returns when PSReadLine history path cannot be accessed" {
		Mock Get-PSReadLineOption { throw "Unavailable" }

		{ ReRun-LastCommand -AutoAccept } | Should -Not -Throw
		Should -Invoke Write-LogWarning -Times 1
		Should -Invoke Write-LogError -Times 1
	}

	It "returns when history file does not exist" {
		Mock Get-PSReadLineOption { [PSCustomObject]@{ HistorySavePath = "C:\\missing_history.txt" } }
		Mock Test-Path { $false }

		{ ReRun-LastCommand -AutoAccept } | Should -Not -Throw
		Should -Invoke Write-LogWarning -Times 1
		Should -Invoke Write-LogError -Times 1
	}
}
