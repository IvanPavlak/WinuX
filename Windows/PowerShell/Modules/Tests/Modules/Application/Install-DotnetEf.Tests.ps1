#Requires -Modules Pester

BeforeAll {
	$script:OriginalConfiguration = $global:Configuration
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Install-DotnetEf.ps1"
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
