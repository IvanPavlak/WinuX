#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. (Join-Path $ModuleRoot "Helper\Functions\Restore-ShellPrompt.ps1")
}

Describe "Restore-ShellPrompt" {
	# The test worker is never inside PSReadLine's ReadLine, so the redraw itself cannot be
	# observed here; what the callers rely on is that the call can never break them.
	It "never throws" {
		{ Restore-ShellPrompt } | Should -Not -Throw
	}

	It "answers with a boolean" {
		Restore-ShellPrompt | Should -BeOfType [bool]
	}

	It "returns `$false when PSReadLine is not loaded" -Skip:($null -ne ('Microsoft.PowerShell.PSConsoleReadLine' -as [type])) {
		Restore-ShellPrompt | Should -BeFalse
	}
}
