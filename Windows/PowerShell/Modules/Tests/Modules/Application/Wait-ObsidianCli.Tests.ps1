#Requires -Modules Pester

BeforeAll {
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Wait-ObsidianCli.ps1"
	. "$AppFunctionsPath\Invoke-ObsidianCli.ps1"
}

Describe "Wait-ObsidianCli" {
	BeforeEach {
		$script:cliCalls = @()
		Mock Write-LogDebug { }
	}

	It "returns true as soon as the CLI stops reporting that it cannot find Obsidian" {
		$script:answers = [System.Collections.Generic.Queue[object]]::new()
		$script:answers.Enqueue(@('The CLI is unable to find Obsidian. Please make sure Obsidian is running and try again.'))
		$script:answers.Enqueue(@('The CLI is unable to find Obsidian. Please make sure Obsidian is running and try again.'))
		$script:answers.Enqueue(@('Empty (active)', 'Server'))
		Mock Invoke-ObsidianCli { $script:cliCalls += , @($Arguments); $script:answers.Dequeue() }

		$result = Wait-ObsidianCli -CliPath 'C:\Apps\Obsidian\Obsidian.com' -Vault 'Obsidian' -TimeoutSeconds 5 -PollMilliseconds 1

		$result | Should -BeTrue
		$script:cliCalls.Count | Should -Be 3
		$script:cliCalls | ForEach-Object { $_ | Should -Be @('vault=Obsidian', 'workspaces') }
	}

	It "probes the vault it was given" {
		Mock Invoke-ObsidianCli { $script:cliCalls += , @($Arguments); @('Empty (active)') }

		Wait-ObsidianCli -CliPath 'C:\Apps\Obsidian\Obsidian.com' -Vault 'MyVault' -TimeoutSeconds 1 -PollMilliseconds 1 | Out-Null

		$script:cliCalls[0] | Should -Be @('vault=MyVault', 'workspaces')
	}

	It "returns false when the CLI never answers before the timeout" {
		Mock Invoke-ObsidianCli { $script:cliCalls += , @($Arguments); @('The CLI is unable to find Obsidian.') }

		$result = Wait-ObsidianCli -CliPath 'C:\Apps\Obsidian\Obsidian.com' -Vault 'Obsidian' -TimeoutSeconds 0 -PollMilliseconds 1

		$result | Should -BeFalse
		$script:cliCalls.Count | Should -BeGreaterOrEqual 1
	}
}
