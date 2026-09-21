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
		(Invoke-ObsidianWorkspaceLoad -CliPath 'C:\Apps\Obsidian\Obsidian.com' -Vault 'MyVault' -Name 'Server').Loaded | Should -BeTrue

		$script:cliCalls.Count | Should -Be 1
		$script:cliCalls[0] | Should -Be @('vault=MyVault', 'workspace:load', 'name=Server')
	}

	It "passes the CLI path through to the one call site" {
		(Invoke-ObsidianWorkspaceLoad -CliPath 'D:\Obsidian\Obsidian.com' -Vault 'V' -Name 'N').Loaded | Should -BeTrue

		Should -Invoke Invoke-ObsidianCli -Times 1 -Exactly -ParameterFilter { $CliPath -eq 'D:\Obsidian\Obsidian.com' }
	}

	It "reports a load that landed with no refusal and no message" {
		$script:cliAnswer = @('Loaded workspace: Server')

		$result = Invoke-ObsidianWorkspaceLoad -CliPath 'C:\Obsidian.com' -Vault 'V' -Name 'Server'

		$result.Loaded | Should -BeTrue
		$result.Refusal | Should -BeNullOrEmpty
		$result.Message | Should -BeNullOrEmpty
		Should -Invoke Write-LogWarning -Times 0
	}

	# The three answers the CLI gives instead of doing the work. Each one used to be swallowed by
	# an unconditional success line.
	It "refuses the load when the per-machine CLI toggle is off, naming the line" {
		$script:cliAnswer = @('Command line interface is not enabled')

		$result = Invoke-ObsidianWorkspaceLoad -CliPath 'C:\Obsidian.com' -Vault 'V' -Name 'Server'

		$result.Loaded | Should -BeFalse
		$result.Refusal | Should -Be 'Command line interface is not enabled'
		Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like '*[[]Server[]] not loaded*not enabled*' }
	}

	It "refuses the load when Obsidian is not answering" {
		$script:cliAnswer = @('The CLI is unable to find Obsidian')

		$result = Invoke-ObsidianWorkspaceLoad -CliPath 'C:\Obsidian.com' -Vault 'V' -Name 'DSA'

		$result.Loaded | Should -BeFalse
		$result.Refusal | Should -Match 'unable to find Obsidian'
		Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like '*unable to find Obsidian*' }
	}

	It "refuses the load when the CLI could not be launched at all" {
		$script:cliAnswer = @('CLI call failed: This command cannot be run')

		(Invoke-ObsidianWorkspaceLoad -CliPath 'C:\Obsidian.com' -Vault 'V' -Name 'DSA').Loaded | Should -BeFalse

		Should -Invoke Write-LogWarning -Times 1 -Exactly
	}

	It "names the fix in the refusal so the message is actionable on its own" {
		$script:cliAnswer = @('Command line interface is not enabled')

		$result = Invoke-ObsidianWorkspaceLoad -CliPath 'C:\Obsidian.com' -Vault 'V' -Name 'Server'

		$result.Message | Should -Match 'Enable-ObsidianCli'
		Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like '*Enable-ObsidianCli*' }
	}

	It "keeps the refusal to itself with -Silent, handing the caller the message instead" {
		$script:cliAnswer = @('Command line interface is not enabled')

		$result = Invoke-ObsidianWorkspaceLoad -CliPath 'C:\Obsidian.com' -Vault 'V' -Name 'Server' -Silent

		$result.Loaded | Should -BeFalse
		$result.Message | Should -Match 'not loaded'
		Should -Invoke Write-LogWarning -Times 0
	}

	It "reads the refusal out of any line of a multi-line answer" {
		$script:cliAnswer = @('Obsidian CLI 1.12.4', 'Command line interface is not enabled')

		(Invoke-ObsidianWorkspaceLoad -CliPath 'C:\Obsidian.com' -Vault 'V' -Name 'Server').Loaded | Should -BeFalse
	}
}
