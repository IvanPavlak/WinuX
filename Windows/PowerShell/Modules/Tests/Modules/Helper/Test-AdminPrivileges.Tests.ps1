#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Test-AdminPrivileges.ps1"
}

Describe "Test-AdminPrivileges" {
	It "returns a boolean in CheckOnly mode" {
		$result = Test-AdminPrivileges -CheckOnly

		$result | Should -BeOfType ([bool])
	}
}
