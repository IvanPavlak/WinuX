#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Update-DirectoryNames.ps1"
}

Describe "Update-DirectoryNames" {
	BeforeEach {
		Mock Get-Date { "2026_05_21" }
		Mock Get-ChildItem {
			@(
				[PSCustomObject]@{
					Name     = "Project_2025_01_01"
					FullName = "C:\\Temp\\Project_2025_01_01"
				}
			)
		}
		Mock Rename-Item { }
		Mock Write-Host { }
		Mock Write-LogWarning { }
	}

	It "does not rename directories in WhatIf mode" {
		{ Update-DirectoryNames -Path "C:\\Temp" -WhatIf } | Should -Not -Throw

		Should -Invoke Rename-Item -Times 0
		Should -Invoke Write-LogWarning -Times 1
	}
}
