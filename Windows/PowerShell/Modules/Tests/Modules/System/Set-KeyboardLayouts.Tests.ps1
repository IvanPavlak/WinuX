#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$ModuleRoot\Helper\Functions\Get-OrderedNames.ps1"
	. "$ModuleRoot\Helper\Functions\Get-OrderedEntry.ps1"

	. "$FunctionsPath\Set-KeyboardLayouts.ps1"
}

Describe "Set-KeyboardLayouts" {
	BeforeEach {
		$global:Configuration = [PSCustomObject]@{
			KeyboardLayoutSets       = @(
				@{ Default = @("US") }
			)
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
