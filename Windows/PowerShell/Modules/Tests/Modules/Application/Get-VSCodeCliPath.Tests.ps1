#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$FunctionsPath\Get-VSCodeCliPath.ps1"
}

Describe "Get-VSCodeCliPath" {
	BeforeEach {
		$script:SavedLocalAppData = $env:LOCALAPPDATA
		$script:SavedProgramFiles = $env:ProgramFiles
		$env:LOCALAPPDATA = Join-Path $TestDrive "local"
		$env:ProgramFiles = Join-Path $TestDrive "programs"
	}

	AfterEach {
		$env:LOCALAPPDATA = $script:SavedLocalAppData
		$env:ProgramFiles = $script:SavedProgramFiles
		Remove-Item -Path (Join-Path $TestDrive "local"), (Join-Path $TestDrive "programs") -Recurse -Force -ErrorAction SilentlyContinue
	}

	It "prefers code on PATH" {
		Mock Get-Command { [pscustomobject]@{ Source = "C:\Tools\code.cmd" } } -ParameterFilter { $Name -eq "code" }

		Get-VSCodeCliPath | Should -Be "C:\Tools\code.cmd"
	}

	It "falls back to the per-user install when code is not on PATH" {
		Mock Get-Command { $null } -ParameterFilter { $Name -eq "code" }
		$cli = Join-Path $env:LOCALAPPDATA "Programs\Microsoft VS Code\bin\code.cmd"
		New-Item -ItemType File -Path $cli -Force | Out-Null

		Get-VSCodeCliPath | Should -Be $cli
	}

	It "falls back to the machine-wide install when there is no per-user install" {
		Mock Get-Command { $null } -ParameterFilter { $Name -eq "code" }
		$cli = Join-Path $env:ProgramFiles "Microsoft VS Code\bin\code.cmd"
		New-Item -ItemType File -Path $cli -Force | Out-Null

		Get-VSCodeCliPath | Should -Be $cli
	}

	It "returns nothing when VS Code is not installed" {
		Mock Get-Command { $null } -ParameterFilter { $Name -eq "code" }

		Get-VSCodeCliPath | Should -BeNullOrEmpty
	}
}
