#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Test-WindowTitleCandidates.ps1"
}

Describe "Test-WindowTitleCandidates" {
	It "returns true when title contains any candidate" {
		$result = Test-WindowTitleCandidates -WindowTitle "Visual Studio Code - WinuX" -Candidates @("Browser", "winux")

		$result | Should -BeTrue
	}

	It "returns false when none of the candidates match" {
		$result = Test-WindowTitleCandidates -WindowTitle "Windows Terminal" -Candidates @("Firefox", "Chrome")

		$result | Should -BeFalse
	}
}
