#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Workflow\Functions"

	. "$FunctionsPath\Open-Project.ps1"
}

Describe "Open-Project" {
	BeforeEach {
		$script:Configuration = @{
			Projects       = @("Demo")
			ProjectActions = @{
				Demo = @(
					@{ Action = "Open-ProjectTerminals-Or-RunProject"; Parameters = @{ Project = "{ProjectName}" } },
					@{ Action = "Open-Browser"; Parameters = @{ Groups = "Docs" } }
				)
			}
		}

		Mock Resolve-Selection { @("Demo") }
		Mock Run-Project { }
		Mock Open-ProjectTerminals { }
		Mock Open-Browser { }
		Mock Write-Host { }
	}

	It "runs project app when RunApp is specified" {
		$result = Open-Project -Project "Demo" -RunApp

		Should -Invoke Run-Project -Times 1 -ParameterFilter { $Project -eq "Demo" }
		Should -Invoke Open-ProjectTerminals -Times 0
		$result | Should -Contain "Demo"
	}

	It "opens project terminals when RunApp is not specified" {
		$result = Open-Project -Project "Demo"

		Should -Invoke Open-ProjectTerminals -Times 1 -ParameterFilter { $Project -eq "Demo" }
		Should -Invoke Run-Project -Times 0
		Should -Invoke Open-Browser -Times 1 -ParameterFilter { $Groups -eq "Docs" }
		$result | Should -Contain "Demo"
	}
}
