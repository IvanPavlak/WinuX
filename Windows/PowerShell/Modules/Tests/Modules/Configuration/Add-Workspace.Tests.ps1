#Requires -Modules Pester

BeforeAll {
	$ConfigurationFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Configuration\Functions"
	. "$ConfigurationFunctionsPath\Find-ConfigurationSection.ps1"
	. "$ConfigurationFunctionsPath\ConvertTo-ActionString.ps1"
	. "$ConfigurationFunctionsPath\Add-Workspace.ps1"
}

Describe "Add-Workspace" {
	BeforeEach {
		$testConfig = Join-Path $TestDrive "Configuration.psd1"
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
}
