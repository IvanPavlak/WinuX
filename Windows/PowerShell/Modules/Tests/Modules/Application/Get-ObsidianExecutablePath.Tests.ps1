#Requires -Modules Pester

BeforeAll {
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Get-ObsidianExecutablePath.ps1"
	. "$AppFunctionsPath\Get-ObsidianCliPath.ps1"
}

Describe "Get-ObsidianExecutablePath" {
	BeforeEach {
		Mock Get-ItemProperty { $null }
	}

	It "prefers Obsidian.exe beside the CLI" {
		Mock Get-ObsidianCliPath { 'C:\Apps\Obsidian\Obsidian.com' }
		Mock Test-Path { $LiteralPath -eq 'C:\Apps\Obsidian\Obsidian.exe' }

		Get-ObsidianExecutablePath | Should -Be 'C:\Apps\Obsidian\Obsidian.exe'
	}

	It "falls back to the default install folder when the CLI is not registered" {
		Mock Get-ObsidianCliPath { $null }
		$expected = Join-Path $env:LOCALAPPDATA 'Programs\obsidian\Obsidian.exe'
		Mock Test-Path { $LiteralPath -eq $expected }

		Get-ObsidianExecutablePath | Should -Be $expected
	}

	It "reads the obsidian:// protocol handler as the last resort" {
		Mock Get-ObsidianCliPath { $null }
		Mock Get-ItemProperty { [PSCustomObject]@{ '(default)' = '"D:\Portable\Obsidian\Obsidian.exe" "%1"' } }
		Mock Test-Path { $LiteralPath -eq 'D:\Portable\Obsidian\Obsidian.exe' }

		Get-ObsidianExecutablePath | Should -Be 'D:\Portable\Obsidian\Obsidian.exe'
	}

	It "returns nothing when no candidate exists" {
		Mock Get-ObsidianCliPath { $null }
		Mock Test-Path { $false }

		Get-ObsidianExecutablePath | Should -BeNullOrEmpty
	}
}
