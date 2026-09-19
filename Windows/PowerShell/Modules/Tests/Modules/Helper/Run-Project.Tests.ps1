#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Run-Project.ps1"

	# The real entry reader, dot-sourced so it resolves against this file's mocks the way the
	# function under test does - `rp` and `op` read a project's tabs through this one function.
	. "$FunctionsPath\Resolve-ProjectTerminalTab.ps1"

	function Open-WSLTab {
		param(
			[string]$Distribution,
			[string]$Path,
			[string]$TabTitle,
			[string]$WindowId,
			[switch]$Quiet
		)
	}

	function Resolve-ProjectDockerCompose {
		param(
			[string]$ProjectName,
			[string]$DatabaseProvider
		)
	}

	function DockerWizard {
		param(
			[switch]$Stop,
			[string]$ComposeProjectPath,
			[string]$ComposeFilePath,
			[switch]$PassThru
		)
	}

	function Resolve-RunProjectSteps {
		param(
			[string[]]$Skip,
			[string[]]$Include
		)
		[ordered]@{ Docker = $true }
	}
}

Describe "Run-Project" {
	BeforeEach {
		$global:Configuration = [PSCustomObject]@{
			RunnableProjectMappings = @()
			ProjectTerminals        = @()
			DockerComposeFiles      = @{}
		}
		Mock Resolve-Selection { @("Demo") }
		Mock Get-WindowHandle { $null }
		Mock Write-Host { }
		Mock Write-LogStep { }
		Mock Write-LogError { }
		Mock Write-LogSuccess { }
		Mock Focus-TerminalTab { }
		Mock Resolve-ProjectDockerCompose { $null }
		Mock Resolve-RunProjectSteps { [ordered]@{ Docker = $true } }
		Mock DockerWizard { [PSCustomObject]@{ Success = $true; ComposeFilePath = $null } }
		Mock Close-ProjectTerminals { 0 }
		Mock Open-Terminal { }
		Mock Open-WSLTab { }
		Mock Write-LogWarning { }
		Mock Resolve-ProjectPath { "C:\Dev\Demo" }
	}

	It "continues safely when no runnable mapping exists for selected project" {
		{ Run-Project } | Should -Not -Throw
		Should -Invoke Resolve-Selection -Times 1
		Should -Invoke Write-LogStep -Times 1
		Should -Invoke Write-LogError -Times 1
	}

	It "passes the resolved compose file to DockerWizard and opens the project tabs" {
		$global:Configuration = [PSCustomObject]@{
			RunnableProjectMappings = @(@{ Name = "Demo"; Commands = @{ Api = "dnr" }; DatabaseProviders = @("PostgreSQL") })
			ProjectTerminals        = @(@{ Name = "Demo"; Paths = @("Api") })
			DockerComposeFiles      = @{ PostgreSQL = "docker-compose.postgresql.yml" }
		}
		Mock Resolve-ProjectDockerCompose {
			[PSCustomObject]@{
				Provider           = "PostgreSQL"
				ComposeFilePath    = "C:\Repo\Docker\docker-compose.postgresql.yml"
				ComposeProjectPath = $null
			}
		}

		Run-Project

		Should -Invoke DockerWizard -Times 1 -ParameterFilter {
			$PassThru -and $ComposeFilePath -eq "C:\Repo\Docker\docker-compose.postgresql.yml"
		}
		Should -Invoke Open-Terminal -Times 1
		Should -Invoke Write-LogError -Times 0
	}

	It "skips the project when Docker is required but fails to start" {
		$global:Configuration = [PSCustomObject]@{
			RunnableProjectMappings = @(@{ Name = "Demo"; Commands = @{ Api = "dnr" }; DatabaseProviders = @("PostgreSQL") })
			ProjectTerminals        = @(@{ Name = "Demo"; Paths = @("Api") })
			DockerComposeFiles      = @{ PostgreSQL = "docker-compose.postgresql.yml" }
		}
		Mock Resolve-ProjectDockerCompose {
			[PSCustomObject]@{
				Provider           = "PostgreSQL"
				ComposeFilePath    = "C:\Repo\Docker\docker-compose.postgresql.yml"
				ComposeProjectPath = $null
			}
		}
		Mock DockerWizard { [PSCustomObject]@{ Success = $false; ComposeFilePath = $null } }

		Run-Project

		Should -Invoke DockerWizard -Times 1
		Should -Invoke Write-LogError -Times 1 -ParameterFilter { $Message -match 'could not be started' }
		Should -Invoke Close-ProjectTerminals -Times 0
		Should -Invoke Open-Terminal -Times 0
	}

	It "offers the runnable projects in the order the mappings are configured" {
		# The mappings are the only definition of a runnable project - no separate name list.
		$global:Configuration = [PSCustomObject]@{
			RunnableProjectMappings = @(
				@{ Name = "Zulu"; Commands = @{} }
				@{ Name = "Alpha"; Commands = @{} }
			)
			ProjectTerminals        = @()
			DockerComposeFiles      = @{}
		}
		$script:offeredOptions = $null
		Mock Resolve-Selection { $script:offeredOptions = $OptionList; @() }

		Run-Project

		@($script:offeredOptions) | Should -Be @("Zulu", "Alpha")
	}

	It "runs each path's own command and opens a bare tab for a path with none" {
		# Commands is keyed by path, so a path without one is not a configuration error -
		# it just gets its terminal tab with nothing run in it.
		$global:Configuration = [PSCustomObject]@{
			RunnableProjectMappings = @(@{ Name = "Demo"; Commands = @{ Ui = "nir" } })
			ProjectTerminals        = @(@{ Name = "Demo"; Paths = @("Api", "Ui") })
			DockerComposeFiles      = @{}
		}
		$script:openedCommands = $null
		Mock Open-Terminal { $script:openedCommands = $Command }

		Run-Project

		Should -Invoke Write-LogError -Times 0
		@($script:openedCommands)[0] | Should -Not -Match 'nir'
		@($script:openedCommands)[1] | Should -Match 'nir$'
	}

	It "opens a WSL entry as a WSL tab instead of handing its path to Set-Location" {
		# The regression: a WSL path read as an ordinary explicit path reached
		# "Set-Location -Path '/mnt/c/...'", and PowerShell resolves a rooted path against the
		# CURRENT DRIVE - so the tab went to C:\mnt\c\... and the project never opened.
		$global:Configuration = [PSCustomObject]@{
			RunnableProjectMappings = @(@{ Name = "Demo"; Commands = @{ ROOT = "docker compose logs -f web" } })
			ProjectTerminals        = @(@{ Name = "Demo"; Paths = @("ROOT", @{ Key = "WSL"; Path = "/mnt/c/Dev/Demo" }) })
			DockerComposeFiles      = @{}
			DefaultWSLDistribution  = "Ubuntu"
		}
		$script:openedCommands = $null
		$script:openedTitles = $null
		Mock Open-Terminal {
			$script:openedCommands = $Command
			$script:openedTitles = $TabTitles
		}

		Run-Project

		@($script:openedCommands).Count | Should -Be 1
		@($script:openedCommands)[0] | Should -Not -Match 'mnt'
		@($script:openedTitles) | Should -Be @("Demo.ROOT")
		Should -Invoke Open-WSLTab -Times 1 -ParameterFilter {
			$Path -eq "/mnt/c/Dev/Demo" -and $TabTitle -eq "Demo.WSL" -and $Distribution -eq "Ubuntu"
		}
	}

	It "reports a command configured for a WSL tab instead of running it in PowerShell" {
		# The tab runs the distribution's shell, so a PowerShell command configured against that
		# key has nowhere to run - the tab still opens in the project.
		$global:Configuration = [PSCustomObject]@{
			RunnableProjectMappings = @(@{ Name = "Demo"; Commands = @{ WSL = "bin/dev" } })
			ProjectTerminals        = @(@{ Name = "Demo"; Paths = @(@{ Key = "WSL"; Path = "/mnt/c/Dev/Demo" }) })
			DockerComposeFiles      = @{}
			DefaultWSLDistribution  = "Ubuntu"
		}

		Run-Project

		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match 'is not run' }
		Should -Invoke Open-WSLTab -Times 1
		Should -Invoke Open-Terminal -Times 0
	}

	It "skips a WSL tab when no distribution is configured" {
		$global:Configuration = [PSCustomObject]@{
			RunnableProjectMappings = @(@{ Name = "Demo"; Commands = @{} })
			ProjectTerminals        = @(@{ Name = "Demo"; Paths = @("ROOT", "WSL") })
			DockerComposeFiles      = @{}
			DefaultWSLDistribution  = ""
		}

		Run-Project

		Should -Invoke Open-WSLTab -Times 0
		Should -Invoke Open-Terminal -Times 1
		Should -Invoke Write-LogError -Times 0
	}

	It "never touches Docker or the provider prompt when the Docker step is disabled" {
		$global:Configuration = [PSCustomObject]@{
			RunnableProjectMappings = @(@{ Name = "Demo"; Commands = @{ Api = "dnr" }; DatabaseProviders = @("PostgreSQL") })
			ProjectTerminals        = @(@{ Name = "Demo"; Paths = @("Api") })
			DockerComposeFiles      = @{ PostgreSQL = "docker-compose.postgresql.yml" }
		}
		Mock Resolve-RunProjectSteps { [ordered]@{ Docker = $false } }

		Run-Project -Skip Docker

		Should -Invoke Resolve-RunProjectSteps -Times 1 -ParameterFilter { $Skip -contains "Docker" }
		Should -Invoke Resolve-ProjectDockerCompose -Times 0
		Should -Invoke DockerWizard -Times 0
		Should -Invoke Open-Terminal -Times 1
	}
}
