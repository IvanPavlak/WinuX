#Requires -Modules Pester

BeforeAll {
	$ConfigurationFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Configuration\Functions"
	. "$ConfigurationFunctionsPath\Find-ConfigurationSection.ps1"
	. "$ConfigurationFunctionsPath\ConvertTo-ActionString.ps1"
	. "$ConfigurationFunctionsPath\Add-BrowserGroup.ps1"
}

Describe "Add-BrowserGroup" {
	BeforeEach {
		$testConfig = Join-Path $TestDrive "Configuration.psd1"
		$configContent = @(
			'@{'
			'	BrowserGroups = @('
			'		@{ Google = @('
			'			"https://www.google.com/"'
			'		)}'
			'	)'
			'}'
		)
		Set-Content -Path $testConfig -Value $configContent
	}

	Context "Named URLs" {
		It "Should add a browser group with named URLs" {
			Add-BrowserGroup -GroupName "DevTools" -Urls @(
				@{ Name = "GitHub"; Url = "https://github.com" }
				@{ Name = "StackOverflow"; Url = "https://stackoverflow.com" }
			) -ConfigurationFilePath $testConfig

			$result = Get-Content -Path $testConfig -Raw

			$result | Should -Match "DevTools"
			$result | Should -Match "GitHub"
			$result | Should -Match "https://github.com"
			$result | Should -Match "StackOverflow"
			$result | Should -Match "https://stackoverflow.com"
		}

		It "Should maintain valid PowerShell data file format" {
			Add-BrowserGroup -GroupName "Test" -Urls @(
				@{ Name = "Site"; Url = "https://example.com" }
			) -ConfigurationFilePath $testConfig

			$parsed = Import-PowerShellDataFile -Path $testConfig
			$parsed | Should -Not -BeNullOrEmpty
			$parsed.BrowserGroups.Count | Should -BeGreaterThan 1
		}
	}

	Context "Simple URLs" {
		It "Should add a browser group with simple URLs" {
			Add-BrowserGroup -GroupName "Search" -SimpleUrls @(
				"https://www.google.com/"
				"https://www.bing.com/"
			) -ConfigurationFilePath $testConfig

			$result = Get-Content -Path $testConfig -Raw

			$result | Should -Match "Search"
			$result | Should -Match "https://www.bing.com/"
		}
	}

	Context "Error handling" {
		It "Should report error when BrowserGroups section not found" {
			$badConfig = Join-Path $TestDrive "Bad.psd1"
			Set-Content -Path $badConfig -Value '@{ NoGroups = @() }'

			Add-BrowserGroup -GroupName "Test" -SimpleUrls @("https://test.com") -ConfigurationFilePath $badConfig

			# Function should output error but not throw
		}
	}
}
