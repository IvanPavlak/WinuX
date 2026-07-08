#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Resolve-ConfigPathValue.ps1"
}

Describe "Resolve-ConfigPathValue" {
	BeforeEach {
		$script:MachineSpecificPaths = [PSCustomObject]@{
			Projects = [PSCustomObject]@{
				Self = [PSCustomObject]@{
					Root = "C:\\Users\\You\\Development\\GitHub\\WinuX"
				}
			}
		}
	}

	It "returns resolved value for valid dot notation path" {
		$result = Resolve-ConfigPathValue -PathExpression "Projects.Self.Root"

		$result | Should -Match "WinuX$"
	}

	It "returns null for missing path segment" {
		$result = Resolve-ConfigPathValue -PathExpression "Projects.Self.Missing"

		$result | Should -Be $null
	}
}
