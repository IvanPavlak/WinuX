#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Get-EfCoreDbContexts.ps1"
}

Describe "Get-EfCoreDbContexts" {
	It "returns empty array when working directory is invalid" {
		$result = Get-EfCoreDbContexts -ProjectPath "a" -StartupProjectPath "b" -WorkingDirectory "C:\\invalid-working-dir"

		$result.Count | Should -Be 0
	}
}
