#Requires -Modules Pester

BeforeAll {
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Get-ObsidianCliPath.ps1"
}

Describe "Get-ObsidianCliPath" {
	It "returns the obsidian command from PATH when registered" {
		Mock Get-Command { [PSCustomObject]@{ Source = 'C:\OnPath\Obsidian.com' } } -ParameterFilter { $Name -eq 'obsidian' }

		Get-ObsidianCliPath | Should -Be 'C:\OnPath\Obsidian.com'
	}

	It "falls back to Obsidian.com in the default install folder" {
		Mock Get-Command { $null } -ParameterFilter { $Name -eq 'obsidian' }
		Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*\Programs\obsidian\Obsidian.com' }

		Get-ObsidianCliPath | Should -Be (Join-Path $env:LOCALAPPDATA 'Programs\obsidian\Obsidian.com')
	}

	It "returns nothing when the CLI is nowhere to be found" {
		Mock Get-Command { $null } -ParameterFilter { $Name -eq 'obsidian' }
		Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like '*\Programs\obsidian\Obsidian.com' }

		Get-ObsidianCliPath | Should -BeNullOrEmpty
	}
}
