#Requires -Modules Pester

BeforeAll {
	$ConfigFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Configuration\Functions"
	. "$ConfigFunctionsPath\ConvertTo-ActionString.ps1"
}

Describe "ConvertTo-ActionString" {
	It "formats action with scalar, array, and boolean parameter types" {
		$action = @{
			Action     = 'Open-Browser'
			Parameters = @{
				Groups  = @('AI', 'Docs')
				Force   = $true
				Profile = 'Default'
			}
		}

		$result = ConvertTo-ActionString -Action $action -Indent "\t\t"

		$result | Should -Match 'Action = "Open-Browser"'
		$result | Should -Match 'Groups = @\("AI", "Docs"\)'
		$result | Should -Match 'Force = \$true'
		$result | Should -Match 'Profile = "Default"'
	}

	It "omits Parameters section when action has no parameters" {
		$action = @{ Action = 'Open-WSLTab' }

		$result = ConvertTo-ActionString -Action $action -Indent "\t"

		$result | Should -Be "\t@{ Action = `"Open-WSLTab`" }"
	}
}
