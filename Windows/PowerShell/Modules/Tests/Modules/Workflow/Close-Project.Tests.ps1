#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$HelperFunctionsPath = Join-Path $ModuleRoot "Helper\Functions"
	$WorkflowFunctionsPath = Join-Path $ModuleRoot "Workflow\Functions"

	. "$HelperFunctionsPath\Resolve-ConfigPathValue.ps1"
	. "$HelperFunctionsPath\Get-WindowTitleCandidates.ps1"
	. "$HelperFunctionsPath\Test-WindowTitleCandidates.ps1"
	. "$WorkflowFunctionsPath\Close-Project.ps1"

	function Resolve-Selection { param($InputObject) $InputObject }
	function Close-ProjectTerminals { param($ProjectName) 0 }
	function Close-BrowserTabsByPattern { param($ProcessName, $TitlePatterns) 0 }
	function Focus-TerminalTab { param($TargetTitle) }
}

Describe "Close-Project" {
	BeforeEach {
		Mock Write-Host { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock Write-LogTitle { }
		Mock Write-LogDebug { }
		Mock Focus-TerminalTab { }
		Mock Close-ProjectTerminals { 0 }
		Mock Close-BrowserTabsByPattern { 0 }

		$script:MachineSpecificPaths = @{
			Projects = @{
				ExampleProject = @{
					Solution = "C:\Projects\ExampleProject\ExampleProject.sln"
					Backend  = "C:\Projects\ExampleProject\ExampleProject.Api"
					Ui       = "C:\Projects\ExampleProject\ExampleProject-UI"
				}
			}
		}

		$script:Configuration = @{
			Projects              = @("ExampleProject")
			VisualStudioSolutions = @(
				@{ Name = "ExampleProject"; Solution = "Projects.ExampleProject.Solution" }
			)
			VSCodeProjects        = @(
				@{ Name = "ExampleProject"; Path = "Projects.ExampleProject.Backend" }
				@{ Name = "ExampleProject-UI"; Path = "Projects.ExampleProject.Ui" }
			)
			ProjectActions        = @{
				ExampleProject = @(
					@{ Action = "Open-VisualStudio"; Parameters = @{ Solution = "{ProjectName}" } }
					@{ Action = "Open-VSCode"; Parameters = @{ Folder = "{ProjectName}" } }
					@{ Action = "Open-VSCode"; Parameters = @{ Folder = "ExampleProject-UI" } }
				)
			}
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
}
