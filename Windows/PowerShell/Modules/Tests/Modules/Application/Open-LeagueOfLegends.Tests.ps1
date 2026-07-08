#Requires -Modules Pester

BeforeAll {
	$script:OriginalConfiguration = $global:Configuration
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Open-LeagueOfLegends.ps1"
}

AfterAll {
	$global:Configuration = $script:OriginalConfiguration
}

Describe "Open-LeagueOfLegends" {
	BeforeEach {
		$global:Configuration = @{ Universal = @{ LeagueOfLegendsExe = 'C:\\Games\\Riot\\LeagueClient.exe' } }
		Mock Start-Application { }
	}

	It "delegates to Start-Application with direct executable path and skip path validation" {
		Open-LeagueOfLegends

		Should -Invoke Start-Application -Times 1 -Exactly
		Should -Invoke Start-Application -Times 1 -Exactly -ParameterFilter {
			$AppName -eq 'League of Legends' -and
			$ProcessName -eq 'LeagueClient' -and
			$StartMethod -eq 'DirectPath'
		}
	}
}
