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

		$global:Configuration = [PSCustomObject]@{
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

	It "resolves -RepositoryEntry instead of the first entry of that name" {
		$entry = @{ Name = "WinuX"; LocalPath = "Projects.SampleProject.LocalPath"; UrlPath = "Universal.GitHub.Repositories.WinuX" }

		$result = Resolve-ProjectPath -ProjectName "WinuX" -ForRepository -RepositoryEntry $entry

		$result.LocalPath | Should -Match "SampleProject$"
	}

	It "returns an empty LocalPath, with no error, for a repository this machine has no path for" {
		Mock Write-LogError { }
		$entry = @{ Name = "WinuX"; LocalPath = "Nowhere.At.All"; UrlPath = "Universal.GitHub.Repositories.WinuX" }

		$result = Resolve-ProjectPath -ProjectName "WinuX" -ForRepository -RepositoryEntry $entry

		$result.RepositoryUrl | Should -Be "https://github.com/ExampleUser/WinuX"
		$result.LocalPath | Should -BeNullOrEmpty
		Should -Invoke Write-LogError -Times 0 -Exactly
	}

	It "reports an unknown repository without ending the caller's loop" {
		Mock Write-LogError { }

		$rounds = 0
		foreach ($round in 1..2) {
			$result = Resolve-ProjectPath -ProjectName "Nope" -ForRepository
			$rounds++
		}

		$rounds | Should -Be 2
		$result | Should -BeNullOrEmpty
		Should -Invoke Write-LogError -Times 2 -Exactly -ParameterFilter { $Message -match "\[Nope\] not found" }
	}
}
