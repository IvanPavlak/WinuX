#Requires -Modules Pester

BeforeAll {
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Invoke-ObsidianCli.ps1"
}

Describe "Invoke-ObsidianCli" {
	BeforeEach {
		Mock Write-LogDebug { }
		Mock Remove-Item { }
	}

	It "runs the CLI in a hidden window with redirected output and returns the non-blank lines" {
		Mock Start-Process {
			Set-Content -LiteralPath $RedirectStandardOutput -Value "Empty (active)`nServer`n`n"
			Set-Content -LiteralPath $RedirectStandardError -Value ''
		}

		$result = @(Invoke-ObsidianCli -CliPath 'C:\Apps\Obsidian\Obsidian.com' -Arguments @('vault=Obsidian', 'workspaces'))

		Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
			$FilePath -eq 'C:\Apps\Obsidian\Obsidian.com' -and
			(@($ArgumentList) -join ' ') -eq 'vault=Obsidian workspaces' -and
			$WindowStyle -eq 'Hidden' -and $PassThru -and
			$RedirectStandardOutput -and $RedirectStandardError
		}
		$result | Should -Be @('Empty (active)', 'Server')
	}

	It "includes stderr lines so callers can see the CLI's refusal" {
		Mock Start-Process {
			Set-Content -LiteralPath $RedirectStandardOutput -Value ''
			Set-Content -LiteralPath $RedirectStandardError -Value 'The CLI is unable to find Obsidian.'
		}

		@(Invoke-ObsidianCli -CliPath 'C:\Apps\Obsidian\Obsidian.com' -Arguments @('vault=Obsidian', 'workspaces')) | Should -Be @('The CLI is unable to find Obsidian.')
	}

	It "reports a failed launch as a line instead of throwing" {
		Mock Start-Process { throw 'not found' }

		$result = @(Invoke-ObsidianCli -CliPath 'C:\Missing\Obsidian.com' -Arguments @('vault=Obsidian', 'workspaces'))

		$result.Count | Should -Be 1
		$result[0] | Should -BeLike 'CLI call failed:*'
	}

	It "kills a call that does not exit within the timeout and answers with a timed-out line" {
		$script:killed = $null
		$script:waitedMs = $null
		Mock Start-Process {
			$process = [PSCustomObject]@{}
			$process | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { param($ms) $script:waitedMs = $ms; $false }
			$process | Add-Member -MemberType ScriptMethod -Name Kill -Value { param($tree) $script:killed = $tree }
			$process
		}

		$result = @(Invoke-ObsidianCli -CliPath 'C:\Apps\Obsidian\Obsidian.com' -Arguments @('vault=Obsidian', 'workspaces') -TimeoutSeconds 2)

		$script:waitedMs | Should -Be 2000
		$script:killed | Should -BeTrue
		$result[0] | Should -Be 'CLI call timed out after 2 s'
	}

	It "returns the answer of a call that exits within the timeout without killing it" {
		$script:killed = $null
		Mock Start-Process {
			Set-Content -LiteralPath $RedirectStandardOutput -Value 'Loaded workspace: Server'
			$process = [PSCustomObject]@{}
			$process | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { param($ms) $true }
			$process | Add-Member -MemberType ScriptMethod -Name Kill -Value { param($tree) $script:killed = $tree }
			$process
		}

		@(Invoke-ObsidianCli -CliPath 'C:\Apps\Obsidian\Obsidian.com' -Arguments @('vault=Obsidian', 'workspaces')) | Should -Be @('Loaded workspace: Server')
		$script:killed | Should -BeNullOrEmpty
	}

	It "cleans up its temporary files" {
		Mock Start-Process { }

		Invoke-ObsidianCli -CliPath 'C:\Apps\Obsidian\Obsidian.com' -Arguments @('vault=Obsidian', 'workspaces') | Out-Null

		Should -Invoke Remove-Item -Times 1 -Exactly
	}
}
