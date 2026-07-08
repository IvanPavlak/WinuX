#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Get-DbContextsFromProject.ps1"
}

Describe "Get-DbContextsFromProject" {
	It "returns empty array when project path is invalid" {
		$result = Get-DbContextsFromProject -ProjectPath "C:\\invalid-project"

		$result.Count | Should -Be 0
	}
}
