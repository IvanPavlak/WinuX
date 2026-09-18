#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Workflow\Functions"

	. "$FunctionsPath\Resolve-DockerComposeStackPath.ps1"
}

Describe "Resolve-DockerComposeStackPath" {
	BeforeEach {
		$global:Configuration = [PSCustomObject]@{
			DockerComposeFiles = @{
				PostgreSQL   = "docker-compose.postgresql.yml"
				ProjectOwned = "D:\Dev\ProjectOwned\compose.yaml"
			}
		}
		$script:MachineSpecificPaths = [PSCustomObject]@{
			DockerDirectory = "C:\Repo\Docker"
		}

		Mock Write-Host { }
	}

	It "joins a relative stack value under DockerDirectory" {
		Resolve-DockerComposeStackPath -Name "PostgreSQL" | Should -Be "C:\Repo\Docker\docker-compose.postgresql.yml"
	}

	It "uses an absolute stack value as-is" {
		# A stack that lives outside the repository's Docker directory - joining it would
		# produce C:\Repo\Docker\D:\Dev\... and every caller would report a missing file
		Resolve-DockerComposeStackPath -Name "ProjectOwned" | Should -Be "D:\Dev\ProjectOwned\compose.yaml"
	}

	It "returns null for a name that is not a configured stack" {
		Resolve-DockerComposeStackPath -Name "NotAStack" | Should -BeNullOrEmpty
	}

	It "returns null for a stack configured with an empty value" {
		$global:Configuration.DockerComposeFiles["Blank"] = "   "

		Resolve-DockerComposeStackPath -Name "Blank" | Should -BeNullOrEmpty
	}

	It "does not throw when DockerComposeFiles is absent from the configuration" {
		$global:Configuration = [PSCustomObject]@{}

		{ Resolve-DockerComposeStackPath -Name "PostgreSQL" } | Should -Not -Throw
		Resolve-DockerComposeStackPath -Name "PostgreSQL" | Should -BeNullOrEmpty
	}

	It "does not check that the compose file exists" {
		# Existence is the caller's business: Start-Containers warns per stack and
		# DockerWizard turns a missing file into a failed start
		Mock Test-Path { $false }

		Resolve-DockerComposeStackPath -Name "PostgreSQL" | Should -Be "C:\Repo\Docker\docker-compose.postgresql.yml"
		Should -Invoke Test-Path -Times 0
	}
}
