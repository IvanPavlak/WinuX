#Requires -Modules Pester

BeforeAll {
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Get-VSCodeExecutablePath.ps1"
	. "$AppFunctionsPath\Get-VSCodeCliPath.ps1"
}

Describe "Get-VSCodeExecutablePath" {
	BeforeEach {
		$script:cli = Join-Path $TestDrive "install\bin\code.cmd"
		New-Item -ItemType File -Path $script:cli -Force | Out-Null
		Mock Get-VSCodeCliPath { $script:cli }
	}

	AfterEach {
		Remove-Item -Path (Join-Path $TestDrive "install") -Recurse -Force -ErrorAction SilentlyContinue
	}

	It "resolves Code.exe one folder above the command line's bin folder" {
		$exe = Join-Path $TestDrive "install\Code.exe"
		New-Item -ItemType File -Path $exe -Force | Out-Null

		Get-VSCodeExecutablePath | Should -Be $exe
	}

	It "returns nothing when there is no Code.exe above the command line" {
		Get-VSCodeExecutablePath | Should -BeNullOrEmpty
	}

	It "returns nothing when VS Code is not installed" {
		Mock Get-VSCodeCliPath { $null }

		Get-VSCodeExecutablePath | Should -BeNullOrEmpty
	}
}
