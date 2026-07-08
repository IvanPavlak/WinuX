#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Set-KeyboardLayouts.ps1"
}

Describe "Set-KeyboardLayouts" {
	BeforeEach {
		$script:Configuration = [PSCustomObject]@{
			KeyboardLayoutSets       = @{
				Default = @("US")
			}
			KeyboardLayouts          = @{
				US = "00000409"
			}
			DefaultKeyboardLayoutSet = "Default"
		}
		Mock Resolve-Selection { "Default" }
		Mock Write-Host { }
		Mock Write-LogError { }
	}

	It "returns when explicitly requested layout set does not exist" {
		{ Set-KeyboardLayouts -LayoutSet "MissingSet" } | Should -Not -Throw
		Should -Invoke Resolve-Selection -Times 0
		Should -Invoke Write-LogError -Times 1
	}
}
