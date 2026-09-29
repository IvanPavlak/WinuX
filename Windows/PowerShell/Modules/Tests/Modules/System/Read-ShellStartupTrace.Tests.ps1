#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. (Join-Path $ModuleRoot "System\Functions\Read-ShellStartupTrace.ps1")
}

Describe "Read-ShellStartupTrace" {
	BeforeEach {
		$script:trace = Join-Path $TestDrive "startup.trace"
	}

	It "maps every stage line to its milliseconds" {
		Set-Content -Path $script:trace -Value "Core`t412.3`nGreeting`t610" -NoNewline

		$result = Read-ShellStartupTrace -Path $script:trace

		$result.Count | Should -Be 2
		$result["Core"] | Should -Be 412.3
		$result["Greeting"] | Should -Be 610
	}

	It "returns an empty table for a missing file" {
		$result = Read-ShellStartupTrace -Path (Join-Path $TestDrive "absent.trace")

		$result | Should -BeOfType [hashtable]
		$result.Count | Should -Be 0
	}

	It "drops lines that do not parse and keeps the rest" {
		Set-Content -Path $script:trace -Value "garbage`nCore`tnot-a-number`nSchema`t12.5`n`n" -NoNewline

		$result = Read-ShellStartupTrace -Path $script:trace

		$result.Count | Should -Be 1
		$result["Schema"] | Should -Be 12.5
	}

	It "keeps the last value of a stage that appears twice" {
		Set-Content -Path $script:trace -Value "Core`t400`nCore`t250" -NoNewline

		(Read-ShellStartupTrace -Path $script:trace)["Core"] | Should -Be 250
	}

	It "parses with an invariant decimal point whatever the current culture" {
		$culture = [cultureinfo]::CurrentCulture
		try {
			[cultureinfo]::CurrentCulture = [cultureinfo]::GetCultureInfo("de-DE")
			Set-Content -Path $script:trace -Value "Core`t1.5" -NoNewline

			(Read-ShellStartupTrace -Path $script:trace)["Core"] | Should -Be 1.5
		}
		finally {
			[cultureinfo]::CurrentCulture = $culture
		}
	}
}
