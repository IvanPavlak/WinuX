#Requires -Modules Pester

BeforeAll {
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Test-ProjectAlreadyOpen.ps1"
}

Describe "Test-ProjectAlreadyOpen" {
	Context "No Windows Open" {
		It "Should return false when no matching windows exist" {
			Mock Get-WindowHandle { @() }

			$result = Test-ProjectAlreadyOpen -ProjectName "TestProject" -ProcessName "Code" -ApplicationName "VSCode"

			$result | Should -Be $false
		}

		It "Should return false when Get-WindowHandle returns null" {
			Mock Get-WindowHandle { $null }

			$result = Test-ProjectAlreadyOpen -ProjectName "TestProject" -ProcessName "Code" -ApplicationName "VSCode"

			$result | Should -Be $false
		}
	}

	Context "Window Title Matching" {
		It "Should return true when window title contains project name" {
			Mock Get-WindowHandle {
				@([PSCustomObject]@{ Title = "TestProject - Visual Studio Code" })
			}

			$result = Test-ProjectAlreadyOpen -ProjectName "TestProject" -ProcessName "Code" -ApplicationName "VSCode"

			$result | Should -Be $true
		}

		It "Should be case-insensitive when matching project name" {
			Mock Get-WindowHandle {
				@([PSCustomObject]@{ Title = "TESTPROJECT - Visual Studio Code" })
			}

			$result = Test-ProjectAlreadyOpen -ProjectName "TestProject" -ProcessName "Code" -ApplicationName "VSCode"

			$result | Should -Be $true
		}

		It "Should return false when window title does not contain project name" {
			Mock Get-WindowHandle {
				@([PSCustomObject]@{ Title = "OtherProject - Visual Studio Code" })
			}

			$result = Test-ProjectAlreadyOpen -ProjectName "TestProject" -ProcessName "Code" -ApplicationName "VSCode"

			$result | Should -Be $false
		}

		It "Should match regex-escaped project names with special characters" {
			Mock Get-WindowHandle {
				@([PSCustomObject]@{ Title = "My.Project.Name - Visual Studio" })
			}

			$result = Test-ProjectAlreadyOpen -ProjectName "My.Project.Name" -ProcessName "devenv" -ApplicationName "Visual Studio"

			$result | Should -Be $true
		}

		It "Should check multiple windows and return true on first match" {
			Mock Get-WindowHandle {
				@(
					[PSCustomObject]@{ Title = "OtherProject - Visual Studio Code" },
					[PSCustomObject]@{ Title = "TestProject - Visual Studio Code" },
					[PSCustomObject]@{ Title = "AnotherProject - Visual Studio Code" }
				)
			}

			$result = Test-ProjectAlreadyOpen -ProjectName "TestProject" -ProcessName "Code" -ApplicationName "VSCode"

			$result | Should -Be $true
		}
	}

	Context "Error Handling" {
		It "Should return false when Get-WindowHandle throws" {
			Mock Get-WindowHandle { throw "Simulated error" }

			$result = Test-ProjectAlreadyOpen -ProjectName "TestProject" -ProcessName "Code" -ApplicationName "VSCode"

			$result | Should -Be $false
		}
	}
}
