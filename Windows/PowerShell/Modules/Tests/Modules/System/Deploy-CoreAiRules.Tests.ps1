#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "System\Functions"
	. "$FunctionsPath\Deploy-CoreAiRules.ps1"
}

Describe "Deploy-CoreAiRules" {
	BeforeEach {
		$script:Configuration = [PSCustomObject]@{
			DefaultWSLDistribution = "Ubuntu"
		}

		Mock Get-RepositoryPath { @{ Repo = "C:\Repo" } }
		Mock Test-WSLDistributionInstalled { $true }
		# The function drives control flow off $LASTEXITCODE after every wsl call;
		# pin it to success so the mock is deterministic regardless of prior commands.
		Mock wsl { $global:LASTEXITCODE = 0 }
		Mock Write-Host { }
		Mock Write-LogTitle { }
		Mock Write-LogSuccess { }
		Mock Write-LogError { }
		Mock Write-LogWarning { }
	}

	It "does not call wsl when the WSL distribution is not installed" {
		Mock Test-WSLDistributionInstalled { $false }

		{ Deploy-CoreAiRules } | Should -Not -Throw

		Should -Invoke wsl -Times 0
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match "not installed" }
	}

	It "skips linking when the managed settings target does not exist inside WSL" {
		Mock wsl { $global:LASTEXITCODE = 1 }

		{ Deploy-CoreAiRules } | Should -Not -Throw

		# Only the existence probe runs; no mkdir, no ln.
		Should -Invoke wsl -Times 1 -Exactly
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match "target does not exist" }
	}

	It "creates the /etc/claude-code symlink as root from the repo's WSL mount path" {
		{ Deploy-CoreAiRules } | Should -Not -Throw

		Should -Invoke wsl -Times 3 -Exactly
		Should -Invoke wsl -Times 1 -Exactly -ParameterFilter { "$args" -eq "-d Ubuntu -u root mkdir -p /etc/claude-code" }
		Should -Invoke wsl -Times 1 -Exactly -ParameterFilter { "$args" -eq "-d Ubuntu -u root ln -sfn /mnt/c/Repo/AI/Claude/managed-settings.json /etc/claude-code/managed-settings.json" }
		Should -Invoke Write-LogError -Times 0
	}

	It "reports failure when the link command fails" {
		Mock wsl { $global:LASTEXITCODE = if ("$args" -match ' ln ') { 1 } else { 0 } }

		{ Deploy-CoreAiRules } | Should -Not -Throw

		Should -Invoke Write-LogSuccess -Times 0
		Should -Invoke Write-LogError -Times 1 -ParameterFilter { $Message -match "Failed to create WSL symlink" }
	}

	It "targets the configured default distribution explicitly on every wsl call" {
		$script:Configuration = [PSCustomObject]@{
			DefaultWSLDistribution = "Debian"
		}

		{ Deploy-CoreAiRules } | Should -Not -Throw

		Should -Invoke wsl -Times 0 -ParameterFilter { "$args" -notmatch '^-d Debian ' }
	}
}
