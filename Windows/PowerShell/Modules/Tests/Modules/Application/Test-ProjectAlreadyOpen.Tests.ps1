#Requires -Modules Pester

BeforeAll {
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	$HelperFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Helper\Functions"
	. "$AppFunctionsPath\Test-ProjectAlreadyOpen.ps1"
	. "$HelperFunctionsPath\Test-WindowTitleCandidates.ps1"
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
		It "Should return true when the window title starts with the project segment" {
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

		It "Should return false when no window title has the project segment" {
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

	Context "Whole Segment Matching" {
		It "Should return false when the project name is only a substring of another window's folder" {
			Mock Get-WindowHandle {
				@(
					[PSCustomObject]@{ Title = "myapp-ui - Visual Studio Code" },
					[PSCustomObject]@{ Title = "Program.cs - myapp-ui - Visual Studio Code" }
				)
			}

			$result = Test-ProjectAlreadyOpen -ProjectName "MyApp" -ProcessName "Code" -ApplicationName "VSCode"

			$result | Should -Be $false
		}

		It "Should return false when the project name only appears inside the application name" {
			Mock Get-WindowHandle {
				@([PSCustomObject]@{ Title = "MyProject - Visual Studio Code" })
			}

			$result = Test-ProjectAlreadyOpen -ProjectName "Studio" -ProcessName "Code" -ApplicationName "VSCode"

			$result | Should -Be $false
		}

		It "Should return true when the project is the folder segment with no active editor" {
			Mock Get-WindowHandle {
				@([PSCustomObject]@{ Title = "MyApp - Visual Studio Code" })
			}

			$result = Test-ProjectAlreadyOpen -ProjectName "MyApp" -ProcessName "Code" -ApplicationName "VSCode"

			$result | Should -Be $true
		}

		It "Should return true when the project is the folder segment behind the active editor" {
			Mock Get-WindowHandle {
				@([PSCustomObject]@{ Title = "Program.cs - MyApp - Visual Studio Code" })
			}

			$result = Test-ProjectAlreadyOpen -ProjectName "MyApp" -ProcessName "Code" -ApplicationName "VSCode"

			$result | Should -Be $true
		}

		It "Should return true when a VS Code profile segment follows the folder segment" {
			Mock Get-WindowHandle {
				@([PSCustomObject]@{ Title = "Program.cs - MyApp - Work - Visual Studio Code" })
			}

			$result = Test-ProjectAlreadyOpen -ProjectName "MyApp" -ProcessName "Code" -ApplicationName "VSCode"

			$result | Should -Be $true
		}

		It "Should return true when the title starts with the dirty marker" {
			Mock Get-WindowHandle {
				@([PSCustomObject]@{ Title = "$([char]0x25CF) Program.cs - MyApp - Visual Studio Code" })
			}

			$result = Test-ProjectAlreadyOpen -ProjectName "MyApp" -ProcessName "Code" -ApplicationName "VSCode"

			$result | Should -Be $true
		}

		It "Should return true when the dirty marker directly precedes the project segment" {
			Mock Get-WindowHandle {
				@([PSCustomObject]@{ Title = "$([char]0x25CF) MyApp - Visual Studio Code" })
			}

			$result = Test-ProjectAlreadyOpen -ProjectName "MyApp" -ProcessName "Code" -ApplicationName "VSCode"

			$result | Should -Be $true
		}

		It "Should match a whole segment case-insensitively" {
			Mock Get-WindowHandle {
				@([PSCustomObject]@{ Title = "Program.cs - myapp - Visual Studio Code" })
			}

			$result = Test-ProjectAlreadyOpen -ProjectName "MyApp" -ProcessName "Code" -ApplicationName "VSCode"

			$result | Should -Be $true
		}

		It "Should find the project window among windows whose folders only contain the name" {
			Mock Get-WindowHandle {
				@(
					[PSCustomObject]@{ Title = "Program.cs - myapp-ui - Visual Studio Code" },
					[PSCustomObject]@{ Title = "Startup.cs - MyApp - Visual Studio Code" }
				)
			}

			$result = Test-ProjectAlreadyOpen -ProjectName "MyApp" -ProcessName "Code" -ApplicationName "VSCode"

			$result | Should -Be $true
		}

		It "Should not treat a workspace window as the same-named folder" {
			Mock Get-WindowHandle {
				@([PSCustomObject]@{ Title = "Program.cs - MyApp (Workspace) - Visual Studio Code" })
			}

			$result = Test-ProjectAlreadyOpen -ProjectName "MyApp" -ProcessName "Code" -ApplicationName "VSCode"

			$result | Should -Be $false
		}

		It "Should match a workspace name including its (Workspace) suffix" {
			Mock Get-WindowHandle {
				@([PSCustomObject]@{ Title = "Program.cs - MyApp (Workspace) - Visual Studio Code" })
			}

			$result = Test-ProjectAlreadyOpen -ProjectName "MyApp (Workspace)" -ProcessName "Code" -ApplicationName "VSCode"

			$result | Should -Be $true
		}
	}

	Context "Visual Studio Titles" {
		It "Should return true when the solution segment carries a debugger state" {
			Mock Get-WindowHandle {
				@([PSCustomObject]@{ Title = "MySolution (Debugging) - Microsoft Visual Studio" })
			}

			$result = Test-ProjectAlreadyOpen -ProjectName "MySolution" -ProcessName "devenv" -ApplicationName "Visual Studio"

			$result | Should -Be $true
		}

		It "Should return true when the application segment carries an elevation suffix" {
			Mock Get-WindowHandle {
				@([PSCustomObject]@{ Title = "MySolution - Microsoft Visual Studio (Administrator)" })
			}

			$result = Test-ProjectAlreadyOpen -ProjectName "MySolution" -ProcessName "devenv" -ApplicationName "Visual Studio"

			$result | Should -Be $true
		}

		It "Should return false when the solution name is only a prefix of another solution" {
			Mock Get-WindowHandle {
				@([PSCustomObject]@{ Title = "MySolution.Tests (Debugging) - Microsoft Visual Studio" })
			}

			$result = Test-ProjectAlreadyOpen -ProjectName "MySolution" -ProcessName "devenv" -ApplicationName "Visual Studio"

			$result | Should -Be $false
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
