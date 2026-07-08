#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Set-WindowModuleDelays.ps1"
}

Describe "Set-WindowModuleDelays" {
	It "updates known keys and ignores unknown keys" {
		$script:WindowModuleDelays = @{
			FocusSettleMs   = 5
			WindowRestoreMs = 20
		}

		Set-WindowModuleDelays -Delays @{ FocusSettleMs = 15; UnknownKey = 999 }

		$script:WindowModuleDelays.FocusSettleMs | Should -Be 15
		$script:WindowModuleDelays.WindowRestoreMs | Should -Be 20
		$script:WindowModuleDelays.ContainsKey("UnknownKey") | Should -BeFalse
	}
}
