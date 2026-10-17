#Requires -Modules Pester

BeforeAll {
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Get-VSCodeExecutablePath.ps1"
	. "$AppFunctionsPath\Get-VSCodeCliPath.ps1"
}

Describe "Get-VSCodeExecutablePath" {
	BeforeEach {
		$script:SavedLocalAppData = $env:LOCALAPPDATA
		$script:SavedProgramFiles = $env:ProgramFiles
		$env:LOCALAPPDATA = Join-Path $TestDrive "local"
		$env:ProgramFiles = Join-Path $TestDrive "programs"
		Mock Get-VSCodeCliPath { $null }
	}

	AfterEach {
		$env:LOCALAPPDATA = $script:SavedLocalAppData
		$env:ProgramFiles = $script:SavedProgramFiles
		Remove-Item -Path (Join-Path $TestDrive "local"), (Join-Path $TestDrive "programs"), (Join-Path $TestDrive "install") -Recurse -Force -ErrorAction SilentlyContinue
	}

	It "resolves Code.exe one folder above the command line's bin folder" {
		$cli = Join-Path $TestDrive "install\bin\code.cmd"
		$exe = Join-Path $TestDrive "install\Code.exe"
		New-Item -ItemType File -Path $cli -Force | Out-Null
		New-Item -ItemType File -Path $exe -Force | Out-Null
		Mock Get-VSCodeCliPath { $cli }

		Get-VSCodeExecutablePath | Should -Be $exe
	}

	It "falls back to the per-user install when the command line gives no executable" {
		$cli = Join-Path $TestDrive "install\bin\code.cmd"
		New-Item -ItemType File -Path $cli -Force | Out-Null
		Mock Get-VSCodeCliPath { $cli }
		$exe = Join-Path $env:LOCALAPPDATA "Programs\Microsoft VS Code\Code.exe"
		New-Item -ItemType File -Path $exe -Force | Out-Null

		Get-VSCodeExecutablePath | Should -Be $exe
	}

	It "falls back to the machine-wide install when there is no per-user install" {
		$exe = Join-Path $env:ProgramFiles "Microsoft VS Code\Code.exe"
		New-Item -ItemType File -Path $exe -Force | Out-Null

		Get-VSCodeExecutablePath | Should -Be $exe
	}

	It "returns nothing when VS Code is not installed" {
		Get-VSCodeExecutablePath | Should -BeNullOrEmpty
	}
}
