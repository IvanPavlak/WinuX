#Requires -Modules Pester

BeforeAll {
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Install-ScoopPackageManager.ps1"
}

Describe "Install-ScoopPackageManager" {
	BeforeEach {
		Mock Write-Host { }
		Mock Invoke-Expression { }
		Mock Invoke-RestMethod { 'echo install scoop' }
	}

	It "skips installation when scoop command already exists" {
		Mock Get-Command { @{ Name = 'scoop' } }

		Install-ScoopPackageManager

		Should -Invoke Invoke-Expression -Times 0
	}

	It "runs install expression when scoop command is missing" {
		Mock Get-Command { $null }

		Install-ScoopPackageManager

		Should -Invoke Invoke-Expression -Times 1 -Exactly
	}
}
