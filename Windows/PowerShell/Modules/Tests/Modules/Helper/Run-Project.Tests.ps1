#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Run-Project.ps1"

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
		$script:Configuration = [PSCustomObject]@{
			RunnableProjects        = @("Demo")
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
		Mock Resolve-ProjectPath { "C:\Dev\Demo" }
	}

	It "continues safely when no runnable mapping exists for selected project" {
		{ Run-Project } | Should -Not -Throw
		Should -Invoke Resolve-Selection -Times 1
		Should -Invoke Write-LogStep -Times 1
		Should -Invoke Write-LogError -Times 1
	}

	It "passes the resolved compose file to DockerWizard and opens the project tabs" {
		$script:Configuration = [PSCustomObject]@{
			RunnableProjects        = @("Demo")
			RunnableProjectMappings = @(@{ Name = "Demo"; Commands = @("dnr"); DatabaseProviders = @("PostgreSQL") })
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
		$script:Configuration = [PSCustomObject]@{
			RunnableProjects        = @("Demo")
			RunnableProjectMappings = @(@{ Name = "Demo"; Commands = @("dnr"); DatabaseProviders = @("PostgreSQL") })
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

	It "never touches Docker or the provider prompt when the Docker step is disabled" {
		$script:Configuration = [PSCustomObject]@{
			RunnableProjects        = @("Demo")
			RunnableProjectMappings = @(@{ Name = "Demo"; Commands = @("dnr"); DatabaseProviders = @("PostgreSQL") })
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
