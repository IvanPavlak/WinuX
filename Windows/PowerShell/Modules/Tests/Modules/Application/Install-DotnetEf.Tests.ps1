#Requires -Modules Pester

BeforeAll {
	$script:OriginalConfiguration = $global:Configuration
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Install-DotnetEf.ps1"

	# Mock requires the command to exist; machines without the .NET SDK have no dotnet.
	# The stub gives Pester a resolvable target - every test then mocks over it.
	if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
		function script:dotnet { }
	}
}

AfterAll {
	$global:Configuration = $script:OriginalConfiguration
}

Describe "Install-DotnetEf" {
	BeforeEach {
		$global:Configuration = @{ DotnetEFVersion = '9.0.0' }
		Mock Write-Host { }
		Mock dotnet { }
	}

	It "skips installation when dotnet command is unavailable" {
		Mock Get-Command { $null }

		Install-DotnetEf

		Should -Invoke dotnet -Times 0
	}

	It "runs dotnet tool update when Update switch is provided" {
		Mock Get-Command {
			param($Name)
			if ($Name -eq 'dotnet') { return @{ Name = 'dotnet' } }
			return $null
		}

		Install-DotnetEf -Update

		Should -Invoke dotnet -Times 1 -Exactly
	}
}
