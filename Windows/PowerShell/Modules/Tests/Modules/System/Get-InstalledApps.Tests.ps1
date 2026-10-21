#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Get-InstalledApps.ps1"
}

Describe "Get-InstalledApps" {
	BeforeEach {
		$script:written = [System.Collections.Generic.List[string]]::new()
		Mock Test-Path { $false }
		Mock Clear-Content { }
		Mock Add-Content { $script:written.Add([string]$Value) }
		Mock Write-Host { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
	}

	It "exports the apps of the local machine instead of nothing" {
		# The loop used to run over an undefined $Hostname, so it exported nothing and still
		# reported success. This reads the real (read-only) registry of the test machine.
		Get-InstalledApps

		$script:written.Count | Should -BeGreaterThan 0
		Should -Invoke Clear-Content -Times 0
		Should -Invoke Write-LogSuccess -Times 1
		Should -Invoke Write-LogWarning -Times 0
	}

	It "labels Wow6432Node entries 32-bit and the plain Uninstall key 64-bit" {
		Get-InstalledApps

		$wow = @($script:written | Where-Object { $_ -match 'Wow6432Node' })
		$native = @($script:written | Where-Object { $_ -notmatch 'Wow6432Node' })
		foreach ($entry in $wow) { $entry | Should -Match 'Bits\s*:\s*32' }
		foreach ($entry in $native) { $entry | Should -Match 'Bits\s*:\s*64' }
	}

	It "clears an existing export before writing" {
		Mock Test-Path { $true }

		Get-InstalledApps

		Should -Invoke Clear-Content -Times 1
	}
}
