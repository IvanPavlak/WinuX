#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Test-WindowTitleCandidates.ps1"
}

Describe "Test-WindowTitleCandidates" {
	It "returns true when any candidate is a whole title segment" {
		$result = Test-WindowTitleCandidates -WindowTitle "Visual Studio Code - WinuX" -Candidates @("Browser", "winux")

		$result | Should -BeTrue
	}

	It "returns false when none of the candidates match" {
		$result = Test-WindowTitleCandidates -WindowTitle "Windows Terminal" -Candidates @("Firefox", "Chrome")

		$result | Should -BeFalse
	}

	Context "Whole segment matching" {
		It "returns false when a candidate is only a substring of another folder segment" {
			$result = Test-WindowTitleCandidates -WindowTitle "Program.cs - myapp-ui - Visual Studio Code" -Candidates @("MyApp")

			$result | Should -BeFalse
		}

		It "returns false when a candidate only appears inside the application name" {
			$result = Test-WindowTitleCandidates -WindowTitle "MyProject - Visual Studio Code" -Candidates @("Studio")

			$result | Should -BeFalse
		}

		It "returns true for the folder segment behind the active editor" {
			$result = Test-WindowTitleCandidates -WindowTitle "Program.cs - MyApp - Visual Studio Code" -Candidates @("MyApp")

			$result | Should -BeTrue
		}

		It "returns true for a first segment behind the dirty marker" {
			$result = Test-WindowTitleCandidates -WindowTitle "$([char]0x25CF) MyApp - Visual Studio Code" -Candidates @("MyApp")

			$result | Should -BeTrue
		}

		It "matches candidates literally rather than as regex" {
			$result = Test-WindowTitleCandidates -WindowTitle "MyXProjectXName - Visual Studio Code" -Candidates @("My.Project.Name")

			$result | Should -BeFalse
		}

		It "skips blank candidates instead of matching the separator" {
			$result = Test-WindowTitleCandidates -WindowTitle "Program.cs - MyApp - Visual Studio Code" -Candidates @("", "   ")

			$result | Should -BeFalse
		}
	}

	Context "Visual Studio debugger state" {
		It "accepts a debugger state after the candidate for devenv" {
			$result = Test-WindowTitleCandidates -WindowTitle "MySolution (Debugging) - Microsoft Visual Studio" -Candidates @("MySolution") -ProcessName "devenv"

			$result | Should -BeTrue
		}

		It "requires the bare segment for any other process" {
			$result = Test-WindowTitleCandidates -WindowTitle "Program.cs - MyApp (Workspace) - Visual Studio Code" -Candidates @("MyApp") -ProcessName "Code"

			$result | Should -BeFalse
		}

		It "returns false for devenv when the candidate is only a prefix of another solution" {
			$result = Test-WindowTitleCandidates -WindowTitle "MySolution.Tests (Debugging) - Microsoft Visual Studio" -Candidates @("MySolution") -ProcessName "devenv"

			$result | Should -BeFalse
		}
	}
}
