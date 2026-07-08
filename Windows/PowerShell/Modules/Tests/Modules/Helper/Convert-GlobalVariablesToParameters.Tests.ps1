#Requires -Modules Pester

BeforeAll {
	$HelperFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Helper\Functions"
	. "$HelperFunctionsPath\Convert-GlobalVariablesToParameters.ps1"
}

Describe "Convert-GlobalVariablesToParameters" {
	Context "Global Variable Replacement" {
		It "Should replace global variable references with parameter references" {
			$definition = @'
function Test-Func {
    param()
    $value = $global:TestVar
}
'@
			$result = Convert-GlobalVariablesToParameters -FunctionDefinition $definition

			$result | Should -Not -Match '\$global:TestVar'
			$result | Should -Match '\$TestVar'
		}

		It "Should return unchanged definition when no global variables exist" {
			$definition = @'
function Test-Func {
    param()
    $value = "hello"
}
'@
			$result = Convert-GlobalVariablesToParameters -FunctionDefinition $definition

			$result | Should -Be $definition
		}
	}

	Context "Dotted Path Global Variables" {
		It "Should convert dotted global variable paths to parameter names" {
			$definition = @'
function Test-Func {
    param()
    $value = $global:Config.Setting
}
'@
			$result = Convert-GlobalVariablesToParameters -FunctionDefinition $definition

			$result | Should -Not -Match '\$global:Config\.Setting'
		}
	}

	Context "Parameter Block Handling" {
		It "Should add parameters to existing param block" {
			$definition = @'
function Test-Func {
    param(
        [string]$ExistingParam
    )
    $value = $global:TestVar
}
'@
			$result = Convert-GlobalVariablesToParameters -FunctionDefinition $definition

			$result | Should -Match '\$ExistingParam'
			$result | Should -Match '\$TestVar'
		}

		It "Should handle multiple global variables" {
			$definition = @'
function Test-Func {
    param()
    $a = $global:VarA
    $b = $global:VarB
}
'@
			$result = Convert-GlobalVariablesToParameters -FunctionDefinition $definition

			$result | Should -Not -Match '\$global:VarA'
			$result | Should -Not -Match '\$global:VarB'
			$result | Should -Match '\$VarA'
			$result | Should -Match '\$VarB'
		}
	}

	Context "Filtered Variables" {
		It "Should only convert specified global variables when GlobalVariables parameter is provided" {
			$definition = @'
function Test-Func {
    param()
    $a = $global:ConvertMe
    $b = $global:KeepMe
}
'@
			$result = Convert-GlobalVariablesToParameters -FunctionDefinition $definition -GlobalVariables @("ConvertMe")

			$result | Should -Not -Match '\$global:ConvertMe'
			$result | Should -Match '\$global:KeepMe'
		}
	}
}
