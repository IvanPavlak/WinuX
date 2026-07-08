#Requires -Modules Pester

BeforeAll {
	$BootstrapFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Bootstrap\Functions"
	. "$BootstrapFunctionsPath\Install-WinGetPackageManager.ps1"

	# Stub the PowerShell Gallery script command so it exists and can be mocked/asserted.
	function winget-install { }
}

Describe "Install-WinGetPackageManager" {
	BeforeEach {
		Mock Write-Host { }
		Mock Write-LogTitle { }
		Mock Write-LogStep { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }
		Mock Test-AdminPrivileges { }
		Mock Install-Script { }
		Mock winget-install { }
	}

	It "returns early when winget is already available" {
		Mock winget { 'v1.9.0' }

		Install-WinGetPackageManager

		Should -Invoke Install-Script -Times 0
		Should -Invoke winget-install -Times 0
	}

	It "installs WinGet via the winget-install script when winget is unavailable" {
		$script:wingetCalls = 0
		Mock winget {
			$script:wingetCalls++
			if ($script:wingetCalls -eq 1) { throw 'winget not found' }
			return 'v1.9.0'
		}

		Install-WinGetPackageManager

		Should -Invoke Install-Script -Times 1 -Exactly -ParameterFilter { $Name -eq 'winget-install' }
		Should -Invoke winget-install -Times 1 -Exactly
	}
}
