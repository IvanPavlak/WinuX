#Requires -Modules Pester

BeforeAll {
	$ConfigurationFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Configuration\Functions"
	. "$ConfigurationFunctionsPath\Find-ConfigurationSection.ps1"
	. "$ConfigurationFunctionsPath\Add-SymbolicLink.ps1"
}

Describe "Add-SymbolicLink" {
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

	Context "Backups" {
		It "Backs the configuration file up into the repository's sink; the copy is the pre-write content" {
			$before = Get-Content -Path $testConfig -Raw

			Add-SymbolicLink -Name "MyApp" -Path "{User}\x" -Target "{RepoRoot}\x" -ConfigurationFilePath $testConfig

			$backups = @(Get-ChildItem -Path $backupKeyDir -Recurse -File)
			$backups.Count | Should -Be 1
			$backups[0].Name | Should -Be "Configuration.psd1"
			Get-Content -Path $backups[0].FullName -Raw | Should -Be $before
		}

		It "Aborts the write when the backup cannot be taken" {
			Mock Backup-RepositoryItem { throw "access denied" }
			$before = Get-Content -Path $testConfig -Raw

			Add-SymbolicLink -Name "MyApp" -Path "{User}\x" -Target "{RepoRoot}\x" -ConfigurationFilePath $testConfig

			Get-Content -Path $testConfig -Raw | Should -Be $before
		}
	}
}
