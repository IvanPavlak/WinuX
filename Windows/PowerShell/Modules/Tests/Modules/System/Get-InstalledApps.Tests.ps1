#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Get-InstalledApps.ps1"
}

Describe "Get-InstalledApps" {
	BeforeEach {
		$script:Hostname = @()
		Mock Test-Path { $false }
		Mock Clear-Content { }
		Mock Add-Content { }
		Mock Write-Host { }
		Mock Write-LogSuccess { }
	}

	It "completes even when no hosts are available to scan" {
		{ Get-InstalledApps } | Should -Not -Throw

		Should -Invoke Clear-Content -Times 0
		Should -Invoke Write-LogSuccess -Times 1
	}
}
