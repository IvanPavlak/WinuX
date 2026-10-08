#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$FunctionsPath\Get-VSCodeInstalledExtensions.ps1"
}

Describe "Get-VSCodeInstalledExtensions" {
	BeforeEach {
		Mock Write-LogDebug { }

		# A stand-in CLI: records its arguments, prints the listing the test set, exits as told.
		$script:Log = Join-Path $TestDrive "calls.log"
		if (Test-Path -Path $script:Log) { Remove-Item -Path $script:Log -Force }
		$env:WINUX_TEST_CODE_LIST = "MyPublisher.One@1.0.0;other.two@2.1.0"
		$env:WINUX_TEST_CODE_EXIT = "0"
		$script:Stub = Join-Path $TestDrive "code-stub.ps1"
		Set-Content -Path $script:Stub -Value @(
			"Add-Content -Path '$script:Log' -Value (`$args -join ' ')",
			"`$env:WINUX_TEST_CODE_LIST -split ';' | Where-Object { `$_ }",
			"exit [int]`$env:WINUX_TEST_CODE_EXIT"
		)
	}

	AfterEach {
		Remove-Item -Path Env:\WINUX_TEST_CODE_LIST, Env:\WINUX_TEST_CODE_EXIT -ErrorAction SilentlyContinue
	}

	It "returns every installed extension with its version" {
		$installed = Get-VSCodeInstalledExtensions -Command $script:Stub -ProfileName "Default"

		@($installed.Keys) -join "," | Should -Be "MyPublisher.One,other.two"
		$installed["other.two"] | Should -Be "2.1.0"
	}

	It "matches ids case-insensitively" {
		$installed = Get-VSCodeInstalledExtensions -Command $script:Stub -ProfileName "Default"

		$installed.Contains("mypublisher.one") | Should -BeTrue
	}

	It "addresses the Default profile without --profile" {
		Get-VSCodeInstalledExtensions -Command $script:Stub -ProfileName "Default" | Out-Null

		Get-Content -Path $script:Log | Should -Be "--list-extensions --show-versions"
	}

	It "addresses any other profile with --profile" {
		Get-VSCodeInstalledExtensions -Command $script:Stub -ProfileName "Writing" | Out-Null

		Get-Content -Path $script:Log | Should -Be "--list-extensions --show-versions --profile Writing"
	}

	It "returns an empty list when nothing is installed" {
		$env:WINUX_TEST_CODE_LIST = ""

		$installed = Get-VSCodeInstalledExtensions -Command $script:Stub -ProfileName "Default"

		$null -eq $installed | Should -BeFalse
		$installed.Count | Should -Be 0
	}

	It "returns nothing when the command line fails" {
		$env:WINUX_TEST_CODE_EXIT = "1"

		Get-VSCodeInstalledExtensions -Command $script:Stub -ProfileName "Missing" | Should -BeNullOrEmpty
	}
}
