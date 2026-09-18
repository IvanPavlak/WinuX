#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Workflow\Functions"

	. "$FunctionsPath\Resolve-ProjectDockerCompose.ps1"
	. "$FunctionsPath\Resolve-DockerComposeStackPath.ps1"
}

Describe "Resolve-ProjectDockerCompose" {
	BeforeEach {
		$global:Configuration = [PSCustomObject]@{
			RunnableProjectMappings = @(
				@{ Name = "PostgresProject"; Commands = @("dnr"); DatabaseProviders = @("PostgreSQL") }
				@{ Name = "OracleProject"; Commands = @("dnr"); DatabaseProviders = @("Oracle") }
				@{ Name = "MultiProviderProject"; Commands = @("dnr"); DatabaseProviders = @("PostgreSQL", "Oracle") }
				@{ Name = "PlainProject"; Commands = @("dnr") }
			)
			DockerComposeFiles      = @{ PostgreSQL = "docker-compose.postgresql.yml" }
			ProjectTerminals        = @(
				@{ Name = "OracleProject"; BasePath = "Projects.OracleProject"; Paths = @("Api") }
			)
		}
		$script:MachineSpecificPaths = [PSCustomObject]@{
			DockerDirectory = "C:\Repo\Docker"
			Projects        = [PSCustomObject]@{
				OracleProject = [PSCustomObject]@{ Root = "C:\Dev\OracleProject" }
			}
		}

		Mock Write-Host { }
		Mock Write-LogError { }
		Mock Resolve-Selection { "PostgreSQL" }
	}

	It "resolves a centralized provider to the compose file under DockerDirectory" {
		$result = Resolve-ProjectDockerCompose -ProjectName "PostgresProject"

		$result.Provider | Should -Be "PostgreSQL"
		$result.ComposeFilePath | Should -Be "C:\Repo\Docker\docker-compose.postgresql.yml"
		$result.ComposeProjectPath | Should -BeNullOrEmpty
		Should -Invoke Resolve-Selection -Times 0
	}

	It "uses an absolute DockerComposeFiles value as-is instead of joining DockerDirectory" {
		# Joining an absolute entry produced C:\Repo\Docker\D:\Stacks\... and every run
		# died on a compose file that was never there - Start-Containers always got this
		# right, and both now share Resolve-DockerComposeStackPath
		$global:Configuration.DockerComposeFiles = @{ PostgreSQL = "D:\Stacks\docker-compose.postgresql.yml" }

		$result = Resolve-ProjectDockerCompose -ProjectName "PostgresProject"

		$result.ComposeFilePath | Should -Be "D:\Stacks\docker-compose.postgresql.yml"
		$result.ComposeProjectPath | Should -BeNullOrEmpty
	}

	It "takes the project-local branch for UsesDocker even when a stack shares the project name" {
		# The project owns its whole stack: its compose file is the project's, and the
		# same-named DockerComposeFiles entry exists only so Start-Containers can offer it
		$global:Configuration.RunnableProjectMappings = @(
			@{ Name = "SelfHostedProject"; Commands = @{ ROOT = "docker compose logs -f web" }; UsesDocker = $true }
		)
		$global:Configuration.DockerComposeFiles = @{ SelfHostedProject = "D:\Dev\SelfHostedProject\compose.yaml" }
		$global:Configuration.ProjectTerminals = @(
			@{ Name = "SelfHostedProject"; BasePath = "Projects.SelfHostedProject"; Paths = @("ROOT") }
		)
		$script:MachineSpecificPaths.Projects | Add-Member -NotePropertyName SelfHostedProject -NotePropertyValue ([PSCustomObject]@{ Root = "D:\Dev\SelfHostedProject" })

		$result = Resolve-ProjectDockerCompose -ProjectName "SelfHostedProject"

		$result.Provider | Should -BeNullOrEmpty
		$result.ComposeFilePath | Should -BeNullOrEmpty
		$result.ComposeProjectPath | Should -Be "D:\Dev\SelfHostedProject"
	}

	It "falls back to the project root for a provider without a centralized compose file" {
		$result = Resolve-ProjectDockerCompose -ProjectName "OracleProject"

		$result.Provider | Should -Be "Oracle"
		$result.ComposeFilePath | Should -BeNullOrEmpty
		$result.ComposeProjectPath | Should -Be "C:\Dev\OracleProject"
	}

	It "returns null for a project with no database providers and no UsesDocker" {
		$result = Resolve-ProjectDockerCompose -ProjectName "PlainProject"

		$result | Should -BeNullOrEmpty
		Should -Invoke Resolve-Selection -Times 0
	}

	It "prompts for the provider when several are configured" {
		$result = Resolve-ProjectDockerCompose -ProjectName "MultiProviderProject"

		Should -Invoke Resolve-Selection -Times 1
		$result.Provider | Should -Be "PostgreSQL"
	}

	It "skips the provider menu when -DatabaseProvider is given" {
		$result = Resolve-ProjectDockerCompose -ProjectName "MultiProviderProject" -DatabaseProvider "PostgreSQL"

		Should -Invoke Resolve-Selection -Times 0
		$result.Provider | Should -Be "PostgreSQL"
		$result.ComposeFilePath | Should -Be "C:\Repo\Docker\docker-compose.postgresql.yml"
	}

	It "honors UsesDocker on a mapping without database providers" {
		$global:Configuration.RunnableProjectMappings += @{ Name = "ComposeOnlyProject"; Commands = @("dnr"); UsesDocker = $true }
		$global:Configuration.ProjectTerminals += @{ Name = "ComposeOnlyProject"; BasePath = "Projects.OracleProject"; Paths = @("Api") }

		$result = Resolve-ProjectDockerCompose -ProjectName "ComposeOnlyProject"

		$result.Provider | Should -BeNullOrEmpty
		$result.ComposeProjectPath | Should -Be "C:\Dev\OracleProject"
	}

	It "returns null and logs an error when no runnable mapping exists" {
		$result = Resolve-ProjectDockerCompose -ProjectName "GhostProject"

		$result | Should -BeNullOrEmpty
		Should -Invoke Write-LogError -Times 1
	}

	It "returns null and logs an error when the project-local fallback has no ProjectTerminals mapping" {
		$global:Configuration.ProjectTerminals = @()

		$result = Resolve-ProjectDockerCompose -ProjectName "OracleProject"

		$result | Should -BeNullOrEmpty
		Should -Invoke Write-LogError -Times 1
	}

	It "returns null and logs an error when the BasePath does not resolve to a Root" {
		# Silently returning an empty ComposeProjectPath would have DockerWizard start
		# Docker and then quietly do nothing else
		$global:Configuration.ProjectTerminals = @(
			@{ Name = "OracleProject"; BasePath = "Projects.NoSuchProject"; Paths = @("Api") }
		)

		$result = Resolve-ProjectDockerCompose -ProjectName "OracleProject"

		$result | Should -BeNullOrEmpty
		Should -Invoke Write-LogError -Times 1
	}

	It "does not throw when DockerComposeFiles is absent from the configuration" {
		# A setup with no Docker at all drops the key; ContainsKey is a method call, so an
		# unguarded null would throw rather than resolve to "no centralized compose file"
		$global:Configuration = [PSCustomObject]@{
			RunnableProjectMappings = @(
				@{ Name = "PostgresProject"; Commands = @("dnr"); DatabaseProviders = @("PostgreSQL") }
			)
			ProjectTerminals        = @()
		}

		{ Resolve-ProjectDockerCompose -ProjectName "PostgresProject" } | Should -Not -Throw
		Resolve-ProjectDockerCompose -ProjectName "PostgresProject" | Should -BeNullOrEmpty
	}
}
