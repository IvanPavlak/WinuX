#Requires -Modules Pester

BeforeAll {
	$ConfigurationFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Configuration\Functions"
	. "$ConfigurationFunctionsPath\Find-ConfigurationSection.ps1"
	. "$ConfigurationFunctionsPath\ConvertTo-ActionString.ps1"
	. "$ConfigurationFunctionsPath\Add-BrowserGroup.ps1"
}

Describe "Add-BrowserGroup" {
	BeforeEach {
		# The writer backs Configuration.psd1 up into the sink of the repository the file belongs
		# to, so the sandbox mirrors the real layout and the backups stay inside TestDrive.
		$repoRoot = Join-Path $TestDrive "repo"
		$psDir = Join-Path $repoRoot "Windows\PowerShell"
		if (Test-Path $repoRoot) { Remove-Item -Path $repoRoot -Recurse -Force }
		New-Item -ItemType Directory -Path $psDir -Force | Out-Null
		$backupKeyDir = Join-Path $repoRoot "Backups\Windows\Config\Configuration"
		$testConfig = Join-Path $psDir "Configuration.psd1"
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

	Context "Backups" {
		It "Backs the configuration file up into the repository's sink; the copy is the pre-write content" {
			$before = Get-Content -Path $testConfig -Raw

			Add-BrowserGroup -GroupName "Search" -SimpleUrls @("https://www.bing.com/") -ConfigurationFilePath $testConfig

			$backups = @(Get-ChildItem -Path $backupKeyDir -Recurse -File)
			$backups.Count | Should -Be 1
			Get-Content -Path $backups[0].FullName -Raw | Should -Be $before
		}

		It "Aborts the write when the backup cannot be taken" {
			Mock Backup-RepositoryItem { throw "access denied" }
			$before = Get-Content -Path $testConfig -Raw

			Add-BrowserGroup -GroupName "Search" -SimpleUrls @("https://www.bing.com/") -ConfigurationFilePath $testConfig

			Get-Content -Path $testConfig -Raw | Should -Be $before
		}
	}
}
