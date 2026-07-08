#Requires -Modules Pester

BeforeAll {
	$ConfigurationFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Configuration\Functions"
	. "$ConfigurationFunctionsPath\Find-ConfigurationSection.ps1"
	. "$ConfigurationFunctionsPath\ConvertTo-ActionString.ps1"
	. "$ConfigurationFunctionsPath\Add-Project.ps1"
}

Describe "Add-Project" {
	BeforeEach {
		$testConfig = Join-Path $TestDrive "Configuration.psd1"
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
}
