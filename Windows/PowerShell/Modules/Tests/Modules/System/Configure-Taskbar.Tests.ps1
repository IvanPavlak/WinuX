#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Configure-Taskbar.ps1"
}

Describe "Configure-Taskbar" {
	BeforeEach {
		$script:Configuration = [PSCustomObject]@{
			Universal            = [PSCustomObject]@{ TaskbarPinFolder = "C:\\Temp\\TaskbarPins" }
			TaskbarConfiguration = $null
			PathTemplates        = [PSCustomObject]@{ SymbolicLinks = [PSCustomObject]@{ TaskbarConfiguration = [PSCustomObject]@{ Path = "C:\\Temp\\taskbar_layout.xml" } } }
		}
		$global:MachineSpecificPaths = [PSCustomObject]@{
			TaskbarConfigurationDir = "C:\\Temp"
		}

		Mock Test-AdminPrivileges { }
		Mock Unpin-TaskbarApps { }
		Mock Test-Path { $false }
		Mock Loading-Spinner { }
		Mock Write-Host { }
		Mock Write-LogTitle { }
		Mock Write-LogStep { }
		Mock Write-LogError { }
	}

	It "returns when TaskbarConfiguration is missing" {
		{ Configure-Taskbar } | Should -Not -Throw

		Should -Invoke Unpin-TaskbarApps -Times 1
		Should -Invoke Write-LogTitle -Times 1
		Should -Invoke Write-LogStep -Times 1
		Should -Invoke Write-LogError -Times 1
	}
}
