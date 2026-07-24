#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Test-VirtualDesktopComHealth.ps1"
}

Describe "Test-VirtualDesktopComHealth" {
	It "returns a result object with Healthy, TimedOut, and Error" {
		$result = Test-VirtualDesktopComHealth -TimeoutMs 15000

		$result.PSObject.Properties.Name | Should -Contain 'Healthy'
		$result.PSObject.Properties.Name | Should -Contain 'TimedOut'
		$result.PSObject.Properties.Name | Should -Contain 'Error'
		$result.Healthy | Should -BeOfType [bool]
		$result.TimedOut | Should -BeOfType [bool]
	}

	It "reports an error message exactly when unhealthy" {
		$result = Test-VirtualDesktopComHealth -TimeoutMs 15000

		if ($result.Healthy) {
			$result.Error | Should -BeNullOrEmpty
		}
		else {
			$result.Error | Should -Not -BeNullOrEmpty
		}
	}

	It "agrees with a direct in-process COM call when the VirtualDesktop types are loaded" {
		# The whole point of this probe is that it shares the CURRENT process's COM
		# state - so its verdict must match what a direct call experiences.
		$desktopType = ([System.Management.Automation.PSTypeName]'VirtualDesktop.Desktop').Type
		if (-not $desktopType) {
			Set-ItResult -Skipped -Because "VirtualDesktop types are not loaded in this session"
			return
		}

		$directCallWorks = $true
		try {
			[void]$desktopType.GetProperty('Count').GetValue($null)
		}
		catch {
			$directCallWorks = $false
		}

		$result = Test-VirtualDesktopComHealth -TimeoutMs 15000

		$result.Healthy | Should -Be $directCallWorks
	}
}
