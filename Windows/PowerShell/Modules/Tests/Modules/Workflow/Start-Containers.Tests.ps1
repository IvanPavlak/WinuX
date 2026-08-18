#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Workflow\Functions"

	. "$FunctionsPath\Start-Containers.ps1"

	function DockerWizard {
		param(
			[switch]$Stop,
			[string]$ComposeProjectPath,
			[string]$ComposeFilePath,
			[switch]$PassThru
		)
	}
}

Describe "Start-Containers" {
	BeforeEach {
		$script:composeCalls = @()

		$script:Configuration = [PSCustomObject]@{
			DockerComposeFiles = @{
				PostgreSQL = "docker-compose.postgresql.yml"
			}
		}
		$script:MachineSpecificPaths = [PSCustomObject]@{
			DockerDirectory = "C:\Repo\Docker"
		}

		Mock Write-Host { }
		Mock Write-LogTitle { }
		Mock Write-LogStep { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }
		Mock Get-Command { [PSCustomObject]@{ Name = 'docker' } } -ParameterFilter { $Name -eq 'docker' }
		Mock Get-Content { @() }
		Mock Test-Path { $true }

		Mock Resolve-Selection { @("PostgreSQL") }

		Mock DockerWizard {
			[PSCustomObject]@{
				Success         = $true
				ComposeFilePath = "C:\Repo\Docker\docker-compose.postgresql.yml"
			}
		}

		Mock docker {
			param([Parameter(ValueFromRemainingArguments = $true)]$Args)
			$cmd = @($Args)
			if ($cmd.Count -ge 1 -and $cmd[0] -eq 'compose') {
				$script:composeCalls += , $cmd
			}
			$global:LASTEXITCODE = 0
		}
	}

	It "starts the single configured stack without showing a menu" {
		Start-Containers

		Should -Invoke Resolve-Selection -Times 0
		Should -Invoke DockerWizard -Times 1 -Exactly -ParameterFilter {
			$PassThru -and $ComposeFilePath -eq "C:\Repo\Docker\docker-compose.postgresql.yml"
		}
		Should -Invoke Write-LogSuccess -Times 1
	}

	It "shows a multi-select menu when several stacks are configured" {
		$script:Configuration = [PSCustomObject]@{
			DockerComposeFiles = @{
				PostgreSQL = "docker-compose.postgresql.yml"
				Redis      = "docker-compose.redis.yml"
			}
		}

		Start-Containers

		Should -Invoke Resolve-Selection -Times 1 -ParameterFilter {
			$OptionList.Count -eq 2 -and
			$OptionList -contains "PostgreSQL" -and
			$OptionList -contains "Redis" -and
			$AllowMultipleSelections
		}
		Should -Invoke DockerWizard -Times 1 -Exactly
	}

	It "resolves a stack by name even when only one is configured" {
		Start-Containers PostgreSQL

		Should -Invoke Resolve-Selection -Times 1 -ParameterFilter { $InputObject -eq "PostgreSQL" }
		Should -Invoke DockerWizard -Times 1 -Exactly
	}

	It "uses an absolute compose path as-is instead of joining DockerDirectory" {
		$script:Configuration = [PSCustomObject]@{
			DockerComposeFiles = @{
				PostgreSQL = "D:\Stacks\docker-compose.postgresql.yml"
			}
		}

		Start-Containers

		Should -Invoke DockerWizard -Times 1 -Exactly -ParameterFilter {
			$ComposeFilePath -eq "D:\Stacks\docker-compose.postgresql.yml"
		}
	}

	It "fails fast without starting Docker when the compose file does not exist" {
		Mock Test-Path { $false }

		Start-Containers

		Should -Invoke DockerWizard -Times 0
		Should -Invoke Write-LogError -Times 1 -ParameterFilter { $Message -match 'not found' }
		Should -Invoke Write-LogSuccess -Times 0
	}

	It "warns when no stacks are configured" {
		$script:Configuration = [PSCustomObject]@{ DockerComposeFiles = @{} }

		Start-Containers

		Should -Invoke DockerWizard -Times 0
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match 'No Docker Compose stacks' }
	}

	It "reports an error when DockerWizard fails to start Docker" {
		Mock DockerWizard {
			[PSCustomObject]@{ Success = $false; ComposeFilePath = $null }
		}

		Start-Containers

		Should -Invoke Write-LogError -Times 1
		Should -Invoke Write-LogSuccess -Times 0
	}

	It "prints the published host ports after the containers are up" {
		Mock Get-Content {
			@(
				'services:',
				'  postgres-17:',
				'    image: postgres:17',
				'    ports:',
				'      - "5432:5432"',
				'  postgres-16:',
				'    image: postgres:16',
				'    ports:',
				'      - "5433:5432"'
			)
		}

		Start-Containers

		Should -Invoke Write-LogStep -Times 1 -ParameterFilter { $Message -match '\[postgres-17\] => localhost:5432' }
		Should -Invoke Write-LogStep -Times 1 -ParameterFilter { $Message -match '\[postgres-16\] => localhost:5433' }
	}

	It "Stop runs docker compose stop and leaves DockerWizard untouched" {
		Start-Containers -Stop

		Should -Invoke DockerWizard -Times 0
		$script:composeCalls.Count | Should -Be 1
		$script:composeCalls[0] | Should -Contain 'stop'
		$script:composeCalls[0] | Should -Contain 'C:\Repo\Docker\docker-compose.postgresql.yml'
	}

	It "Stop with Down runs docker compose down" {
		Start-Containers -Stop -Down

		$script:composeCalls.Count | Should -Be 1
		$script:composeCalls[0] | Should -Contain 'down'
	}

	It "Down alone implies Stop" {
		Start-Containers -Down

		Should -Invoke DockerWizard -Times 0
		$script:composeCalls.Count | Should -Be 1
		$script:composeCalls[0] | Should -Contain 'down'
	}

	It "Stop warns per stack when the compose file does not exist" {
		Mock Test-Path { $false }

		Start-Containers -Stop

		$script:composeCalls.Count | Should -Be 0
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match 'not found' }
	}

	It "Stop warns and does nothing when the Docker daemon is not running" {
		Mock docker {
			param([Parameter(ValueFromRemainingArguments = $true)]$Args)
			$global:LASTEXITCODE = 1
		}

		Start-Containers -Stop

		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match 'not running' }
		$script:composeCalls.Count | Should -Be 0
	}
}
