#Requires -Modules Pester

BeforeAll {
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Start-ObsidianDetached.ps1"
	. "$AppFunctionsPath\Get-ObsidianExecutablePath.ps1"
	. "$AppFunctionsPath\Start-ProcessDetached.ps1"
}

Describe "Start-ObsidianDetached" {
	BeforeEach {
		Mock Write-LogDebug { }
		Mock Get-ObsidianExecutablePath { 'C:\Apps\Obsidian\Obsidian.exe' }
		Mock Start-ProcessDetached { 4242 }
	}

	It "launches Obsidian.exe detached with the quoted vault URI and the URI as the fallback" {
		Start-ObsidianDetached -Vault 'Obsidian'

		Should -Invoke Start-ProcessDetached -Times 1 -Exactly -ParameterFilter {
			$FilePath -eq 'C:\Apps\Obsidian\Obsidian.exe' -and
			$ArgumentList -eq '"obsidian://open?vault=Obsidian"' -and
			$Fallback.FilePath -eq 'obsidian://open?vault=Obsidian' -and $Fallback.Count -eq 1
		}
	}

	It "URI-encodes the vault name in both the argument and the fallback" {
		Start-ObsidianDetached -Vault 'My Vault'

		Should -Invoke Start-ProcessDetached -Times 1 -Exactly -ParameterFilter {
			$ArgumentList -eq '"obsidian://open?vault=My%20Vault"' -and $Fallback.FilePath -eq 'obsidian://open?vault=My%20Vault'
		}
	}

	It "hands an empty executable and the URI fallback to the helper when Obsidian.exe cannot be found" {
		Mock Get-ObsidianExecutablePath { $null }

		Start-ObsidianDetached -Vault 'Obsidian'

		Should -Invoke Start-ProcessDetached -Times 1 -Exactly -ParameterFilter {
			-not $FilePath -and $Fallback.FilePath -eq 'obsidian://open?vault=Obsidian'
		}
	}
}
