#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "AI\Functions"
	. "$FunctionsPath\Test-AiModsCli.ps1"
}

Describe "Test-AiModsCli" {
	BeforeEach {
		Mock Write-LogDebug { }

		# A stand-in CLI: records every call and rejects any path containing "bad".
		$script:Log = Join-Path $TestDrive "calls.log"
		if (Test-Path -Path $script:Log) { Remove-Item -Path $script:Log -Force }
		$script:Stub = Join-Path $TestDrive "claude-stub.ps1"
		Set-Content -Path $script:Stub -Value @(
			"Add-Content -Path '$script:Log' -Value (`$args -join ' ')",
			"if (`$args[2] -like '*bad*') { exit 1 }",
			"exit 0"
		)
	}

	It "reports the CLI as missing and checks nothing when the command does not resolve" {
		$result = Test-AiModsCli -ModPath @("C:\mods\alpha") -Command "winux-no-such-command-$([guid]::NewGuid())"

		$result.Installed | Should -BeFalse
		$result.Invalid | Should -BeNullOrEmpty
	}

	It "returns no invalid mods when every validation passes" {
		$result = Test-AiModsCli -ModPath @("C:\mods\alpha", "C:\mods\bravo") -Command $script:Stub

		$result.Installed | Should -BeTrue
		$result.Invalid | Should -BeNullOrEmpty
	}

	It "returns the paths whose validation failed" {
		$result = Test-AiModsCli -ModPath @("C:\mods\alpha", "C:\mods\bad-mod") -Command $script:Stub

		@($result.Invalid) | Should -Be @("C:\mods\bad-mod")
	}

	It "calls plugin validate once per mod" {
		Test-AiModsCli -ModPath @("C:\mods\alpha", "C:\mods\bravo") -Command $script:Stub | Out-Null

		@(Get-Content -Path $script:Log) | Should -Be @("plugin validate C:\mods\alpha", "plugin validate C:\mods\bravo")
	}

	It "skips empty paths" {
		Test-AiModsCli -ModPath @("", "C:\mods\alpha") -Command $script:Stub | Out-Null

		@(Get-Content -Path $script:Log) | Should -Be @("plugin validate C:\mods\alpha")
	}
}
