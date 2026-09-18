#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. (Join-Path $ModuleRoot "Helper\Functions\Get-ShellProcessName.ps1")
}

Describe "Get-ShellProcessName" {
	It "names the shell, the packaged-app frame host and the notification host" {
		$names = @(Get-ShellProcessName)

		$names | Should -Contain 'explorer'
		$names | Should -Contain 'ApplicationFrameHost'
		$names | Should -Contain 'ShellExperienceHost'
	}

	It "returns bare process names with no extension or path" {
		@(Get-ShellProcessName) | ForEach-Object { $_ | Should -Not -Match '[\\/.]' }
	}

	It "is usable as a case-insensitive set" {
		$set = [System.Collections.Generic.HashSet[string]]::new([string[]](Get-ShellProcessName), [System.StringComparer]::OrdinalIgnoreCase)

		$set.Contains('shellexperiencehost') | Should -BeTrue
		$set.Contains('firefox') | Should -BeFalse
	}
}
