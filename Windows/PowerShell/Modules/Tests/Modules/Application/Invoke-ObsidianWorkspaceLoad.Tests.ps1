#Requires -Modules Pester

BeforeAll {
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Invoke-ObsidianCli.ps1"
	. "$AppFunctionsPath\Invoke-ObsidianWorkspaceLoad.ps1"
}

Describe "Invoke-ObsidianWorkspaceLoad" {
	BeforeEach {
		$script:cliCalls = @()
		$script:cliAnswer = @()
		Mock Invoke-ObsidianCli { $script:cliCalls += , @($Arguments); $script:cliAnswer }
		Mock Write-LogWarning { }
	}

	It "sends the CLI the vault, the verb and the name, in that order" {
		Invoke-ObsidianWorkspaceLoad -CliPath 'C:\Apps\Obsidian\Obsidian.com' -Vault 'MyVault' -Name 'Server' | Should -BeTrue

		$script:cliCalls.Count | Should -Be 1
		$script:cliCalls[0] | Should -Be @('vault=MyVault', 'workspace:load', 'name=Server')
	}

	It "passes the CLI path through to the one call site" {
		Invoke-ObsidianWorkspaceLoad -CliPath 'D:\Obsidian\Obsidian.com' -Vault 'V' -Name 'N' | Should -BeTrue

		Should -Invoke Invoke-ObsidianCli -Times 1 -Exactly -ParameterFilter { $CliPath -eq 'D:\Obsidian\Obsidian.com' }
	}

	It "reports a silent answer as a load that landed" {
		$script:cliAnswer = @('Loaded workspace: Server')

		Invoke-ObsidianWorkspaceLoad -CliPath 'C:\Obsidian.com' -Vault 'V' -Name 'Server' | Should -BeTrue

		Should -Invoke Write-LogWarning -Times 0
	}

	# The three answers the CLI gives instead of doing the work. Each one used to be swallowed by
	# an unconditional success line.
	It "refuses the load when the per-machine CLI toggle is off" {
		$script:cliAnswer = @('Command line interface is not enabled')

		Invoke-ObsidianWorkspaceLoad -CliPath 'C:\Obsidian.com' -Vault 'V' -Name 'Server' | Should -BeFalse

		Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like '*[[]Server[]] not loaded*not enabled*' }
	}

	It "refuses the load when Obsidian went away between the poll and the load" {
		$script:cliAnswer = @('The CLI is unable to find Obsidian')

		Invoke-ObsidianWorkspaceLoad -CliPath 'C:\Obsidian.com' -Vault 'V' -Name 'DSA' | Should -BeFalse

		Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like '*unable to find Obsidian*' }
	}

	It "refuses the load when the CLI could not be launched at all" {
		$script:cliAnswer = @('CLI call failed: This command cannot be run')

		Invoke-ObsidianWorkspaceLoad -CliPath 'C:\Obsidian.com' -Vault 'V' -Name 'DSA' | Should -BeFalse

		Should -Invoke Write-LogWarning -Times 1 -Exactly
	}

	It "names the fix in the refusal so the message is actionable on its own" {
		$script:cliAnswer = @('Command line interface is not enabled')

		Invoke-ObsidianWorkspaceLoad -CliPath 'C:\Obsidian.com' -Vault 'V' -Name 'Server' | Should -BeFalse

		Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like '*Enable-ObsidianCli*' }
	}

	It "reads the refusal out of any line of a multi-line answer" {
		$script:cliAnswer = @('Obsidian CLI 1.12.4', 'Command line interface is not enabled')

		Invoke-ObsidianWorkspaceLoad -CliPath 'C:\Obsidian.com' -Vault 'V' -Name 'Server' | Should -BeFalse
	}
}
