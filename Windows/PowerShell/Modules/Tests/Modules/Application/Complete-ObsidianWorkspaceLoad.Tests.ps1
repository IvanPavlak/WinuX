#Requires -Modules Pester

BeforeAll {
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Invoke-ObsidianCli.ps1"
	. "$AppFunctionsPath\Wait-ObsidianCli.ps1"
	. "$AppFunctionsPath\Invoke-ObsidianWorkspaceLoad.ps1"
	. "$AppFunctionsPath\Complete-ObsidianWorkspaceLoad.ps1"
}

Describe "Complete-ObsidianWorkspaceLoad" {
	BeforeEach {
		Mock Wait-ObsidianCli { $true }
		Mock Invoke-ObsidianWorkspaceLoad { $true }
		Mock Write-LogWarning { }
		Mock Write-LogSuccess { }
	}

	It "polls the CLI and then loads on a cold start" {
		Complete-ObsidianWorkspaceLoad -CliPath 'C:\Obsidian.com' -Vault 'MyVault' -Name 'Server' -ColdStart | Should -BeTrue

		Should -Invoke Wait-ObsidianCli -Times 1 -Exactly -ParameterFilter { $CliPath -eq 'C:\Obsidian.com' -and $Vault -eq 'MyVault' -and $TimeoutSeconds -eq 10 }
		Should -Invoke Invoke-ObsidianWorkspaceLoad -Times 1 -Exactly -ParameterFilter { $CliPath -eq 'C:\Obsidian.com' -and $Vault -eq 'MyVault' -and $Name -eq 'Server' }
		Should -Invoke Write-LogSuccess -Times 1 -Exactly -ParameterFilter { $Message -like '*[[]Server[]]*' }
	}

	It "skips the poll for a load against an already-running Obsidian" {
		# It answered before the open began, so the poll would only be a wasted process launch.
		Complete-ObsidianWorkspaceLoad -CliPath 'C:\Obsidian.com' -Vault 'V' -Name 'DSA' | Should -BeTrue

		Should -Invoke Wait-ObsidianCli -Times 0
		Should -Invoke Invoke-ObsidianWorkspaceLoad -Times 1 -Exactly
	}

	It "honours a caller's readiness budget" {
		Complete-ObsidianWorkspaceLoad -CliPath 'C:\Obsidian.com' -Vault 'V' -Name 'Server' -ColdStart -TimeoutSeconds 30 | Should -BeTrue

		Should -Invoke Wait-ObsidianCli -Times 1 -Exactly -ParameterFilter { $TimeoutSeconds -eq 30 }
	}

	It "warns and loads nothing when the CLI never answers" {
		Mock Wait-ObsidianCli { $false }

		Complete-ObsidianWorkspaceLoad -CliPath 'C:\Obsidian.com' -Vault 'V' -Name 'Server' -ColdStart | Should -BeFalse

		Should -Invoke Invoke-ObsidianWorkspaceLoad -Times 0
		Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like '*did not answer*[[]Server[]]*' }
		Should -Invoke Write-LogSuccess -Times 0
	}

	It "stays silent about success when the CLI refused the load" {
		Mock Invoke-ObsidianWorkspaceLoad { $false }

		Complete-ObsidianWorkspaceLoad -CliPath 'C:\Obsidian.com' -Vault 'V' -Name 'Server' | Should -BeFalse

		# The refusal itself is reported by Invoke-ObsidianWorkspaceLoad, which owns the CLI answer.
		Should -Invoke Write-LogSuccess -Times 0
	}
}
