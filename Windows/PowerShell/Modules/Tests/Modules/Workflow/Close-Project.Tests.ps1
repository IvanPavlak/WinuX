#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$HelperFunctionsPath = Join-Path $ModuleRoot "Helper\Functions"
	$WorkflowFunctionsPath = Join-Path $ModuleRoot "Workflow\Functions"

	. "$HelperFunctionsPath\Get-ConfigSetting.ps1"
	. "$HelperFunctionsPath\Get-OrderedNames.ps1"
	. "$HelperFunctionsPath\Get-OrderedEntry.ps1"
	. "$HelperFunctionsPath\Get-WindowTitleCandidates.ps1"
	. "$HelperFunctionsPath\Test-WindowTitleCandidates.ps1"
	. "$WorkflowFunctionsPath\Get-SwaggerCloseTitlePatterns.ps1"
	. "$WorkflowFunctionsPath\Close-Project.ps1"

	function Resolve-Selection { param($InputObject) $InputObject }
	function Close-ProjectTerminals { param($ProjectName) 0 }
	function Close-BrowserTabsByPattern { param($ProcessName, $TitlePatterns) 0 }
	function Focus-TerminalTab { param($TargetTitle, [IntPtr]$WindowHandle) }
	# Stubbed so the test run neither walks its own process tree nor touches the real keyboard state.
	function Resolve-HostingTerminalTab { }
	function Reset-KeyboardModifiers { }
	# The graceful close goes through the Window module's seam; stubbed so no WM_CLOSE is posted.
	function Close-Window { param([IntPtr[]]$Handle) $Handle.Count }
}

Describe "Close-Project" {
	BeforeEach {
		Mock Write-Host { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock Write-LogTitle { }
		Mock Write-LogDebug { }
		Mock Focus-TerminalTab { }
		Mock Resolve-HostingTerminalTab { $null }
		Mock Reset-KeyboardModifiers { }
		Mock Close-ProjectTerminals { 0 }
		Mock Close-BrowserTabsByPattern { 0 }

		$global:MachineSpecificPaths = @{
			Projects = @{
				ExampleProject = @{
					Solution = "C:\Projects\ExampleProject\ExampleProject.sln"
					Backend  = "C:\Projects\ExampleProject\ExampleProject.Api"
					Ui       = "C:\Projects\ExampleProject\ExampleProject-UI"
				}
			}
		}

		$global:Configuration = @{
			VisualStudioSolutions = @(
				@{ Name = "ExampleProject"; Solution = "Projects.ExampleProject.Solution" }
			)
			VSCodeProjects        = @(
				@{ Name = "ExampleProject"; Path = "Projects.ExampleProject.Backend" }
				@{ Name = "ExampleProject-UI"; Path = "Projects.ExampleProject.Ui" }
			)
			ProjectActions        = @(
				@{ ExampleProject = @(
						@{ Action = "Open-VisualStudio"; Parameters = @{ Solution = "{ProjectName}" } }
						@{ Action = "Open-VSCode"; Parameters = @{ Folder = "{ProjectName}" } }
						@{ Action = "Open-VSCode"; Parameters = @{ Folder = "ExampleProject-UI" } }
					)
				}
			)
			BrowserGroups         = @{}
			Universal             = @{
				DefaultBrowser = "Firefox"
				Browsers       = @{
					Firefox = @{}
				}
			}
		}
	}

	It "matches resolved Visual Studio and VSCode titles for ExampleProject" {
		Mock Get-WindowHandle {
			@(
				[PSCustomObject]@{ Title = "ExampleProject - Microsoft Visual Studio"; Handle = [System.IntPtr]1 },
				[PSCustomObject]@{ Title = "ExampleProject.Api - Visual Studio Code"; Handle = [System.IntPtr]2 },
				[PSCustomObject]@{ Title = "ExampleProject-UI - Visual Studio Code"; Handle = [System.IntPtr]3 }
			)
		}

		Close-Project -Project "ExampleProject"

		Should -Invoke Write-LogSuccess -Times 5
	}

	It "does not report no-window warnings for resolved ExampleProject aliases in debug mode" {
		Mock Get-WindowHandle {
			@(
				[PSCustomObject]@{ Title = "ExampleProject - Microsoft Visual Studio"; Handle = [System.IntPtr]1 },
				[PSCustomObject]@{ Title = "ExampleProject.Api - Visual Studio Code"; Handle = [System.IntPtr]2 },
				[PSCustomObject]@{ Title = "ExampleProject-UI - Visual Studio Code"; Handle = [System.IntPtr]3 }
			)
		}

		Close-Project -Project "ExampleProject"

		Should -Invoke Write-LogSuccess -Times 5
	}

	Context "similarly named windows" {
		BeforeEach {
			$script:closedHandles = @()
			Mock Close-Window {
				param([IntPtr[]]$Handle)
				$script:closedHandles += $Handle
				$Handle.Count
			}
		}

		It "does not close windows whose solution or folder only contains the project's names" {
			Mock Get-WindowHandle {
				@([PSCustomObject]@{ Title = "ExampleProject.Tests - Microsoft Visual Studio"; Handle = [System.IntPtr]4 })
			} -ParameterFilter { $ProcessName -eq "devenv" }
			Mock Get-WindowHandle {
				@([PSCustomObject]@{ Title = "Program.cs - exampleproject-admin - Visual Studio Code"; Handle = [System.IntPtr]5 })
			} -ParameterFilter { $ProcessName -eq "Code" }

			Close-Project -Project "ExampleProject"

			Should -Invoke Close-Window -Times 0 -Exactly
		}

		It "closes only the project's own windows when similarly named ones are open" {
			Mock Get-WindowHandle {
				@(
					[PSCustomObject]@{ Title = "ExampleProject (Debugging) - Microsoft Visual Studio"; Handle = [System.IntPtr]1 },
					[PSCustomObject]@{ Title = "ExampleProject.Tests - Microsoft Visual Studio"; Handle = [System.IntPtr]4 }
				)
			} -ParameterFilter { $ProcessName -eq "devenv" }
			Mock Get-WindowHandle {
				@(
					[PSCustomObject]@{ Title = "Program.cs - ExampleProject.Api - Visual Studio Code"; Handle = [System.IntPtr]2 },
					[PSCustomObject]@{ Title = "Program.cs - exampleproject-admin - Visual Studio Code"; Handle = [System.IntPtr]5 }
				)
			} -ParameterFilter { $ProcessName -eq "Code" }

			Close-Project -Project "ExampleProject"

			$script:closedHandles.Count | Should -Be 2
			$script:closedHandles | Should -Contain ([System.IntPtr]1)
			$script:closedHandles | Should -Contain ([System.IntPtr]2)
		}
	}

	Context "swagger close patterns" {
		BeforeEach {
			Mock Get-WindowHandle { @() }
			$script:patternCalls = @()
			Mock Close-BrowserTabsByPattern {
				param($ProcessName, $TitlePatterns)
				$script:patternCalls += , @($TitlePatterns)
				0
			}
		}

		It "includes the swagger patterns when the project has a localhost swagger entry" {
			$global:Configuration.BrowserGroups = @(
				@{
					Swagger = @(
						@{ Name = 'ExampleProject'; Url = 'http://localhost:5000/swagger/index.html' }
					)
				}
			)

			Close-Project -Project "ExampleProject"

			$script:patternCalls.Count | Should -Be 1
			$script:patternCalls[0] | Should -Contain "(?i)ExampleProject"
			$script:patternCalls[0] | Should -Contain "(?i)swagger ui"
			$script:patternCalls[0] | Should -Contain "(?i)problem loading page"
		}

		It "passes only the project-name pattern when the project has no swagger entry" {
			Close-Project -Project "ExampleProject"

			$script:patternCalls.Count | Should -Be 1
			$script:patternCalls[0] | Should -Be @("(?i)ExampleProject")
		}
	}

	Context "Handing control back" {
		It "returns focus to this shell's own terminal window" {
			Mock Resolve-HostingTerminalTab { [PSCustomObject]@{ Handle = [IntPtr]4242; ProcessId = 1; TabTitle = "PowerShell" } }

			Close-Project -Project "ExampleProject"

			Should -Invoke Focus-TerminalTab -Times 1 -Exactly -ParameterFilter { $WindowHandle -eq [IntPtr]4242 }
		}

		It "releases any modifier left held by synthesized keystrokes" {
			Close-Project -Project "ExampleProject"

			Should -Invoke Reset-KeyboardModifiers -Times 1 -Exactly
		}
	}
}
