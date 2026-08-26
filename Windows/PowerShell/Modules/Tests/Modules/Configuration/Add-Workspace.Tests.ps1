#Requires -Modules Pester

BeforeAll {
	$ConfigurationFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Configuration\Functions"
	. "$ConfigurationFunctionsPath\Find-ConfigurationSection.ps1"
	. "$ConfigurationFunctionsPath\ConvertTo-ActionString.ps1"
	. "$ConfigurationFunctionsPath\Add-Workspace.ps1"
}

Describe "Add-Workspace" {
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
			'	Workspaces = @('
			'		"Existing"'
			'	)'
			''
			'	WorkspaceActions = @{'
			'		Existing                = @('
			'			@{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = "Existing" } }'
			'		)'
			'	}'
			'}'
		)
		Set-Content -Path $testConfig -Value $configContent
	}

	Context "Adding workspace with actions" {
		It "Should add workspace name to Workspaces array" {
			Add-Workspace -Name "NewWS" -ConfigurationFilePath $testConfig

			$result = Get-Content -Path $testConfig -Raw
			$result | Should -Match '"NewWS"'
		}

		It "Should add WorkspaceActions entry" {
			Add-Workspace -Name "NewWS" -Actions @(
				@{ Action = "Open-Browser"; Parameters = @{ Groups = @("AI", "GitHub") } }
				@{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = "NewWS" } }
			) -ConfigurationFilePath $testConfig

			$result = Get-Content -Path $testConfig -Raw
			$result | Should -Match "NewWS"
			$result | Should -Match "Open-Browser"
			$result | Should -Match "Set-WorkspaceWindowLayout"
		}

		It "Should create default action when none specified" {
			Add-Workspace -Name "NewWS" -ConfigurationFilePath $testConfig

			$result = Get-Content -Path $testConfig -Raw
			$result | Should -Match "Set-WorkspaceWindowLayout"
			$result | Should -Match "NewWS"
		}

		It "Should maintain valid PowerShell data file format" {
			Add-Workspace -Name "NewWS" -Actions @(
				@{ Action = "Open-Browser"; Parameters = @{ Groups = @("AI") } }
			) -ConfigurationFilePath $testConfig

			$parsed = Import-PowerShellDataFile -Path $testConfig
			$parsed | Should -Not -BeNullOrEmpty
			$parsed.Workspaces | Should -Contain "NewWS"
			$parsed.WorkspaceActions.NewWS | Should -Not -BeNullOrEmpty
		}
	}

	Context "Backups" {
		It "Backs the configuration file up into the repository's sink; the copy is the pre-write content" {
			$before = Get-Content -Path $testConfig -Raw

			Add-Workspace -Name "NewWS" -ConfigurationFilePath $testConfig

			$backups = @(Get-ChildItem -Path $backupKeyDir -Recurse -File)
			$backups.Count | Should -Be 1
			Get-Content -Path $backups[0].FullName -Raw | Should -Be $before
		}

		It "Aborts the write when the backup cannot be taken" {
			Mock Backup-RepositoryItem { throw "access denied" }
			$before = Get-Content -Path $testConfig -Raw

			Add-Workspace -Name "NewWS" -ConfigurationFilePath $testConfig

			Get-Content -Path $testConfig -Raw | Should -Be $before
		}
	}
}
