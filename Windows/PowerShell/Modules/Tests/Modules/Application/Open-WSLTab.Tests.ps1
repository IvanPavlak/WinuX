#Requires -Modules Pester

BeforeAll {
	$script:OriginalConfiguration = $global:Configuration
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Open-WSLTab.ps1"
}

AfterAll {
	$global:Configuration = $script:OriginalConfiguration
}

Describe "Open-WSLTab" {
	BeforeEach {
		$global:Configuration = @{ DefaultWSLDistribution = 'Ubuntu-22.04' }
		Mock Write-Host { }
		Mock 'wt.exe' { }
	}

	It "opens a new Windows Terminal tab for the configured WSL distribution" {
		Open-WSLTab

		Should -Invoke 'wt.exe' -Times 1 -Exactly
	}
}
