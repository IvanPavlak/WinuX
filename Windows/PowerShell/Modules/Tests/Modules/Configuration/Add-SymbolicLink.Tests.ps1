#Requires -Modules Pester

BeforeAll {
	$ConfigurationFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Configuration\Functions"
	. "$ConfigurationFunctionsPath\Find-ConfigurationSection.ps1"
	. "$ConfigurationFunctionsPath\Add-SymbolicLink.ps1"
}

Describe "Add-SymbolicLink" {
	BeforeEach {
		$testConfig = Join-Path $TestDrive "Configuration.psd1"
		$configContent = @(
			'@{'
			'	SymbolicLinks = @{'
			'		Git                  = @{'
			'			Path   = "{User}\.gitconfig"'
			'			Target = "{RepoRoot}\Git\.gitconfig"'
			'		}'
			'	}'
			'}'
		)
		Set-Content -Path $testConfig -Value $configContent
	}

	Context "Simple symbolic link" {
		It "Should add a simple symbolic link entry" {
			Add-SymbolicLink -Name "MyApp" `
				-Path "{AppData}\MyApp\config.json" `
				-Target "{RepoRoot}\MyApp\config.json" `
				-ConfigurationFilePath $testConfig

			$parsed = Import-PowerShellDataFile -Path $testConfig
			$parsed.SymbolicLinks.MyApp | Should -Not -BeNullOrEmpty
			$parsed.SymbolicLinks.MyApp.Path | Should -Be "{AppData}\MyApp\config.json"
			$parsed.SymbolicLinks.MyApp.Target | Should -Be "{RepoRoot}\MyApp\config.json"
		}

		It "Should preserve existing entries" {
			Add-SymbolicLink -Name "MyApp" `
				-Path "{AppData}\MyApp\config.json" `
				-Target "{RepoRoot}\MyApp\config.json" `
				-ConfigurationFilePath $testConfig

			$parsed = Import-PowerShellDataFile -Path $testConfig
			$parsed.SymbolicLinks.Git | Should -Not -BeNullOrEmpty
			$parsed.SymbolicLinks.Git.Path | Should -Be "{User}\.gitconfig"
		}
	}

	Context "Nested symbolic link" {
		It "Should add a nested symbolic link with multiple files" {
			Add-SymbolicLink -Name "PowerToys" -Links @(
				@{ Name = "Settings"; Path = "{User}\AppData\settings.json"; Target = "{RepoRoot}\PowerToys\settings.json" }
				@{ Name = "Layouts"; Path = "{User}\AppData\layouts.json"; Target = "{RepoRoot}\PowerToys\layouts.json" }
			) -ConfigurationFilePath $testConfig

			$parsed = Import-PowerShellDataFile -Path $testConfig
			$parsed.SymbolicLinks.PowerToys | Should -Not -BeNullOrEmpty
			$parsed.SymbolicLinks.PowerToys.Settings | Should -Not -BeNullOrEmpty
			$parsed.SymbolicLinks.PowerToys.Layouts | Should -Not -BeNullOrEmpty
		}
	}

	Context "Format validation" {
		It "Should maintain valid PowerShell data file format" {
			Add-SymbolicLink -Name "Test" `
				-Path "{User}\test" `
				-Target "{RepoRoot}\test" `
				-ConfigurationFilePath $testConfig

			$parsed = Import-PowerShellDataFile -Path $testConfig
			$parsed | Should -Not -BeNullOrEmpty
		}
	}
}
