#Requires -Modules Pester

BeforeAll {
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Get-ObsidianWorkspaceNames.ps1"

	$script:VaultDirectory = Join-Path $TestDrive 'Obsidian'
	New-Item -ItemType Directory -Path (Join-Path $script:VaultDirectory '.obsidian') -Force | Out-Null
	@{
		workspaces = @{
			Empty  = @{ main = @{} }
			Server = @{ main = @{} }
			DSA    = @{ main = @{} }
		}
		active     = 'Server'
	} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $script:VaultDirectory '.obsidian\workspaces.json')

	$script:BrokenVaultDirectory = Join-Path $TestDrive 'Broken'
	New-Item -ItemType Directory -Path (Join-Path $script:BrokenVaultDirectory '.obsidian') -Force | Out-Null
	Set-Content -LiteralPath (Join-Path $script:BrokenVaultDirectory '.obsidian\workspaces.json') -Value '{ not json'
}

Describe "Get-ObsidianWorkspaceNames" {
	BeforeEach {
		Mock Write-LogDebug { }
	}

	It "returns the saved workspace names" {
		$names = @(Get-ObsidianWorkspaceNames -VaultDirectory $script:VaultDirectory)

		$names | Should -Contain 'Empty'
		$names | Should -Contain 'Server'
		$names | Should -Contain 'DSA'
		$names.Count | Should -Be 3
	}

	It "returns nothing for an empty vault directory" {
		@(Get-ObsidianWorkspaceNames -VaultDirectory '').Count | Should -Be 0
	}

	It "returns nothing when workspaces.json is missing" {
		@(Get-ObsidianWorkspaceNames -VaultDirectory (Join-Path $TestDrive 'Nope')).Count | Should -Be 0
	}

	It "returns nothing when workspaces.json does not parse" {
		@(Get-ObsidianWorkspaceNames -VaultDirectory $script:BrokenVaultDirectory).Count | Should -Be 0
	}
}
