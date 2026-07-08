#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Set-WindowPosition.ps1"
}

Describe "Set-WindowPosition" {
	BeforeEach {
		$script:WindowModuleDelays = @{ WindowRestoreMs = 1; WindowPositionMs = 1 }
		Mock Start-Sleep { }
	}

	It "returns false when window cannot be positioned" {
		$result = Set-WindowPosition -WindowHandle ([IntPtr]::Zero) -X 0 -Y 0 -Width 800 -Height 600

		$result | Should -BeFalse
	}
}
