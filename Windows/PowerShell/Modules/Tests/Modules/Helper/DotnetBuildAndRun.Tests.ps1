#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\DotnetBuildAndRun.ps1"
}

Describe "DotnetBuildAndRun" {
	BeforeEach {
		$script:DotnetCommands = @()
		function global:dotnet {
			param([string]$Command)
			$script:DotnetCommands += $Command
		}
	}

	AfterEach {
		Remove-Item Function:\dotnet -ErrorAction SilentlyContinue
	}

	It "invokes build then run" {
		DotnetBuildAndRun

		$script:DotnetCommands.Count | Should -Be 2
		$script:DotnetCommands[0] | Should -Be "build"
		$script:DotnetCommands[1] | Should -Be "run"
	}
}
