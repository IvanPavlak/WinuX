#Requires -Modules Pester

BeforeAll {
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Start-ObsidianDetached.ps1"
	. "$AppFunctionsPath\Get-ObsidianExecutablePath.ps1"
}

Describe "Start-ObsidianDetached" {
	BeforeEach {
		Mock Write-LogDebug { }
		Mock Start-Process { }
		Mock Invoke-CimMethod { [PSCustomObject]@{ ReturnValue = 0; ProcessId = 4242 } }
	}

	It "creates Obsidian.exe through WMI with the vault URI so no console is inherited" {
		Mock Get-ObsidianExecutablePath { 'C:\Apps\Obsidian\Obsidian.exe' }

		Start-ObsidianDetached -Vault 'Obsidian'

		Should -Invoke Invoke-CimMethod -Times 1 -Exactly -ParameterFilter {
			$ClassName -eq 'Win32_Process' -and $MethodName -eq 'Create' -and
			$Arguments.CommandLine -eq '"C:\Apps\Obsidian\Obsidian.exe" "obsidian://open?vault=Obsidian"'
		}
		Should -Invoke Start-Process -Times 0
	}

	It "URI-encodes the vault name" {
		Mock Get-ObsidianExecutablePath { 'C:\Apps\Obsidian\Obsidian.exe' }

		Start-ObsidianDetached -Vault 'My Vault'

		Should -Invoke Invoke-CimMethod -Times 1 -Exactly -ParameterFilter {
			$Arguments.CommandLine -eq '"C:\Apps\Obsidian\Obsidian.exe" "obsidian://open?vault=My%20Vault"'
		}
	}

	It "falls back to the obsidian:// URI when the executable cannot be found" {
		Mock Get-ObsidianExecutablePath { $null }

		Start-ObsidianDetached -Vault 'My Vault'

		Should -Invoke Invoke-CimMethod -Times 0
		Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $FilePath -eq 'obsidian://open?vault=My%20Vault' }
	}

	It "falls back to the obsidian:// URI when WMI refuses to create the process" {
		Mock Get-ObsidianExecutablePath { 'C:\Apps\Obsidian\Obsidian.exe' }
		Mock Invoke-CimMethod { [PSCustomObject]@{ ReturnValue = 8; ProcessId = $null } }

		Start-ObsidianDetached -Vault 'Obsidian'

		Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $FilePath -eq 'obsidian://open?vault=Obsidian' }
	}

	It "falls back to the obsidian:// URI when WMI throws" {
		Mock Get-ObsidianExecutablePath { 'C:\Apps\Obsidian\Obsidian.exe' }
		Mock Invoke-CimMethod { throw 'access denied' }

		Start-ObsidianDetached -Vault 'Obsidian'

		Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $FilePath -eq 'obsidian://open?vault=Obsidian' }
	}
}
