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

	It "returns null for an unknown project, path key or repository without leaving the caller's loop" {
		# A bare break here used to end the caller's nearest loop, dropping every project or
		# repository after the bad one.
		Mock Write-LogError { }

		$visited = foreach ($name in @("Missing", "SampleProject")) {
			$result = Resolve-ProjectPath -ProjectName $name -PathKey "LocalPath"
			[PSCustomObject]@{ Name = $name; Result = $result }
		}

		@($visited).Count | Should -Be 2
		$visited[0].Result | Should -BeNullOrEmpty
		$visited[1].Result | Should -Match "SampleProject$"

		$unknownKey = foreach ($i in 1..2) { Resolve-ProjectPath -ProjectName "SampleProject" -PathKey "Nope"; "after-$i" }
		@($unknownKey) | Should -Be @("after-1", "after-2")

		$unknownRepo = foreach ($i in 1..2) { Resolve-ProjectPath -ProjectName "Missing" -ForRepository; "after-$i" }
		@($unknownRepo) | Should -Be @("after-1", "after-2")
		Should -Invoke Write-LogError -Times 5
	}

	It "returns repository url and local path when ForRepository is used" {
		$result = Resolve-ProjectPath -ProjectName "WinuX" -ForRepository

		$result.RepositoryUrl | Should -Be "https://github.com/ExampleUser/WinuX"
		$result.LocalPath | Should -Match "WinuX$"
	}
}
