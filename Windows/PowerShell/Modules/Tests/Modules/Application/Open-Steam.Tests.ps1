#Requires -Modules Pester

BeforeAll {
	$script:OriginalConfiguration = $global:Configuration
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Open-Steam.ps1"
}

AfterAll {
	$global:Configuration = $script:OriginalConfiguration
}

Describe "Open-Steam" {
	BeforeEach {
		$global:Configuration = @{ Universal = @{ SteamExe = 'C:\\Tools\\Steam\\steam.exe' } }
		Mock Start-Application { }
	}

	It "delegates to Start-Application with direct executable path and skip path validation" {
		Open-Steam

		Should -Invoke Start-Application -Times 1 -Exactly
		Should -Invoke Start-Application -Times 1 -Exactly -ParameterFilter {
			$AppName -eq 'Steam' -and
			$ProcessName -eq 'steamwebhelper' -and
			$StartMethod -eq 'DirectPath'
		}
	}
}
