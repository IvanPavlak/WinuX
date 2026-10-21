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

	It "renames a name that is only a date to today's date" {
		# The prefix used to be taken as $parts[0..0] even with no prefix, so the year stayed
		# in front: 2025_01_01 became 2025_2026_05_21.
		Mock Get-ChildItem { @([PSCustomObject]@{ Name = "2025_01_01"; FullName = "C:\Temp\2025_01_01" }) }
		Mock Write-LogSuccess { }

		Update-DirectoryNames -Path "C:\Temp"

		Should -Invoke Rename-Item -Times 1 -Exactly -ParameterFilter { $NewName -eq "2026_05_21" }
	}

	It "keeps a multi-part prefix and replaces only the date" {
		Mock Get-ChildItem { @([PSCustomObject]@{ Name = "My_Project_2025_01_01"; FullName = "C:\Temp\My_Project_2025_01_01" }) }
		Mock Write-LogSuccess { }

		Update-DirectoryNames -Path "C:\Temp"

		Should -Invoke Rename-Item -Times 1 -Exactly -ParameterFilter { $NewName -eq "My_Project_2026_05_21" }
	}

	It "leaves a directory alone when its date is already today's" {
		Mock Get-ChildItem { @([PSCustomObject]@{ Name = "Project_2026_05_21"; FullName = "C:\Temp\Project_2026_05_21" }) }
		Mock Write-LogStep { }

		Update-DirectoryNames -Path "C:\Temp"

		Should -Invoke Rename-Item -Times 0
	}
}
