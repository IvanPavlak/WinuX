#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules

	. "$ModuleRoot\Git\Functions\Set-GitConsoleColor.ps1"

	$script:Names = @("GIT_CONFIG_COUNT", "GIT_CONFIG_KEY_0", "GIT_CONFIG_VALUE_0")
}

Describe "Set-GitConsoleColor" {
	BeforeEach {
		# Put back exactly the git environment this test found.
		$script:Saved = @{}
		foreach ($name in $script:Names) { $script:Saved[$name] = [Environment]::GetEnvironmentVariable($name) }
		foreach ($name in $script:Names) { [Environment]::SetEnvironmentVariable($name, $null) }
	}

	AfterEach {
		foreach ($name in $script:Names) { [Environment]::SetEnvironmentVariable($name, $script:Saved[$name]) }
	}

	It "forces color.ui=always through git's environment configuration, unless the output is redirected" {
		$result = Set-GitConsoleColor

		if ([Console]::IsOutputRedirected) {
			# A log file or a pipe would get escape codes: nothing is set.
			$result | Should -BeFalse
			$env:GIT_CONFIG_COUNT | Should -BeNullOrEmpty
		}
		else {
			$result | Should -BeTrue
			$env:GIT_CONFIG_COUNT | Should -Be "1"
			$env:GIT_CONFIG_KEY_0 | Should -Be "color.ui"
			$env:GIT_CONFIG_VALUE_0 | Should -Be "always"
		}
	}

	It "changes nothing when git's environment configuration is already in use" {
		$env:GIT_CONFIG_COUNT = "1"
		$env:GIT_CONFIG_KEY_0 = "core.pager"
		$env:GIT_CONFIG_VALUE_0 = "less"

		Set-GitConsoleColor | Should -BeFalse

		$env:GIT_CONFIG_KEY_0 | Should -Be "core.pager"
		$env:GIT_CONFIG_VALUE_0 | Should -Be "less"
	}

	It "removes the three variables with -Off" {
		$env:GIT_CONFIG_COUNT = "1"
		$env:GIT_CONFIG_KEY_0 = "color.ui"
		$env:GIT_CONFIG_VALUE_0 = "always"

		Set-GitConsoleColor -Off

		$env:GIT_CONFIG_COUNT | Should -BeNullOrEmpty
		$env:GIT_CONFIG_KEY_0 | Should -BeNullOrEmpty
		$env:GIT_CONFIG_VALUE_0 | Should -BeNullOrEmpty
	}

	It "accepts -Off when nothing is set" {
		{ Set-GitConsoleColor -Off } | Should -Not -Throw
	}
}
