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

	Context "machine scopes" {
		It "writes Machine and LayoutMachine after Parameters, in that order" {
			$action = @{
				Action        = 'Open-Browser'
				Parameters    = @{ Groups = @('Google') }
				Machine       = 'PC/Work'
				LayoutMachine = 'Work'
			}

			$result = ConvertTo-ActionString -Action $action -Indent "`t"

			$result | Should -Be "`t@{ Action = `"Open-Browser`"; Parameters = @{ Groups = @(`"Google`") }; Machine = `"PC/Work`"; LayoutMachine = `"Work`" }"
		}

		It "writes a scope on an action without parameters and joins an array scope with slashes" {
			$result = ConvertTo-ActionString -Action @{ Action = 'Open-Outlook'; Machine = @('PC', 'Work') } -Indent "`t"

			$result | Should -Be "`t@{ Action = `"Open-Outlook`"; Machine = `"PC/Work`" }"
		}

		It "omits blank scopes" {
			$result = ConvertTo-ActionString -Action @{ Action = 'Open-Outlook'; Machine = ''; LayoutMachine = '   ' } -Indent "`t"

			$result | Should -Be "`t@{ Action = `"Open-Outlook`" }"
		}
	}

	Context "per-machine parameter tables" {
		It "writes the tables after Parameters and before the scopes, with nested hashtables" {
			$action = @{
				Action                  = 'Open-Browser'
				Parameters              = @{ Groups = @('Google') }
				LayoutMachineParameters = @{ PC = @{ Instances = 2 } }
				Machine                 = 'PC/Work'
			}

			$result = ConvertTo-ActionString -Action $action -Indent "`t"

			$result | Should -Be "`t@{ Action = `"Open-Browser`"; Parameters = @{ Groups = @(`"Google`") }; LayoutMachineParameters = @{ PC = @{ Instances = `"2`" } }; Machine = `"PC/Work`" }"
		}

		It "quotes a scope-string row key, writes null values as `$null and sorts keys" {
			$action = @{
				Action            = 'Open-Project'
				Parameters        = @{ RunApp = $true; Project = 'Client' }
				MachineParameters = @{ 'Laptop/Work' = @{ RunApp = $null; Project = 'ClientLite' } }
			}

			$result = ConvertTo-ActionString -Action $action -Indent "`t"

			$result | Should -Be "`t@{ Action = `"Open-Project`"; Parameters = @{ Project = `"Client`"; RunApp = `$true }; MachineParameters = @{ `"Laptop/Work`" = @{ Project = `"ClientLite`"; RunApp = `$null } } }"
		}

		It "writes MachineParameters before LayoutMachineParameters and omits empty or non-hashtable tables" {
			$action = @{
				Action                  = 'A'
				MachineParameters       = @{ Work = @{ X = 1 } }
				LayoutMachineParameters = @{}
			}

			$result = ConvertTo-ActionString -Action $action -Indent "`t"

			$result | Should -Be "`t@{ Action = `"A`"; MachineParameters = @{ Work = @{ X = `"1`" } } }"
			ConvertTo-ActionString -Action @{ Action = 'B'; LayoutMachineParameters = 'PC' } -Indent "`t" | Should -Be "`t@{ Action = `"B`" }"
		}
	}
}
