#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Workflow\Functions"

	. "$FunctionsPath\Close-ProjectTerminals.ps1"

	# Stub before mocking: these live in the Helper and Window modules, which this file never loads.
	function Get-WindowHandle { param($ProcessName) }
	function Resolve-HostingTerminalTab { }
	function Get-WindowsTerminalTabTitles { param([IntPtr]$WindowHandle) }
	function Close-WindowsTerminalTab { param([IntPtr]$WindowHandle, [string]$TabTitle) }
	function Ensure-DesktopVisible { param([IntPtr]$WindowHandle, [int]$DesktopIndex) }
}

Describe "Close-ProjectTerminals" {
	BeforeEach {
		Mock Write-LogDebug { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock Start-Sleep { }
		Mock Test-LogVerbose { $false }
		Mock Ensure-DesktopVisible { $null }
		Mock Close-WindowsTerminalTab { $true }
		Mock Resolve-HostingTerminalTab { $null }
		Mock Get-WindowHandle {
			@([PSCustomObject]@{ Handle = [IntPtr]100; Title = "PowerShell" })
		}
		Mock Get-WindowsTerminalTabTitles {
			@("PowerShell", "AnotherProject.Api", "AnotherProject.Ui", "OtherProject.Api")
		}
	}

	Context "When Windows Terminal is not running" {
		It "Should return 0 without reading or closing anything" {
			Mock Get-WindowHandle { @() }

			$result = Close-ProjectTerminals -ProjectName "AnotherProject"

			$result | Should -Be 0
			Should -Invoke Close-WindowsTerminalTab -Times 0
		}
	}

	Context "Closing the project's tabs" {
		It "closes every tab of the project and only those, returning the count" {
			$result = Close-ProjectTerminals -ProjectName "AnotherProject"

			$result | Should -Be 2
			Should -Invoke Close-WindowsTerminalTab -Times 1 -Exactly -ParameterFilter { $TabTitle -eq "AnotherProject.Api" -and $WindowHandle -eq [IntPtr]100 }
			Should -Invoke Close-WindowsTerminalTab -Times 1 -Exactly -ParameterFilter { $TabTitle -eq "AnotherProject.Ui" }
			Should -Invoke Close-WindowsTerminalTab -Times 0 -ParameterFilter { $TabTitle -eq "OtherProject.Api" }
			Should -Invoke Close-WindowsTerminalTab -Times 0 -ParameterFilter { $TabTitle -eq "PowerShell" }
		}

		It "never closes the tab this shell runs in, even when it is one of the project's tabs" {
			# Closing it would end this process mid-run and leave the other project tabs open.
			Mock Resolve-HostingTerminalTab { [PSCustomObject]@{ Handle = [IntPtr]100; ProcessId = 1; TabTitle = "AnotherProject.Api" } }

			$result = Close-ProjectTerminals -ProjectName "AnotherProject"

			$result | Should -Be 1
			Should -Invoke Close-WindowsTerminalTab -Times 0 -ParameterFilter { $TabTitle -eq "AnotherProject.Api" }
			Should -Invoke Close-WindowsTerminalTab -Times 1 -Exactly -ParameterFilter { $TabTitle -eq "AnotherProject.Ui" }
		}

		It "still closes a same-named tab in a window this shell does not run in" {
			Mock Get-WindowHandle {
				@(
					[PSCustomObject]@{ Handle = [IntPtr]100; Title = "PowerShell" }
					[PSCustomObject]@{ Handle = [IntPtr]200; Title = "AnotherProject.Api" }
				)
			}
			Mock Get-WindowsTerminalTabTitles { @("AnotherProject.Api") } -ParameterFilter { $WindowHandle -eq [IntPtr]200 }
			Mock Resolve-HostingTerminalTab { [PSCustomObject]@{ Handle = [IntPtr]100; ProcessId = 1; TabTitle = "AnotherProject.Api" } }

			Close-ProjectTerminals -ProjectName "AnotherProject" | Out-Null

			Should -Invoke Close-WindowsTerminalTab -Times 1 -Exactly -ParameterFilter { $TabTitle -eq "AnotherProject.Api" -and $WindowHandle -eq [IntPtr]200 }
			Should -Invoke Close-WindowsTerminalTab -Times 0 -ParameterFilter { $TabTitle -eq "AnotherProject.Api" -and $WindowHandle -eq [IntPtr]100 }
		}

		It "never closes the tab named by -StartingTabTitle" {
			$result = Close-ProjectTerminals -ProjectName "AnotherProject" -StartingTabTitle "AnotherProject.Ui"

			$result | Should -Be 1
			Should -Invoke Close-WindowsTerminalTab -Times 0 -ParameterFilter { $TabTitle -eq "AnotherProject.Ui" }
		}

		It "searches only the window named by -TerminalWindowHandle" {
			Mock Get-WindowHandle {
				@(
					[PSCustomObject]@{ Handle = [IntPtr]100; Title = "PowerShell" }
					[PSCustomObject]@{ Handle = [IntPtr]200; Title = "Other" }
				)
			}

			Close-ProjectTerminals -ProjectName "AnotherProject" -TerminalWindowHandle ([IntPtr]200) | Out-Null

			Should -Invoke Get-WindowsTerminalTabTitles -Times 0 -ParameterFilter { $WindowHandle -eq [IntPtr]100 }
			Should -Invoke Close-WindowsTerminalTab -Times 0 -ParameterFilter { $WindowHandle -eq [IntPtr]100 }
		}

		It "does not count a tab whose close button could not be invoked" {
			Mock Close-WindowsTerminalTab { $false } -ParameterFilter { $TabTitle -eq "AnotherProject.Ui" }

			Close-ProjectTerminals -ProjectName "AnotherProject" | Should -Be 1
		}
	}

	Context "A terminal parked on another virtual desktop" {
		It "brings its desktop up for the read and puts the view back" {
			$script:tabReads = 0
			Mock Get-WindowsTerminalTabTitles {
				$script:tabReads++
				if ($script:tabReads -eq 1) { return $null }
				@("AnotherProject.Api")
			}
			Mock Ensure-DesktopVisible { 0 } -ParameterFilter { $WindowHandle -eq [IntPtr]100 }

			$result = Close-ProjectTerminals -ProjectName "AnotherProject"

			$result | Should -Be 1
			Should -Invoke Ensure-DesktopVisible -Times 1 -Exactly -ParameterFilter { $WindowHandle -eq [IntPtr]100 }
			Should -Invoke Ensure-DesktopVisible -Times 1 -Exactly -ParameterFilter { [int64]$WindowHandle -eq 0 -and $DesktopIndex -eq 0 }
		}

		It "closes nothing in a window whose tabs stay unreadable" {
			Mock Get-WindowsTerminalTabTitles { $null }

			$result = Close-ProjectTerminals -ProjectName "AnotherProject"

			$result | Should -Be 0
			Should -Invoke Close-WindowsTerminalTab -Times 0
			Should -Invoke Write-LogWarning -Times 1 -Exactly
		}
	}

	Context "Parameter validation" {
		It "Should require ProjectName parameter" {
			$cmd = Get-Command Close-ProjectTerminals
			$param = $cmd.Parameters['ProjectName']
			$param | Should -Not -BeNullOrEmpty

			$mandatoryAttr = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
			$mandatoryAttr.Mandatory | Should -BeTrue
		}
	}
}
