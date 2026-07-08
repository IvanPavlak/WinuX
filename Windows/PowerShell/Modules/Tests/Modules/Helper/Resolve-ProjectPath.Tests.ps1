#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Resolve-ProjectPath.ps1"
}

Describe "Resolve-ProjectPath" {
	BeforeEach {
		Mock Write-Host { }

		$script:MachineSpecificPaths = [PSCustomObject]@{
			Projects     = [PSCustomObject]@{
				SampleProject = [PSCustomObject]@{
					LocalPath  = "C:\\Dev\\SampleProject"
					RemotePath = "\\\\server\\SampleProject"
				}
			}
			Repositories = [PSCustomObject]@{
				WinuX = [PSCustomObject]@{
					Local = "C:\\Dev\\WinuX"
				}
			}
		}

		$script:Configuration = [PSCustomObject]@{
			ProjectTerminals = @(
				[PSCustomObject]@{
					Name     = "SampleProject"
					BasePath = "Projects.SampleProject"
					Paths    = @("LocalPath", "RemotePath")
				}
			)
			RepositoryGroups = @(
				@{ Private = @(
						@{ Name = "WinuX"; LocalPath = "Repositories.WinuX.Local"; UrlPath = "Universal.GitHub.Repositories.WinuX" }
					)
				}
			)
			Universal        = [PSCustomObject]@{
				GitHub = [PSCustomObject]@{
					Base         = "https://github.com"
					Repositories = [PSCustomObject]@{
						WinuX = "/ExampleUser/WinuX"
					}
				}
			}
		}
	}

	It "returns specific project path when PathKey is provided" {
		$result = Resolve-ProjectPath -ProjectName "SampleProject" -PathKey "LocalPath"

		$result | Should -Match "SampleProject$"
	}

	It "returns repository url and local path when ForRepository is used" {
		$result = Resolve-ProjectPath -ProjectName "WinuX" -ForRepository

		$result.RepositoryUrl | Should -Be "https://github.com/ExampleUser/WinuX"
		$result.LocalPath | Should -Match "WinuX$"
	}
}
