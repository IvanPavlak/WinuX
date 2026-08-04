#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	# The unconfigured-section guards warn through Confirm-ConfigValue (Helper);
	# dot-source it (and its Test-ConfigValue dependency) so the Write-LogWarning
	# mocks in these tests apply to the guard's warning.
	. "$ModuleRoot\Helper\Functions\Test-ConfigValue.ps1"
	. "$ModuleRoot\Helper\Functions\Confirm-ConfigValue.ps1"

	. "$FunctionsPath\Set-ExplorerOptions.ps1"
}

Describe "Set-ExplorerOptions" {
	BeforeEach {
		$script:Configuration = [PSCustomObject]@{
			ExplorerOptions = $null
		}
		Mock Write-Host { }
		Mock Write-LogTitle { }
		Mock Write-LogError { }
		Mock Write-LogWarning { }
		Mock Restart-Explorer { }
	}

	It "returns with a warning when ExplorerOptions are missing from configuration" {
		{ Set-ExplorerOptions } | Should -Not -Throw
		Should -Invoke Restart-Explorer -Times 0
		Should -Invoke Write-LogTitle -Times 1
		Should -Invoke Write-LogError -Times 0
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match "ExplorerOptions not configured" }
	}
}
