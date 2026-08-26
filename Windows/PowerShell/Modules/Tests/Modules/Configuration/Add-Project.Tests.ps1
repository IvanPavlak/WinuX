#Requires -Modules Pester

BeforeAll {
	$ConfigurationFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Configuration\Functions"
	. "$ConfigurationFunctionsPath\Find-ConfigurationSection.ps1"
	. "$ConfigurationFunctionsPath\ConvertTo-ActionString.ps1"
	. "$ConfigurationFunctionsPath\Add-Project.ps1"
}

Describe "Add-Project" {
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
			'	Projects = @('
			'		"Existing"'
			'	)'
			''
			'	ProjectTerminals = @('
			'		@{ Name = "Existing"; BasePath = "Projects.Existing"; Paths = @("ROOT") }'
			'	)'
			''
			'	ProjectActions = @{'
			'		Existing                    = @('
			'			@{ Action = "Open-VSCode"; Parameters = @{ Folder = "{ProjectName}" } }'
			'		)'
			'	}'
			''
			'	RunnableProjects = @('
			'		"Existing"'
			'	)'
			''
			'	TerminalTabs = @{'
			'		Existing                    = @('
			'			@{ Title = "Root"; Path = "DEFAULT" }'
			'		)'
			'	}'
			'}'
		)
		Set-Content -Path $testConfig -Value $configContent
	}

	Context "Basic project addition" {
		It "Should add project to Projects array" {
			Add-Project -Name "NewApp" -ConfigurationFilePath $testConfig

			$parsed = Import-PowerShellDataFile -Path $testConfig
			$parsed.Projects | Should -Contain "NewApp"
		}

		It "Should create default ProjectActions" {
			Add-Project -Name "NewApp" -ConfigurationFilePath $testConfig

			$parsed = Import-PowerShellDataFile -Path $testConfig
			$parsed.ProjectActions.NewApp | Should -Not -BeNullOrEmpty
		}

		It "Should use custom actions when provided" {
			Add-Project -Name "NewApp" -Actions @(
				@{ Action = "Open-VisualStudio"; Parameters = @{ Solution = "{ProjectName}" } }
			) -ConfigurationFilePath $testConfig

			$result = Get-Content -Path $testConfig -Raw
			$result | Should -Match "Open-VisualStudio"
		}
	}

	Context "Optional sections" {
		It "Should add TerminalTabs when provided" {
			Add-Project -Name "NewApp" -TerminalTabs @(
				@{ Title = "Root"; Path = "DEFAULT" }
				@{ Title = "API"; Path = "{ProjectName}\api" }
			) -ConfigurationFilePath $testConfig

			$parsed = Import-PowerShellDataFile -Path $testConfig
			$parsed.TerminalTabs.NewApp | Should -Not -BeNullOrEmpty
			$parsed.TerminalTabs.NewApp.Count | Should -Be 2
		}

		It "Should add to RunnableProjects when -Runnable is set" {
			Add-Project -Name "NewApp" -Runnable -ConfigurationFilePath $testConfig

			$parsed = Import-PowerShellDataFile -Path $testConfig
			$parsed.RunnableProjects | Should -Contain "NewApp"
		}

		It "Should add ProjectTerminals entry when BasePath and Paths provided" {
			Add-Project -Name "NewApp" -BasePath "Projects.NewApp" -Paths @("ROOT", "API") -ConfigurationFilePath $testConfig

			$parsed = Import-PowerShellDataFile -Path $testConfig
			$entry = $parsed.ProjectTerminals | Where-Object { $_.Name -eq "NewApp" }
			$entry | Should -Not -BeNullOrEmpty
			$entry.BasePath | Should -Be "Projects.NewApp"
		}
	}

	Context "Full project with all options" {
		It "Should maintain valid format with all options" {
			Add-Project -Name "FullApp" `
				-Actions @(
				@{ Action = "Open-VSCode"; Parameters = @{ Folder = "{ProjectName}" } }
			) `
				-TerminalTabs @(
				@{ Title = "Root"; Path = "DEFAULT" }
			) `
				-BasePath "Projects.FullApp" `
				-Paths @("ROOT") `
				-Runnable `
				-ConfigurationFilePath $testConfig

			$parsed = Import-PowerShellDataFile -Path $testConfig
			$parsed | Should -Not -BeNullOrEmpty
			$parsed.Projects | Should -Contain "FullApp"
			$parsed.ProjectActions.FullApp | Should -Not -BeNullOrEmpty
			$parsed.TerminalTabs.FullApp | Should -Not -BeNullOrEmpty
			$parsed.RunnableProjects | Should -Contain "FullApp"
			$entry = $parsed.ProjectTerminals | Where-Object { $_.Name -eq "FullApp" }
			$entry | Should -Not -BeNullOrEmpty
		}
	}

	Context "Backups" {
		It "Backs the configuration file up into the repository's sink; the copy is the pre-write content" {
			$before = Get-Content -Path $testConfig -Raw

			Add-Project -Name "NewApp" -ConfigurationFilePath $testConfig

			$backups = @(Get-ChildItem -Path $backupKeyDir -Recurse -File)
			$backups.Count | Should -Be 1
			Get-Content -Path $backups[0].FullName -Raw | Should -Be $before
		}

		It "Aborts the write when the backup cannot be taken" {
			Mock Backup-RepositoryItem { throw "access denied" }
			$before = Get-Content -Path $testConfig -Raw

			Add-Project -Name "NewApp" -ConfigurationFilePath $testConfig

			Get-Content -Path $testConfig -Raw | Should -Be $before
		}
	}
}
