#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Workflow\Functions"

	. "$FunctionsPath\Training-Backup.ps1"
}

Describe "Training-Backup" {
	BeforeEach {
		Mock Set-Location { }
		Mock Write-Host { }
		Mock Write-LogSuccess { }
		Mock Write-LogError { }
	}

	It "runs backup script and restores original location" {
		Mock Get-Location { "C:\Start" }

		Training-Backup

		Should -Invoke Set-Location -Times 1
		Should -Invoke Write-LogError -Times 2
	}
}
