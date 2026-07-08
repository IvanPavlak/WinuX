#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Configure-NuGetConfig.ps1"
}

Describe "Configure-NuGetConfig" {
	BeforeEach {
		$global:MachineSpecificPaths = [PSCustomObject]@{
			NuGetConfig = [PSCustomObject]@{
				SourcePath      = "C:\\WinuX\\NuGet\\nuget.config"
				DestinationPath = "C:\\Users\\You\\AppData\\Roaming\\NuGet\\NuGet.config"
			}
		}

		Mock Test-Path {
			if ($Path -eq "C:\\WinuX\\NuGet\\nuget.config") {
				$false
			}
			else {
				$false
			}
		}
		Mock Custom-ReadHost { "ignored" }
		Mock Write-Host { }
	}

	It "returns when source nuget.config is missing" {
		{ Configure-NuGetConfig } | Should -Not -Throw

		Should -Invoke Custom-ReadHost -Times 0
	}
}
