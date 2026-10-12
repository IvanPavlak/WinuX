#Requires -Modules Pester

BeforeAll {
	$ConfigurationFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Configuration\Functions"
	. "$ConfigurationFunctionsPath\Find-ConfigurationSection.ps1"
	. "$ConfigurationFunctionsPath\ConvertTo-ActionString.ps1"
	. "$ConfigurationFunctionsPath\Add-Workspace.ps1"
	. (Join-Path (Get-RepositoryPath).Modules "Helper\Functions\Get-OrderedNames.ps1")
	. (Join-Path (Get-RepositoryPath).Modules "Helper\Functions\Get-OrderedEntry.ps1")
	. (Join-Path (Get-RepositoryPath).Modules "Helper\Functions\Get-OrderedNames.ps1")
	. (Join-Path (Get-RepositoryPath).Modules "Helper\Functions\Get-OrderedEntry.ps1")
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
			'	WorkspaceActions = @('
			'		@{ Existing                = @('
			'				@{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = "Existing" } }'
			'			)'
			'		}'
			'	)'
			'}'
		)
		Set-Content -Path $testConfig -Value $configContent
	}

	Context "Adding workspace with actions" {
		It "Should write one entry, in WorkspaceActions, and no second name list" {
			Add-Workspace -Name "NewWS" -ConfigurationFilePath $testConfig

			$parsed = Import-PowerShellDataFile -Path $testConfig
			$parsed.ContainsKey("Workspaces") | Should -BeFalse
			@(Get-OrderedNames $parsed.WorkspaceActions) | Should -Be @("Existing", "NewWS")
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
			Get-OrderedEntry $parsed.WorkspaceActions "NewWS" | Should -Not -BeNullOrEmpty
			# Appended last, so the new workspace shows up at the end of the menu.
			@(Get-OrderedNames $parsed.WorkspaceActions)[-1] | Should -Be "NewWS"
		}
	}

	Context "Adding a templated workspace" {
		BeforeEach {
			Mock Write-LogError { }
			Mock Get-ConfigSetting { @{ Project = @{ Actions = @(@{ Action = 'Open-Project' }) } } } -ParameterFilter { $Path -eq 'WorkspaceTemplates' }
		}

		It "writes the one-line templated entry, appended last" {
			Add-Workspace -Name "MyProject" -Template "Project" -ConfigurationFilePath $testConfig

			$parsed = Import-PowerShellDataFile -Path $testConfig
			@(Get-OrderedNames $parsed.WorkspaceActions) | Should -Be @("Existing", "MyProject")
			$entry = Get-OrderedEntry $parsed.WorkspaceActions "MyProject"
			$entry | Should -BeOfType [hashtable]
			$entry.Template | Should -Be "Project"
			@($entry.Keys) | Should -Be @("Template")
			@(Get-Content -Path $testConfig | Where-Object { $_ -match 'MyProject' }).Count | Should -Be 1
		}

		It "accepts the template name case-insensitively" {
			Add-Workspace -Name "MyProject" -Template "project" -ConfigurationFilePath $testConfig

			(Get-OrderedEntry (Import-PowerShellDataFile -Path $testConfig).WorkspaceActions "MyProject").Template | Should -Be "project"
			Should -Invoke Write-LogError -Times 0
		}

		It "refuses an unknown template and leaves the file unchanged" {
			$before = Get-Content -Path $testConfig -Raw

			Add-Workspace -Name "MyProject" -Template "Missing" -ConfigurationFilePath $testConfig

			Get-Content -Path $testConfig -Raw | Should -Be $before
			Should -Invoke Write-LogError -Times 1 -Exactly
		}

		It "writes the entry when no WorkspaceTemplates are loaded to check against" {
			Mock Get-ConfigSetting { $null } -ParameterFilter { $Path -eq 'WorkspaceTemplates' }

			Add-Workspace -Name "MyProject" -Template "Project" -ConfigurationFilePath $testConfig

			(Get-OrderedEntry (Import-PowerShellDataFile -Path $testConfig).WorkspaceActions "MyProject").Template | Should -Be "Project"
		}

		It "cannot combine -Template with -Actions" {
			$before = Get-Content -Path $testConfig -Raw

			{ Add-Workspace -Name "MyProject" -Template "Project" -Actions @(@{ Action = "Open-Browser" }) -ConfigurationFilePath $testConfig } | Should -Throw

			Get-Content -Path $testConfig -Raw | Should -Be $before
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
