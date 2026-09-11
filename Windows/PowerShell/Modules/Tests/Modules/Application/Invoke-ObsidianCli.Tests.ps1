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
			$WindowStyle -eq 'Hidden' -and $Wait -and
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

	It "cleans up its temporary files" {
		Mock Start-Process { }

		Invoke-ObsidianCli -CliPath 'C:\Apps\Obsidian\Obsidian.com' -Arguments @('vault=Obsidian', 'workspaces') | Out-Null

		Should -Invoke Remove-Item -Times 1 -Exactly
	}
}
