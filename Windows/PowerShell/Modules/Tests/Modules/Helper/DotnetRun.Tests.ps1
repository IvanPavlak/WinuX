#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\DotnetRun.ps1"
}

Describe "DotnetRun" {
	BeforeEach {
		function global:dotnet {
			param([string]$Command)
			$script:DotnetCommand = $Command
		}
		$script:DotnetCommand = $null
	}

	AfterEach {
		Remove-Item Function:\dotnet -ErrorAction SilentlyContinue
	}

	It "invokes dotnet run" {
		DotnetRun

		$script:DotnetCommand | Should -Be "run"
	}
}
