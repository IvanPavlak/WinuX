#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Write-ManualInstructionsToDesktop.ps1"
}

Describe "Write-ManualInstructionsToDesktop" {
	BeforeEach {
		Mock Out-File { }
		Mock Write-Host { }
	}

	It "writes instructions document to a desktop file path" {
		{ Write-ManualInstructionsToDesktop -FileName "setup.txt" -Title "Setup" -Content "Step 1" } | Should -Throw
	}
}
