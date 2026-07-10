#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Workflow\Functions"

	. "$FunctionsPath\Open-ProjectTerminals.ps1"

	# Stub dependent functions
	function Resolve-Selection { param($InputObject, $OptionList, $MenuTitle, [switch]$AllowMultipleSelections) $InputObject }
	function Resolve-ProjectPath { param($ProjectName, $PathKey) "C:\Fake\$ProjectName\$PathKey" }
	function Test-TerminalTabsAlreadyOpen { param($ExpectedTabNames, $ProjectName) [PSCustomObject]@{ AllOpen = $false; FoundTabs = @() } }
	function Open-Terminal { param($Command, [switch]$InSameShell, $WindowId, $TabTitles) }
}

Describe "Open-ProjectTerminals" {
	BeforeEach {
		Mock Write-Host { }
		Mock Write-LogError { }
		Mock Start-Sleep { }
		Mock Start-Process { }
		Mock Open-Terminal { }
		Mock Send-TerminalKeys { }
		Mock Resolve-Selection { param($InputObject) $InputObject }
		Mock Resolve-ProjectPath { param($ProjectName, $PathKey) "C:\Fake\$ProjectName\$PathKey" }
		Mock Test-TerminalTabsAlreadyOpen { [PSCustomObject]@{ AllOpen = $false; FoundTabs = @() } }

		$script:Configuration = @{
			ProjectTerminals       = @(
				@{ Name = "TestProject"; BasePath = "Projects.TestProject"; Paths = @("Api", "Ui") }
				@{ Name = "ProjectA"; BasePath = "Projects.ProjectA"; Paths = @("Root") }
				@{ Name = "ProjectB"; BasePath = "Projects.ProjectB"; Paths = @("Root") }
				@{ Name = "DefaultProject"; BasePath = "Projects.DefaultProject"; Paths = @("DEFAULT", "WSL") }
				@{ Name = "CustomProject"; BasePath = "Projects.CustomProject"; Paths = @(@{ Key = "Logs"; Path = "C:\CustomLogs" }, "Api") }
				@{ Name = "MixedProject"; BasePath = "Projects.MixedProject"; Paths = @("DEFAULT", @{ Key = "Docs"; Path = "C:\Docs" }, "Api") }
				@{ Name = "PlainCustom"; BasePath = "Projects.PlainCustom"; Paths = @(@{ Key = "Shell" }) }
			)
			DefaultWSLDistribution = "Ubuntu"
		}

		# Shells descended from an Open-Workspace -Alongside bootstrap carry a real
		# WT_WINDOW_ID, which the caller-window resolution prefers over "0" - clear it
		# so the window-id assertions below are deterministic regardless of where the
		# test run was started from.
		$script:previousWtWindowId = $env:WT_WINDOW_ID
		Remove-Item Env:WT_WINDOW_ID -ErrorAction SilentlyContinue
	}

	AfterEach {
		if ($null -ne $script:previousWtWindowId) {
			$env:WT_WINDOW_ID = $script:previousWtWindowId
		}
		else {
			Remove-Item Env:WT_WINDOW_ID -ErrorAction SilentlyContinue
		}
	}

	Context "Parameter validation" {
		It "Should have InSameGroup parameter" {
			$cmd = Get-Command Open-ProjectTerminals
			$cmd.Parameters.ContainsKey('InSameGroup') | Should -BeTrue
		}

		It "Should have InSameShell parameter" {
			$cmd = Get-Command Open-ProjectTerminals
			$cmd.Parameters.ContainsKey('InSameShell') | Should -BeTrue
		}

		It "Should have InSameGroup default to true" {
			$cmd = Get-Command Open-ProjectTerminals
			$param = $cmd.Parameters['InSameGroup']
			$switchAttr = $param.ParameterType
			$switchAttr.Name | Should -Be 'SwitchParameter'
		}

		It "Should have InSameShell default to true" {
			$cmd = Get-Command Open-ProjectTerminals
			$param = $cmd.Parameters['InSameShell']
			$switchAttr = $param.ParameterType
			$switchAttr.Name | Should -Be 'SwitchParameter'
		}

		It "Should have FocusTab parameter with default value of 0" {
			$cmd = Get-Command Open-ProjectTerminals
			$cmd.Parameters.ContainsKey('FocusTab') | Should -BeTrue
		}

		It "Should have InvokeOnefetch parameter" {
			$cmd = Get-Command Open-ProjectTerminals
			$cmd.Parameters.ContainsKey('InvokeOnefetch') | Should -BeTrue
		}

		It "Should have Project parameter" {
			$cmd = Get-Command Open-ProjectTerminals
			$cmd.Parameters.ContainsKey('Project') | Should -BeTrue
		}
	}

	Context "When InSameShell and InSameGroup are both true (default)" {
		It "Should call Open-Terminal with WindowId 0" {
			Open-ProjectTerminals -Project "TestProject" -InSameShell

			Should -Invoke Open-Terminal -Times 2 -ParameterFilter {
				$WindowId -eq "0"
			}
		}

		It "Should prefer WT_WINDOW_ID over window 0 when the calling shell knows its window" {
			$env:WT_WINDOW_ID = "caller-window-guid"

			Open-ProjectTerminals -Project "TestProject" -InSameShell

			Should -Invoke Open-Terminal -Times 2 -ParameterFilter {
				$WindowId -eq "caller-window-guid"
			}
		}

		It "Should check for already open tabs" {
			Open-ProjectTerminals -Project "TestProject" -InSameShell

			Should -Invoke Test-TerminalTabsAlreadyOpen -Times 1
		}

		It "Should skip project when all tabs already exist" {
			Mock Test-TerminalTabsAlreadyOpen { [PSCustomObject]@{ AllOpen = $true; FoundTabs = @("TestProject.Api", "TestProject.Ui") } }

			Open-ProjectTerminals -Project "TestProject" -InSameShell

			Should -Invoke Open-Terminal -Times 0
		}

		It "Should open only missing tabs when some already exist" {
			Mock Test-TerminalTabsAlreadyOpen { [PSCustomObject]@{ AllOpen = $false; FoundTabs = @("TestProject.Api") } }

			$script:capturedTabs = [System.Collections.ArrayList]@()
			Mock Open-Terminal {
				[void]$script:capturedTabs.Add($TabTitles)
			}

			Open-ProjectTerminals -Project "TestProject" -InSameShell

			$script:capturedTabs.Count | Should -Be 1
			$script:capturedTabs[0] | Should -Be "TestProject.Ui"
		}

		It "Should use window 0 for missing tabs when some already exist" {
			Mock Test-TerminalTabsAlreadyOpen { [PSCustomObject]@{ AllOpen = $false; FoundTabs = @("TestProject.Api") } }

			$script:capturedIds = [System.Collections.ArrayList]@()
			Mock Open-Terminal {
				[void]$script:capturedIds.Add($WindowId)
			}

			Open-ProjectTerminals -Project "TestProject" -InSameShell

			$script:capturedIds.Count | Should -Be 1
			$script:capturedIds[0] | Should -Be "0"
		}
	}

	Context "When InSameShell is true and InSameGroup is false" {
		It "Should call Open-Terminal with a GUID WindowId (not 0)" {
			Open-ProjectTerminals -Project "TestProject" -InSameShell -InSameGroup:$false

			Should -Invoke Open-Terminal -Times 2 -ParameterFilter {
				$WindowId -ne "0" -and $WindowId -ne $null
			}
		}

		It "Should use the same WindowId for all tabs within one project" {
			$capturedWindowIds = @()
			Mock Open-Terminal { $capturedWindowIds += $WindowId }.GetNewClosure()

			# We need a variable accessible inside the mock
			$script:capturedIds = [System.Collections.ArrayList]@()
			Mock Open-Terminal {
				[void]$script:capturedIds.Add($WindowId)
			}

			Open-ProjectTerminals -Project "TestProject" -InSameShell -InSameGroup:$false

			$script:capturedIds.Count | Should -Be 2
			$script:capturedIds[0] | Should -Be $script:capturedIds[1]
			$script:capturedIds[0] | Should -Not -Be "0"
		}

		It "Should use different WindowIds for different projects" {
			$script:capturedIds = [System.Collections.ArrayList]@()
			Mock Open-Terminal {
				[void]$script:capturedIds.Add($WindowId)
			}

			Open-ProjectTerminals -Project "ProjectA", "ProjectB" -InSameShell -InSameGroup:$false

			# ProjectA gets 1 tab, ProjectB gets 1 tab - each with different GUIDs
			$script:capturedIds.Count | Should -Be 2
			$script:capturedIds[0] | Should -Not -Be $script:capturedIds[1]
		}

		It "Should still check for already open tabs" {
			Open-ProjectTerminals -Project "TestProject" -InSameShell -InSameGroup:$false

			Should -Invoke Test-TerminalTabsAlreadyOpen -Times 1
		}
	}

	Context "When InSameShell is false and InSameGroup is true" {
		It "Should call Open-Terminal with a shared GUID WindowId for all projects" {
			$script:capturedIds = [System.Collections.ArrayList]@()
			Mock Open-Terminal {
				[void]$script:capturedIds.Add($WindowId)
			}

			Open-ProjectTerminals -Project "ProjectA", "ProjectB" -InSameShell:$false

			$script:capturedIds.Count | Should -Be 2
			# All tabs share the same GUID
			$script:capturedIds[0] | Should -Be $script:capturedIds[1]
			# But it's not window 0
			$script:capturedIds[0] | Should -Not -Be "0"
		}
	}

	Context "When both InSameShell and InSameGroup are false" {
		It "Should call Open-Terminal with unique GUID WindowId for each tab" {
			$script:capturedIds = [System.Collections.ArrayList]@()
			Mock Open-Terminal {
				[void]$script:capturedIds.Add($WindowId)
			}

			Open-ProjectTerminals -Project "TestProject" -InSameShell:$false -InSameGroup:$false

			$script:capturedIds.Count | Should -Be 2
			$script:capturedIds[0] | Should -Not -Be $script:capturedIds[1]
			$script:capturedIds[0] | Should -Not -Be "0"
			$script:capturedIds[1] | Should -Not -Be "0"
		}
	}

	Context "When project is not found in configuration" {
		It "Should display error message" {
			Open-ProjectTerminals -Project "NonExistent"

			Should -Invoke Write-LogError -ParameterFilter {
				$Message -like "*not found in configuration*"
			}
		}

		It "Should not call Open-Terminal" {
			Open-ProjectTerminals -Project "NonExistent"

			Should -Invoke Open-Terminal -Times 0
		}
	}

	Context "DEFAULT path type" {
		It "Should call Open-Terminal with empty command for DEFAULT entry" {
			$script:capturedCmds = [System.Collections.ArrayList]@()
			$script:capturedTitles = [System.Collections.ArrayList]@()
			Mock Open-Terminal {
				[void]$script:capturedCmds.Add($Command)
				[void]$script:capturedTitles.Add($TabTitles)
			}

			Open-ProjectTerminals -Project "DefaultProject" -InSameShell

			# DEFAULT tab should be called with empty command
			$script:capturedCmds.Count | Should -BeGreaterOrEqual 1
			$script:capturedCmds[0] | Should -Be ""
			$script:capturedTitles[0] | Should -Be "DefaultProject.DEFAULT"
		}

		It "Should open both DEFAULT and WSL tabs" {
			$script:capturedTitles = [System.Collections.ArrayList]@()
			Mock Open-Terminal {
				[void]$script:capturedTitles.Add($TabTitles)
			}

			Open-ProjectTerminals -Project "DefaultProject" -InSameShell

			# DEFAULT tab via Open-Terminal, WSL tab via wt.exe
			$script:capturedTitles.Count | Should -Be 1
			$script:capturedTitles[0] | Should -Be "DefaultProject.DEFAULT"
			# WSL is handled via wt.exe direct call, not Open-Terminal
			Should -Invoke Start-Process -Times 1
		}
	}

	Context "Custom path entries (hashtable)" {
		It "Should call Open-Terminal with Set-Location for custom path entry" {
			$script:capturedCmds = [System.Collections.ArrayList]@()
			$script:capturedTitles = [System.Collections.ArrayList]@()
			Mock Open-Terminal {
				[void]$script:capturedCmds.Add($Command)
				[void]$script:capturedTitles.Add($TabTitles)
			}

			Open-ProjectTerminals -Project "CustomProject" -InSameShell -InvokeOnefetch:$false

			# First tab: custom path, Second tab: regular Api
			$script:capturedCmds.Count | Should -Be 2
			$script:capturedCmds[0] | Should -BeLike "*Set-Location*CustomLogs*"
			$script:capturedTitles[0] | Should -Be "CustomProject.Logs"
			$script:capturedTitles[1] | Should -Be "CustomProject.Api"
		}

		It "Should open plain tab for hashtable entry without Path" {
			$script:capturedCmds = [System.Collections.ArrayList]@()
			$script:capturedTitles = [System.Collections.ArrayList]@()
			Mock Open-Terminal {
				[void]$script:capturedCmds.Add($Command)
				[void]$script:capturedTitles.Add($TabTitles)
			}

			Open-ProjectTerminals -Project "PlainCustom" -InSameShell

			$script:capturedCmds.Count | Should -Be 1
			$script:capturedCmds[0] | Should -Be ""
			$script:capturedTitles[0] | Should -Be "PlainCustom.Shell"
		}
	}

	Context "Mixed path types" {
		It "Should handle DEFAULT, custom path, and regular path entries together" {
			$script:capturedCmds = [System.Collections.ArrayList]@()
			$script:capturedTitles = [System.Collections.ArrayList]@()
			Mock Open-Terminal {
				[void]$script:capturedCmds.Add($Command)
				[void]$script:capturedTitles.Add($TabTitles)
			}

			Open-ProjectTerminals -Project "MixedProject" -InSameShell -InvokeOnefetch:$false

			$script:capturedCmds.Count | Should -Be 3
			# DEFAULT tab
			$script:capturedCmds[0] | Should -Be ""
			$script:capturedTitles[0] | Should -Be "MixedProject.DEFAULT"
			# Custom path tab
			$script:capturedCmds[1] | Should -BeLike "*Set-Location*Docs*"
			$script:capturedTitles[1] | Should -Be "MixedProject.Docs"
			# Regular path tab
			$script:capturedCmds[2] | Should -BeLike "*Set-Location*"
			$script:capturedTitles[2] | Should -Be "MixedProject.Api"
		}

		It "Should build expected tab names correctly for mixed entry types" {
			$script:capturedExpected = $null
			Mock Test-TerminalTabsAlreadyOpen {
				$script:capturedExpected = $ExpectedTabNames
				[PSCustomObject]@{ AllOpen = $false; FoundTabs = @() }
			}

			Open-ProjectTerminals -Project "MixedProject" -InSameShell

			$script:capturedExpected | Should -Contain "MixedProject.DEFAULT"
			$script:capturedExpected | Should -Contain "MixedProject.Docs"
			$script:capturedExpected | Should -Contain "MixedProject.Api"
		}
	}
}
