#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\List-Functions.ps1"
}

Describe "List-Functions" {
	BeforeEach {
		$script:MachineSpecificPaths = [PSCustomObject]@{
			Projects = [PSCustomObject]@{
				Self    = [PSCustomObject]@{
					Root = "C:\\MissingRoot"
				}
				Modules = "C:\\MissingModules"
			}
		}

		Mock Test-Path { $false }
		Mock Write-Error { }
	}

	It "reports an error and returns when the documentation cannot be found" {
		{ List-Functions } | Should -Not -Throw
		Should -Invoke Write-Error -Times 1
	}
}
