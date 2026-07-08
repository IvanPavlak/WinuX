#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Get-WindowTitleCandidates.ps1"
}

Describe "Get-WindowTitleCandidates" {
	It "returns distinct full path, filename, and filename-without-extension candidates" {
		$result = Get-WindowTitleCandidates -Names @("C:\\Dev\\MyApp\\Program.cs", "Program.cs")

		(($result | Where-Object { $_ -match "Program\.cs$" }).Count -ge 1) | Should -BeTrue
		$result | Should -Contain "Program.cs"
		$result | Should -Contain "Program"
		($result | Where-Object { $_ -eq "Program.cs" }).Count | Should -Be 1
	}

	It "skips empty and whitespace names" {
		$result = Get-WindowTitleCandidates -Names @("", "   ")

		$result.Count | Should -Be 0
	}
}
