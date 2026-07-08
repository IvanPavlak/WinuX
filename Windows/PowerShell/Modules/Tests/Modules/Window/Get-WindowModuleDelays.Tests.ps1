#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Get-WindowModuleDelays.ps1"
}

Describe "Get-WindowModuleDelays" {
	It "returns a clone of module delay settings" {
		$script:WindowModuleDelays = @{ FocusSettleMs = 10; WindowPositionMs = 30 }

		$result = Get-WindowModuleDelays
		$result.FocusSettleMs = 99

		$result.WindowPositionMs | Should -Be 30
		$script:WindowModuleDelays.FocusSettleMs | Should -Be 10
	}
}
